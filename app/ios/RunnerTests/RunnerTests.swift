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

/// Simulator fixture only. Keep one private lane per active WebKit request so
/// an idle stream pull cannot hold up another stream, a unary RPC, or close.
@MainActor
private final class OfficialHostCIMailbox {
  private let directory: URL
  private var inFlight = 0
  private var inFlightFileCalls = 0
  private var invalidatedGeneration: UInt64 = 0
  private(set) var peakConcurrentCalls = 0
  var allowBrowserSessionCreates = false

  init(directory: URL) { self.directory = directory }

  func invalidate(_ generation: UInt64) {
    invalidatedGeneration = max(invalidatedGeneration, generation)
  }

  func checkHostFailure() throws {
    let errorURL = directory.appendingPathComponent("official-host-ci-error")
    if let failure = try? String(contentsOf: errorURL, encoding: .utf8) {
      throw NSError(domain: "OfficialHostCI", code: 1, userInfo: [NSLocalizedDescriptionKey: failure])
    }
  }

  func request(_ request: IosOfficialWebBridge.HTTPRequest, generation: UInt64) async throws -> IosOfficialWebBridge.Reply {
    guard generation > invalidatedGeneration, inFlight < 16 else { throw URLError(.resourceUnavailable) }
    guard request.method == "POST", let data = request.body,
          let body = String(data: data, encoding: .utf8),
          request.headers.contains(where: { header in
            let mediaType = header.value.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
            return header.name.lowercased() == "content-type" && mediaType?.lowercased() == "application/json"
          }), let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw URLError(.badServerResponse)
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 40
    let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let requestURL = directory.appendingPathComponent("official-call-\(id).json")
    let replyURL = directory.appendingPathComponent("official-reply-\(id).json")
    let files = FileManager.default
    inFlight += 1
    defer { inFlight -= 1 }
    // The official shell restores its own blank Session on initial connect.
    // Let the raw gate observe the originally empty Host and exactly its own
    // two creates before releasing the genuine browser restoration request.
    let isBrowserCreate = request.pathAndQuery == "/api/session/create"
      && (frame["rpcId"] as? String)?.hasPrefix("ios-web-test-") != true
    while isBrowserCreate && !allowBrowserSessionCreates {
      try await waitForLane(generation, deadline: deadline)
    }
    let payload = try JSONSerialization.data(withJSONObject: ["path": request.pathAndQuery, "body": body])
    guard payload.count <= 256 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
    try checkLane(generation, deadline: deadline)
    try payload.write(to: requestURL, options: .atomic)
    inFlightFileCalls += 1
    peakConcurrentCalls = max(peakConcurrentCalls, inFlightFileCalls)
    defer {
      try? files.removeItem(at: requestURL)
      try? files.removeItem(at: replyURL)
      inFlightFileCalls -= 1
    }
    while !files.fileExists(atPath: replyURL.path) {
      try await waitForLane(generation, deadline: deadline)
    }
    try checkLane(generation, deadline: deadline)
    // A JSON string may encode one byte as six escape characters.
    let values = try replyURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink == false,
          let size = values.fileSize, size > 0, size <= 6 * 256 * 1024 + 64 else {
      throw URLError(.badServerResponse)
    }
    let reply = try Data(contentsOf: replyURL)
    guard reply.count == size,
          let result = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
          let status = result["status"] as? Int, (200...599).contains(status),
          let text = result["body"] as? String, text.utf8.count <= 256 * 1024 else {
      throw URLError(.badServerResponse)
    }
    return .response(.init(status: status,
      headers: [.init(name: "content-type", value: "application/json")], body: Data(text.utf8)))
  }

  private func checkLane(_ generation: UInt64, deadline: TimeInterval) throws {
    try checkHostFailure()
    try Task.checkCancellation()
    guard generation > invalidatedGeneration else { throw CancellationError() }
    guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
  }

  private func waitForLane(_ generation: UInt64, deadline: TimeInterval) async throws {
    try checkLane(generation, deadline: deadline)
    try await Task.sleep(for: .milliseconds(25))
  }

