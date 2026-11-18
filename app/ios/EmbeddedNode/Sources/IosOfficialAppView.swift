import Darwin
import Foundation
import UIKit
import WebKit

/// The app presents the official WebKit page; this controller owns only the
/// native credential/channel form and the lifetime of that page.
@MainActor
final class IosOfficialAppView: UIViewController {
  struct Resources {
    let assets: IosOfficialWebAssets
    let script: String

    init(bundle: Bundle) throws {
      guard let hook = bundle.url(forResource: "official-web-bridge", withExtension: "js") else {
        throw URLError(.fileDoesNotExist)
      }
      let values = try hook.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink == false,
            let size = values.fileSize, (1...65_536).contains(size) else {
        throw URLError(.cannotDecodeContentData)
      }
      let data = try Data(contentsOf: hook)
      guard data.count == size, let script = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeContentData)
      }
      let directory = bundle.bundleURL.appendingPathComponent("dsh-official-web", isDirectory: true)
      // Reuse the current validated graph schema until the shipped graph expands.
      assets = try IosOfficialWebAssets(previewDirectory: directory)
      self.script = "globalThis.__DSH_IOS_APP_CARRIER__ = true;\n" + script
    }
  }

  private let resources: Resources
  private let getMailbox: () throws -> IosOfficialAppMailbox
  private let form = UIScrollView()
  private let key = UITextField()
  private let channel = UISegmentedControl(items: ["DeepSeek", "OpenAI Chat"])
  private let baseURL = UITextField()
  private let model = UITextField()
  private let connect = UIButton(type: .system)
  private let status = UILabel()
  private var bridge: IosOfficialWebBridge?
  private var mailbox: IosOfficialAppMailbox?
  private var startup: Task<Void, Never>?
  private var finishing = false

  init(resources: Resources, getMailbox: @escaping () throws -> IosOfficialAppMailbox) {
    self.resources = resources
    self.getMailbox = getMailbox
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Official Chat"
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain,
      target: self, action: #selector(close))

    key.isSecureTextEntry = true
    key.keyboardType = .asciiCapable
    baseURL.keyboardType = .URL
    for field in [key, baseURL, model] {
      field.borderStyle = .roundedRect
      field.font = .preferredFont(forTextStyle: .body)
      field.adjustsFontForContentSizeCategory = true
      field.autocorrectionType = .no
      field.autocapitalizationType = .none
      field.spellCheckingType = .no
      field.smartQuotesType = .no
      field.smartDashesType = .no
      field.smartInsertDeleteType = .no
    }
    key.placeholder = "Enter API key"
    channel.selectedSegmentIndex = 0
    channel.accessibilityLabel = "Protocol"
    channel.addTarget(self, action: #selector(channelChanged), for: .valueChanged)
    baseURL.text = "https://api.deepseek.com/anthropic"
    model.text = "deepseek-flash"
    var button = UIButton.Configuration.filled()
    button.title = "Open Chat"
    connect.configuration = button
    connect.addTarget(self, action: #selector(start), for: .touchUpInside)
    status.font = .preferredFont(forTextStyle: .footnote)
    status.adjustsFontForContentSizeCategory = true
    status.textColor = .secondaryLabel
    status.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [field("API key", key), field("Protocol", channel),
      field("HTTPS base URL", baseURL), field("Model ID", model), connect, status])
    stack.axis = .vertical
    stack.spacing = 16
    form.keyboardDismissMode = .interactive
    form.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(form)
    form.addSubview(stack)
    NSLayoutConstraint.activate([
      form.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      form.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      form.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      form.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: form.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: form.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.leadingAnchor.constraint(equalTo: form.contentLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: form.contentLayoutGuide.trailingAnchor, constant: -20),
      stack.widthAnchor.constraint(equalTo: form.frameLayoutGuide.widthAnchor, constant: -40),
    ])
  }

  private func field(_ title: String, _ input: UIView) -> UIStackView {
    let label = UILabel()
    label.text = title
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.adjustsFontForContentSizeCategory = true
    label.isAccessibilityElement = false
    input.accessibilityLabel = title
    let field = UIStackView(arrangedSubviews: [label, input])
    field.axis = .vertical
    field.spacing = 6
    return field
  }

  @objc private func channelChanged() {
    let deepSeekURL = "https://api.deepseek.com/anthropic"
    let openAIURL = "https://api.openai.com/v1"
    if baseURL.text?.isEmpty != false || baseURL.text == deepSeekURL || baseURL.text == openAIURL {
      baseURL.text = channel.selectedSegmentIndex == 0 ? deepSeekURL : openAIURL
    }
    if model.text?.isEmpty != false || model.text == "deepseek-flash" || model.text == "gpt-4.1-mini" {
      model.text = channel.selectedSegmentIndex == 0 ? "deepseek-flash" : "gpt-4.1-mini"
    }
  }

  @objc private func start() {
    guard startup == nil, !finishing, bridge == nil else { return }
    // Never capture the key in the asynchronous task, a JS string, or argv.
    defer { key.text = nil }
    do {
      let setup = try IosOfficialAppMailbox.Setup(apiKey: key.text ?? "",
        channelProtocol: channel.selectedSegmentIndex == 0 ? "deepseek" : "openai-chat",
        baseURL: baseURL.text ?? "", modelID: model.text ?? "")
      let mailbox = try getMailbox()
      let generation = try mailbox.begin(setup)
      self.mailbox = mailbox
      view.endEditing(true)
      setFormEnabled(false)
      status.text = "Starting Official Chat…"
      startup = Task {
        do {
          try await mailbox.waitUntilReady(generation)
          try Task.checkCancellation()
          showPage(mailbox, generation: generation)
          let deadline = ProcessInfo.processInfo.systemUptime + 20
          while bridge?.isReady != true {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw IosOfficialAppMailbox.Failure.page }
            try await Task.sleep(nanoseconds: 50_000_000)
          }
          startup = nil
        } catch {
          guard !Task.isCancelled else { return }
          finishPage(dismiss: false, message: Self.message(for: error))
        }
      }
    } catch {
      status.text = Self.message(for: error)
    }
  }

  private func setFormEnabled(_ enabled: Bool) {
    for control in [key, channel, baseURL, model, connect] as [UIControl] { control.isEnabled = enabled }
  }

  private func showPage(_ mailbox: IosOfficialAppMailbox, generation: UUID) {
    let bridge = IosOfficialWebBridge(assets: resources.assets, documentStartScript: resources.script,
      handler: { operation, page in
        switch operation {
        case .request(let request): return try await mailbox.request(request, generation: generation, page: page)
        }
      }, onInvalidate: { [weak self] page in
        mailbox.invalidate(page: page, generation: generation)
        if self?.bridge?.navigationFailure != nil {
          self?.finishPage(dismiss: false, message: Self.message(for: IosOfficialAppMailbox.Failure.page))
        }
      })
    self.bridge = bridge
    let web = bridge.webView!
    web.translatesAutoresizingMaskIntoConstraints = false
    form.isHidden = true
    view.addSubview(web)
    NSLayoutConstraint.activate([
      web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Set Channel", style: .plain,
      target: self, action: #selector(setChannel))
    bridge.load()
  }

  @objc private func close() { finishPage(dismiss: true) }
  @objc private func setChannel() { finishPage(dismiss: false) }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || navigationController?.isBeingDismissed == true {
      finishPage(dismiss: false)
    }
  }

  private func finishPage(dismiss: Bool, message: String? = nil) {
    guard !finishing else { return }
    finishing = true
    startup?.cancel()
    startup = nil
    key.text = nil
    view.endEditing(true)
    navigationItem.leftBarButtonItem?.isEnabled = false
    navigationItem.rightBarButtonItem?.isEnabled = false
    setFormEnabled(false)
    if mailbox != nil {
      // Keep the page alive briefly for its stream close commands. Native stop
      // below is the authoritative cleanup even if WebKit never responds.
      Task {
        if let bridge, bridge.isReady {
          bridge.webView.evaluateJavaScript("void window.__iosOfficialBridgeClose?.();", completionHandler: nil)
          try? await Task.sleep(nanoseconds: 350_000_000)
        }
        bridge?.invalidate()
        bridge?.webView.stopLoading()
        bridge?.webView.removeFromSuperview()
        bridge = nil
        form.isHidden = false
        status.text = "Closing the previous channel…"
        var finalMessage = message
        do { try await mailbox?.stop() }
        catch { finalMessage = Self.message(for: error) }
        mailbox = nil
        finishUI(dismiss: dismiss, message: finalMessage)
      }
    } else {
      finishUI(dismiss: dismiss, message: message)
    }
  }

  private func finishUI(dismiss: Bool, message: String?) {
    navigationItem.rightBarButtonItem = nil
    if dismiss {
      self.dismiss(animated: true)
    } else {
      finishing = false
      navigationItem.leftBarButtonItem?.isEnabled = true
      setFormEnabled(true)
      status.text = message
    }
  }

  private static func message(for error: Error) -> String {
    switch error as? IosOfficialAppMailbox.Failure {
    case .key: return "Enter a valid API key."
    case .channel: return "Enter a valid HTTPS base URL and model ID."
    case .workspace: return "The private app workspace is unavailable."
    case .busy: return "The previous channel is still closing. Try again in a moment."
    case .page: return "The official page did not load. Try opening it again."
    case .timeout: return "The local runtime did not respond in time. Try again or reopen the app."
    default: return "Official Chat could not start on this device."
    }
  }
}

