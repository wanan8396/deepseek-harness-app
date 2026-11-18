import DshEmbeddedNode
import Flutter
import WebKit
import XCTest

private final class WebAssetNavigation: NSObject, WKNavigationDelegate {
  let loaded: XCTestExpectation
  var error: Error?
  init(_ loaded: XCTestExpectation) { self.loaded = loaded }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    self.error = error; loaded.fulfill()
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    self.error = error; loaded.fulfill()
  }
}

final class RunnerTests: XCTestCase {
  // This runs node_start inside the actual iOS Simulator application process.
  // It deliberately never treats a version/capability probe as a DSH boot.
  @MainActor
  func testEmbeddedNodeExecutesInsideIOS() async throws {
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
    let hostBundle = Bundle(for: Self.self).bundleURL.appendingPathComponent("dsh-official-host-ci", isDirectory: true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: hostBundle.appendingPathComponent("official-host.mjs").path))
    try hostBundle.path.write(to: directory.appendingPathComponent("official-host-path.txt"), atomically: true, encoding: .utf8)
    let output = directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
    let mailbox = try IosChatMailbox(reportURL: output)
    // Start the real page before Node's cold initialization. On a loaded CI
    // runner WebKit's first GPU process took over 13 seconds to launch.
    let bridge = try await startOfficialWebSessionPage(directory)
    defer { bridge.invalidate() }
    XCTAssertTrue(DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { code in
      XCTFail("Node runtime exited unexpectedly: \(code)")
    })
    let reportDeadline = ProcessInfo.processInfo.systemUptime + 45
    while !FileManager.default.fileExists(atPath: output.path) && ProcessInfo.processInfo.systemUptime < reportDeadline {
      try await Task.sleep(for: .milliseconds(100))
    }
    _ = try XCTUnwrap(FileManager.default.fileExists(atPath: output.path) ? true : nil,
      "Embedded Node did not write its probe report")
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

