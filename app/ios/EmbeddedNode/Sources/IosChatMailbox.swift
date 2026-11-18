import CoreFoundation
import Darwin
import Foundation

/// Native half of the file mailbox beside the one per-process Node probe report.
/// The Flutter channel does not expose mailbox paths. XCTest can attach to the
/// same mailbox with its own probe report URL and exercise the actual transport.
public final class IosChatMailbox {
  public enum Method: String {
    case start, snapshot, send, cancel, stop, answerApproval
  }

  public struct Failure: Error {
    public let code: String
    fileprivate init(_ code: String) { self.code = code }
  }

  private typealias Reply = Result<[String: Any], Failure>
  private struct Job {
    let id: String
    let body: Data
    let deadline: DispatchTime
    let completion: (Reply) -> Void
  }

  private struct Published {
    let id: String
    let deadline: DispatchTime
    let completion: (Reply) -> Void
    var requestName: String { "request-\(id).json" }
    var responseName: String { "response-\(id).json" }
  }

  private static let maxRequestBytes = 16 * 1024
  private static let maxResponseBytes = 256 * 1024
  private static let maxInFlight = 8
  private static let publicCodes: Set<String> = [
    "IOS_CHAT_BAD_REQUEST", "IOS_CHAT_REQUEST_EXPIRED", "IOS_CHAT_NOT_STARTED", "IOS_CHAT_BUSY",
    "IOS_CHAT_START_FAILED", "IOS_CHAT_SEND_FAILED", "IOS_CHAT_CANCEL_FAILED", "IOS_CHAT_STOP_FAILED",
    "IOS_CHAT_STORAGE_FAILED", "IOS_CHAT_MODEL_FAILED", "IOS_CHAT_RESPONSE_LIMIT", "IOS_CHAT_UNAVAILABLE",
    "IOS_CHAT_INPUT_INVALID", "IOS_CHAT_AUTH_FAILED", "IOS_CHAT_RATE_LIMITED", "IOS_CHAT_TIMEOUT",
    "IOS_CHAT_NETWORK_FAILED", "IOS_CHAT_KEY_INVALID", "IOS_CHAT_BOOT_FAILED", "IOS_CHAT_STOPPED",
    "IOS_CHAT_INVALID_REQUEST", "IOS_CHAT_PROTOCOL_ERROR", "IOS_CHAT_CHANNEL_INVALID", "IOS_CHAT_APPROVAL_STALE",
  ]

  private let directory: Int32
  private let worker = DispatchQueue(label: "dsh.ios.chat-mailbox", qos: .userInitiated)
  private let admission = NSLock()
  private var inFlight = 0 // Counts from admission until the main-queue callback.
  private var accepting = true // Both admission fields are protected by the lock.
  private var waiting: [Job] = [] // The rest of the lifetime state belongs to `worker`.
  private var active: Published?

  public init(reportURL: URL) throws {
    let name = reportURL.lastPathComponent + ".chat"
    guard reportURL.isFileURL, reportURL.path.hasPrefix("/"), Self.isMailboxName(name) else {
      throw Failure("IOS_CHAT_INVALID_REQUEST")
    }
    var path = reportURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    // Do not use a recursive create or touch the report or its parent's other data.
    if mkdir(path.path, 0o700) != 0, errno != EEXIST {
      throw Failure("IOS_CHAT_UNAVAILABLE")
    }
    let fd = Darwin.open(path.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure("IOS_CHAT_UNAVAILABLE") }
    var attributes = stat()
    guard fstat(fd, &attributes) == 0, attributes.st_uid == geteuid(),
          attributes.st_mode & 0o7777 == 0o700 else {
      Darwin.close(fd)
      throw Failure("IOS_CHAT_UNAVAILABLE")
    }
    do {
      // This folder is transport, not chat history, and can briefly hold a key.
      var exclusions = URLResourceValues()
      exclusions.isExcludedFromBackup = true
      try path.setResourceValues(exclusions)
    } catch {
      Darwin.close(fd)
      throw Failure("IOS_CHAT_UNAVAILABLE")
    }
    directory = fd
  }

