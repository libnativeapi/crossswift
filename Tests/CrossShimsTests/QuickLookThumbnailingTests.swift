#if !os(macOS) && canImport(QuickLookThumbnailing)
  import CoreGraphics
  import CrossAppKit
  import Foundation
  import QuickLookThumbnailing
  import XCTest

  final class QuickLookThumbnailingTests: XCTestCase {
    /// Writes a minimal valid 24-bit uncompressed BMP file of the requested dimensions.
    private func writeTempBMP(to url: URL, width: Int, height: Int) throws {
      let rowStride = ((width * 3) + 3) & ~3
      let pixelBytes = rowStride * height
      let fileSize = 54 + pixelBytes
      var data = Data(count: fileSize)
      data.withUnsafeMutableBytes { raw in
        let p = raw.bindMemory(to: UInt8.self)
        // BITMAPFILEHEADER (14 bytes)
        p[0] = 0x42 // 'B'
        p[1] = 0x4D // 'M'
        func writeU32(_ offset: Int, _ val: UInt32) {
          p[offset] = UInt8(val & 0xFF)
          p[offset + 1] = UInt8((val >> 8) & 0xFF)
          p[offset + 2] = UInt8((val >> 16) & 0xFF)
          p[offset + 3] = UInt8((val >> 24) & 0xFF)
        }
        func writeU16(_ offset: Int, _ val: UInt16) {
          p[offset] = UInt8(val & 0xFF)
          p[offset + 1] = UInt8((val >> 8) & 0xFF)
        }
        writeU32(2, UInt32(fileSize))
        writeU32(10, 54)
        // BITMAPINFOHEADER (40 bytes)
        writeU32(14, 40)
        writeU32(18, UInt32(width))
        writeU32(22, UInt32(height))
        writeU16(26, 1) // planes
        writeU16(28, 24) // bpp
        writeU32(34, UInt32(pixelBytes))
        // Fill with a visible blue/orange gradient so the image is non-empty.
        for y in 0..<height {
          for x in 0..<width {
            let off = 54 + y * rowStride + x * 3
            p[off] = UInt8((x * 255) / max(width - 1, 1))
            p[off + 1] = UInt8((y * 255) / max(height - 1, 1))
            p[off + 2] = 0xCC
          }
        }
      }
      try data.write(to: url, options: .atomic)
    }

    func testImageFileGeneratesRealPNGThumbnailRespectingSizeAndScale() async throws {
      #if os(Windows)
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("ql-thumb-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let imgURL = dir.appendingPathComponent("sample.bmp")
        try writeTempBMP(to: imgURL, width: 160, height: 80)

        let req = QLThumbnailGenerator.Request(
          fileAt: imgURL,
          size: CGSize(width: 40, height: 40),
          scale: 2.0,
          representationTypes: .thumbnail
        )
        let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
        let png = try XCTUnwrap(rep.nsImage.imageData)
        XCTAssertGreaterThan(png.count, 32)
        // Verify PNG magic signature: 89 50 4E 47 0D 0A 1A 0A
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(rep.type, .thumbnail)

        // Requested pixel box is 40*2 = 80x80; 160x80 preserves 2:1 aspect -> <= 80x40 px.
        let cg = rep.cgImage
        XCTAssertGreaterThan(cg.width, 0)
        XCTAssertGreaterThan(cg.height, 0)
        XCTAssertLessThanOrEqual(cg.width, 80)
        XCTAssertLessThanOrEqual(cg.height, 80)
        // nsImage.size is in logical points (pixels / scale).
        XCTAssertEqual(rep.nsImage.size.width, CGFloat(cg.width) / 2.0, accuracy: 0.5)
        XCTAssertEqual(rep.nsImage.size.height, CGFloat(cg.height) / 2.0, accuracy: 0.5)
        XCTAssertEqual(cg.pngData, png)
      #endif
    }

    func testRegularFileFallsBackToIconForAllAndRejectsThumbnailOnlyWhenUnavailable() async throws {
      #if os(Windows)
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("ql-regular-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("notes.xyzunknown")
        try Data("hello crossswift".utf8).write(to: fileURL, options: .atomic)

        let allReq = QLThumbnailGenerator.Request(
          fileAt: fileURL,
          size: CGSize(width: 48, height: 48),
          scale: 1.0,
          representationTypes: .all
        )
        let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: allReq)
        let png = try XCTUnwrap(rep.nsImage.imageData)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(rep.cgImage.width, 0)
        XCTAssertGreaterThan(rep.cgImage.height, 0)
        XCTAssertEqual(rep.type, .icon)

        let iconOnlyReq = QLThumbnailGenerator.Request(
          fileAt: fileURL,
          size: CGSize(width: 32, height: 32),
          scale: 1.0,
          representationTypes: .icon
        )
        let iconRep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: iconOnlyReq)
        XCTAssertEqual(iconRep.type, .icon)
        XCTAssertNotNil(iconRep.nsImage.imageData)

        // A file with no shell thumbnail handler must fail when only .thumbnail is permitted.
        let thumbOnlyReq = QLThumbnailGenerator.Request(
          fileAt: fileURL,
          size: CGSize(width: 48, height: 48),
          scale: 1.0,
          representationTypes: .thumbnail
        )
        do {
          _ = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: thumbOnlyReq)
          XCTFail("Expected error for .thumbnail-only request on a non-thumbnailable file")
        } catch {
          XCTAssertEqual((error as NSError).domain, QLThumbnailGenerator.errorDomain)
        }
      #endif
    }

    func testNonexistentFileAndInvalidRequestsThrowCleanErrors() async {
      let missingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("does-not-exist-\(UUID().uuidString).png")
      let missingReq = QLThumbnailGenerator.Request(
        fileAt: missingURL,
        size: CGSize(width: 64, height: 64),
        scale: 2.0,
        representationTypes: .all
      )
      do {
        _ = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: missingReq)
        XCTFail("Expected error for nonexistent file")
      } catch {
        let nsErr = error as NSError
        XCTAssertEqual(nsErr.domain, QLThumbnailGenerator.errorDomain)
        XCTAssertEqual(nsErr.code, NSFileReadNoSuchFileError)
      }

      let emptyTypesReq = QLThumbnailGenerator.Request(
        fileAt: FileManager.default.temporaryDirectory,
        size: CGSize(width: 32, height: 32),
        scale: 1.0,
        representationTypes: []
      )
      do {
        _ = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: emptyTypesReq)
        XCTFail("Expected error for empty representationTypes")
      } catch {
        XCTAssertEqual((error as NSError).domain, QLThumbnailGenerator.errorDomain)
      }
    }

    func testCompletionHandlerDeliversThumbnail() throws {
      #if os(Windows)
        let dir = FileManager.default.temporaryDirectory
          .appendingPathComponent("ql-cb-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let imgURL = dir.appendingPathComponent("cb.bmp")
        try writeTempBMP(to: imgURL, width: 64, height: 64)

        let exp = expectation(description: "thumbnail completion")
        let req = QLThumbnailGenerator.Request(
          fileAt: imgURL,
          size: CGSize(width: 32, height: 32),
          scale: 1.0,
          representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
          XCTAssertNil(err)
          XCTAssertNotNil(rep?.nsImage.imageData)
          exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
      #endif
    }
  }
#endif
