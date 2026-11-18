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
    case "startChat": handleChat(.start, call.arguments, result: result)
    case "chatSnapshot": handleChat(.snapshot, call.arguments, result: result)
    case "chatSend": handleChat(.send, call.arguments, result: result)
    case "chatCancel": handleChat(.cancel, call.arguments, result: result)
    case "chatStop": handleChat(.stop, call.arguments, result: result)
    case "chatAnswerApproval": handleChat(.answerApproval, call.arguments, result: result)
    case "openOfficialChat":
      DispatchQueue.main.async { self.openOfficialChat(call.arguments, result: result) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  @MainActor
  private func openOfficialChat(_ arguments: Any?, result: @escaping FlutterResult) {
    guard arguments == nil || arguments is NSNull else {
      result(Self.chatError("IOS_OFFICIAL_INVALID_REQUEST")); return
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
      self.ensureNodeStarted()
      guard self.nodeRunning, let report = self.reportURL else { throw IosOfficialAppMailbox.Failure.unavailable }
      if let mailbox = self.officialMailbox { return mailbox }
      let mailbox = try IosOfficialAppMailbox(reportURL: report, runtimeIsRunning: { [weak self] in
        self?.nodeRunning == true
      })
      self.officialMailbox = mailbox
      return mailbox
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
      if method == .start { ensureNodeStarted() }
      if let mailbox = chatMailbox {
        mailbox.submit(method, params: params) { reply in
          switch reply {
          case .success(let snapshot): result(snapshot)
          case .failure(let failure): result(Self.chatError(failure.code))
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
      "dshVersion": "0.2.2-rc.3", "requiredNode": ">=24.9.0",
      "compatible": compatible, "engineReady": false,
      "reason": reason ?? (state == "probeReady" && !compatible ? "node_capabilities" : ""),
      "report": report ?? [:], "appBackgrounded": UIApplication.shared.applicationState == .background,
    ]
  }
}
