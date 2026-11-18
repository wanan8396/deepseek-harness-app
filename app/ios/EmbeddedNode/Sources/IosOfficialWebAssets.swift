import Foundation
import WebKit

/// Serves only the immutable, locked official frontend files. No HTTP server,
/// no fallback to a network URL, and no dynamic API routes at this layer.
public final class IosOfficialWebAssets: NSObject, WKURLSchemeHandler {
  public static let scheme = "dsh-app"
  public static let startURL = URL(string: "dsh-app://bundle/index.html")!
  private static let mime: [String: String] = [
    "css": "text/css", "html": "text/html", "jpeg": "image/jpeg", "jpg": "image/jpeg",
    "js": "text/javascript", "json": "application/json", "mjs": "text/javascript",
    "png": "image/png", "ico": "image/x-icon", "svg": "image/svg+xml", "txt": "text/plain",
    "ttf": "font/ttf", "wasm": "application/wasm", "webmanifest": "application/manifest+json",
    "webp": "image/webp", "woff": "font/woff", "woff2": "font/woff2",
  ]
  private struct Manifest: Decodable {
    let package: String
    let version: String
    let files: [Entry]
    struct Entry: Decodable { let path: String; let bytes: Int }
  }
  private let root: URL
  private let lengths: [String: Int]
  private let lock = NSLock()
  private var served: Set<String> = []

  public override init() {
    let root = Bundle(for: IosOfficialWebAssets.self).bundleURL
      .appendingPathComponent("dsh-web-frontend", isDirectory: true)
    self.root = root
    let manifest = try? JSONDecoder().decode(Manifest.self,
      from: Data(contentsOf: root.appendingPathComponent("distribution-manifest.json")))
    var lengths: [String: Int] = [:]
    if let manifest = manifest, manifest.package == "@deepseek-ai/dsh-web-frontend",
       manifest.version == "0.2.2-rc.3" {
      for entry in manifest.files where entry.bytes >= 0 && entry.bytes <= 64 * 1024 * 1024 {
        lengths[entry.path] = entry.bytes
      }
    }
    self.lengths = lengths
    super.init()
  }

  public var servedPaths: Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return served
  }

  public func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let request = urlSchemeTask.request
    guard request.httpMethod == "GET", let url = request.url,
          let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme == Self.scheme, parts.host == "bundle", parts.port == nil,
          parts.user == nil, parts.password == nil, parts.query == nil,
          parts.percentEncodedPath.hasPrefix("/"), !parts.percentEncodedPath.contains("%") else {
      urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
      return
    }
    let path = String(parts.percentEncodedPath.dropFirst())
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
          let size = lengths[path], let mime = Self.mime[(path as NSString).pathExtension],
          let data = try? Data(contentsOf: root.appendingPathComponent(path), options: [.mappedIfSafe]),
          size == data.count,
          let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime, "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*",
            "Content-Security-Policy": "default-src 'none'; script-src dsh-app:; style-src dsh-app: 'unsafe-inline'; font-src dsh-app:; img-src dsh-app: data:; manifest-src dsh-app:; connect-src 'none'",
          ]) else {
      urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
      return
    }
    // Synchronous delivery in this callback avoids stop-vs-late-reply races.
    lock.lock(); served.insert(path); lock.unlock()
    urlSchemeTask.didReceive(response)
    urlSchemeTask.didReceive(data)
    urlSchemeTask.didFinish()
  }

  public func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
