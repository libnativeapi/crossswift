import XCTest
import UniformTypeIdentifiers
@testable import CrossAppKit

final class CrossAppKitTests: XCTestCase {
  func testCoordinateYFlipRoundTrip() {
    let primaryH: CGFloat = 1080
    let appKitRect = NSRect(x: 200, y: 300, width: 750, height: 475)
    let topLeft = CrossAppKitCoordinates.rectToNativeTopLeft(appKitRect, primaryHeight: primaryH)
    XCTAssertEqual(topLeft.x, 200, accuracy: 0.001)
    XCTAssertEqual(topLeft.y, 1080 - 300 - 475, accuracy: 0.001)
    let restored = CrossAppKitCoordinates.rectFromNativeTopLeft(
      x: topLeft.x, y: topLeft.y, width: topLeft.width, height: topLeft.height, primaryHeight: primaryH
    )
    XCTAssertEqual(restored, appKitRect)
  }

  func testDynamicColorResolvesByAppearance() {
    let color = CrossAppKit.NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? CrossAppKit.NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)
        : CrossAppKit.NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
    }
    let dark = color.resolved(for: CrossAppKit.NSAppearance(named: .darkAqua))
    let light = color.resolved(for: CrossAppKit.NSAppearance(named: .aqua))
    XCTAssertEqual(dark.r, 1.0, accuracy: 0.001)
    XCTAssertEqual(dark.a, 0.4, accuracy: 0.001)
    XCTAssertEqual(light.r, 0.0, accuracy: 0.001)
    XCTAssertEqual(light.a, 0.55, accuracy: 0.001)
  }

  func testFontTextStylePreservesDescriptorWeight() {
    let headline = CrossAppKit.NSFont.preferredFont(forTextStyle: .headline)
    XCTAssertEqual(headline.pointSize, 13)
    XCTAssertEqual(headline.fontDescriptor.weight, CrossAppKit.NSFont.Weight.bold)
    let scaled = CrossAppKit.NSFont(descriptor: headline.fontDescriptor, size: 16)
    XCTAssertEqual(scaled?.pointSize, 16)
    XCTAssertEqual(scaled?.fontDescriptor.weight, CrossAppKit.NSFont.Weight.bold)
  }

  func testBundleAwareXCAassetsPDFResolution() throws {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossappkit-xcassets-\(UUID().uuidString)")
    let imageset = tmp.appendingPathComponent("FluentIcons.xcassets/ic_fluent_home_20_regular.imageset")
    try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let pdfURL = imageset.appendingPathComponent("ic_fluent_home_20_regular.pdf")
    try "%PDF-1.4\n".write(to: pdfURL, atomically: true, encoding: .utf8)
    let contentsJSON = """
    {
      "images" : [
        {
          "filename" : "ic_fluent_home_20_regular.pdf",
          "idiom" : "universal"
        }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try contentsJSON.write(
      to: imageset.appendingPathComponent("Contents.json"),
      atomically: true,
      encoding: .utf8
    )

    let bundle = try XCTUnwrap(Bundle(url: tmp))
    let resolved = CrossAppKit.NSImage.resolveAssetPath(named: "ic_fluent_home_20_regular", in: bundle)
    XCTAssertEqual(
      resolved.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
      pdfURL.standardizedFileURL.path
    )
    let nsImg: CrossAppKit.NSImage? = bundle.image(forResource: "ic_fluent_home_20_regular")
    XCTAssertNotNil(nsImg)
    XCTAssertEqual(
      nsImg?.filePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
      pdfURL.standardizedFileURL.path
    )
  }

  func testOffscreenImageDrawingRecordsTileAndSymbol() {
    let previousRenderer = CrossAppKit.NSImage.offscreenRenderer
    let previousLookup = CrossAppKit.NSImage.symbolLookupHandler
    defer {
      CrossAppKit.NSImage.offscreenRenderer = previousRenderer
      CrossAppKit.NSImage.symbolLookupHandler = previousLookup
    }

    nonisolated(unsafe) var capturedOps: [_OffscreenDrawOp] = []
    CrossAppKit.NSImage.symbolLookupHandler = { $0 == "doc.text" }
    CrossAppKit.NSImage.offscreenRenderer = { _, _, ops in
      capturedOps = ops
      return Data([0x89, 0x50, 0x4E, 0x47])
    }

    let img = CrossAppKit.NSImage(size: NSSize(width: 48, height: 48), flipped: false) { _ in
      CrossAppKit.NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.09).setFill()
      CrossAppKit.NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 40, height: 40), xRadius: 10, yRadius: 10).fill()
      let ink = CrossAppKit.NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
      let cfg = CrossAppKit.NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        .applying(.init(paletteColors: [ink]))
      if let sym = CrossAppKit.NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg)
      {
        sym.draw(in: NSRect(x: 12, y: 12, width: sym.size.width, height: sym.size.height))
      }
      return true
    }

    XCTAssertEqual(capturedOps.count, 2)
    XCTAssertNotNil(img.imageData)
    if case .symbol(let name, _, _, let pt, _) = capturedOps[1] {
      XCTAssertEqual(name, "doc.text")
      XCTAssertEqual(pt, 21, accuracy: 0.001)
    } else {
      XCTFail("Expected symbol op at index 1")
    }
  }

  func testCurrentRunningApplicationHasNoHardcodedHostAppIdentity() {
    let app = CrossAppKit.NSRunningApplication.current
    let bundleID = (app.bundleIdentifier ?? "").lowercased()
    let name = (app.localizedName ?? "").lowercased()
    XCTAssertFalse(bundleID.contains("tinycast"))
    XCTAssertFalse(bundleID.contains("abueammar"))
    XCTAssertFalse(name.contains("tinycast"))
  }

  func testPasteboardCustomTypesRegisterDynamically() {
    let pb = CrossAppKit.NSPasteboard.withUniqueName()
    let customType = CrossAppKit.NSPasteboard.PasteboardType("dev.crossswift.test.custom")
    let item = CrossAppKit.NSPasteboardItem()
    item.setString("payload", forType: customType)
    XCTAssertTrue(pb.writeObjects([item]))
    XCTAssertEqual(pb.string(forType: customType), "payload")
    XCTAssertEqual(pb.types?.contains(customType), true)
  }

  @MainActor
  func testOpenSavePanelExtensionsAndTildeAbbreviation() {
    XCTAssertEqual(
      CrossAppKit.NSSavePanel._normalizeDialogExtensions([.json, .plainText], allowAppBundleShortcuts: false),
      [".json", ".txt"]
    )
    XCTAssertTrue([UTType.folder, UTType.applicationBundle].allSatisfy { $0.conforms(to: .directory) })
    #if os(Windows)
      XCTAssertEqual(
        CrossAppKit.NSSavePanel._normalizeDialogExtensions([.applicationBundle], allowAppBundleShortcuts: true),
        [".exe", ".lnk"]
      )
      let home = NSHomeDirectory()
      if !home.isEmpty {
        let sub = URL(filePath: home).appendingPathComponent("Desktop").path
        XCTAssertEqual((sub as NSString).abbreviatingWithTildeInPath, "~/Desktop")
      }
      XCTAssertEqual(("/D:/Apps/Tools" as NSString).abbreviatingWithTildeInPath, "D:\\Apps\\Tools")
    #endif
  }
}