/// Swift/Node carrier. The only writable scope is the private generation
/// transport directory next to the shared probe report, never the AppState.
@MainActor
final class IosOfficialAppMailbox {
  enum Failure: Error { case key, channel, workspace, busy, page, timeout, unavailable, invalidFrame }

  struct Setup: Encodable {
    private struct Channel: Encodable {
      let `protocol`: String
      let baseUrl: String
      let modelId: String
    }
    private let apiKey: String
    private let channel: Channel

    init(apiKey: String, channelProtocol: String, baseURL: String, modelID: String) throws {
      let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (1...1024).contains(key.utf8.count), key.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
        throw Failure.key
      }
      let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
      let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
      guard ["deepseek", "openai-chat"].contains(channelProtocol), (1...2048).contains(base.utf16.count),
            (1...256).contains(model.utf16.count), base.rangeOfCharacter(from: forbidden) == nil,
            model.rangeOfCharacter(from: forbidden) == nil, !base.contains("\\"),
            let url = URLComponents(string: base), url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil, !base.contains(key), !model.contains(key) else {
        throw Failure.channel
      }
      self.apiKey = key
      channel = Channel(protocol: channelProtocol, baseUrl: base, modelId: model)
    }
  }

  private struct Request: Encodable {
    let path: String
    let method: String
    let headers: [[String]]
    let body: String
  }

  private struct Response: Decodable {
    let status: Int
    let headers: [[String]]?
    let body: String
  }

  private struct Ready: Decodable {
    let ok: Bool
    let code: String?
  }

  private static let startName = "official-start.json"
  private static let readyName = "official-ready.json"
  private static let stopName = "official-stop"
  private static let stoppedName = "official-stopped"
  private static let maxTextBytes = 256 * 1024
  private static let maxFrameBytes = 6 * maxTextBytes + 1024
  private static let one = Data("1".utf8)
  private let directory: Int32
  private let path: URL
  private let runtimeIsRunning: () -> Bool
  private var generation: UUID?
  private var pageReady = false
  private var needsStop = false
  private var stopSent = false
  private var invalidatedPage: UInt64 = 0
  private var inFlight = 0

  init(reportURL: URL, runtimeIsRunning: @escaping () -> Bool) throws {
    var path = reportURL.appendingPathExtension("official")
    guard reportURL.isFileURL, reportURL.path.hasPrefix("/"), Self.isOfficialDirectory(path.lastPathComponent),
          mkdir(path.path, 0o700) == 0 || errno == EEXIST else { throw Failure.unavailable }
    let fd = Darwin.open(path.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure.unavailable }
    do {
      var info = stat()
      guard fstat(fd, &info) == 0, Self.isPrivateDirectory(info) else { throw Failure.unavailable }
      var excluded = URLResourceValues()
      excluded.isExcludedFromBackup = true
      try path.setResourceValues(excluded)
    } catch {
      Darwin.close(fd)
      throw Failure.unavailable
    }
    directory = fd
    self.path = path
    self.runtimeIsRunning = runtimeIsRunning
  }

  deinit { Darwin.close(directory) }

  func begin(_ setup: Setup) throws -> UUID {
    guard runtimeIsRunning() else { throw Failure.unavailable }
    if needsStop, stopSent { _ = try settleStop() }
    guard !needsStop else { throw Failure.busy }
    // The previous generation is settled. Discard its control replies before
    // admitting this credential frame, never while a stop is in flight.
    remove(Self.readyName)
    remove(Self.stoppedName)
    var data = try JSONEncoder().encode(setup)
    defer { data.resetBytes(in: 0..<data.count) }
    guard data.count <= 16 * 1024 else { throw Failure.channel }
    try publish(data, to: Self.startName)
    let ticket = UUID()
    needsStop = true
    stopSent = false
    pageReady = false
    invalidatedPage = 0
    generation = ticket
    return ticket
  }

  func waitUntilReady(_ generation: UUID) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    defer { if self.generation == generation { remove(Self.startName) } }
    while true {
      try check(generation, deadline: deadline)
      if let bytes = try read(Self.readyName, limit: 1024) {
        let ready = try JSONDecoder().decode(Ready.self, from: bytes)
        guard ready.ok else {
          switch ready.code {
          case "IOS_CHAT_KEY_INVALID": throw Failure.key
          case "IOS_CHAT_CHANNEL_INVALID": throw Failure.channel
          case "IOS_OFFICIAL_WORKSPACE_UNAVAILABLE": throw Failure.workspace
          default: throw Failure.unavailable
          }
        }
        pageReady = true
        return
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func invalidate(page: UInt64, generation: UUID) {
    guard self.generation == generation else { return }
    invalidatedPage = max(invalidatedPage, page)
  }

  func request(_ request: IosOfficialWebBridge.HTTPRequest, generation: UUID,
               page: UInt64) async throws -> IosOfficialWebBridge.Reply {
    let deadline = ProcessInfo.processInfo.systemUptime + 35
    try check(generation, deadline: deadline)
    guard pageReady, page > invalidatedPage, inFlight < 16 else { throw Failure.busy }
    guard request.method == "POST", let bytes = request.body, bytes.count <= Self.maxTextBytes,
          let body = String(data: bytes, encoding: .utf8), request.headers.contains(where: { header in
            let mediaType = header.value.split(separator: ";").first?.trimmingCharacters(in: .whitespaces)
            return header.name.lowercased() == "content-type" && mediaType?.lowercased() == "application/json"
          }) else { throw Failure.invalidFrame }
    let headers = request.headers.map { [$0.name, $0.value] }
    guard Self.validHeaders(headers) else { throw Failure.invalidFrame }
    let data = try JSONEncoder().encode(Request(path: request.pathAndQuery, method: request.method,
      headers: headers, body: body))
    guard data.count <= Self.maxFrameBytes else { throw Failure.invalidFrame }
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let call = "official-call-\(id).json"
    let reply = "official-reply-\(id).json"
    try publish(data, to: call)
    inFlight += 1
    defer {
      inFlight -= 1
      remove(call)
      remove(reply)
    }
    while true {
      try check(generation, deadline: deadline)
      guard page > invalidatedPage else { throw CancellationError() }
      if let bytes = try read(reply, limit: Self.maxFrameBytes) {
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        let headers = response.headers ?? [["content-type", "application/json"]]
        guard (200...599).contains(response.status), response.body.utf8.count <= Self.maxTextBytes,
              Self.validHeaders(headers) else { throw Failure.invalidFrame }
        return .response(.init(status: response.status, headers: headers.map { .init(name: $0[0], value: $0[1]) },
          body: Data(response.body.utf8)))
      }
      // Each lane suspends independently; a stream pull does not block a close
      // command, a second stream or a unary request.
      try await Task.sleep(nanoseconds: 25_000_000)
    }
  }

  func stop() async throws {
    guard needsStop else { return }
    generation = nil
    pageReady = false
    remove(Self.startName)
    if !runtimeIsRunning() {
      cleanLanes()
      needsStop = false
      return
    }
    if !stopSent {
      try publish(Self.one, to: Self.stopName)
      stopSent = true
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 8
    while try !settleStop() {
      guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timeout }
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  private func settleStop() throws -> Bool {
    guard let ack = try read(Self.stoppedName, limit: 1) else { return false }
    guard ack == Self.one else { throw Failure.invalidFrame }
    cleanLanes()
    needsStop = false
    return true
  }

  private func check(_ generation: UUID, deadline: TimeInterval) throws {
    try Task.checkCancellation()
    guard generation == self.generation else { throw CancellationError() }
    guard runtimeIsRunning() else { throw Failure.unavailable }
    guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timeout }
  }

  private static func validHeaders(_ headers: [[String]]) -> Bool {
    headers.count <= 32 && headers.allSatisfy { pair in
      pair.count == 2 && (1...128).contains(pair[0].utf8.count) && pair[1].utf8.count <= 4096
        && pair.allSatisfy { !$0.contains("\r") && !$0.contains("\n") && !$0.contains("\0") }
    }
  }

  private func publish(_ data: Data, to name: String) throws {
    let temporary = ".official-\(UUID().uuidString.lowercased()).tmp"
    let fd = Darwin.openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw Failure.unavailable }
    let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { remove(temporary) }
    guard fchmod(fd, 0o600) == 0 else { throw Failure.unavailable }
    try output.write(contentsOf: data)
    try output.close()
    // Only complete 0600 files become visible, inside the no-backup directory.
    guard renameatx_np(directory, temporary, directory, name, UInt32(RENAME_EXCL)) == 0 else {
      throw Failure.unavailable
    }
  }

  private func read(_ name: String, limit: Int) throws -> Data? {
    let fd = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    if fd < 0, errno == ENOENT { return nil }
    guard fd >= 0 else { throw Failure.invalidFrame }
    let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? input.close() }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          info.st_mode & 0o7777 == 0o600, info.st_uid == geteuid(), (1...2).contains(info.st_nlink),
          info.st_size > 0, info.st_size <= off_t(limit),
          let data = try input.read(upToCount: limit + 1), data.count == Int(info.st_size) else {
      throw Failure.invalidFrame
    }
    return data
  }

  private func remove(_ name: String) { _ = unlinkat(directory, name, 0) }

  private func cleanLanes() {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: path.path) else { return }
    for name in names where name.range(of: #"\Aofficial-(call|reply)-[0-9a-f]{32}\.json\z"#,
                                       options: .regularExpression) != nil {
      remove(name)
    }
  }

  private nonisolated static func isOfficialDirectory(_ name: String) -> Bool {
    let suffix = ".json.official"
    guard name.hasSuffix(suffix) else { return false }
    let stem = String(name.dropLast(suffix.count))
    return UUID(uuidString: stem)?.uuidString.lowercased() == stem
  }

  private nonisolated static func isPrivateDirectory(_ info: stat) -> Bool {
    info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) && info.st_uid == geteuid() && info.st_mode & 0o7777 == 0o700
  }

  /// Clear abandoned credential frames after process termination, strictly in
  /// private per-report transport directories owned by this app user.
  nonisolated static func removeStaleMailboxes(in parent: URL) {
    let fd = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { return }
    defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, isPrivateDirectory(info),
          let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
    for name in names where isOfficialDirectory(name) {
      guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0, isPrivateDirectory(info) else { continue }
      let retired = UUID().uuidString.lowercased() + ".json.official"
      guard renameatx_np(fd, name, fd, retired, UInt32(RENAME_EXCL)) == 0 else { continue }
      let url = parent.appendingPathComponent(retired, isDirectory: true)
      var moved = stat()
      if lstat(url.path, &moved) == 0, moved.st_dev == info.st_dev, moved.st_ino == info.st_ino {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }
}
