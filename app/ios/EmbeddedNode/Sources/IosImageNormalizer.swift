import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Local raster normalization for bytes already admitted by the caller. This
/// API does not select files, open URLs, or grant access to attachments.
public enum IosImageNormalizer {
  public static let maxSourceBytes = 20 * 1024 * 1024
  public static let maxSourcePixels = 40_000_000
  public static let maxSourceEdge = 16_384
  public static let maxOutputEdge = 2_048
  public static let maxOutputBytes = 6 * 1024 * 1024

  public enum Format: String, Sendable {
    case jpeg, png

    public var mimeType: String { self == .jpeg ? "image/jpeg" : "image/png" }
    fileprivate var type: UTType { self == .jpeg ? .jpeg : .png }
  }

  public struct Result: Sendable {
    public let data: Data
    public let format: Format
    public let width: Int
    public let height: Int
  }

  public enum Failure: Error, Equatable {
    case invalidImage
    case unsupportedFormat
    case notStatic
    case sourceTooLarge
    case outputTooLarge
    case encodingFailed
  }

  /// Synchronous CPU/codec work. A UI or plugin should submit one job at a
  /// time to an off-main serial worker, then return the result on its UI lane.
  public static func normalize(_ sourceData: Data) throws -> Result {
    guard !sourceData.isEmpty else { throw Failure.invalidImage }
    guard sourceData.count <= maxSourceBytes else { throw Failure.sourceTooLarge }
    return try autoreleasepool {
      let readOptions = [kCGImageSourceShouldCache: false] as CFDictionary
      guard let source = CGImageSourceCreateWithData(sourceData as CFData, readOptions),
            let identifier = CGImageSourceGetType(source) else { throw Failure.invalidImage }
      let type = identifier as String
      guard type == UTType.jpeg.identifier || type == UTType.png.identifier || type == UTType.heic.identifier
        else { throw Failure.unsupportedFormat }
      let count = CGImageSourceGetCount(source)
      guard count > 0 else { throw Failure.invalidImage }
      guard count == 1 else { throw Failure.notStatic }
      let pngHasAlpha: Bool?
      if type == UTType.png.identifier {
        pngHasAlpha = try sourceData.withUnsafeBytes(inspectStaticPNG)
      } else {
        pngHasAlpha = nil
        if type == UTType.heic.identifier {
          try sourceData.withUnsafeBytes(validateStaticHEIC)
        }
      }

      guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, readOptions) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0,
            let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0
        else { throw Failure.invalidImage }
      guard width <= maxSourceEdge, height <= maxSourceEdge, width <= maxSourcePixels / height
        else { throw Failure.sourceTooLarge }

      let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxOutputEdge),
        kCGImageSourceShouldCacheImmediately: true,
      ] as [CFString: Any] as CFDictionary
      guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
            thumbnail.width > 0, thumbnail.height > 0,
            max(thumbnail.width, thumbnail.height) <= maxOutputEdge,
            CGImageSourceGetStatus(source) == .statusComplete,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        else { throw Failure.invalidImage }

      let format: Format
      if let pngHasAlpha {
        format = pngHasAlpha ? .png : .jpeg
      } else if type == UTType.jpeg.identifier {
        format = .jpeg // JPEG has no alpha, even if the decoder uses an RGBA backing store.
      } else {
        switch thumbnail.alphaInfo {
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly: format = .png
        default: format = .jpeg
        }
      }
      do {
        return try encodeRaster(thumbnail, format: format, maxEdge: maxOutputEdge)
      } catch Failure.outputTooLarge where max(thumbnail.width, thumbnail.height) > 1_024 {
        // A high-entropy PNG may exceed the byte cap at the first size. Keep
        // its alpha and retry once with a smaller raster, not a second decode.
        return try encodeRaster(thumbnail, format: format, maxEdge: 1_024)
      }
    }
  }

  private static func inspectStaticPNG(_ bytes: UnsafeRawBufferPointer) throws -> Bool {
    // ImageIO may expose a single image for an APNG with a single frame or a
    // separate poster. Inspect chunk boundaries, not arbitrary contents.
    guard bytes.count >= 33, bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
          word(bytes, 8) == 13, word(bytes, 12) == 0x4948_4452 // IHDR
      else { throw Failure.invalidImage }
    let colorType = bytes[25]
    var hasAlpha = colorType == 4 || colorType == 6
    var offset = 33
    while bytes.count - offset >= 12 {
      let length = Int(word(bytes, offset))
      guard length <= bytes.count - offset - 12 else { throw Failure.invalidImage }
      let kind = word(bytes, offset + 4)
      offset += 12 + length
      switch kind {
      case 0x6163_544C, 0x6663_544C, 0x6664_4154: // acTL, fcTL, fdAT
        throw Failure.notStatic
      case 0x7452_4E53: // tRNS (palette, RGB or grayscale transparency)
        hasAlpha = true
      case 0x4945_4E44: // IEND
        guard length == 0, offset == bytes.count else { throw Failure.invalidImage }
        return hasAlpha
      default: break
      }
    }
    throw Failure.invalidImage
  }

  private static func validateStaticHEIC(_ bytes: UnsafeRawBufferPointer) throws {
    // A HEIF file can contain image items and timed tracks together. Reject
    // top-level movie boxes even if ImageIO only exposes one still image item.
    var offset = 0
    while bytes.count - offset >= 8 {
      let remaining = bytes.count - offset
      let size = word(bytes, offset)
      let kind = word(bytes, offset + 4)
      let length: Int
      if size == 1 {
        guard remaining >= 16 else { throw Failure.invalidImage }
        let extended = (UInt64(word(bytes, offset + 8)) << 32) | UInt64(word(bytes, offset + 12))
        guard extended >= 16, extended <= UInt64(remaining) else { throw Failure.invalidImage }
        length = Int(extended)
      } else if size == 0 {
        length = remaining
      } else {
        length = Int(size)
        guard length >= 8, length <= remaining else { throw Failure.invalidImage }
      }
      guard kind != 0x6D6F_6F76 else { throw Failure.notStatic } // moov
      offset += length
    }
    guard offset == bytes.count else { throw Failure.invalidImage }
  }

  private static func word(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
    (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
      | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
  }

  private static func encodeRaster(_ image: CGImage, format: Format, maxEdge: Int) throws -> Result {
    let divisor = max(max(image.width, image.height), maxEdge)
    let width = max(1, image.width * maxEdge / divisor)
    let height = max(1, image.height * maxEdge / divisor)
    let alpha: CGImageAlphaInfo = format == .png ? .premultipliedLast : .noneSkipLast
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: colorSpace, bitmapInfo: alpha.rawValue)
      else { throw Failure.encodingFailed }
    context.setBlendMode(.copy)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let raster = context.makeImage() else { throw Failure.encodingFailed }

    let sink = BoundedOutput()
    var callbacks = CGDataConsumerCallbacks(putBytes: { info, buffer, count in
      guard let info else { return 0 }
      return Unmanaged<BoundedOutput>.fromOpaque(info).takeUnretainedValue().append(buffer, count: count)
    }, releaseConsumer: nil)
    guard let consumer = CGDataConsumer(info: Unmanaged.passUnretained(sink).toOpaque(), cbks: &callbacks),
          let destination = CGImageDestinationCreateWithDataConsumer(consumer, format.type.identifier as CFString, 1, nil)
      else { throw Failure.encodingFailed }
    let options = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary : nil
    // Encode only the new 8-bit sRGB raster. Never copy source image properties,
    // orientation tags, thumbnails, auxiliary images, or color profile bytes.
    CGImageDestinationAddImage(destination, raster, options)
    let success = CGImageDestinationFinalize(destination)
    if sink.exceededLimit { throw Failure.outputTooLarge }
    guard success, !sink.data.isEmpty else { throw Failure.encodingFailed }
    return Result(data: sink.data, format: format, width: width, height: height)
  }

  private final class BoundedOutput {
    private(set) var data = Data()
    private(set) var exceededLimit = false

    func append(_ buffer: UnsafeRawPointer, count: Int) -> Int {
      guard !exceededLimit, count >= 0, count <= maxOutputBytes - data.count else {
        exceededLimit = true
        return 0
      }
      data.append(buffer.assumingMemoryBound(to: UInt8.self), count: count)
      return count
    }
  }
}
