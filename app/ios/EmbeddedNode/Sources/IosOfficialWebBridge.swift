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
  private var committed = false

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
    config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "dshBridge")
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

  public func load() { webView.load(URLRequest(url: IosOfficialWebAssets.bootstrapURL)) }

  public func invalidate() {
    let current = generation
    generation &+= 1
    committed = false
    onInvalidate(current)
  }

  public func userContentController(_ userContentController: WKUserContentController,
                                    didReceive message: WKScriptMessage,
                                    replyHandler: @escaping (Any?, String?) -> Void) {
    let current = generation
    Task { @MainActor in
      guard message.name == "dshBridge", message.webView === webView, committed,
            webView.url == IosOfficialWebAssets.bootstrapURL,
            let body = message.body as? [String: Any], body["type"] as? String == "request",
            let method = body["method"] as? String, ["GET", "POST"].contains(method),
            let path = body["path"] as? String, path.hasPrefix("/api/"), path.count <= 256,
            !path.contains("\\") else {
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

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if webView.url == IosOfficialWebAssets.bootstrapURL { committed = true }
  }

  public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    committed = false
  }
}
