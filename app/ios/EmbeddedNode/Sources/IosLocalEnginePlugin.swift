import Flutter
import Foundation
import UIKit

/// The native probe never announces DSH readiness. A compatible runtime is a
/// prerequisite, not evidence that the DSH profile and native addons booted.
public final class IosLocalEnginePlugin: NSObject, FlutterPlugin {
  // Flutter can register again with another engine, but Node is process-wide.
  private static let shared = IosLocalEnginePlugin()
  // Purge transient files from previous processes before admitting either boot path.
  private let runtimeDirectory = IosLocalEnginePlugin.prepareRuntimeDirectory()
  private var chatMailbox: IosChatMailbox?
  private var officialMailbox: IosOfficialAppMailbox?
  private weak var officialModal: UINavigationController?
  private var flutterGeneration: UUID?
  private var flutterReady = false
  private var flutterStopping = false
  // Reserve the legacy owner before dispatching its asynchronous startup so
  // two Flutter engines or the diagnostic WebKit surface cannot race it.
  private var legacyOwnsChat = false
  private var nodeRunning = false
  private var state = "idle"
  private var reason: String?
  private var report: [String: Any]?
  private var deadline: Date?
  private var reportURL: URL?
  private var timedOut = false

  private override init() { super.init() }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dsh/ios-local", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Own admission for both chat surfaces and the probe on the same main
    // queue, including the native exit callback.
    if !Thread.isMainThread {
      DispatchQueue.main.async { self.handle(call, result: result) }
      return
    }
    switch call.method {
    case "getStatus": result(snapshot())
    case "startProbe":
      ensureNodeStarted()
      result(snapshot())
    case "startChat":
      if flutterGeneration != nil || flutterStopping || officialModal != nil {
        result(Self.chatError("IOS_OFFICIAL_BUSY")); return
      }
      handleChat(.start, call.arguments, result: result)
    case "chatSnapshot": handleChat(.snapshot, call.arguments, result: result)
    case "chatSend": handleChat(.send, call.arguments, result: result)
    case "chatCancel": handleChat(.cancel, call.arguments, result: result)
    case "chatStop": handleChat(.stop, call.arguments, result: result)
    case "chatAnswerApproval": handleChat(.answerApproval, call.arguments, result: result)
    case "openOfficialChat":
      DispatchQueue.main.async { self.openOfficialChat(call.arguments, result: result) }
    case "startOfficialRuntime", "callOfficialRuntime", "stopOfficialRuntime":
      Task { @MainActor in await self.handleOfficialRuntime(call, result: result) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  @MainActor
  private func ownedMailbox() throws -> IosOfficialAppMailbox {
    let resources = Bundle(for: DshEmbeddedNode.self)
    guard resources.url(forResource: "official-app-mailbox", withExtension: "mjs", subdirectory: "dsh-official-app") != nil
      else { throw IosOfficialAppMailbox.Failure.unavailable }
    ensureNodeStarted()
    guard nodeRunning, let reportURL else { throw IosOfficialAppMailbox.Failure.unavailable }
    if let officialMailbox { return officialMailbox }
    let mailbox = try IosOfficialAppMailbox(reportURL: reportURL, runtimeIsRunning: { [weak self] in self?.nodeRunning == true })
    officialMailbox = mailbox
    return mailbox
  }

  @MainActor
  private func handleOfficialRuntime(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    guard let args = call.arguments as? [String: Any] else {
      result(Self.chatError("IOS_OFFICIAL_INVALID_REQUEST")); return
    }
    do {
      switch call.method {
      case "startOfficialRuntime":
        guard Set(args.keys) == ["apiKey", "protocol", "baseUrl", "modelId"],
              let apiKey = args["apiKey"] as? String, let mode = args["protocol"] as? String,
              let baseURL = args["baseUrl"] as? String, let model = args["modelId"] as? String
          else { throw IosOfficialAppMailbox.Failure.invalidFrame }
        guard officialModal == nil, flutterGeneration == nil, !flutterStopping, !legacyOwnsChat
          else { throw IosOfficialAppMailbox.Failure.busy }
        let setup = try IosOfficialAppMailbox.Setup(apiKey: apiKey, channelProtocol: mode, baseURL: baseURL, modelID: model)
        let mailbox = try ownedMailbox()
        let ticket = try mailbox.begin(setup)
        flutterGeneration = ticket
        do {
          try await mailbox.waitUntilReady(ticket)
          guard flutterGeneration == ticket else { throw CancellationError() }
          flutterReady = true
          result(ticket.uuidString.lowercased())
        } catch {
          flutterReady = false
          flutterStopping = true
          flutterGeneration = nil
          try? await mailbox.stop()
          flutterStopping = false
          throw error
        }
      case "callOfficialRuntime":
        guard Set(args.keys) == ["generation", "path", "body"],
              let ticket = args["generation"] as? String, let path = args["path"] as? String,
              let body = args["body"] as? String else { throw IosOfficialAppMailbox.Failure.invalidFrame }
        guard let generation = flutterGeneration, generation.uuidString.lowercased() == ticket,
              flutterReady, !flutterStopping, let mailbox = officialMailbox else { throw CancellationError() }
        let reply = try await mailbox.request(path: path, body: body, generation: generation)
        result(["status": reply.status, "body": reply.body])
      case "stopOfficialRuntime":
        guard Set(args.keys) == ["generation"], let ticket = args["generation"] as? String
          else { throw IosOfficialAppMailbox.Failure.invalidFrame }
        guard let generation = flutterGeneration, generation.uuidString.lowercased() == ticket,
              !flutterStopping, let mailbox = officialMailbox else { throw CancellationError() }
        flutterReady = false
        flutterStopping = true
        defer { flutterStopping = false }
        try await mailbox.stop()
        flutterGeneration = nil
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    } catch is CancellationError {
      result(Self.chatError("IOS_OFFICIAL_GENERATION_STALE"))
    } catch let failure as IosOfficialAppMailbox.Failure {
      let code: String
      switch failure {
      case .key: code = "IOS_CHAT_KEY_INVALID"
      case .channel: code = "IOS_CHAT_CHANNEL_INVALID"
      case .workspace: code = "IOS_OFFICIAL_WORKSPACE_UNAVAILABLE"
      case .busy: code = "IOS_OFFICIAL_BUSY"
      case .timeout: code = "IOS_OFFICIAL_TIMEOUT"
      case .invalidFrame: code = "IOS_OFFICIAL_INVALID_REQUEST"
      case .page, .unavailable: code = "IOS_OFFICIAL_UNAVAILABLE"
      }
      result(Self.chatError(code))
    } catch {
      result(Self.chatError("IOS_OFFICIAL_UNAVAILABLE"))
    }
  }

  @MainActor
  private func openOfficialChat(_ arguments: Any?, result: @escaping FlutterResult) {
    guard arguments == nil || arguments is NSNull else {
      result(Self.chatError("IOS_OFFICIAL_INVALID_REQUEST")); return
    }
    guard flutterGeneration == nil, !flutterStopping, !legacyOwnsChat else {
      result(Self.chatError("IOS_OFFICIAL_BUSY")); return
    }
    if officialModal?.presentingViewController != nil {
      result(nil); return
    }
    let bundle = Bundle(for: DshEmbeddedNode.self)
    guard bundle.url(forResource: "official-app-mailbox", withExtension: "mjs", subdirectory: "dsh-official-app") != nil,
          let resources = try? IosOfficialAppView.Resources(bundle: bundle) else {
      // A missing production package does not activate the runtime or alter
      // the legacy Flutter chat's behavior.
      result(Self.chatError("IOS_OFFICIAL_ASSETS_UNAVAILABLE")); return
    }
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }.flatMap { $0.windows }
    guard let presenter = windows.first(where: \.isKeyWindow)?.rootViewController,
          presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil,
          !presenter.isBeingDismissed else {
      result(Self.chatError("IOS_OFFICIAL_PRESENTATION_UNAVAILABLE")); return
    }
    let page = IosOfficialAppView(resources: resources, getMailbox: { [weak self] in
      guard let self else { throw IosOfficialAppMailbox.Failure.unavailable }
      return try self.ownedMailbox()
    })
    let modal = UINavigationController(rootViewController: page)
    modal.modalPresentationStyle = .fullScreen
    officialModal = modal
    presenter.present(modal, animated: true)
    result(nil)
  }

  private func handleChat(_ method: IosChatMailbox.Method, _ arguments: Any?, result: @escaping FlutterResult) {
    let args: [String: Any]
    if arguments == nil || arguments is NSNull {
      args = [:]
    } else if let dictionary = arguments as? [String: Any] {
      args = dictionary
    } else {
      result(Self.chatError("IOS_CHAT_INVALID_REQUEST"))
      return
    }

    switch IosChatMailbox.parameters(for: method, params: args) {
    case .failure(let failure): result(Self.chatError(failure.code))
    case .success(let params):
      if method == .start {
        guard !legacyOwnsChat else { result(Self.chatError("IOS_OFFICIAL_BUSY")); return }
        ensureNodeStarted()
      }
      if let mailbox = chatMailbox {
        if method == .start { legacyOwnsChat = true }
        mailbox.submit(method, params: params) { [weak self] reply in
          switch reply {
          case .success(let snapshot):
            if method == .stop { self?.legacyOwnsChat = false }
            result(snapshot)
          case .failure(let failure):
            // Keep the reservation on an ambiguous start outcome. Only a
            // confirmed stop or process exit releases this owner.
            result(Self.chatError(failure.code))
          }
        }
      } else if state == "idle" {
        // Chat calls other than start do not start Node.
        switch method {
        case .send: result(Self.chatError("IOS_CHAT_NOT_STARTED"))
        case .answerApproval: result(Self.chatError("IOS_CHAT_APPROVAL_STALE"))
        default:
          result(["state": "stopped", "messages": [], "draft": "", "errorCode": NSNull(), "approval": NSNull()] as [String: Any])
        }
      } else {
        result(Self.chatError("IOS_CHAT_UNAVAILABLE"))
      }
    }
  }

  private static func chatError(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }

  private static func prepareRuntimeDirectory() -> URL? {
    do {
      let support = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
      let directory = support.appendingPathComponent("DeepSeekHarness/RuntimeProbe", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      IosChatMailbox.removeStaleMailboxes(in: directory)
      IosOfficialAppMailbox.removeStaleMailboxes(in: directory)
      return directory
    } catch { return nil }
  }

  private func ensureNodeStarted() {
    guard state == "idle" else { return }
    let resources = Bundle(for: DshEmbeddedNode.self)
    guard let script = resources.path(forResource: "probe", ofType: "cjs"),
          resources.path(forResource: "requirements", ofType: "json") != nil,
          resources.path(forResource: "meta-probe", ofType: "mjs") != nil else {
      state = "error"; reason = "runtime_unavailable"; return
    }
    guard let directory = runtimeDirectory else {
      state = "error"; reason = "probe_failed"; return
    }
    // Never accept a stale report left by an earlier application process. Chat
    // startup is independent of completion or timeout of this diagnostics run.
    let output = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
    chatMailbox = try? IosChatMailbox(reportURL: output)
    reportURL = output
    state = "starting"; deadline = Date().addingTimeInterval(45)
    nodeRunning = DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { [weak self] _ in
      self?.nodeExited()
    }
    if !nodeRunning { nodeExited() }
  }

  private func nodeExited() {
    nodeRunning = false
    legacyOwnsChat = false
    flutterReady = false
    flutterGeneration = nil
    chatMailbox?.invalidate()
    chatMailbox = nil
    state = "error"; reason = "probe_failed"
  }

  private func snapshot() -> [String: Any] {
    if state == "starting", !timedOut, let file = reportURL,
       let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
       let bytes = attributes[.size] as? NSNumber, bytes.intValue <= 65536,
       let data = try? Data(contentsOf: file),
       let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       value["schemaVersion"] as? Int == 1, value["engineReady"] as? Bool == false {
      report = value
      if value["phase"] as? String == "probeReady",
         value["runtimeCompatible"] is Bool,
         let versions = value["versions"] as? [String: Any], versions["node"] is String {
        state = "probeReady"
      } else {
        state = "error"; reason = "probe_failed"
      }
    }
    if state == "starting", let end = deadline, Date() > end {
      timedOut = true; state = "error"; reason = "probe_timeout"
    }
    let versions = report?["versions"] as? [String: Any] ?? [:]
    let compatible = report?["runtimeCompatible"] as? Bool ?? false
    return [
      "state": state, "nodeVersion": versions["node"] as? String ?? "",
      "dshVersion": IosOfficialWebAssets.pinnedEngineVersion() ?? "",
      "requiredNode": IosOfficialWebAssets.pinnedNodeRequirement() ?? "",
      "compatible": compatible, "engineReady": false,
      "reason": reason ?? (state == "probeReady" && !compatible ? "node_capabilities" : ""),
      "report": report ?? [:], "appBackgrounded": UIApplication.shared.applicationState == .background,
    ]
  }
}