  func removeSettledFiles() throws {
    // Call only after Node acknowledges stop; this also cleans any late reply
    // written after a cancelled or timed-out lane had already exited.
    let files = FileManager.default
    let names = try files.contentsOfDirectory(atPath: directory.path)
    for name in names where name.range(of: #"^official-(call-|reply-)?[0-9a-f]{32}\.(json|tmp)$"#,
                                      options: .regularExpression) != nil {
      try files.removeItem(at: directory.appendingPathComponent(name))
    }
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
    let officialMailbox = OfficialHostCIMailbox(directory: directory)
    // Start the real preview page before Node's cold initialization. On a
    // loaded CI runner WebKit's first GPU process took over 13 seconds to launch.
    let bridge: IosOfficialWebBridge?
    do { bridge = try await startOfficialWebSessionPage(officialMailbox) }
    catch {
      XCTFail("CI-only official Web bootstrap: \(error.localizedDescription)")
      bridge = nil
    }
    defer { bridge?.invalidate() }
    var nodeRunning = false
    nodeRunning = DshEmbeddedNode.startProbe(atPath: script, reportPath: output.path) { code in
      nodeRunning = false // The Objective-C wrapper delivers completion on the main queue.
      XCTFail("Node runtime exited unexpectedly: \(code)")
    }
    XCTAssertTrue(nodeRunning)
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
    let initialChat = try await request(mailbox, .snapshot)
    XCTAssertEqual(initialChat["state"] as? String, "stopped")
    let startedChat = try await request(mailbox, .start, apiKey)
    XCTAssertEqual(startedChat["state"] as? String, "ready")
    let firstSend = try await request(mailbox, .send, "chat-ci-first")
    XCTAssertEqual(firstSend["state"] as? String, "running")
    let streaming = try await waitForChat(mailbox) { $0["draft"] as? String == "ci-provider-stream-" }
    XCTAssertEqual(streaming["state"] as? String, "running")
    let settled = try await waitForChat(mailbox) { $0["state"] as? String == "ready" }
    let history = [["role": "user", "text": "chat-ci-first"],
      ["role": "assistant", "text": "ci-provider-stream-complete"]]
    XCTAssertEqual(settled["messages"] as? [[String: String]], history)
    XCTAssertTrue(settled["errorCode"] is NSNull)
    let firstStop = try await request(mailbox, .stop)
    XCTAssertEqual(firstStop["state"] as? String, "stopped")
    let reopenedChat = try await request(mailbox, .start, apiKey)
    XCTAssertEqual(reopenedChat["messages"] as? [[String: String]], history)
    let resumedSend = try await request(mailbox, .send, "chat-ci-resumed")
    XCTAssertEqual(resumedSend["state"] as? String, "running")
    let resumed = try await waitForChat(mailbox) { $0["state"] as? String == "ready" }
    XCTAssertEqual(resumed["messages"] as? [[String: String]], history + [
      ["role": "user", "text": "chat-ci-resumed"],
      ["role": "assistant", "text": "ci-provider-stream-complete"],
    ])
    _ = try await request(mailbox, .send, "chat-ci-cancel")
    _ = try await waitForChat(mailbox) { $0["draft"] as? String == "ci-provider-stream-" }
    let cancelled = try await request(mailbox, .cancel)
    XCTAssertEqual(cancelled["state"] as? String, "ready")
    XCTAssertEqual(cancelled["draft"] as? String, "")
    _ = try await request(mailbox, .send, "chat-ci-auth-error")
    let failed = try await waitForChat(mailbox) { $0["state"] as? String == "ready" }
    XCTAssertEqual(failed["errorCode"] as? String, "IOS_CHAT_AUTH_FAILED")
    XCTAssertFalse(String(describing: failed).contains(apiKey))
    let adapterStop = try await request(mailbox, .stop)
    XCTAssertEqual(adapterStop["state"] as? String, "stopped")

    // Same on-device engine, now using a custom HTTPS Chat Completions route.
    let custom: [String: Any] = ["apiKey": apiKey, "protocol": "openai-chat",
      "baseUrl": "https://models.example/v1", "modelId": "fixture-model"]
    let customChat = try await request(mailbox, .start, params: custom)
    XCTAssertEqual(customChat["state"] as? String, "ready")
    _ = try await request(mailbox, .send, "chat-ci-workspace-allow")
    let waiting = try await waitForChat(mailbox) { $0["approval"] is [String: Any] }
    let approval = try XCTUnwrap(waiting["approval"] as? [String: Any])
    let file = directory.appendingPathComponent("ChatData/Workspace/allowed.txt")
    let expectedText = "fixture 雪🧪\nsecond line\n"
    XCTAssertEqual(approval["toolName"] as? String, "workspace_create_text")
    XCTAssertEqual(approval["path"] as? String, "allowed.txt")
    XCTAssertEqual(approval["preview"] as? String, expectedText)
    XCTAssertEqual(approval["byteLength"] as? Int, expectedText.utf8.count)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    let id = try XCTUnwrap(approval["id"] as? String)
    _ = try await request(mailbox, .answerApproval, params: ["id": id, "allowed": true])
    let toolTurn = try await waitForChat(mailbox, seconds: 25) { $0["state"] as? String == "ready" }
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
    let customStop = try await request(mailbox, .stop)
    XCTAssertEqual(customStop["state"] as? String, "stopped")

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

    if let bridge {
      do {
        try await verifyOfficialWebSessionRPC(directory, bridge: bridge, mailbox: officialMailbox)
      } catch {
        // Leave no live CI streams even if its independent probe fails.
        try? await stopOfficialWebSession(directory, bridge: bridge, mailbox: officialMailbox)
        XCTFail("CI-only official Web gate: \(error.localizedDescription)")
      }
    }
    // Node is process-wide: the production carrier was started by the same
    // framework probe as the other gates, not by the CI-only preview Host.
    try await verifyProductionOfficialWeb(root, reportURL: output, runtimeIsRunning: { nodeRunning })
  }

