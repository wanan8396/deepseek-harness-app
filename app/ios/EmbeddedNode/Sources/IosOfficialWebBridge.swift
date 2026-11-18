import Foundation
import WebKit

/// Page-world transport for the official frontend. It never opens a socket.
@MainActor
public final class IosOfficialWebBridge: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
  public struct Header {
    public let name: String
    public let value: String
    public init(name: String, value: String) { self.name = name; self.value = value }
  }

  public struct HTTPRequest {
    public let method: String
    public let pathAndQuery: String
    public let headers: [Header]
    public let body: Data?
  }

  public struct HTTPResponse {
    public let status: Int
    public let headers: [Header]
    public let body: Data?
    public init(status: Int, headers: [Header] = [], body: Data? = nil) {
      self.status = status
      self.headers = headers
      self.body = body
    }
  }

  public enum Operation { case request(HTTPRequest) }
  public enum Reply { case response(HTTPResponse) }
  public typealias Handler = @MainActor (Operation, UInt64) async throws -> Reply

  public private(set) var webView: WKWebView!
  private let handler: Handler
  private let onInvalidate: (UInt64) -> Void
  private var generation: UInt64 = 1
  public private(set) var isReady = false
  public private(set) var navigationFailure: Error?

  public init(assets: IosOfficialWebAssets, documentStartScript: String, handler: @escaping Handler,
              onInvalidate: @escaping (UInt64) -> Void = { _ in }) {
    self.handler = handler
    self.onInvalidate = onInvalidate
    super.init()
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.setURLSchemeHandler(assets, forURLScheme: IosOfficialWebAssets.scheme)
    config.userContentController.addUserScript(WKUserScript(
      source: documentStartScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    config.userContentController.addScriptMessageHandler(
      WeakMessageHandler(bridge: self), contentWorld: .page, name: "dshBridge")
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
    web.navigationDelegate = self
    webView = web
  }

  public static func ciFixture(schemeHandler: IosOfficialWebAssets, documentStartScript: String,
                               handler: @escaping Handler,
                               onInvalidate: @escaping (UInt64) -> Void = { _ in }) -> IosOfficialWebBridge {
    IosOfficialWebBridge(assets: schemeHandler, documentStartScript: documentStartScript,
                         handler: handler, onInvalidate: onInvalidate)
  }

  public func load() {
    navigationFailure = nil
    webView.load(URLRequest(url: IosOfficialWebAssets.bootstrapURL))
  }

  public func invalidate() {
    let current = generation
    generation &+= 1
    isReady = false
    onInvalidate(current)
  }

  // WKUserContentController retains its handler; a weak proxy lets the App
  // drop the entire page and its owner without a WebView/bridge retain cycle.
  @MainActor
  private final class WeakMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var bridge: IosOfficialWebBridge?
    init(bridge: IosOfficialWebBridge) { self.bridge = bridge }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
      guard let bridge else { replyHandler(nil, "IOS_WEB_TRANSPORT_INVALIDATED"); return }
      bridge.userContentController(userContentController, didReceive: message, replyHandler: replyHandler)
    }
  }

  public func userContentController(_ userContentController: WKUserContentController,
                                    didReceive message: WKScriptMessage,
                                    replyHandler: @escaping (Any?, String?) -> Void) {
    let current = generation
    Task { @MainActor in
      guard current == generation, message.name == "dshBridge", message.webView === webView,
            isReady, message.frameInfo.isMainFrame,
            message.frameInfo.request.url == IosOfficialWebAssets.bootstrapURL,
            webView.url == IosOfficialWebAssets.bootstrapURL,
            let body = message.body as? [String: Any], body["type"] as? String == "request",
            let method = body["method"] as? String, ["GET", "POST"].contains(method),
            let path = body["path"] as? String, path.utf8.count <= 256,
            let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil,
            parts.fragment == nil, parts.percentEncodedPath.hasPrefix("/api/"),
            !parts.percentEncodedPath.contains("%"), !path.contains("\\"),
            !parts.percentEncodedPath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
        replyHandler(nil, "IOS_WEB_TRANSPORT_BLOCKED")
        return
      }
      var headers: [Header] = []
      if let raw = body["headers"] as? [[String]] {
        for pair in raw.prefix(32) where pair.count == 2 {
          headers.append(Header(name: pair[0], value: pair[1]))
        }
      }
      var data: Data?
      if let encoded = body["body"] as? String {
        guard encoded.utf8.count <= 360_000, let decoded = Data(base64Encoded: encoded),
              decoded.count <= 256 * 1024 else {
          replyHandler(nil, "IOS_WEB_TRANSPORT_BLOCKED")
          return
        }
        data = decoded
      }
      do {
        let reply = try await handler(
          .request(HTTPRequest(method: method, pathAndQuery: path, headers: headers, body: data)), current)
        guard current == generation else {
          replyHandler(nil, "IOS_WEB_TRANSPORT_INVALIDATED")
          return
        }
        switch reply {
        case .response(let response):
          replyHandler([
            "status": response.status,
            "headers": response.headers.map { [$0.name, $0.value] },
            "body": response.body?.base64EncodedString() ?? "",
          ], nil)
        }
      } catch {
        replyHandler(nil, "IOS_WEB_TRANSPORT_FAILED")
      }
    }
  }

  public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let allowed = action.targetFrame?.isMainFrame == true
      && action.request.url == IosOfficialWebAssets.bootstrapURL
    decisionHandler(allowed ? .allow : .cancel)
  }

  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    invalidate()
  }

  public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    isReady = webView.url == IosOfficialWebAssets.bootstrapURL
  }

  public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    navigationFailure = error
    invalidate()
  }

  public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    navigationFailure = error
    invalidate()
  }

  public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    navigationFailure = NSError(domain: WKErrorDomain, code: WKError.Code.webContentProcessTerminated.rawValue)
    invalidate()
  }
}
