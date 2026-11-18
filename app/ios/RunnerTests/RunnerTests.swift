import DshEmbeddedNode
import Flutter
import XCTest

final class RunnerTests: XCTestCase {
  // This runs node_start inside the actual iOS Simulator application process.
  // It deliberately never treats a version/capability probe as a DSH boot.
  func testEmbeddedNodeExecutesInsideIOS() throws {
    let root = Bundle(for: DshEmbeddedNode.self)
    let script = try XCTUnwrap(root.path(forResource: "probe", ofType: "cjs"))
    XCTAssertNotNil(root.path(forResource: "meta-probe", ofType: "mjs"))
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: output) }
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
  }
}
