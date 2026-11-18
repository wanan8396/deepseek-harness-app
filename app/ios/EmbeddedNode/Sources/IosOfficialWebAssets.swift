import Foundation
import WebKit

/// Serves only the immutable, locked official frontend files. No HTTP server,
/// no fallback to a network URL, and no dynamic API routes at this layer.
public final class IosOfficialWebAssets: NSObject, WKURLSchemeHandler {
  public static let scheme = "dsh-app"
  public static let startURL = URL(string: "dsh-app://bundle/index.html")!
  public static let bootstrapURL = URL(string: "dsh-app://bundle/")!
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
  private struct Bootstrap: Decodable {
    struct Resource: Decodable { let url: String; let path: String; let contentType: String; let bytes: Int }
    let schemaVersion: Int
    let package: String
    let version: String
    let index: Manifest.Entry
    let resources: [Resource]
    let cspScriptHashes: [String]
  }
  private struct Asset {
    let url: URL
    let bytes: Int
    let contentType: String
    var scriptHashes: [String] = []
  }
  private let assets: [String: Asset]
  private let lock = NSLock()
  private var served: Set<String> = []

  public override init() {
    let bundle = Bundle(for: IosOfficialWebAssets.self).bundleURL
    let root = bundle.appendingPathComponent("dsh-web-frontend", isDirectory: true)
    let manifest = try? JSONDecoder().decode(Manifest.self,
      from: Data(contentsOf: root.appendingPathComponent("distribution-manifest.json")))
    var assets: [String: Asset] = [:]
    if let manifest = manifest, manifest.package == "@deepseek-ai/dsh-web-frontend",
       manifest.version == "0.2.2-rc.3" {
      for entry in manifest.files where Self.bounded(entry.path, entry.bytes) {
        guard let type = Self.mime[(entry.path as NSString).pathExtension] else { continue }
        assets["/" + entry.path] = Asset(url: root.appendingPathComponent(entry.path), bytes: entry.bytes, contentType: type)
      }
    }
    let bootstrap = bundle.appendingPathComponent("dsh-web-bootstrap", isDirectory: true)
    if let data = try? Data(contentsOf: bootstrap.appendingPathComponent("distribution-manifest.json")),
       let manifest = try? JSONDecoder().decode(Bootstrap.self, from: data),
       manifest.package == "@deepseek-ai/dsh-client-modules", manifest.version == "0.2.2-rc.3",
       manifest.schemaVersion == 1, manifest.index.path == "index.html", Self.bounded(manifest.index.path, manifest.index.bytes),
       manifest.resources.count == 2, !manifest.cspScriptHashes.isEmpty,
       manifest.cspScriptHashes.allSatisfy({ $0.range(of: #"^sha256-[A-Za-z0-9+/]{43}=$"#, options: .regularExpression) != nil }) {
      var resources: [String: Asset] = [:]
      for resource in manifest.resources {
        guard resource.url.hasPrefix("/plugins/??@deepseek-ai/dsh-client-modules/client.js&rev="),
              resource.url.count <= 240, ["bootstrap-combo.js", "bootstrap-entry.js"].contains(resource.path),
              Self.bounded(resource.path, resource.bytes) else { continue }
        resources[resource.url] = Asset(url: bootstrap.appendingPathComponent(resource.path),
          bytes: resource.bytes, contentType: "text/javascript; charset=utf-8")
      }
      if resources.count == 2 {
        assets["/"] = Asset(url: bootstrap.appendingPathComponent(manifest.index.path), bytes: manifest.index.bytes,
          contentType: "text/html; charset=utf-8", scriptHashes: manifest.cspScriptHashes)
        assets.merge(resources) { current, _ in current }
      }
    }
    self.assets = assets
    super.init()
  }

  private static func bounded(_ path: String, _ bytes: Int) -> Bool {
    guard bytes >= 0, bytes <= 64 * 1024 * 1024, path.utf8.count <= 256,
          !path.contains("\\"), !path.contains("%") else { return false }
    return !path.split(separator: "/", omittingEmptySubsequences: false)
      .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
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
          parts.user == nil, parts.password == nil, parts.fragment == nil,
          parts.percentEncodedPath.hasPrefix("/"), !parts.percentEncodedPath.contains("%") else {
      urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
      return
    }
    let path = parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    guard let asset = assets[path],
          let data = try? Data(contentsOf: asset.url, options: [.mappedIfSafe]),
          asset.bytes == data.count else {
      urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
      return
    }
    // Cordis initializes its evaluator at import; only manifest scripts and the
    // exact generated inline bootstrap hashes have a source in this document.
    let hashes = asset.scriptHashes.map { " '\($0)'" }.joined()
    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
      "Content-Type": asset.contentType, "Cache-Control": "no-store", "Access-Control-Allow-Origin": "*",
      "Content-Security-Policy": "default-src 'none'; script-src dsh-app: 'unsafe-eval'\(hashes); style-src dsh-app: 'unsafe-inline'; font-src dsh-app:; img-src dsh-app: data:; manifest-src dsh-app:; connect-src 'none'; form-action 'none'; base-uri 'none'",
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
