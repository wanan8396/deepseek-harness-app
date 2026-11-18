import Flutter
import Foundation
import UIKit

/// The native probe never announces DSH readiness. A compatible runtime is a
/// prerequisite, not evidence that the DSH profile and native addons booted.
public final class IosLocalEnginePlugin: NSObject, FlutterPlugin {
  // Flutter can register again with another engine, but Node is process-wide.
  private static let shared = IosLocalEnginePlugin()
  private lazy var runtimeDirectory = Self.prepareRuntimeDirectory()
  private var chatMailbox: IosChatMailbox?
  private var state = "idle"
  private var reason: String?
  private var report: [String: Any]?
  private var deadline: Date?
  private var reportURL: URL?
  private var timedOut = false

  private override init() { super.init() }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = shared
    _ = plugin.runtimeDirectory // Clean old transient inputs once, before any Node boot.
    let channel = FlutterMethodChannel(name: "dsh/ios-local", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Own probe and chat-start admission on the same main queue, including the
    // native exit callback. Mailbox polling and file exchange run off-main.
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
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func handleChat(_ method: IosChatMailbox.Method, _ arguments: Any?, result: @escaping FlutterResult) {
    let value: String?
    switch method {
    case .start, .send:
      let name = method == .start ? "apiKey" : "text"
      guard let args = arguments as? [String: Any], args.count == 1, let text = args[name] as? String else {
        result(Self.chatError("IOS_CHAT_INVALID_REQUEST"))
        return
      }
      value = text
    case .snapshot, .cancel, .stop:
      guard arguments == nil || arguments is NSNull || (arguments as? [String: Any])?.isEmpty == true else {
        result(Self.chatError("IOS_CHAT_INVALID_REQUEST"))
        return
      }
      value = nil
    }

    switch IosChatMailbox.parameters(for: method, value: value) {
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
        // Looking at chat or stopping an unopened chat does not start Node.
        if method == .send { result(Self.chatError("IOS_CHAT_NOT_STARTED")) }
        else { result(["state": "stopped", "messages": [], "draft": "", "errorCode": NSNull()] as [String: Any]) }
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
    let started = DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { [weak self] _ in
      self?.nodeExited()
    }
    if !started { nodeExited() }
  }

  private func nodeExited() {
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
