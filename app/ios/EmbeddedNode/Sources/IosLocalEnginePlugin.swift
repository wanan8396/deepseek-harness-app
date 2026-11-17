import Flutter
import Foundation
import UIKit

/// The native probe never announces DSH readiness. A compatible runtime is a
/// prerequisite, not evidence that the DSH profile and native addons booted.
public final class IosLocalEnginePlugin: NSObject, FlutterPlugin {
  private var state = "idle"
  private var reason: String?
  private var report: [String: Any]?
  private var deadline: Date?
  private var reportURL: URL?
  private var timedOut = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = IosLocalEnginePlugin()
    let channel = FlutterMethodChannel(name: "dsh/ios-local", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus": result(snapshot())
    case "startProbe":
      if state == "idle" { start() }
      result(snapshot())
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start() {
    guard let script = Bundle.main.path(forResource: "probe", ofType: "cjs"),
          Bundle.main.path(forResource: "requirements", ofType: "json") != nil,
          Bundle.main.path(forResource: "meta-probe", ofType: "mjs") != nil else {
      state = "error"; reason = "runtime_unavailable"; return
    }
    do {
      let support = try FileManager.default.url(for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true)
      let directory = support.appendingPathComponent("DeepSeekHarness/RuntimeProbe", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      // Never accept a stale report left by an earlier application process.
      let output = directory.appendingPathComponent(UUID().uuidString + ".json")
      reportURL = output
      state = "starting"; deadline = Date().addingTimeInterval(45)
      let started = DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { [weak self] _ in
        guard let self = self else { return }
        self.state = "error"; self.reason = "probe_failed"
      }
      if !started { state = "error"; reason = "probe_failed" }
    } catch {
      state = "error"; reason = "probe_failed"
    }
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