  deinit { Darwin.close(directory) }

  /// Completion always runs on the main queue. Calls are published in admission
  /// order, so JS never observes a later stop/start before an earlier mutation.
  public func request(
    _ method: Method, value: String? = nil,
    completion: @escaping (Result<[String: Any], Failure>) -> Void
  ) {
    let params: [String: Any]
    switch method {
    case .start: params = ["apiKey": value ?? ""]
    case .send: params = ["text": value ?? ""]
    case .snapshot, .cancel, .stop, .answerApproval:
      guard value == nil else {
        DispatchQueue.main.async { completion(.failure(Failure("IOS_CHAT_INVALID_REQUEST"))) }
        return
      }
      params = [:]
    }
    request(method, params: params, completion: completion)
  }

  /// Submit a chat request with structured parameters, on the same ordered mailbox.
  public func request(
    _ method: Method, params: [String: Any],
    completion: @escaping (Result<[String: Any], Failure>) -> Void
  ) {
    switch Self.parameters(for: method, params: params) {
    case .success(let params): submit(method, params: params, completion: completion)
    case .failure(let error):
      DispatchQueue.main.async { completion(.failure(error)) }
    }
  }

  static func parameters(for method: Method, params: [String: Any]) -> Result<[String: Any], Failure> {
    let invalid = Failure("IOS_CHAT_INVALID_REQUEST")
    switch method {
    case .start:
      let keys = Set(params.keys)
      let custom = keys == ["apiKey", "protocol", "baseUrl", "modelId"]
      guard custom || keys == ["apiKey"], let rawKey = params["apiKey"] as? String else {
        return .failure(invalid)
      }
      let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (1...1024).contains(key.utf8.count), key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
        return .failure(Failure("IOS_CHAT_KEY_INVALID"))
      }
      guard custom else { return .success(["apiKey": key]) }
      guard let channelProtocol = params["protocol"] as? String,
            let baseUrl = params["baseUrl"] as? String, let modelId = params["modelId"] as? String else {
        return .failure(invalid)
      }
      // Bound the inputs; JS owns the allowed protocols, URL rules and model syntax.
      guard (1...32).contains(channelProtocol.utf16.count), (1...2048).contains(baseUrl.utf16.count),
            (1...256).contains(modelId.utf16.count) else {
        return .failure(Failure("IOS_CHAT_CHANNEL_INVALID"))
      }
      return .success(["apiKey": key, "protocol": channelProtocol, "baseUrl": baseUrl, "modelId": modelId])
    case .send:
      guard Set(params.keys) == ["text"], let text = params["text"] as? String else {
        return .failure(invalid)
      }
      guard text.utf8.count <= 8192, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(Failure("IOS_CHAT_INPUT_INVALID"))
      }
      return .success(["text": text])
    case .answerApproval:
      guard Set(params.keys) == ["id", "allowed"], let id = params["id"] as? String,
            isLowercaseUUID(id), let allowed = jsonBoolean(params["allowed"]) else {
        return .failure(invalid)
      }
      return .success(["id": id, "allowed": allowed])
    case .snapshot, .cancel, .stop:
      return params.isEmpty ? .success([:]) : .failure(invalid)
    }
  }

  func submit(
    _ method: Method, params: [String: Any],
    completion: @escaping (Result<[String: Any], Failure>) -> Void
  ) {
    let id = UUID().uuidString.lowercased()
    let envelope: [String: Any] = ["id": id, "method": method.rawValue, "params": params]
    guard let body = try? JSONSerialization.data(withJSONObject: envelope, options: [.withoutEscapingSlashes]),
          body.count <= Self.maxRequestBytes else {
      DispatchQueue.main.async { completion(.failure(Failure("IOS_CHAT_INPUT_INVALID"))) }
      return
    }

    admission.lock()
    defer { admission.unlock() }
    guard accepting else {
      DispatchQueue.main.async { completion(.failure(Failure("IOS_CHAT_UNAVAILABLE"))) }
      return
    }
    guard inFlight < Self.maxInFlight else {
      DispatchQueue.main.async { completion(.failure(Failure("IOS_CHAT_BUSY"))) }
      return
    }
    inFlight += 1
    let job = Job(id: id, body: body, deadline: .now() + .seconds(25), completion: completion)
    worker.async {
      self.waiting.append(job)
      self.pump()
    }
  }

  // Called only after the shared Node runtime fails to start or has exited.
  func invalidate() {
    admission.lock()
    defer { admission.unlock() }
    guard accepting else { return }
    accepting = false
    worker.async {
      let error = Reply.failure(Failure("IOS_CHAT_UNAVAILABLE"))
      if let current = self.active {
        self.remove(current.requestName)
        self.remove(current.responseName)
        self.active = nil
        self.complete(current.completion, with: error)
      }
      let queued = self.waiting
      self.waiting.removeAll()
      for job in queued { self.complete(job.completion, with: error) }
    }
  }

  private func pump() {
    while active == nil, !waiting.isEmpty {
      let job = waiting.removeFirst()
      guard DispatchTime.now() < job.deadline else {
        complete(job.completion, with: .failure(Failure("IOS_CHAT_TIMEOUT")))
        continue
      }
      let file = Published(id: job.id, deadline: job.deadline, completion: job.completion)
      do {
        try publish(job.body, requestName: file.requestName)
        // The worker no longer retains the request body after this turn.
        active = file
        worker.asyncAfter(deadline: .now() + .milliseconds(80)) { self.poll(file.id) }
      } catch {
        complete(job.completion, with: .failure(Failure("IOS_CHAT_UNAVAILABLE")))
      }
    }
  }

  private func publish(_ body: Data, requestName: String) throws {
    let temporary = ".request-\(UUID().uuidString.lowercased()).tmp"
    let fd = Darwin.openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw Failure("IOS_CHAT_UNAVAILABLE") }
    defer { remove(temporary) }
    let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    guard fchmod(fd, 0o600) == 0 else { throw Failure("IOS_CHAT_UNAVAILABLE") }
    try output.write(contentsOf: body)
    try output.close()
    // The watcher sees only a fully written file, and no existing request can
    // be overwritten. All operations are relative to the opened mailbox dir.
    guard renameatx_np(directory, temporary, directory, requestName, UInt32(RENAME_EXCL)) == 0 else {
      throw Failure("IOS_CHAT_UNAVAILABLE")
    }
  }

  private func poll(_ id: String) {
    guard let file = active, file.id == id else { return }
    let reply: Reply
    do {
      if let response = try readResponse(file) {
        reply = response
      } else if DispatchTime.now() < file.deadline {
        worker.asyncAfter(deadline: .now() + .milliseconds(80)) { self.poll(id) }
        return
      } else {
        // If Node already consumed this request, it still owns the operation.
        // It serializes subsequent work and expires orphan replies.
        reply = .failure(Failure("IOS_CHAT_TIMEOUT"))
      }
    } catch {
      reply = .failure(Failure("IOS_CHAT_PROTOCOL_ERROR"))
    }
    remove(file.requestName)
    remove(file.responseName)
    active = nil
    complete(file.completion, with: reply)
    pump()
  }

  private func readResponse(_ file: Published) throws -> Reply? {
    let fd = Darwin.openat(directory, file.responseName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    if fd < 0, errno == ENOENT { return nil }
    guard fd >= 0 else { throw Failure("IOS_CHAT_PROTOCOL_ERROR") }
    let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? input.close() }
    var attributes = stat()
    guard fstat(fd, &attributes) == 0,
          attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          attributes.st_mode & 0o7777 == 0o600, attributes.st_uid == geteuid(),
          // Node publishes via exclusive hard link, then drops its temp link.
          (1...2).contains(attributes.st_nlink),
          attributes.st_size > 0, attributes.st_size <= off_t(Self.maxResponseBytes),
          let data = try input.read(upToCount: Self.maxResponseBytes + 1),
          data.count == Int(attributes.st_size),
          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          envelope["id"] as? String == file.id else {
      throw Failure("IOS_CHAT_PROTOCOL_ERROR")
    }
    if Set(envelope.keys) == ["id", "errorCode"], let error = envelope["errorCode"] as? String,
       Self.publicCodes.contains(error) {
      return .failure(Failure(error))
    }
    guard Set(envelope.keys) == ["id", "result"], let result = envelope["result"] as? [String: Any],
          Set(result.keys) == ["state", "messages", "draft", "errorCode", "approval"],
          let state = result["state"] as? String, ["ready", "running", "stopped"].contains(state),
          let messages = result["messages"] as? [[String: Any]], result["draft"] is String,
          let error = result["errorCode"], error is NSNull || Self.publicCodes.contains(error as? String ?? ""),
          let approval = result["approval"], Self.isApproval(approval),
          messages.allSatisfy({ message in
            Set(message.keys) == ["role", "text"]
              && ["user", "assistant", "tool"].contains(message["role"] as? String ?? "")
              && message["text"] is String
          }) else { throw Failure("IOS_CHAT_PROTOCOL_ERROR") }
    return .success(result)
  }

  private static func isApproval(_ value: Any) -> Bool {
    if value is NSNull { return true }
    guard let approval = value as? [String: Any],
          Set(approval.keys) == ["id", "toolName", "path", "byteLength", "preview", "previewTruncated"],
          let id = approval["id"] as? String, isLowercaseUUID(id),
          approval["toolName"] as? String == "workspace_create_text",
          let path = approval["path"] as? String, (1...480).contains(path.utf8.count),
          let bytes = approval["byteLength"] as? NSNumber, CFGetTypeID(bytes) == CFNumberGetTypeID(),
          !["f", "d"].contains(String(cString: bytes.objCType)),
          let byteLength = bytes as? Int, (0...4096).contains(byteLength),
          let preview = approval["preview"] as? String, preview.utf8.count <= 512,
          jsonBoolean(approval["previewTruncated"]) != nil else { return false }
    return true
  }

  private static func isLowercaseUUID(_ value: String) -> Bool {
    value.utf8.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value
  }

  private static func jsonBoolean(_ value: Any?) -> Bool? {
    // `as? Bool` on NSNumber also accepts numeric 0 and 1.
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
  }

  private func remove(_ name: String) { _ = unlinkat(directory, name, 0) }

  private func complete(_ completion: @escaping (Reply) -> Void, with reply: Reply) {
    DispatchQueue.main.async {
      self.admission.lock()
      self.inFlight -= 1
      self.admission.unlock()
      completion(reply)
    }
  }

  /// Called before creating this process's report, only in RuntimeProbe, never
  /// in the shared ChatData directory or on the old probe reports themselves.
  static func removeStaleMailboxes(in parent: URL) {
    let fd = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { return }
    defer { Darwin.close(fd) }
    var parentInfo = stat()
    guard fstat(fd, &parentInfo) == 0, parentInfo.st_uid == geteuid(),
          parentInfo.st_mode & 0o7777 == 0o700,
          let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
    for name in entries where isMailboxName(name) {
      var attributes = stat()
      guard fstatat(fd, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0,
            attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
            attributes.st_uid == geteuid(), attributes.st_mode & 0o7777 == 0o700 else { continue }
      // Move to a fresh name and verify the same inode before removal. Nothing
      // at the old public name is touched after the rename.
      let retired = UUID().uuidString.lowercased() + ".json.chat"
      let retiredURL = parent.appendingPathComponent(retired, isDirectory: true)
      guard renameatx_np(fd, name, fd, retired, UInt32(RENAME_EXCL)) == 0 else { continue }
      var moved = stat()
      if lstat(retiredURL.path, &moved) == 0,
         moved.st_dev == attributes.st_dev, moved.st_ino == attributes.st_ino {
        try? FileManager.default.removeItem(at: retiredURL)
      }
    }
  }

  private static func isMailboxName(_ name: String) -> Bool {
    let suffix = ".json.chat"
    guard name.hasSuffix(suffix) else { return false }
    let stem = String(name.dropLast(suffix.count))
    guard let uuid = UUID(uuidString: stem) else { return false }
    return stem == uuid.uuidString || stem == uuid.uuidString.lowercased()
  }
}
