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

  func testOpenSavePanelExtensionsAndTildeAbbreviation() {
    MainActor.assumeIsolated {
      #if !os(macOS)
        XCTAssertEqual(
          CrossAppKit.NSSavePanel._normalizeDialogExtensions([.json, .plainText], allowAppBundleShortcuts: false),
          [".json", ".txt"]
        )
      #endif
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

  func testWin32KeyCodeAndScanCodeMapping() {
    // OEM punctuation, numpad, F13-F20, modifiers
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xBA), 0x29) // ;
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xBF), 0x2C) // /
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xC0), 0x32) // `
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xDB), 0x21) // [
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xDC), 0x2A) // \
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xDD), 0x1E) // ]
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xDE), 0x27) // '
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x60), 0x52) // Numpad 0
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x7C), 0x69) // F13
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x83), 0x5A) // F20
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xA0), 0x38) // LShift
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0xA1), 0x3C) // RShift

    // Extended scan code disambiguates Return vs Keypad Enter and physical QWERTZ Y/Z
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x0D, scanCode: 0x1C), 0x24)
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x0D, scanCode: 0xE01C), 0x4C)
    // On QWERTZ, pressing physical Y key (scan 0x15) sends VK_Z (0x5A) -> physical kVK_ANSI_Y (0x10).
    XCTAssertEqual(CrossAppKit.NSEvent.carbonKeyCode(fromWin32VK: 0x5A, scanCode: 0x15), 0x10)

    // Reverse lookup round-trip
    XCTAssertEqual(CrossAppKit.NSEvent.win32VirtualKey(fromCarbonKeyCode: 0x00), 0x41) // A
    XCTAssertEqual(CrossAppKit.NSEvent.win32VirtualKey(fromCarbonKeyCode: 0x29), 0xBA) // ;
    XCTAssertEqual(CrossAppKit.NSEvent.win32VirtualKey(fromCarbonKeyCode: 0x7E), 0x26) // Up
  }

  func testWin32KeyEventCharactersAndModifierSemantics() {
    // Plain letter
    let lowerA = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x41, modifierFlags: [])
    XCTAssertEqual(lowerA.characters, "a")
    XCTAssertEqual(lowerA.charactersIgnoringModifiers, "a")
    XCTAssertEqual(lowerA.keyCode, 0x00)

    // Shift applies to BOTH characters and charactersIgnoringModifiers
    let upperA = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x41, modifierFlags: [.shift])
    XCTAssertEqual(upperA.characters, "A")
    XCTAssertEqual(upperA.charactersIgnoringModifiers, "A")

    // Control+N: characters is ASCII control char (\u{0E}), charactersIgnoringModifiers is "n"
    let ctrlN = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x4E, modifierFlags: [.control])
    XCTAssertEqual(ctrlN.characters, "\u{0E}")
    XCTAssertEqual(ctrlN.charactersIgnoringModifiers, "n")

    // Command+Z and Command+Shift+Z preserve AppKit semantics
    let cmdZ = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x5A, modifierFlags: [.command])
    XCTAssertEqual(cmdZ.characters, "z")
    XCTAssertEqual(cmdZ.charactersIgnoringModifiers, "z")
    let cmdShiftZ = CrossAppKit.NSEvent.win32KeyEvent(
      type: .keyDown, vk: 0x5A, modifierFlags: [.command, .shift]
    )
    XCTAssertEqual(cmdShiftZ.characters, "Z")
    XCTAssertEqual(cmdShiftZ.charactersIgnoringModifiers, "Z")

    // Special keys: arrows, Shift+Tab (backTab), Backspace (0x7F), Extended Keypad Enter (0x03)
    let up = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x26)
    XCTAssertEqual(up.specialKey, .upArrow)
    let backTab = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x09, modifierFlags: [.shift])
    XCTAssertEqual(backTab.specialKey, .backTab)
    let backspace = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x08)
    XCTAssertEqual(backspace.specialKey, .delete)
    let kpEnter = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x0D, scanCode: 0xE01C)
    XCTAssertEqual(kpEnter.specialKey, .enter)

    // flagsChanged events have nil characters
    let flagsEv = CrossAppKit.NSEvent.win32KeyEvent(
      type: .flagsChanged, vk: 0xA0, modifierFlags: [.shift]
    )
    XCTAssertNil(flagsEv.characters)
    XCTAssertNil(flagsEv.charactersIgnoringModifiers)
    XCTAssertEqual(flagsEv.keyCode, 0x38)

    // characters(byApplyingModifiers:) dynamically reflects requested modifiers
    XCTAssertEqual(lowerA.characters(byApplyingModifiers: [.shift]), "A")
    XCTAssertEqual(upperA.characters(byApplyingModifiers: []), "a")

    // Repeated ToUnicodeEx calls on punctuation/accent keys must not corrupt subsequent key state
    for _ in 0..<5 {
      _ = CrossAppKit.NSEvent.translateWin32Key(vk: 0xC0, modifierFlags: [])
      _ = CrossAppKit.NSEvent.translateWin32Key(vk: 0xDE, modifierFlags: [.shift])
    }
    let cleanE = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x45, modifierFlags: [])
    XCTAssertEqual(cleanE.characters, "e")
    XCTAssertEqual(cleanE.charactersIgnoringModifiers, "e")
  }

  func testKeyEquivalentMatchingForButtonMenuAndWindow() {
    MainActor.assumeIsolated {
      let cmdK = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x4B, modifierFlags: [.command])
      XCTAssertTrue(cmdK.matchesKeyEquivalent("k", modifierMask: [.command]))
      XCTAssertFalse(cmdK.matchesKeyEquivalent("K", modifierMask: [.command])) // uppercase requires Shift
      XCTAssertFalse(cmdK.matchesKeyEquivalent("k", modifierMask: [.control]))

      let cmdShiftZ = CrossAppKit.NSEvent.win32KeyEvent(
        type: .keyDown, vk: 0x5A, modifierFlags: [.command, .shift]
      )
      XCTAssertTrue(cmdShiftZ.matchesKeyEquivalent("Z", modifierMask: [.command]))
      XCTAssertTrue(cmdShiftZ.matchesKeyEquivalent("z", modifierMask: [.command, .shift]))
      XCTAssertFalse(cmdShiftZ.matchesKeyEquivalent("z", modifierMask: [.command]))

      // Shifted layout symbol (e.g. Cmd+?) matches even if modifierMask only specifies [.command]
      let cmdQuestion = CrossAppKit.NSEvent(
        type: .keyDown,
        modifierFlags: [.command, .shift],
        characters: "?",
        charactersIgnoringModifiers: "?",
        keyCode: 0x2C
      )
      XCTAssertTrue(cmdQuestion.matchesKeyEquivalent("?", modifierMask: [.command]))

      // NSButton + NSWindow.performKeyEquivalent routing
      let win = CrossAppKit.NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      defer { win.close() }
      let root = CrossAppKit.NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
      let button = CrossAppKit.NSButton(title: "Save", target: nil, action: nil)
      button.keyEquivalent = "s"
      button.keyEquivalentModifierMask = [.command]
      var buttonClicks = 0
      button.actionHandler = { _ in buttonClicks += 1 }
      root.addSubview(button)
      win.contentView = root

      let cmdS = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x53, modifierFlags: [.command])
      XCTAssertTrue(win.performKeyEquivalent(with: cmdS))
      XCTAssertEqual(buttonClicks, 1)

      // Disabled button must not fire
      button.isEnabled = false
      XCTAssertFalse(win.performKeyEquivalent(with: cmdS))
      XCTAssertEqual(buttonClicks, 1)

      // NSMenu.performKeyEquivalent (including submenu)
      let menu = CrossAppKit.NSMenu(title: "Main")
      let sub = CrossAppKit.NSMenu(title: "Edit")
      var undoCount = 0
      let undoItem = CrossAppKit.NSMenuItem(title: "Undo", action: nil, keyEquivalent: "z")
      undoItem.keyEquivalentModifierMask = [.command]
      undoItem.actionClosure = { undoCount += 1 }
      sub.addItem(undoItem)
      let editRoot = CrossAppKit.NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
      editRoot.submenu = sub
      menu.addItem(editRoot)

      let cmdZ = CrossAppKit.NSEvent.win32KeyEvent(type: .keyDown, vk: 0x5A, modifierFlags: [.command])
      XCTAssertTrue(menu.performKeyEquivalent(with: cmdZ))
      XCTAssertEqual(undoCount, 1)
    }
  }

  func testWindowFrameAndContentLayoutRectParity() {
    MainActor.assumeIsolated {
      let content = NSRect(x: 100, y: 120, width: 420, height: 300)

      // Borderless window has zero chrome insets
      let borderlessFrame = CrossAppKit.NSWindow.frameRect(forContentRect: content, styleMask: [.borderless])
      XCTAssertEqual(borderlessFrame, content)
      XCTAssertEqual(
        CrossAppKit.NSWindow.contentRect(forFrameRect: borderlessFrame, styleMask: [.borderless]),
        content
      )

      // Titled window round-trips cleanly and includes real Win32 chrome on Windows
      let titledStyle: CrossAppKit.NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
      let titledFrame = CrossAppKit.NSWindow.frameRect(forContentRect: content, styleMask: titledStyle)
      let roundTripped = CrossAppKit.NSWindow.contentRect(forFrameRect: titledFrame, styleMask: titledStyle)
      XCTAssertEqual(roundTripped.origin.x, content.origin.x, accuracy: 0.5)
      XCTAssertEqual(roundTripped.origin.y, content.origin.y, accuracy: 0.5)
      XCTAssertEqual(roundTripped.width, content.width, accuracy: 0.5)
      XCTAssertEqual(roundTripped.height, content.height, accuracy: 0.5)
      #if os(Windows)
        XCTAssertGreaterThan(titledFrame.height, content.height)
        XCTAssertGreaterThan(titledFrame.width, content.width)
      #endif

      // Live titled window with .fullSizeContentView matches AppWindowController's fitContent math
      let win = CrossAppKit.NSWindow(
        contentRect: NSRect(x: 80, y: 80, width: 400, height: 280),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      defer { win.close() }
      let contentFromFrame = win.contentRect(forFrameRect: win.frame)
      let layoutRect = win.contentLayoutRect
      XCTAssertEqual(contentFromFrame.height - layoutRect.height, 0, accuracy: 1.0)
      #if os(Windows)
        XCTAssertGreaterThan(win.frame.height, layoutRect.height)
      #endif

      // contentMinSize round-trips cleanly
      let targetMin = NSSize(width: 360, height: 240)
      win.contentMinSize = targetMin
      XCTAssertEqual(win.contentMinSize, targetMin)
    }
  }

  func testPanelActivationAndChildFocusRestoration() {
    final class NonKeyPanel: CrossAppKit.NSPanel {
      override var canBecomeKey: Bool { false }
    }
    final class CloseCounterDelegate: NSObject, CrossAppKit.NSWindowDelegate {
      var willCloseCount = 0
      func windowWillClose(_ notification: Notification) {
        willCloseCount += 1
      }
    }

    MainActor.assumeIsolated {
      let parent = CrossAppKit.NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 480, height: 360),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      let panel = CrossAppKit.NSPanel(
        contentRect: NSRect(x: 140, y: 140, width: 300, height: 200),
        styleMask: [.borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      let blocker = NonKeyPanel(
        contentRect: NSRect(x: 100, y: 100, width: 480, height: 360),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      defer {
        blocker.close()
        panel.close()
        parent.close()
      }

      XCTAssertTrue(parent.canBecomeMain)
      XCTAssertFalse(panel.canBecomeMain)
      XCTAssertFalse(blocker.canBecomeKey)

      parent.makeKeyAndOrderFront(nil)
      XCTAssertTrue(parent.isKeyWindow)
      XCTAssertTrue(parent.isMainWindow)

      // Ordering front a non-key blocker panel must NOT steal key focus from parent
      parent.addChildWindow(blocker, ordered: .above)
      blocker.orderFront(nil)
      XCTAssertTrue(parent.isKeyWindow)
      XCTAssertFalse(blocker.isKeyWindow)

      // Opening child editor panel makes panel key while keeping parent main
      parent.addChildWindow(panel, ordered: .above)
      panel.makeKeyAndOrderFront(nil)
      XCTAssertTrue(panel.isKeyWindow)
      XCTAssertFalse(panel.isMainWindow)
      XCTAssertFalse(parent.isKeyWindow)
      XCTAssertTrue(parent.isMainWindow)

      // Closing a non-key blocker must not disturb the key panel
      parent.removeChildWindow(blocker)
      blocker.orderOut(nil)
      XCTAssertTrue(panel.isKeyWindow)

      // Removing child window before orderOut (SettingsEditorPresenter pattern) still restores parent key focus
      parent.removeChildWindow(panel)
      panel.orderOut(nil)
      XCTAssertFalse(panel.isKeyWindow)
      XCTAssertTrue(parent.isKeyWindow)
      XCTAssertTrue(parent.isMainWindow)

      // close() with isReleasedWhenClosed = true notifies delegate exactly once
      let closeDelegate = CloseCounterDelegate()
      let tempWin = CrossAppKit.NSWindow(
        contentRect: NSRect(x: 120, y: 120, width: 200, height: 150),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
      )
      tempWin.isReleasedWhenClosed = true
      tempWin.delegate = closeDelegate
      tempWin.makeKeyAndOrderFront(nil)
      tempWin.close()
      XCTAssertEqual(closeDelegate.willCloseCount, 1)
      XCTAssertTrue(parent.isKeyWindow)
    }
  }
}
