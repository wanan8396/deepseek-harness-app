import DshEmbeddedNode
import Flutter
import XCTest

final class RunnerTests: XCTestCase {
  // This runs node_start inside the actual iOS Simulator application process.
  // It deliberately never treats a version/capability probe as a DSH boot.
  func testEmbeddedNodeExecutesInsideIOS() throws {
    let root = Bundle(for: DshEmbeddedNode.self)
    let probe = try XCTUnwrap(root.path(forResource: "probe", ofType: "cjs"))
    XCTAssertNotNil(root.path(forResource: "meta-probe", ofType: "mjs"))
    let testFile = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "chat-ci-entry", withExtension: "cjs"))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let script = directory.appendingPathComponent("chat-ci-entry.cjs").path
    try FileManager.default.copyItem(at: testFile, to: URL(fileURLWithPath: script))
    try probe.write(to: directory.appendingPathComponent("probe-path.txt"), atomically: true, encoding: .utf8)
    let output = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
    let mailbox = try IosChatMailbox(reportURL: output)
    XCTAssertTrue(DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { code in
      XCTFail("Node runtime exited unexpectedly: \(code)")
    })
    let ready = expectation(description: "Actual embedded JavaScript wrote its report")
    let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
      guard FileManager.default.fileExists(atPath: output.path) else { return }
      timer.invalidate(); ready.fulfill()
    }
    wait(for: [ready], timeout: 45)
    timer.invalidate()
    let data = try Data(contentsOf: output)
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = "embedded-node-capability-report.json"
    attachment.lifetime = .keepAlways
    add(attachment)
    let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let versions = try XCTUnwrap(value["versions"] as? [String: Any])
    XCTAssertEqual(versions["node"] as? String, "24.22.1")
    XCTAssertEqual(value["schemaVersion"] as? Int, 1)
    XCTAssertEqual(value["phase"] as? String, "probeReady")
    XCTAssertEqual(value["engineReady"] as? Bool, false)
    XCTAssertEqual(value["runtimeCompatible"] as? Bool, true,
      "Embedded Node is missing required APIs: \(value["missing"] ?? "unknown")")
    let capabilities = try XCTUnwrap(value["capabilities"] as? [String: Any])
    for key in ["filesystemWriteRead", "getBuiltinModule", "sqlite", "sqliteFts5", "intl",
                "importMetaMain", "importMetaFilename", "importMetaDirname"] {
      XCTAssertEqual(capabilities[key] as? Bool, true, "Required API failed: \(key)")
    }
    let loader = try XCTUnwrap(value["loader"] as? [String: Any])
    for key in ["dshLoaderBooted", "serviceVerified", "disposeVerified", "badBaselineRejected"] {
      XCTAssertEqual(loader[key] as? Bool, true, "DSH Loader gate failed: \(key), stage=\(loader["stage"] ?? "unknown")")
    }
    XCTAssertEqual(loader["engineReady"] as? Bool, false)
    XCTAssertEqual(loader["stage"] as? String, "complete")
    let core = try XCTUnwrap(value["core"] as? [String: Any])
    for key in ["coreBooted", "servicesVerified", "firstTurnStreamed", "secondTurnHistoryVerified",
                "cancellationSettled", "errorSettled", "disposeVerified", "badBaselineRejected"] {
      XCTAssertEqual(core[key] as? Bool, true, "DSH core gate failed: \(key), stage=\(core["stage"] ?? "unknown")")
    }
    XCTAssertEqual(core["ephemeral"] as? Bool, true)
    XCTAssertEqual(core["engineReady"] as? Bool, false)
    XCTAssertEqual(core["stage"] as? String, "complete")
    let persistence = try XCTUnwrap(value["persistence"] as? [String: Any])
    for key in ["storageBooted", "writerExclusionVerified", "readWhileOwnedVerified", "atomicAppendVerified",
                "flushVerified", "coldResumeVerified", "disposeVerified", "badBaselineRejected"] {
      XCTAssertEqual(persistence[key] as? Bool, true,
        "DSH persistence gate failed: \(key), stage=\(persistence["stage"] ?? "unknown")")
    }
    XCTAssertEqual(persistence["engineReady"] as? Bool, false)
    XCTAssertEqual(persistence["modelKind"] as? String, "offline-fixture")
    XCTAssertEqual(persistence["persistentStore"] as? Bool, true)
    XCTAssertEqual(persistence["stage"] as? String, "complete")
    // A second call must not initialize another V8 runtime in this process.
    XCTAssertFalse(DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { _ in })

    // The production Swift mailbox and actual AgentLoop/DeepSeek adapter run
    // in this same process. Only the outbound fetch response is a test fixture.
    let apiKey = "ci-test-only-not-a-credential"
    XCTAssertEqual(try request(mailbox, .snapshot)["state"] as? String, "stopped")
    XCTAssertEqual(try request(mailbox, .start, apiKey)["state"] as? String, "ready")
    XCTAssertEqual(try request(mailbox, .send, "chat-ci-first")["state"] as? String, "running")
    let streaming = try waitForChat(mailbox) { $0["draft"] as? String == "ci-provider-stream-" }
    XCTAssertEqual(streaming["state"] as? String, "running")
    let settled = try waitForChat(mailbox) { $0["state"] as? String == "ready" }
    let history = [["role": "user", "text": "chat-ci-first"],
      ["role": "assistant", "text": "ci-provider-stream-complete"]]
    XCTAssertEqual(settled["messages"] as? [[String: String]], history)
    XCTAssertTrue(settled["errorCode"] is NSNull)
    XCTAssertEqual(try request(mailbox, .stop)["state"] as? String, "stopped")
    XCTAssertEqual(try request(mailbox, .start, apiKey)["messages"] as? [[String: String]], history)
    XCTAssertEqual(try request(mailbox, .send, "chat-ci-resumed")["state"] as? String, "running")
    let resumed = try waitForChat(mailbox) { $0["state"] as? String == "ready" }
    XCTAssertEqual(resumed["messages"] as? [[String: String]], history + [
      ["role": "user", "text": "chat-ci-resumed"],
      ["role": "assistant", "text": "ci-provider-stream-complete"],
    ])
    _ = try request(mailbox, .send, "chat-ci-cancel")
    _ = try waitForChat(mailbox) { $0["draft"] as? String == "ci-provider-stream-" }
    let cancelled = try request(mailbox, .cancel)
    XCTAssertEqual(cancelled["state"] as? String, "ready")
    XCTAssertEqual(cancelled["draft"] as? String, "")
    _ = try request(mailbox, .send, "chat-ci-auth-error")
    let failed = try waitForChat(mailbox) { $0["state"] as? String == "ready" }
    XCTAssertEqual(failed["errorCode"] as? String, "IOS_CHAT_AUTH_FAILED")
    XCTAssertFalse(String(describing: failed).contains(apiKey))
    XCTAssertEqual(try request(mailbox, .stop)["state"] as? String, "stopped")
  }

  private func request(_ mailbox: IosChatMailbox, _ method: IosChatMailbox.Method,
                       _ value: String? = nil) throws -> [String: Any] {
    let done = expectation(description: "chat mailbox reply")
    var response: Result<[String: Any], IosChatMailbox.Failure>?
    mailbox.request(method, value: value) { reply in
      response = reply
      done.fulfill()
    }
    wait(for: [done], timeout: 30)
    return try XCTUnwrap(response).get()
  }

  private func waitForChat(_ mailbox: IosChatMailbox,
                           until predicate: ([String: Any]) -> Bool) throws -> [String: Any] {
    let deadline = ProcessInfo.processInfo.systemUptime + 10
    var last: [String: Any] = [:]
    repeat {
      last = try request(mailbox, .snapshot)
      if predicate(last) { return last }
    } while ProcessInfo.processInfo.systemUptime < deadline
    XCTFail("Chat state not observed: \(last["state"] ?? "unknown") \(last["errorCode"] ?? "none")")
    return last
  }
}