    // Same on-device engine, now using a custom HTTPS Chat Completions route.
    let custom: [String: Any] = ["apiKey": apiKey, "protocol": "openai-chat",
      "baseUrl": "https://models.example/v1", "modelId": "fixture-model"]
    XCTAssertEqual(try request(mailbox, .start, params: custom)["state"] as? String, "ready")
    _ = try request(mailbox, .send, "chat-ci-workspace-allow")
    let waiting = try waitForChat(mailbox) { $0["approval"] is [String: Any] }
    let approval = try XCTUnwrap(waiting["approval"] as? [String: Any])
    let file = directory.appendingPathComponent("ChatData/Workspace/allowed.txt")
    let expectedText = "fixture 雪🧪\nsecond line\n"
    XCTAssertEqual(approval["toolName"] as? String, "workspace_create_text")
    XCTAssertEqual(approval["path"] as? String, "allowed.txt")
    XCTAssertEqual(approval["preview"] as? String, expectedText)
    XCTAssertEqual(approval["byteLength"] as? Int, expectedText.utf8.count)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    let id = try XCTUnwrap(approval["id"] as? String)
    _ = try request(mailbox, .answerApproval, params: ["id": id, "allowed": true])
    let toolTurn = try waitForChat(mailbox, seconds: 25) { $0["state"] as? String == "ready" }
    XCTAssertTrue(toolTurn["errorCode"] is NSNull, "Tool turn error: \(toolTurn["errorCode"] ?? "missing")")
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), expectedText, "Approved workspace file differs")
    let toolMessages = try XCTUnwrap(toolTurn["messages"] as? [[String: String]])
    XCTAssertTrue(toolMessages.contains { $0["role"] == "assistant" && $0["text"] == "ci-workspace-tools-complete" },
      "Model did not complete the workspace tool sequence: \(toolMessages)")
    let decoded = try toolMessages.filter { $0["role"] == "tool" }.compactMap { message -> [String: Any]? in
      guard let text = message["text"] else { return nil }
      return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }
    XCTAssertTrue(decoded.contains { $0["path"] as? String == "allowed.txt" && $0["text"] as? String == expectedText })
    XCTAssertEqual(try request(mailbox, .stop)["state"] as? String, "stopped")

    let chatEvidence: [String: Any] = [
      "modelTransport": "synthetic-https-response", "bridge": "swift-private-file-mailbox",
      "officialAdapterVerified": true, "inProcessChatVerified": true, "cancellationVerified": true,
      "closeReopenVerified": true, "authFailureVerified": true, "liveModelVerified": false,
      "customCompletionsVerified": true, "approvedWorkspaceToolCallVerified": true,
    ]
    let evidence = XCTAttachment(data: try JSONSerialization.data(withJSONObject: chatEvidence),
      uniformTypeIdentifier: "public.json")
    evidence.name = "embedded-ios-chat-verification.json"
    evidence.lifetime = .keepAlways
    add(evidence)

    try await verifyOfficialWebSessionRPC(directory, bridge: bridge)
  }

  @MainActor
  private func startOfficialWebSessionPage(_ directory: URL) async throws -> IosOfficialWebBridge {
    let requestURL = directory.appendingPathComponent("official-rpc-request.json")
    let replyURL = directory.appendingPathComponent("official-rpc-response.json")
    let errorURL = directory.appendingPathComponent("official-host-ci-error")
    let script = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "official-web-bridge", withExtension: "js"))
    let assets = IosOfficialWebAssets()
    var busy = false
    let bridge = IosOfficialWebBridge(assets: assets,
      documentStartScript: try String(contentsOf: script, encoding: .utf8), handler: { operation, _ in
      guard !busy else { throw URLError(.resourceUnavailable) }
      busy = true
      defer { busy = false }
      switch operation {
      case .request(let request):
        let body = try XCTUnwrap(request.body.flatMap { String(data: $0, encoding: .utf8) })
        try JSONSerialization.data(withJSONObject: ["path": request.pathAndQuery, "body": body])
          .write(to: requestURL, options: .atomic)
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while ProcessInfo.processInfo.systemUptime < deadline {
          if let failure = try? String(contentsOf: errorURL, encoding: .utf8) {
            throw NSError(domain: "OfficialHostCI", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])
          }
          if let data = try? Data(contentsOf: replyURL) {
            try FileManager.default.removeItem(at: replyURL)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let status = try XCTUnwrap(result["status"] as? Int)
            let body = try XCTUnwrap(result["body"] as? String)
            return .response(.init(status: status,
              headers: [.init(name: "content-type", value: "application/json")], body: Data(body.utf8)))
          }
          try await Task.sleep(for: .milliseconds(25))
        }
        throw URLError(.timedOut)
      }
    })
    bridge.load()
    let deadline = ProcessInfo.processInfo.systemUptime + 35
    while !bridge.isReady && ProcessInfo.processInfo.systemUptime < deadline {
      if let error = bridge.navigationFailure { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(bridge.isReady ? true : nil,
      "App bootstrap document did not commit; served=\(assets.servedPaths.sorted()), URL=\(String(describing: bridge.webView.url))")
    // The scheme response can commit before document-start scripts execute.
    let transport = try await pageResult(bridge.webView, "return typeof globalThis.__DSH_TRANSPORT__?.openStream === 'function';")
    XCTAssertEqual(transport as? Bool, true)
    return bridge
  }

  @MainActor
  private func verifyOfficialWebSessionRPC(_ directory: URL, bridge: IosOfficialWebBridge) async throws {
    let requestURL = directory.appendingPathComponent("official-rpc-request.json")
    let errorURL = directory.appendingPathComponent("official-host-ci-error")
    let raw = try await pageResult(bridge.webView, """
      let count = 0;
      async function rpc(method, args) {
        const rpcId = 'ios-web-test-' + ++count;
        const response = await window.__DSH_TRANSPORT__.fetch('api/' + method, {
          method: 'POST', headers: {'content-type': 'application/json'},
          body: JSON.stringify({type: 'client-request', rpcId, method, payload: {args}}),
        });
        if (!response.ok) throw new Error(method + ': HTTP ' + response.status);
        const reply = await response.json();
        if (reply.type !== 'server-response' || reply.rpcId !== rpcId || !reply.result?.ok) {
          throw new Error(method + ': ' + JSON.stringify(reply.result));
        }
        return reply.result.value;
      }
      const first = await rpc('session/create', {request: {}});
      const second = await rpc('session/create', {request: {}});
      const list = await rpc('session/list', {_request: {}});
      const controller = new AbortController();
      const iterator = window.__DSH_TRANSPORT__.openStream('session/follow', {
        args: {request: {address: {kind: 'session', sessionId: first.sessionId}, maxMessages: 10}},
      }, controller.signal)[Symbol.asyncIterator]();
      const initial = (await iterator.next()).value;
      const title = 'WebKit stream fixture';
      await rpc('session/rename', {request: {sessionId: first.sessionId, title}});
      const update = (await iterator.next()).value;
      controller.abort();
      const closed = await iterator.return();
      return { ids: [first.sessionId, second.sessionId], listed: list.items.map(x => x.sessionId),
        openingMatches: initial.type === 'snapshot' && initial.header.id === first.sessionId,
        updateMatches: update.type === 'event' && update.event.type === 'session/title' && update.event.data.title === title,
        closed: closed.done === true };
      """)
    let result = try XCTUnwrap(raw as? [String: Any])
    let ids = try XCTUnwrap(result["ids"] as? [String])
    let listed = try XCTUnwrap(result["listed"] as? [String])
    XCTAssertEqual(ids.count, 2)
    XCTAssertEqual(Set(ids).count, 2)
    XCTAssertEqual(Set(listed), Set(ids))
    XCTAssertEqual(result["openingMatches"] as? Bool, true)
    XCTAssertEqual(result["updateMatches"] as? Bool, true)
    XCTAssertEqual(result["closed"] as? Bool, true)
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("OfficialHostCI/sessions/sessions.sqlite").path))
    bridge.invalidate()
    // Acknowledge Host disposal before returning to the outer test, which
    // removes the directory. Node must not write diagnostics into a removed path.
    let stopped = directory.appendingPathComponent("official-host-ci-stopped")
    try Data(#"{"stop":true}"#.utf8).write(to: requestURL, options: .atomic)
    let stopDeadline = ProcessInfo.processInfo.systemUptime + 8
    while ProcessInfo.processInfo.systemUptime < stopDeadline && !FileManager.default.fileExists(atPath: stopped.path) {
      if let failure = try? String(contentsOf: errorURL, encoding: .utf8) {
        throw NSError(domain: "OfficialHostCI", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(try? Data(contentsOf: stopped), "Official Host did not acknowledge shutdown")
    let report = try JSONSerialization.data(withJSONObject: [
      "webKitToEmbeddedOfficialSessionRpcVerified": true, "sessionsCreated": ids.count,
      "sqlitePresent": true, "usesLocalTCP": false, "officialUIReady": false,
      "nodeStreamSnapshotVerified": true, "nodeStreamTitleEventVerified": true, "hostShutdownAcknowledged": true,
      "stage": "ci-only-session-transport",
    ])
    let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-embedded-session-rpc.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testOfficialFrontendAssetsLoadWithoutTCP() async throws {
    let assets = IosOfficialWebAssets()
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.setURLSchemeHandler(assets, forURLScheme: IosOfficialWebAssets.scheme)
    config.userContentController.addUserScript(WKUserScript(source: """
      window.__iosWebProbeErrors = [];
      addEventListener('error', event => window.__iosWebProbeErrors.push(String(event.message || event.target?.src || 'resource-error')), true);
      addEventListener('securitypolicyviolation', event => window.__iosWebProbeErrors.push(event.violatedDirective + ': ' + event.blockedURI));
      addEventListener('unhandledrejection', event => window.__iosWebProbeErrors.push(String(event.reason)));
      """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
    let navigation = WebAssetNavigation(expectation(description: "Stock DSH frontend loads from App URL"))
    web.navigationDelegate = navigation
    web.load(URLRequest(url: IosOfficialWebAssets.startURL))
    await fulfillment(of: [navigation.loaded], timeout: 15)
    XCTAssertNil(navigation.error)
    XCTAssertEqual(web.url, IosOfficialWebAssets.startURL)
    XCTAssertTrue(assets.servedPaths.contains("/index.html"))
    XCTAssertTrue(assets.servedPaths.contains { $0.hasPrefix("/assets/index-") && $0.hasSuffix(".js") })
    XCTAssertTrue(assets.servedPaths.contains { $0.hasPrefix("/assets/index-") && $0.hasSuffix(".css") })
    var boot: String?
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    repeat {
      boot = try await web.evaluateJavaScript("""
        JSON.stringify({boot: document.querySelector('#root')?.textContent ?? '', errors: window.__iosWebProbeErrors})
        """) as? String
      if boot?.contains("window.__ModuleLoader__ bootstrap facade is missing") == true { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    } while ProcessInfo.processInfo.systemUptime < deadline
    XCTAssertTrue(boot?.contains("window.__ModuleLoader__ bootstrap facade is missing") == true,
      "Stock entry must execute; no module loader or fake backend is supplied: \(boot ?? "no diagnostics")")
    let report = try JSONSerialization.data(withJSONObject: [
      "officialAssetsServed": true, "stockEntryExecuted": true, "usesLocalTCP": false,
      "officialUIReady": false, "missingCapability": "client-module-bootstrap-and-engine-transport",
    ])
    let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-assets-only.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testOfficialModuleBootstrapInWebKit() async throws {
    let assets = IosOfficialWebAssets()
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.setURLSchemeHandler(assets, forURLScheme: IosOfficialWebAssets.scheme)
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
    let navigation = WebAssetNavigation(expectation(description: "Generated official bootstrap document"))
    web.navigationDelegate = navigation
    web.load(URLRequest(url: IosOfficialWebAssets.bootstrapURL))
    await fulfillment(of: [navigation.loaded], timeout: 15)
    XCTAssertNil(navigation.error)
    XCTAssertEqual(web.url, IosOfficialWebAssets.bootstrapURL)
    XCTAssertTrue(assets.servedPaths.contains("/"))
    let observed = try await web.evaluateJavaScript("""
      JSON.stringify({mode: globalThis.__ModuleLoader__?.mode,
        release: globalThis.__DSH_BOOT__?.release, entries: globalThis.__DSH_BOOT__?.entries?.map(x=>x.id),
        bootVisible: document.querySelector('#root [data-dsh-boot]') !== null,
        composerVisible: document.querySelector('#root [data-composer-input]') !== null})
      """) as? String
    let text = try XCTUnwrap(observed)
    let state = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    XCTAssertEqual(state["mode"] as? String, "live", text)
    XCTAssertEqual(state["entries"] as? [String], ["@deepseek-ai/dsh-client-modules"], text)
    XCTAssertEqual((state["release"] as? [String: String])?["version"], "0.2.2-rc.3", text)
    XCTAssertEqual(state["bootVisible"] as? Bool, true, text)
    XCTAssertEqual(state["composerVisible"] as? Bool, false, text)
    XCTAssertTrue(assets.servedPaths.contains { $0.hasPrefix("/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev=") },
      "WebKit did not fetch the official combo route")
    let report = try JSONSerialization.data(withJSONObject: [
      "officialModuleBootstrapVerified": state["mode"] as? String == "live",
      "officialUIReady": false, "usesLocalTCP": false, "stage": "singleton-module-loader",
    ])
    let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-module-bootstrap.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Mount the stock renderer and actual official sidebar modules from the
  /// cloud preview. Host calls are deliberately unavailable in this DOM gate.
  @MainActor
  func testOfficialSidebarRendersWithoutTCP() async throws {
    let directory = Bundle(for: Self.self).bundleURL.appendingPathComponent("dsh-web-shell-preview", isDirectory: true)
    let assets = try IosOfficialWebAssets(previewDirectory: directory)
    let setup = """
      window.__iosPreviewErrors = [];
      addEventListener('error', event => window.__iosPreviewErrors.push(String(event.message || event.target?.src || 'resource-error')), true);
      addEventListener('unhandledrejection', event => window.__iosPreviewErrors.push(String(event.reason)));
      addEventListener('securitypolicyviolation', event => window.__iosPreviewErrors.push(event.violatedDirective + ': ' + event.blockedURI));
      window.__DSH_TRANSPORT__ = Object.freeze({ownsHost: true,
        fetch: async () => new Response(null, {status: 503}),
        openStream: async function* () { throw new Error('IOS_PREVIEW_NO_HOST'); },
      });
      """
    let bridge = IosOfficialWebBridge(assets: assets, documentStartScript: setup, handler: { _, _ in
      .response(.init(status: 503))
    })
    defer { bridge.invalidate() }
    bridge.load()
    let deadline = ProcessInfo.processInfo.systemUptime + 18
    var state: [String: Any] = [:]
    repeat {
      if let error = bridge.navigationFailure { throw error }
      if bridge.isReady {
        let observation = try await bridge.webView.evaluateJavaScript("""
          JSON.stringify({mode: globalThis.__ModuleLoader__?.mode,
            entries: globalThis.__DSH_BOOT__?.entries?.length,
            bootVisible: !!document.querySelector('#root > [data-dsh-boot]'),
            layout: !!document.querySelector('#root [data-slot="root"]'),
            sidebar: !!document.querySelector('#root [data-slot="sidebar"]'),
            sidebarControl: !!document.querySelector('#root [data-sidebar-opener], #root [data-sidebar-toggle]'),
            composer: !!document.querySelector('#root [data-composer-input]'),
            slotErrors: Array.from(document.querySelectorAll('#root [data-slot-error]'), x => x.getAttribute('data-slot-error')),
            errors: globalThis.__iosPreviewErrors?.slice(0, 8),
            body: document.querySelector('#root')?.textContent?.slice(0, 1024)})
          """) as? String
        if let observation {
          state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(observation.utf8)) as? [String: Any])
        }
        if state["sidebarControl"] as? Bool == true { break }
      }
      try await Task.sleep(for: .milliseconds(100))
    } while ProcessInfo.processInfo.systemUptime < deadline
    let detail = "\(state)"
    XCTAssertEqual(state["mode"] as? String, "live", detail)
    XCTAssertEqual(state["entries"] as? Int, 20, detail)
    XCTAssertEqual(state["bootVisible"] as? Bool, false, detail)
    XCTAssertEqual(state["layout"] as? Bool, true, detail)
    XCTAssertEqual(state["sidebar"] as? Bool, true, detail)
    XCTAssertEqual(state["sidebarControl"] as? Bool, true, detail)
    XCTAssertEqual(state["slotErrors"] as? [String], [], detail)
    XCTAssertTrue(assets.servedPaths.contains { $0.hasPrefix("/plugins/??") && $0.count > 240 })
    state["stage"] = "official-shell-render-without-host"
    state["usesLocalTCP"] = false
    state["officialUIReady"] = false
    let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: state), uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-sidebar-render.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Exercise the genuine page script and WebKit message handler. The reply
  /// is a Swift fixture, not a Node or official Host end-to-end result.
  @MainActor
  func testOfficialWebBridgeCarriesUnaryRequest() async throws {
    let script = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "official-web-bridge", withExtension: "js"))
    var received: [IosOfficialWebBridge.HTTPRequest] = []
    let bridge = IosOfficialWebBridge.ciFixture(schemeHandler: IosOfficialWebAssets(),
      documentStartScript: try String(contentsOf: script, encoding: .utf8)) { operation, _ in
      switch operation {
      case .request(let request): received.append(request)
      }
      return .response(IosOfficialWebBridge.HTTPResponse(status: 201,
        headers: [.init(name: "content-type", value: "text/plain; charset=utf-8")], body: Data("收到🧪".utf8)))
    }
    defer { bridge.invalidate() }
    bridge.load()
    let deadline = ProcessInfo.processInfo.systemUptime + 15
    while !bridge.isReady && ProcessInfo.processInfo.systemUptime < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    XCTAssertTrue(bridge.isReady)
    let raw = try await pageResult(bridge.webView, """
      const fetch = window.__DSH_TRANSPORT__.fetch;
      const response = await fetch('api/session/list?check=1', {
        method: 'POST', headers: {'content-type': 'text/plain'}, body: '请求🧪',
      });
      let foreignBlocked = false;
      try { await fetch('https://example.invalid/api/session/list'); } catch { foreignBlocked = true; }
      return { status: response.status, text: await response.text(), foreignBlocked };
      """)
    let value = try XCTUnwrap(raw as? [String: Any])
    XCTAssertEqual(value["status"] as? Int, 201)
    XCTAssertEqual(value["text"] as? String, "收到🧪")
    XCTAssertEqual(value["foreignBlocked"] as? Bool, true)
    XCTAssertEqual(received.count, 1)
    let request = try XCTUnwrap(received.first)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.pathAndQuery, "/api/session/list?check=1")
    XCTAssertEqual(request.body, Data("请求🧪".utf8))
    bridge.invalidate()
    let rejected = try await pageResult(bridge.webView, """
      try { await window.__DSH_TRANSPORT__.fetch('api/session/list'); return false; }
      catch { return true; }
      """)
    XCTAssertEqual(rejected as? Bool, true)
    XCTAssertEqual(received.count, 1)
    let report = try JSONSerialization.data(withJSONObject: [
      "webKitUnaryBridgeVerified": true, "crossOriginBlocked": true, "invalidatedPageBlocked": true,
      "officialWebTransportVerified": false, "usesLocalTCP": false,
    ])
    let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-unary-bridge-fixture.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Avoid the Swift WebKit overlay missing from the iOS 18 simulator.
  /// Await the JS promise in the page and retrieve its result with a bounded poll.
  @MainActor
  private func pageResult(_ web: WKWebView, _ body: String) async throws -> Any? {
    let slot = "__iosTest_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    _ = try await web.evaluateJavaScript("""
      void (async () => { \(body) })().then(
        value => globalThis.\(slot) = JSON.stringify({value}),
        error => globalThis.\(slot) = JSON.stringify({error: String(error)}));
      true;
      """)
    let deadline = ProcessInfo.processInfo.systemUptime + 27
    while ProcessInfo.processInfo.systemUptime < deadline {
      let raw = try await web.evaluateJavaScript("""
        (() => { const value = globalThis.\(slot); delete globalThis.\(slot); return value ?? ''; })()
        """)
      if let envelope = raw as? String, !envelope.isEmpty {
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(envelope.utf8)) as? [String: Any])
        if let error = decoded["error"] as? String {
          throw NSError(domain: "OfficialWebCI", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        return decoded["value"]
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw URLError(.timedOut)
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

  private func request(_ mailbox: IosChatMailbox, _ method: IosChatMailbox.Method,
                       params: [String: Any]) throws -> [String: Any] {
    let done = expectation(description: "chat mailbox structured reply")
    var response: Result<[String: Any], IosChatMailbox.Failure>?
    mailbox.request(method, params: params) { reply in
      response = reply
      done.fulfill()
    }
    wait(for: [done], timeout: 30)
    return try XCTUnwrap(response).get()
  }

  private func waitForChat(_ mailbox: IosChatMailbox, seconds: TimeInterval = 10,
                           until predicate: ([String: Any]) -> Bool) throws -> [String: Any] {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    var last: [String: Any] = [:]
    repeat {
      last = try request(mailbox, .snapshot)
      if predicate(last) { return last }
    } while ProcessInfo.processInfo.systemUptime < deadline
    XCTFail("Chat state not observed: \(last["state"] ?? "unknown") \(last["errorCode"] ?? "none")")
    return last
  }
}
