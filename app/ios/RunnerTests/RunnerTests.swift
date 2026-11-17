import DshEmbeddedNode
import Flutter
import XCTest

final class RunnerTests: XCTestCase {
  // This runs node_start inside the actual iOS Simulator application process.
  // It deliberately never treats a version/capability probe as a DSH boot.
  func testEmbeddedNodeExecutesInsideIOS() throws {
    let root = Bundle.main
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
    let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
    let versions = try XCTUnwrap(value["versions"] as? [String: Any])
    XCTAssertEqual(versions["node"] as? String, "24.22.1")
    XCTAssertEqual(value["schemaVersion"] as? Int, 1)
    XCTAssertEqual(value["phase"] as? String, "probeReady")
    XCTAssertEqual(value["engineReady"] as? Bool, false)
    XCTAssertNotNil(value["runtimeCompatible"] as? Bool)
    XCTAssertNotNil(value["capabilities"] as? [String: Any])
    // A second call must not initialize another V8 runtime in this process.
    XCTAssertFalse(DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { _ in })
  }
}