  @MainActor
  private func verifyProductionOfficialWeb(_ framework: Bundle, reportURL: URL,
                                           runtimeIsRunning: @escaping () -> Bool) async throws {
    let files = FileManager.default
    let channel = try IosOfficialAppMailbox.Setup(apiKey: "ios-prod-ci-not-a-credential",
      channelProtocol: "openai-chat", baseURL: "https://official-ios-ci.invalid/v1", modelID: "ios-production-fixture")
    let production = framework.bundleURL.appendingPathComponent("dsh-official-web", isDirectory: true)
    let wire = reportURL.appendingPathExtension("official")
    let workspace = reportURL.deletingLastPathComponent()
      .appendingPathComponent("OfficialAppState/Workspace", isDirectory: true)
    let file = workspace.appendingPathComponent("official-approved.txt")
    let attachmentName = "official-web-production-e2e.json"
    var evidence: [String: Any] = [
      "stage": "load-framework-assets", "officialUIReady": false, "usesLocalTCP": false,
      "modelTransport": "synthetic-https-response", "modelId": "ios-production-fixture",
      "assets": "dsh-official-web", "carrier": "production-swift-mailbox",
    ]
    var mailbox: IosOfficialAppMailbox?
    var bridge: IosOfficialWebBridge?
    var responses: Set<String> = []
    do {
      let assets = try IosOfficialWebAssets(previewDirectory: production)
      let hook = try XCTUnwrap(framework.url(forResource: "official-web-bridge", withExtension: "js"))
      let script = "globalThis.__DSH_IOS_APP_CARRIER__ = true;\n"
        + (try String(contentsOf: hook, encoding: .utf8)) + "\n" + officialWebDiagnostics
      evidence["stage"] = "start-production-carrier"
      let carrier = try IosOfficialAppMailbox(reportURL: reportURL, runtimeIsRunning: runtimeIsRunning)
      mailbox = carrier
      let generation = try carrier.begin(channel)
      try await carrier.waitUntilReady(generation)
      let permissions = try files.attributesOfItem(atPath: wire.path)[.posixPermissions] as? NSNumber
      XCTAssertEqual(permissions?.intValue, 0o700)
      evidence["privateMailboxVerified"] = permissions?.intValue == 0o700
      let workspaceValues = try workspace.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      let workspacePermissions = try files.attributesOfItem(atPath: workspace.path)[.posixPermissions] as? NSNumber
      let privateWorkspace = workspaceValues.isDirectory == true && workspaceValues.isSymbolicLink == false
        && workspacePermissions?.intValue == 0o700
      _ = try XCTUnwrap(privateWorkspace ? true : nil, "Expected the production Host's private Workspace")
      evidence["privateWorkspaceVerified"] = privateWorkspace
      XCTAssertFalse(files.fileExists(atPath: wire.appendingPathComponent("official-start.json").path))

      evidence["stage"] = "load-production-webkit"
      let page = IosOfficialWebBridge(assets: assets, documentStartScript: script,
        handler: { operation, page in
          switch operation {
          case .request(let request):
            let reply = try await carrier.request(request, generation: generation, page: page)
            if case .response(let response) = reply {
              responses.insert("\(request.pathAndQuery):\(response.status)")
            }
            return reply
          }
        }, onInvalidate: { carrier.invalidate(page: $0, generation: generation) })
      bridge = page
      page.load()
      try await waitForOfficialWebPage(page, assets: assets)
      let web = page.webView!
      let initial = try await productionPageResult(web, label: "live official graph and editable composer", """
        await waitFor(() => globalThis.__ModuleLoader__?.mode === 'live'
          && !root()?.querySelector('[data-dsh-boot]') && conversation() && composer());
        return {entries: globalThis.__DSH_BOOT__?.entries?.length,
          release: globalThis.__DSH_BOOT__?.release?.version,
          carrier: globalThis.__DSH_IOS_APP_CARRIER__ === true,
          session: conversation().getAttribute('data-conversation-session')};
        """)
      let entries = initial["entries"] as? Int
      _ = try XCTUnwrap(entries == 28 ? entries : nil, "Expected the shipped 28-entry graph, got \(initial)")
      XCTAssertEqual(initial["release"] as? String, "0.2.2-rc.3")
      XCTAssertEqual(initial["carrier"] as? Bool, true)
      let session = try XCTUnwrap(initial["session"] as? String)
      evidence["graphEntries"] = entries
      evidence["sessionId"] = session
      evidence["officialComposerReady"] = true
      _ = try XCTUnwrap(!files.fileExists(atPath: file.path) ? true : nil, "Workspace fixture already exists")

      evidence["stage"] = "submit-official-composer"
      let submitted = try await productionPageResult(web, label: "insert and send from official composer", """
        const input = await waitFor(composer);
        const prompt = 'official-tool-fixture';
        input.focus();
        const selection = window.getSelection();
        if (selection && !input.contains(selection.anchorNode)) {
          const range = document.createRange();
          range.selectNodeContents(input);
          range.collapse(false);
          selection.removeAllRanges();
          selection.addRange(range);
        }
        if (!document.execCommand('insertText', false, prompt)) throw new Error('insertText failed');
        // WebKit's edit command emits input; sending a second synthetic input
        // applies the same insertText twice in the production Lexical editor.
        // In this locked graph only the primary composer action sets aria-busy.
        const send = await waitFor(() => input.textContent === prompt
          && input.closest('[data-composer-card]')?.querySelector('button[aria-busy="false"]:enabled'));
        send.click();
        return {clicked: true};
        """)
      XCTAssertEqual(submitted["clicked"] as? Bool, true)
      evidence["officialComposerSubmitClicked"] = submitted["clicked"]

      evidence["stage"] = "wait-for-official-approval"
      let approval = try await productionPageResult(web, label: "approval card with file and preview", """
        const card = await waitFor(() => {
          const item = approvalCard();
          const detail = item?.querySelector('[data-approval-scroll]')?.textContent ?? '';
          return detail.includes('official-approved.txt') && detail.includes('official simulator approved')
            && allowOnce(item) && item;
        });
        return {key: card.getAttribute('data-approval-key')};
        """)
      let approvalKey = try XCTUnwrap(approval["key"] as? String)
      evidence["officialApprovalDetailsVerified"] = true
      // This check runs between observing the native approval request in the
      // official renderer and the only action which answers it.
      _ = try XCTUnwrap(!files.fileExists(atPath: file.path) ? true : nil, "Tool wrote before approval")
      evidence["fileAbsentBeforeApproval"] = true

      evidence["stage"] = "allow-once-from-official-card"
      let approvalJSON = String(decoding: try JSONEncoder().encode(approvalKey), as: UTF8.self)
      let allowed = try await productionPageResult(web, label: "click official Allow once", """
        const card = approvalCard();
        const button = card?.getAttribute('data-approval-key') === \(approvalJSON) ? allowOnce(card) : null;
        if (!button) throw new Error('Original approval is no longer answerable');
        button.click();
        return {clicked: true};
        """)
      XCTAssertEqual(allowed["clicked"] as? Bool, true)
      evidence["officialAllowOnceClicked"] = allowed["clicked"]

      evidence["stage"] = "verify-visible-result-and-file"
      let result = try await productionPageResult(web, label: "assistant result and cleared approval", """
        await waitFor(() => !approvalCard() && Array.from(conversation()?.querySelectorAll(
          '[data-chat-flow-kind="assistant-step"]') ?? []).some(node =>
            node.getClientRects().length > 0 && node.textContent.includes('official-tool-result')));
        return {session: conversation().getAttribute('data-conversation-session')};
        """)
      XCTAssertEqual(result["session"] as? String, session)
      evidence["officialAssistantResultVisible"] = true
      let bytes = try Data(contentsOf: file)
      _ = try XCTUnwrap(bytes == Data("official simulator approved\n".utf8) ? true : nil,
        "Approved Workspace file must contain the exact fixture bytes")
      evidence["approvedFileBytesVerified"] = true
      let promptReachedCarrier = responses.contains("/api/session/prompt:200")
      let answerReachedCarrier = responses.contains("/api/$events/result:200")
      let streamedThroughCarrier = responses.contains("/api/ios-app/stream:200")
      XCTAssertTrue(promptReachedCarrier && answerReachedCarrier && streamedThroughCarrier, "\(responses.sorted())")
      evidence["promptReachedProductionCarrier"] = promptReachedCarrier
      evidence["approvalReachedProductionCarrier"] = answerReachedCarrier
      evidence["productionStreamVerified"] = streamedThroughCarrier

      evidence["stage"] = "stop-production-carrier"
      let closed = try await pageResult(web, "await globalThis.__iosOfficialBridgeClose(); return true;",
        seconds: 10, label: "close production page streams")
      XCTAssertEqual(closed as? Bool, true)
      page.invalidate()
      web.stopLoading()
      try await carrier.stop()
      let stopped = try Data(contentsOf: wire.appendingPathComponent("official-stopped")) == Data("1".utf8)
      XCTAssertTrue(stopped)
      evidence["hostShutdownAcknowledged"] = stopped
      evidence["stage"] = "production-official-web-chat-and-approval"
      evidence["officialUIReady"] = true
      try addJSONEvidence(evidence, name: attachmentName)
    } catch {
      bridge?.invalidate()
      bridge?.webView.stopLoading()
      try? await mailbox?.stop()
      evidence["failure"] = error.localizedDescription
      evidence["carrierResponses"] = responses.sorted()
      try? addJSONEvidence(evidence, name: attachmentName)
      throw error
    }
  }

