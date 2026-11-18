import CoreGraphics
import DshEmbeddedNode
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class IosImageNormalizerTests: XCTestCase {
  func testJPEGAppliesOrientationAndShrinksWithoutRetainingMetadata() throws {
    let context = try makeContext(width: 2_400, height: 1_200)
    context.setFillColor(red: 0, green: 0.4, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_200))
    let marker = "fixture-private-description"
    let input = try XCTUnwrap(encode(try XCTUnwrap(context.makeImage()), type: .jpeg, options: [
      kCGImagePropertyOrientation: 6,
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: marker],
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 12.5, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 56.5, kCGImagePropertyGPSLongitudeRef: "W",
      ],
    ]))
    let inputProperties = try properties(input)
    XCTAssertEqual(inputProperties[kCGImagePropertyOrientation] as? Int, 6)
    XCTAssertNotNil(inputProperties[kCGImagePropertyExifDictionary])
    XCTAssertNotNil(inputProperties[kCGImagePropertyGPSDictionary])

    let result = try IosImageNormalizer.normalize(input)
    XCTAssertEqual(result.format, .jpeg)
    XCTAssertEqual(result.format.mimeType, "image/jpeg")
    XCTAssertGreaterThan(result.height, result.width, "EXIF rotation should produce a portrait raster")
    XCTAssertLessThan(result.height, 2_400)
    XCTAssertLessThanOrEqual(result.height, IosImageNormalizer.maxOutputEdge)
    XCTAssertLessThanOrEqual(abs(result.height - 2 * result.width), 2)
    XCTAssertLessThanOrEqual(result.data.count, IosImageNormalizer.maxOutputBytes)
    let outputProperties = try properties(result.data)
    XCTAssertEqual(outputProperties[kCGImagePropertyPixelWidth] as? Int, result.width)
    XCTAssertEqual(outputProperties[kCGImagePropertyPixelHeight] as? Int, result.height)
    XCTAssertTrue(outputProperties[kCGImagePropertyOrientation] == nil ||
                  outputProperties[kCGImagePropertyOrientation] as? Int == 1)
    XCTAssertNil(outputProperties[kCGImagePropertyExifDictionary])
    XCTAssertNil(outputProperties[kCGImagePropertyGPSDictionary])
    XCTAssertNil(result.data.range(of: Data(marker.utf8)))
  }

  func testTransparentPNGRemainsPNGWithoutUpscaling() throws {
    let context = try makeContext(width: 64, height: 48, alpha: true)
    let rect = CGRect(x: 0, y: 0, width: 64, height: 48)
    context.clear(rect)
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
    context.fill(rect)
    let source = try XCTUnwrap(encode(try XCTUnwrap(context.makeImage()), type: .png))
    let result = try IosImageNormalizer.normalize(source)
    XCTAssertEqual(result.format, .png)
    XCTAssertEqual(result.format.mimeType, "image/png")
    XCTAssertEqual(result.width, 64)
    XCTAssertEqual(result.height, 48)

    let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource(result.data), 0, nil))
    let pixel = try makeContext(width: 1, height: 1, alpha: true)
    pixel.setBlendMode(.copy)
    pixel.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let alpha = try XCTUnwrap(pixel.data).load(fromByteOffset: 3, as: UInt8.self)
    XCTAssertTrue((126...129).contains(alpha))
  }

  func testHighEntropyAlphaPNGStaysUnderOutputCap() throws {
    let edge = IosImageNormalizer.maxOutputEdge
    let context = try makeContext(width: edge, height: edge, alpha: true)
    let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
    var state: UInt32 = 0xD5A5_B4A1
    for offset in stride(from: 0, to: edge * edge * 4, by: 4) {
      state ^= state << 13
      state ^= state >> 17
      state ^= state << 5
      pixels[offset] = UInt8(state & 0x7f)
      pixels[offset + 1] = UInt8((state >> 8) & 0x7f)
      pixels[offset + 2] = UInt8((state >> 16) & 0x7f)
      pixels[offset + 3] = state & 0x8000_0000 == 0 ? 128 : 255
    }
    let input = try XCTUnwrap(encode(try XCTUnwrap(context.makeImage()), type: .png))
    XCTAssertGreaterThan(input.count, IosImageNormalizer.maxOutputBytes)
    let result = try IosImageNormalizer.normalize(input)
    XCTAssertEqual(result.format, .png)
    XCTAssertLessThan(result.width, edge)
    XCTAssertLessThanOrEqual(result.data.count, IosImageNormalizer.maxOutputBytes)
    XCTAssertEqual(try properties(result.data)[kCGImagePropertyPixelHeight] as? Int, result.height)
  }

  func testStaticHEICNormalizesToJPEGWhenFixtureEncoderIsAvailable() throws {
    let context = try makeContext(width: 80, height: 48)
    context.setFillColor(red: 0.7, green: 0.2, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 48))
    guard let heic = encode(try XCTUnwrap(context.makeImage()), type: .heic) else {
      throw XCTSkip("ImageIO HEIC fixture encoder is unavailable on this simulator.")
    }
    let result = try IosImageNormalizer.normalize(heic)
    XCTAssertEqual(result.format, .jpeg)
    XCTAssertEqual(result.width, 80)
    XCTAssertEqual(result.height, 48)
  }

  func testRejectsInvalidUnsupportedOversizedAndAnimatedInputs() throws {
    assertFailure(Data("not an image".utf8), .invalidImage)
    assertFailure(Data(count: IosImageNormalizer.maxSourceBytes + 1), .sourceTooLarge)

    let edge = IosImageNormalizer.maxSourceEdge + 1
    let wide = try makeContext(width: edge, height: 1)
    let widePNG = try XCTUnwrap(encode(try XCTUnwrap(wide.makeImage()), type: .png))
    assertFailure(widePNG, .sourceTooLarge)

    let context = try makeContext(width: 1, height: 1)
    let image = try XCTUnwrap(context.makeImage())
    let gif = try XCTUnwrap(encode(image, type: .gif))
    assertFailure(gif, .unsupportedFormat)
    let png = try XCTUnwrap(encode(image, type: .png))
    guard png.count > 33 else { return XCTFail("PNG fixture has no complete IHDR") }
    assertFailure(Data(png.dropLast(12)), .invalidImage)

    // Add a one-frame animation control and frame control after IHDR. A
    // single IDAT image is not enough to establish that a PNG is static.
    var apng = Data(png.prefix(33))
    apng.append(pngChunk("acTL", payload: [0, 0, 0, 1, 0, 0, 0, 0]))
    apng.append(pngChunk("fcTL", payload: [
      0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 10, 0, 0,
    ]))
    apng.append(contentsOf: png.dropFirst(33))
    assertFailure(apng, .notStatic)
  }

  private func makeContext(width: Int, height: Int, alpha: Bool = false) throws -> CGContext {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let alphaInfo: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
    return try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: space, bitmapInfo: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
  }

  private func encode(_ image: CGImage, type: UTType, options: [CFString: Any] = [:]) -> Data? {
    guard let data = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    return CGImageDestinationFinalize(destination) ? (data as Data) : nil
  }

  private func imageSource(_ data: Data) throws -> CGImageSource {
    try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
  }

  private func properties(_ data: Data) throws -> [CFString: Any] {
    try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource(data), 0, nil) as? [CFString: Any])
  }

  private func assertFailure(_ data: Data, _ expected: IosImageNormalizer.Failure,
                             file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try IosImageNormalizer.normalize(data), file: file, line: line) {
      XCTAssertEqual($0 as? IosImageNormalizer.Failure, expected, file: file, line: line)
    }
  }

  private func pngChunk(_ name: String, payload: [UInt8]) -> Data {
    let body = Array(name.utf8) + payload
    var crc = UInt32.max
    for byte in body {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB8_8320) }
    }
    func bytes(_ value: UInt32) -> [UInt8] {
      [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
    }
    return Data(bytes(UInt32(payload.count)) + body + bytes(~crc))
  }
}
