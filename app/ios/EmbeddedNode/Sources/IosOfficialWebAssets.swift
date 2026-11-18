import CryptoKit
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
  private struct Preview: Decodable {
    struct File: Decodable {
      let path: String
      let bytes: Int
      let sha256: String
    }
    struct Resource: Decodable {
      let url: String
      let contentType: String
      let path: String
      let bytes: Int
      let sha256: String
    }
    struct Graph: Decodable {
      struct Release: Decodable { let version: String }
      struct Entry: Decodable { let id: String; let rev: String; let url: String }
      struct Batch: Decodable { let phase: String; let entries: [String]; let rev: String; let url: String }
      let release: Release
      let entries: [Entry]
      let batches: [Batch]
    }
    let schemaVersion: Int
    let stage: String
    let officialUIReady: Bool
    let graph: Graph
    let index: File
    let resources: [Resource]
    struct AppAsset: Decodable {
      let route: String
      let path: String
      let contentType: String
      let bytes: Int
      let sha256: String
    }
    let appAssets: [AppAsset]?
    let cspScriptHashes: [String]
  }
  private struct Asset {
    let url: URL
    let bytes: Int
    let contentType: String
    var scriptHashes: [String] = []
    var previewData: Data? = nil
  }
  private let assets: [String: Asset]
  private let lock = NSLock()
  private var served: Set<String> = []

  private struct EnginePin: Decodable {
    struct Engine: Decodable { let version: String; let node: String }
    let engine: Engine
  }

  // Read the same declared upstream version which the exporter verifies against
  // the official npm lock. This file is part of the signed framework bundle.
  public static func pinnedEngineVersion() -> String? { enginePin()?.version }

  static func pinnedNodeRequirement() -> String? { enginePin()?.node }

  private static func enginePin() -> EnginePin.Engine? {
    let bundle = Bundle(for: IosOfficialWebAssets.self).bundleURL
    guard let data = try? previewFile(bundle.appendingPathComponent("requirements.json"), limit: 16 * 1024),
          let pin = try? JSONDecoder().decode(EnginePin.self, from: data),
          matches(pin.engine.version, #"\A[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*)?\z"#) else { return nil }
    return pin.engine
  }

  private static func stockAssets(in bundle: URL) -> [String: Asset] {
    guard let version = pinnedEngineVersion() else { return [:] }
    let root = bundle.appendingPathComponent("dsh-web-frontend", isDirectory: true)
    let manifest = try? JSONDecoder().decode(Manifest.self,
      from: Data(contentsOf: root.appendingPathComponent("distribution-manifest.json")))
    var assets: [String: Asset] = [:]
    if let manifest = manifest, manifest.package == "@deepseek-ai/dsh-web-frontend",
       manifest.version == version {
      for entry in manifest.files where Self.bounded(entry.path, entry.bytes) {
        guard let type = Self.mime[(entry.path as NSString).pathExtension] else { continue }
        assets["/" + entry.path] = Asset(url: root.appendingPathComponent(entry.path), bytes: entry.bytes, contentType: type)
      }
    }
    return assets
  }

  public override init() {
    let bundle = Bundle(for: IosOfficialWebAssets.self).bundleURL
    var assets = Self.stockAssets(in: bundle)
    let bootstrap = bundle.appendingPathComponent("dsh-web-bootstrap", isDirectory: true)
    if let version = Self.pinnedEngineVersion(),
       let data = try? Data(contentsOf: bootstrap.appendingPathComponent("distribution-manifest.json")),
       let manifest = try? JSONDecoder().decode(Bootstrap.self, from: data),
       manifest.package == "@deepseek-ai/dsh-client-modules", manifest.version == version,
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

  /// XCTest-only fixture; the default initializer never looks for a preview.
  /// An invalid fixture fails as a unit, without falling back to the singleton.
  public init(previewDirectory: URL) throws {
    let bundle = Bundle(for: IosOfficialWebAssets.self).bundleURL
    var assets = Self.stockAssets(in: bundle)
    let preview = try Self.previewAssets(in: previewDirectory)
    guard assets["/index.html"] != nil, assets.keys.allSatisfy({ preview[$0] == nil }) else {
      throw URLError(.cannotDecodeContentData)
    }
    assets.merge(preview) { current, _ in current }
    self.assets = assets
    super.init()
  }

  private static func previewAssets(in root: URL) throws -> [String: Asset] {
    let invalid = URLError(.cannotDecodeContentData)
    guard root.isFileURL, let version = pinnedEngineVersion() else { throw invalid }
    let bundles = root.appendingPathComponent("bundles", isDirectory: true)
    for directory in [root, bundles] {
      let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink == false else { throw invalid }
    }
    let manifestURL = root.appendingPathComponent("distribution-manifest.json")
    let manifest = try JSONDecoder().decode(Preview.self, from: previewFile(manifestURL, limit: 1024 * 1024))
    guard manifest.schemaVersion == 1, manifest.stage == "official-shell-preview", !manifest.officialUIReady,
          manifest.graph.release.version == version, manifest.graph.entries.count >= 20,
          manifest.index.path == "index.html", (20...128).contains(manifest.resources.count) else { throw invalid }

    var ids: Set<String> = []
    var routes: Set<String> = []
    for row in manifest.graph.entries {
      guard matches(row.id, #"\A@deepseek-ai/dsh-[a-z0-9-]+\z"#), ids.insert(row.id).inserted,
            let route = previewRoute(row.url, ids: [row.id], rev: row.rev), routes.insert(route).inserted else {
        throw invalid
      }
    }
    var batched: Set<String> = []
    var batchRoutes: Set<String> = []
    var bootstrapCount = 0
    for batch in manifest.graph.batches {
      if batch.phase == "bootstrap" {
        guard batch.entries == ["@deepseek-ai/dsh-client-modules"] else { throw invalid }
        bootstrapCount += 1
      } else if batch.phase != "application" {
        throw invalid
      }
      for id in batch.entries {
        guard ids.contains(id), batched.insert(id).inserted else { throw invalid }
      }
      guard let route = previewRoute(batch.url, ids: batch.entries, rev: batch.rev),
            batchRoutes.insert(route).inserted else { throw invalid }
    }
    routes.formUnion(batchRoutes)
    guard bootstrapCount == 1, batchRoutes.count >= 2, batched == ids,
          routes.count == manifest.resources.count else { throw invalid }

    let indexURL = root.appendingPathComponent(manifest.index.path)
    let index = try checkedPreviewFile(indexURL, bytes: manifest.index.bytes, sha256: manifest.index.sha256)
    guard let html = String(data: index, encoding: .utf8) else { throw invalid }
    // Match the exporter's literal <script> tags, then hash the exact UTF-8 bodies.
    let text = html as NSString
    let inlineScripts = try NSRegularExpression(pattern: #"<script>([\s\S]*?)</script>"#)
    let hashes = inlineScripts.matches(in: html, range: NSRange(location: 0, length: text.length)).map {
      "sha256-" + Data(SHA256.hash(data: Data(text.substring(with: $0.range(at: 1)).utf8))).base64EncodedString()
    }
    guard hashes.count >= 3, hashes == manifest.cspScriptHashes else { throw invalid }

    let javascript = "text/javascript; charset=utf-8"
    var assets = ["/": Asset(url: indexURL, bytes: index.count, contentType: "text/html; charset=utf-8",
                             scriptHashes: hashes, previewData: index)]
    for (offset, resource) in manifest.resources.enumerated() {
      let filename = "\(offset)-\(resource.sha256.prefix(12)).js"
      guard routes.remove(resource.url) != nil, resource.contentType == javascript,
            matches(resource.sha256, #"\A[0-9a-f]{64}\z"#), resource.path == "bundles/" + filename else { throw invalid }
      let url = bundles.appendingPathComponent(filename)
      let data = try checkedPreviewFile(url, bytes: resource.bytes, sha256: resource.sha256)
      assets[resource.url] = Asset(url: url, bytes: data.count, contentType: javascript, previewData: data)
    }
    if let extras = manifest.appAssets {
      guard manifest.graph.entries.count == 28, extras.count == 1, let item = extras.first,
            item.route == "/plugins/@deepseek-ai/dsh-client-ui-chat/assets/running-whale%402x-06738fa29b2f.png",
            item.path == "running-whale.png", item.contentType == "image/png", item.bytes == 21631,
            item.sha256 == "0fd990d118113d19af7af4480f2b55d610b103451a08be6f7bf5a146823f8bd3" else { throw invalid }
      let url = root.appendingPathComponent(item.path)
      let data = try checkedPreviewFile(url, bytes: item.bytes, sha256: item.sha256)
      assets[item.route] = Asset(url: url, bytes: data.count, contentType: item.contentType, previewData: data)
    }
    return assets
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func previewRoute(_ reference: String, ids: [String], rev: String) -> String? {
    guard !ids.isEmpty, matches(rev, #"\A[0-9a-f]{12}\z"#), reference.utf8.count < 3072,
          reference == "plugins/??" + ids.map({ $0 + "/client.js" }).joined(separator: ",") + "&rev=" + rev else {
      return nil
    }
    return "/" + reference
  }

  private static func previewFile(_ url: URL, limit: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink == false,
          let size = values.fileSize, size > 0, size <= limit else { throw URLError(.cannotDecodeContentData) }
    let data = try Data(contentsOf: url)
    guard data.count == size else { throw URLError(.cannotDecodeContentData) }
    return data
  }

  private static func checkedPreviewFile(_ url: URL, bytes: Int, sha256: String) throws -> Data {
    guard bytes > 0, bounded(url.lastPathComponent, bytes) else { throw URLError(.cannotDecodeContentData) }
    // Keep the verified bytes so a later replacement of the fixture cannot alter the response.
    let data = try previewFile(url, limit: bytes)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard data.count == bytes, digest == sha256 else { throw URLError(.cannotDecodeContentData) }
    return data
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
          parts.percentEncodedPath.hasPrefix("/"),
           !parts.percentEncodedPath.contains("%") ||
             (parts.percentEncodedQuery == nil && parts.percentEncodedPath == "/plugins/@deepseek-ai/dsh-client-ui-chat/assets/running-whale%402x-06738fa29b2f.png") else {
      urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
      return
    }
    let path = parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    guard let asset = assets[path],
          let data = asset.previewData ?? (try? Data(contentsOf: asset.url, options: [.mappedIfSafe])),
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