  @MainActor
  private func productionPageResult(_ web: WKWebView, label: String, _ body: String) async throws -> [String: Any] {
    let result = try await pageResult(web, """
      const root = () => document.getElementById('root');
      const conversation = () => root()?.querySelector('[data-conversation-content][data-conversation-session]');
      const composer = () => conversation()?.querySelector('[data-composer-input][contenteditable="true"]');
      const approvalCard = () => conversation()?.querySelector('[data-approval-key]');
      const allowOnceLabels = new Set(['allow once', '允许一次', '1 回だけ許可', 'permitir una vez',
        'autoriser une fois', 'einmal zulassen', 'разрешить один раз', 'permitir uma vez']);
      const allowOnce = card => Array.from(card?.querySelectorAll('button:enabled') ?? [])
        .find(button => allowOnceLabels.has(button.textContent.trim().toLowerCase()));
      const deadline = performance.now() + 25_000;
      async function waitFor(observe) {
        for (;;) {
          const value = observe();
          if (value) return value;
          if (performance.now() >= deadline) {
            throw new Error(JSON.stringify({mode: globalThis.__ModuleLoader__?.mode,
              entries: globalThis.__DSH_BOOT__?.entries?.length,
              phase: conversation()?.getAttribute('data-content-phase'),
              hasComposer: !!composer(), hasApproval: !!approvalCard(),
              slotErrors: Array.from(root()?.querySelectorAll('[data-slot-error]') ?? [], x => x.getAttribute('data-slot-error')),
              errors: globalThis.__iosOfficialErrors?.slice(0, 8), body: root()?.innerText?.slice(0, 768)}));
          }
          await new Promise(resolve => setTimeout(resolve, 75));
        }
      }
      \(body)
      """, seconds: 35, label: label)
    return try XCTUnwrap(result as? [String: Any], label)
  }

  private var officialWebDiagnostics: String {
    """
      globalThis.__iosOfficialErrors = [];
      addEventListener('error', event => globalThis.__iosOfficialErrors.push(String(event.message || event.target?.src || 'resource-error')), true);
      addEventListener('unhandledrejection', event => globalThis.__iosOfficialErrors.push(String(event.reason)));
      addEventListener('securitypolicyviolation', event => globalThis.__iosOfficialErrors.push(event.violatedDirective + ': ' + event.blockedURI));
      """
  }

  private func addJSONEvidence(_ fields: [String: Any], name: String) throws {
    let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func startOfficialWebSessionPage(_ mailbox: OfficialHostCIMailbox) async throws -> IosOfficialWebBridge {
    let bundle = Bundle(for: Self.self)
    let preview = bundle.bundleURL.appendingPathComponent("dsh-web-shell-preview", isDirectory: true)
    let script = try XCTUnwrap(bundle.url(forResource: "official-web-bridge", withExtension: "js"))
    let assets = try IosOfficialWebAssets(previewDirectory: preview)
    let diagnostics = """
      globalThis.__iosOfficialErrors = [];
      addEventListener('error', event => globalThis.__iosOfficialErrors.push(String(event.message || event.target?.src || 'resource-error')), true);
      addEventListener('unhandledrejection', event => globalThis.__iosOfficialErrors.push(String(event.reason)));
      addEventListener('securitypolicyviolation', event => globalThis.__iosOfficialErrors.push(event.violatedDirective + ': ' + event.blockedURI));
      """
    let bridge = IosOfficialWebBridge(assets: assets,
      documentStartScript: diagnostics + "\n" + (try String(contentsOf: script, encoding: .utf8)),
      handler: { operation, generation in
        switch operation {
        case .request(let request): return try await mailbox.request(request, generation: generation)
        }
      }, onInvalidate: { mailbox.invalidate($0) })
    bridge.load()
    try await waitForOfficialWebPage(bridge, assets: assets)
    return bridge
  }

  @MainActor
  private func waitForOfficialWebPage(_ bridge: IosOfficialWebBridge, assets: IosOfficialWebAssets) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 35
    while !bridge.isReady && ProcessInfo.processInfo.systemUptime < deadline {
      if let error = bridge.navigationFailure { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    _ = try XCTUnwrap(bridge.isReady ? true : nil,
      "App bootstrap document did not commit; served=\(assets.servedPaths.sorted()), URL=\(String(describing: bridge.webView.url))")
    // The scheme response can commit before document-start scripts execute.
    let transport = try await pageResult(bridge.webView, "return typeof globalThis.__DSH_TRANSPORT__?.openStream === 'function';")
    _ = try XCTUnwrap(transport as? Bool == true ? true : nil, "Document-start transport was not installed")
  }

  @MainActor
  private func verifyOfficialWebSessionRPC(_ directory: URL, bridge: IosOfficialWebBridge,
                                           mailbox: OfficialHostCIMailbox) async throws {
    let ready = try await waitForOfficialHostFile(directory.appendingPathComponent("official-host-ci-ready"),
                                                  mailbox: mailbox, seconds: 35)
    let host = try XCTUnwrap(JSONSerialization.jsonObject(with: ready) as? [String: Any])
    let workspaceId = try XCTUnwrap(host["workspaceId"] as? String)
    let workspaceJSON = try JSONEncoder().encode(workspaceId)
    let raw = try await pageResult(bridge.webView, """
      const workspaceId = \(String(decoding: workspaceJSON, as: UTF8.self));
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
      const empty = await rpc('session/list', {_request: {}});
      const first = await rpc('session/create', {request: {workspaceId}});
      const second = await rpc('session/create', {request: {workspaceId}});
      const list = await rpc('session/list', {_request: {}});
      const controller = new AbortController();
      const iterator = window.__DSH_TRANSPORT__.openStream('session/follow', {
        args: {request: {address: {kind: 'session', sessionId: first.sessionId}, maxMessages: 10}},
      }, controller.signal)[Symbol.asyncIterator]();
      let initial, update, closed;
      const title = 'WebKit stream fixture';
      try {
        initial = (await iterator.next()).value;
        // Leave the second stream pull outstanding while a separate unary
        // request writes the title. They must not serialize through one slot.
        const pendingUpdate = iterator.next();
        const [, frame] = await Promise.all([
          rpc('session/rename', {request: {sessionId: first.sessionId, title}}), pendingUpdate,
        ]);
        update = frame.value;
      } finally {
        controller.abort();
        closed = await iterator.return();
      }
      return { initiallyEmpty: empty.items.length === 0,
        ids: [first.sessionId, second.sessionId], listed: list.items.map(x => x.sessionId),
        openingMatches: initial?.type === 'snapshot' && initial.header.id === first.sessionId,
        updateMatches: update?.type === 'event' && update.event.type === 'session/title' && update.event.data.title === title,
        closed: closed.done === true };
      """)
    let result = try XCTUnwrap(raw as? [String: Any])
    let ids = try XCTUnwrap(result["ids"] as? [String])
    let listed = try XCTUnwrap(result["listed"] as? [String])
    let initiallyEmpty = result["initiallyEmpty"] as? Bool == true
    let snapshotVerified = result["openingMatches"] as? Bool == true
    let titleEventVerified = result["updateMatches"] as? Bool == true
    let streamClosed = result["closed"] as? Bool == true
    let sqlitePresent = FileManager.default.fileExists(atPath: directory.appendingPathComponent("OfficialHostCI/sessions/sessions.sqlite").path)
    XCTAssertTrue(initiallyEmpty)
    XCTAssertEqual(ids.count, 2)
    XCTAssertEqual(Set(ids).count, 2)
    XCTAssertEqual(Set(listed), Set(ids))
    XCTAssertTrue(snapshotVerified)
    XCTAssertTrue(titleEventVerified)
    XCTAssertTrue(streamClosed)
    XCTAssertTrue(sqlitePresent)
    XCTAssertGreaterThan(mailbox.peakConcurrentCalls, 1, "WebKit requests did not overlap across private lanes")
    mailbox.allowBrowserSessionCreates = true

    // The official sidebar intentionally hides non-current blank sessions.
    // The test Host runs actual deterministic turns so both rows are eligible.
    let idsJSON = try JSONEncoder().encode(ids)
    let engaged = try await pageResult(bridge.webView, """
      const response = await globalThis.__DSH_TRANSPORT__.fetch('api/ios-ci/engage', {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({sessionIds: \(String(decoding: idsJSON, as: UTF8.self))}),
      });
      if (!response.ok) throw new Error('Official fixture turns: ' + response.status + ' ' + await response.text());
      return (await response.json()).engaged === true;
      """)
    _ = try XCTUnwrap(engaged as? Bool == true ? true : nil, "Official Host did not complete both fixture turns")
    let selection = try await verifyOfficialSidebar(bridge.webView, workspaceJSON: workspaceJSON, idsJSON: idsJSON)
    let selected = try XCTUnwrap(selection["selectedSessionIds"] as? [String])
    let workspaceVerified = selection["workspaceVerified"] as? Bool == true
    XCTAssertTrue(workspaceVerified)
    let selectionMatches = selected.count == ids.count && Set(selected) == Set(ids)
    XCTAssertTrue(selectionMatches, "Expected both sessions selected by DOM clicks: \(ids), got \(selected)")
    try await stopOfficialWebSession(directory, bridge: bridge, mailbox: mailbox)

    let report = try JSONSerialization.data(withJSONObject: [
      "webKitToEmbeddedOfficialSessionRpcVerified": initiallyEmpty && ids.count == 2
        && Set(ids).count == 2 && Set(listed) == Set(ids),
      "sessionsCreated": ids.count, "sqlitePresent": sqlitePresent, "usesLocalTCP": false, "officialUIReady": false,
      "nodeStreamSnapshotVerified": snapshotVerified, "nodeStreamTitleEventVerified": titleEventVerified,
      "nodeStreamClosed": streamClosed, "hostShutdownAcknowledged": true,
      "officialSidebarWorkspaceVerified": workspaceVerified, "officialSidebarSessionSelectionVerified": selectionMatches,
      "selectedSessionIds": selected, "peakConcurrentFileCalls": mailbox.peakConcurrentCalls,
      "stage": "ci-only-official-sidebar-session-navigation",
    ])
    let attachment = XCTAttachment(data: report, uniformTypeIdentifier: "public.json")
    attachment.name = "official-web-embedded-session-rpc.json"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func verifyOfficialSidebar(_ web: WKWebView, workspaceJSON: Data, idsJSON: Data) async throws -> [String: Any] {
    let observation = try await pageResult(web, """
      const workspaceId = \(String(decoding: workspaceJSON, as: UTF8.self));
      const ids = \(String(decoding: idsJSON, as: UTF8.self));
      const root = document.getElementById('root');
      const list = () => root?.querySelector('[data-sidebar-list-area]');
      const row = (key) => list()?.querySelector(`[role="treeitem"][data-row-key="${CSS.escape(key)}"]`);
      const workspace = () => row('workspace:' + workspaceId);
      const conversation = () => root?.querySelector('[data-conversation-content][data-conversation-session]');
      const collapsed = () => root?.querySelector('[data-sidebar-collapsed]');
      const deadline = performance.now() + 22_000;
      async function waitFor(label, observe) {
        for (;;) {
          const value = observe();
          if (value) return value;
          if (performance.now() >= deadline) {
            const detail = {label, rows: Array.from(list()?.querySelectorAll('[data-row-key]') ?? [],
                r => [r.getAttribute('data-row-key'), r.getAttribute('aria-expanded'), r.getAttribute('aria-selected')]),
              conversation: conversation()?.getAttribute('data-conversation-session'),
              slotErrors: Array.from(root?.querySelectorAll('[data-slot-error]') ?? [], x => x.getAttribute('data-slot-error')),
              errors: globalThis.__iosOfficialErrors?.slice(0, 8), body: root?.textContent?.slice(0, 1024)};
            throw new Error('Official sidebar: ' + JSON.stringify(detail));
          }
          await new Promise(resolve => setTimeout(resolve, 75));
        }
      }
      async function openSidebar() {
        if (collapsed()) {
          const opener = await waitFor('sidebar opener', () => root?.querySelector('[data-sidebar-opener]'));
          opener.click();
        }
        await waitFor('open sidebar', () => list() && !collapsed());
      }
      await waitFor('official live renderer', () => globalThis.__ModuleLoader__?.mode === 'live'
        && !root?.querySelector('[data-dsh-boot]') && list());
      await openSidebar();
      const project = await waitFor('seeded workspace row', () => {
        const item = workspace();
        return item?.textContent.includes('iOS Test Workspace') && item;
      });
      if (project.getAttribute('aria-expanded') !== 'true') project.click();
      await waitFor('expanded workspace', () => workspace()?.getAttribute('aria-expanded') === 'true');
      const selectedSessionIds = [];
      // The official browser may have restored one of these sessions already.
      // Click the other row first so every click must change the real selection.
      const activeId = conversation()?.getAttribute('data-conversation-session');
      const order = activeId === ids[0] || row('session:' + ids[0])?.getAttribute('aria-selected') === 'true'
        ? [ids[1], ids[0]] : ids;
      for (const id of order) {
        await openSidebar();
        const item = await waitFor('workspace session row ' + id, () => {
          const candidate = row('session:' + id);
          // rc.3 wraps the Workspace header in a HoverCard. Its parent is
          // not necessarily the group's own Session-row parent.
          return workspace()?.getAttribute('aria-expanded') === 'true' && candidate;
        });
        if (item.getAttribute('aria-selected') !== 'false') throw new Error('Session already selected before click: ' + id);
        item.click();
        await waitFor('selected session ' + id, () => {
          const active = conversation();
          return row('session:' + id)?.getAttribute('aria-selected') === 'true'
            && active?.getAttribute('data-conversation-session') === id
            && active.getAttribute('data-content-phase') === 'active';
        });
        selectedSessionIds.push(conversation().getAttribute('data-conversation-session'));
      }
      return { workspaceVerified: true, selectedSessionIds };
      """)
    return try XCTUnwrap(observation as? [String: Any])
  }

  @MainActor
  private func waitForOfficialHostFile(_ url: URL, mailbox: OfficialHostCIMailbox, seconds: TimeInterval) async throws -> Data {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
      try mailbox.checkHostFailure()
      if FileManager.default.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
      try await Task.sleep(for: .milliseconds(25))
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw NSError(domain: "OfficialHostCI", code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(url.lastPathComponent)"])
  }

  @MainActor
  private func stopOfficialWebSession(_ directory: URL, bridge: IosOfficialWebBridge, mailbox: OfficialHostCIMailbox) async throws {
    // Stop new stream opens and await closes while the bridge is still valid.
    // Even if the page is gone, send the stop marker so Node can abort all lanes.
    let closed = try? await pageResult(bridge.webView, """
      await globalThis.__iosOfficialBridgeClose();
      return true;
      """, seconds: 8)
    bridge.invalidate()
    let stop = directory.appendingPathComponent("official-host-ci-stop")
    let stopped = directory.appendingPathComponent("official-host-ci-stopped")
    if !FileManager.default.fileExists(atPath: stopped.path) {
      try Data("1".utf8).write(to: stop, options: .atomic)
      _ = try await waitForOfficialHostFile(stopped, mailbox: mailbox, seconds: 8)
    }
    try mailbox.removeSettledFiles()
    XCTAssertEqual(closed as? Bool, true, "The official page did not close its stream transport")
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
    await fulfillment(of: [navigation.loaded], timeout: 40)
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
    await fulfillment(of: [navigation.loaded], timeout: 40)
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
  private func pageResult(_ web: WKWebView, _ body: String, seconds: TimeInterval = 30,
                          label: String = "WebKit script") async throws -> Any? {
    let slot = "__iosTest_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    _ = try await web.evaluateJavaScript("""
      void (async () => { \(body) })().then(
        value => globalThis.\(slot) = JSON.stringify({value}),
        error => globalThis.\(slot) = JSON.stringify({error: String(error)}));
      true;
      """)
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    while ProcessInfo.processInfo.systemUptime < deadline {
      let raw = try await web.evaluateJavaScript("""
        (() => { const value = globalThis.\(slot); delete globalThis.\(slot); return value ?? ''; })()
        """)
      if let envelope = raw as? String, !envelope.isEmpty {
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(envelope.utf8)) as? [String: Any])
        if let error = decoded["error"] as? String {
          throw NSError(domain: "OfficialWebCI", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(label): \(error)"])
        }
        return decoded["value"]
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw NSError(domain: "OfficialWebCI", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(label) timed out"])
  }

  private typealias ChatReply = Result<[String: Any], IosChatMailbox.Failure>

  @MainActor
  private func awaitChatReply(_ method: IosChatMailbox.Method,
                              submit: (@escaping (ChatReply) -> Void) -> Void) async throws -> [String: Any] {
    // The production mailbox always completes on the main queue. Suspend the
    // XCTest instead of blocking that queue with a synchronous expectation.
    try await withCheckedThrowingContinuation { continuation in
      var pending: CheckedContinuation<[String: Any], Error>? = continuation
      let timeout = Task { @MainActor in
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        let waiting = pending
        pending = nil
        waiting?.resume(throwing: NSError(domain: "IosChatMailboxCI", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Chat mailbox timed out: \(method.rawValue)"]))
      }
      submit { reply in
        timeout.cancel()
        guard let waiting = pending else { return }
        pending = nil
        switch reply {
        case .success(let value): waiting.resume(returning: value)
        case .failure(let error): waiting.resume(throwing: error)
        }
      }
    }
  }

  @MainActor
  private func request(_ mailbox: IosChatMailbox, _ method: IosChatMailbox.Method,
                       _ value: String? = nil) async throws -> [String: Any] {
    try await awaitChatReply(method) { completion in
      mailbox.request(method, value: value, completion: completion)
    }
  }

  @MainActor
  private func request(_ mailbox: IosChatMailbox, _ method: IosChatMailbox.Method,
                       params: [String: Any]) async throws -> [String: Any] {
    try await awaitChatReply(method) { completion in
      mailbox.request(method, params: params, completion: completion)
    }
  }

  @MainActor
  private func waitForChat(_ mailbox: IosChatMailbox, seconds: TimeInterval = 10,
                           until predicate: ([String: Any]) -> Bool) async throws -> [String: Any] {
    let deadline = ProcessInfo.processInfo.systemUptime + seconds
    var last: [String: Any] = [:]
    repeat {
      last = try await request(mailbox, .snapshot)
      if predicate(last) { return last }
      try await Task.sleep(for: .milliseconds(25))
    } while ProcessInfo.processInfo.systemUptime < deadline
    XCTFail("Chat state not observed: \(last["state"] ?? "unknown") \(last["errorCode"] ?? "none")")
    return last
  }
}
