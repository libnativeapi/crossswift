import Foundation
#if !os(macOS)
  import NativeAPI
  import UniformTypeIdentifiers
#endif

@MainActor
public protocol NSMenuDelegate: AnyObject {
  func menuWillOpen(_ menu: NSMenu)
  func menuDidClose(_ menu: NSMenu)
  func menuNeedsUpdate(_ menu: NSMenu)
}

extension NSMenuDelegate {
  public func menuWillOpen(_ menu: NSMenu) {}
  public func menuDidClose(_ menu: NSMenu) {}
  public func menuNeedsUpdate(_ menu: NSMenu) {}
}

@MainActor
open class NSMenuItem: NSObject {
  public var title: String {
    didSet {
      #if !os(macOS)
        nativeItem?.setLabel(title)
      #endif
    }
  }
  public weak var target: AnyObject?
  public var action: Selector?
  public var actionClosure: (() -> Void)?
  public var keyEquivalent: String
  public var keyEquivalentModifierMask: NSEvent.ModifierFlags = [.command]
  public var image: NSImage? {
    didSet {
      #if !os(macOS)
        nativeItem?.setIcon(image?.toNativeImage())
      #endif
    }
  }
  public var state: NSControl.StateValue = .off {
    didSet {
      #if !os(macOS)
        let s: NativeAPI.MenuItemState = state == .on ? .checked : (state == .mixed ? .mixed : .unchecked)
        nativeItem?.setState(s)
      #endif
    }
  }
  public var isEnabled: Bool = true {
    didSet {
      #if !os(macOS)
        nativeItem?.setEnabled(isEnabled)
      #endif
    }
  }
  public var isHidden: Bool = false
  public var isAlternate: Bool = false
  public let isSeparatorItem: Bool
  public private(set) var isSectionHeader: Bool = false
  public var identifier: NSUserInterfaceItemIdentifier?
  public var attributedTitle: NSAttributedString? {
    didSet {
      if let attr = attributedTitle {
        title = attr.string
      }
    }
  }
  public weak var menu: NSMenu?
  public var representedObject: Any?
  public var tag: Int = 0
  public var toolTip: String?
  public var submenu: NSMenu? {
    didSet {
      #if !os(macOS)
        nativeItem?.setSubmenu(submenu?.nativeMenu)
      #endif
    }
  }

  #if !os(macOS)
    public private(set) var nativeItem: NativeAPI.MenuItem?
    private var listenerId: ListenerId?
  #endif

  public init(title string: String, action selector: Selector?, keyEquivalent charCode: String) {
    self.title = string
    self.action = selector
    self.keyEquivalent = charCode
    self.isSeparatorItem = false
    super.init()
    setupNativeItem(isSeparator: false)
  }

  private init(separator: Bool) {
    self.title = ""
    self.action = nil
    self.keyEquivalent = ""
    self.isSeparatorItem = true
    super.init()
    setupNativeItem(isSeparator: true)
  }

  public convenience override init() {
    self.init(title: "", action: nil, keyEquivalent: "")
  }

  private func setupNativeItem(isSeparator: Bool) {
    #if !os(macOS)
      let kind: NativeAPI.MenuItemType = isSeparator ? .separator : .normal
      if let item = NativeAPI.MenuItem.createWithLabelAndType(title, type: kind) {
        self.nativeItem = item
        if !keyEquivalent.isEmpty {
          var mods: NativeAPI.ModifierKey = []
          if keyEquivalentModifierMask.contains(.command) { mods.insert(.ctrl) }
          if keyEquivalentModifierMask.contains(.control) { mods.insert(.ctrl) }
          if keyEquivalentModifierMask.contains(.shift) { mods.insert(.shift) }
          if keyEquivalentModifierMask.contains(.option) { mods.insert(.alt) }
          item.setAccelerator(NativeAPI.KeyboardAccelerator(modifiers: mods, key: keyEquivalent.uppercased()))
        }
        listenerId = item.addListener { [weak self] event in
          if case .itemClicked = event {
            #if os(Linux)
              MainActor.assumeIsolated {
                self?.invoke()
              }
            #else
              DispatchQueue.main.async {
                MainActor.assumeIsolated {
                  self?.invoke()
                }
              }
            #endif
          }
        }
      }
    #endif
  }

  public func invoke() {
    guard isEnabled else { return }
    if let closure = actionClosure {
      closure()
      return
    }
    #if canImport(ObjectiveC)
      if let target = target as? NSObject, let action {
        _ = target.perform(action, with: self)
      }
    #endif
  }

  public static func separator() -> NSMenuItem {
    NSMenuItem(separator: true)
  }

  public static func sectionHeader(title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.isSectionHeader = true
    return item
  }
}

@MainActor
open class NSMenu: NSObject {
  public var title: String
  public weak var delegate: (any NSMenuDelegate)?
  public var autoenablesItems: Bool = true
  public var minimumWidth: CGFloat = 0
  public var size: NSSize { NSSize(width: max(minimumWidth, 180), height: CGFloat(items.count * 24)) }
  public var numberOfItems: Int { items.count }
  public var font: NSFont?
  public private(set) var items: [NSMenuItem] = []

  #if !os(macOS)
    public private(set) var nativeMenu: NativeAPI.Menu?
  #endif

  public init(title: String = "") {
    self.title = title
    super.init()
    #if !os(macOS)
      self.nativeMenu = NativeAPI.Menu.create()
    #endif
  }

  public convenience override init() {
    self.init(title: "")
  }

  public func addItem(_ newItem: NSMenuItem) {
    newItem.menu = self
    items.append(newItem)
    #if !os(macOS)
      if newItem.isSeparatorItem {
        nativeMenu?.addSeparator()
      } else if let ni = newItem.nativeItem {
        nativeMenu?.addItem(ni)
      }
    #endif
  }

  @discardableResult
  public func addItem(withTitle string: String, action selector: Selector?, keyEquivalent charCode: String) -> NSMenuItem {
    let item = NSMenuItem(title: string, action: selector, keyEquivalent: charCode)
    addItem(item)
    return item
  }

  public func insertItem(_ newItem: NSMenuItem, at index: Int) {
    let idx = min(max(0, index), items.count)
    newItem.menu = self
    items.insert(newItem, at: idx)
    #if !os(macOS)
      if let ni = newItem.nativeItem {
        nativeMenu?.insertItem(CUnsignedLong(idx), item: ni)
      }
    #endif
  }

  public func index(of item: NSMenuItem) -> Int {
    items.firstIndex { $0 === item } ?? -1
  }

  public func removeItem(_ item: NSMenuItem) {
    if item.menu === self { item.menu = nil }
    items.removeAll { $0 === item }
    #if !os(macOS)
      if let ni = item.nativeItem {
        _ = nativeMenu?.removeItem(ni)
      }
    #endif
  }

  public func removeItem(at index: Int) {
    guard items.indices.contains(index) else { return }
    removeItem(items[index])
  }

  public func cancelTracking() {}

  public func removeAllItems() {
    items.removeAll()
    #if !os(macOS)
      nativeMenu?.clear()
    #endif
  }

  @discardableResult
  public func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
    delegate?.menuNeedsUpdate(self)
    delegate?.menuWillOpen(self)
    defer { delegate?.menuDidClose(self) }
    #if !os(macOS)
      guard let nm = nativeMenu else { return false }
      if let view, let win = view.window {
        let winPt = view.convert(location, to: nil)
        let screenPt = win.convertPoint(toScreen: winPt)
        let top = CrossAppKitCoordinates.pointToNativeTopLeft(screenPt)
        guard let strat = NativeAPI.PositioningStrategy.absolute(NativeAPI.Point(x: top.x, y: top.y)) else {
          return false
        }
        return nm.open(strat, placement: .bottomStart)
      }
      guard let strat = NativeAPI.PositioningStrategy.cursorPosition() else { return false }
      return nm.open(strat, placement: .bottomStart)
    #else
      return false
    #endif
  }
}

open class NSStatusBarButton: NSButton {
  public var appearsDisabled: Bool = false
  @MainActor internal weak var ownerStatusItem: NSStatusItem?

  public override var image: NSImage? {
    didSet {
      MainActor.assumeIsolated { ownerStatusItem?.syncButtonAppearance() }
    }
  }

  public override var title: String {
    didSet {
      MainActor.assumeIsolated { ownerStatusItem?.syncButtonAppearance() }
    }
  }

  public override var toolTip: String? {
    didSet {
      MainActor.assumeIsolated { ownerStatusItem?.syncButtonAppearance() }
    }
  }

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
}

@MainActor
open class NSStatusItem: NSObject {
  public static let variableLength: CGFloat = -1
  public static let squareLength: CGFloat = -2

  public let button: NSStatusBarButton? = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
  public var length: CGFloat
  public var autosaveName: String?
  public var onLeftClick: (() -> Void)? {
    didSet {
      #if !os(macOS)
        syncContextMenuTrigger()
      #endif
    }
  }
  public var isVisible: Bool = true {
    didSet {
      #if !os(macOS)
        _ = nativeTrayIcon?.setVisible(isVisible)
      #endif
    }
  }
  public var menu: NSMenu? {
    didSet {
      #if !os(macOS)
        nativeTrayIcon?.setContextMenu(menu?.nativeMenu)
        syncContextMenuTrigger()
      #endif
    }
  }

  #if !os(macOS)
    public private(set) var nativeTrayIcon: NativeAPI.TrayIcon?
    private var listenerId: ListenerId?

    private func syncContextMenuTrigger() {
      #if os(Linux)
        if menu == nil {
          nativeTrayIcon?.setContextMenuTrigger(.none)
        } else if onLeftClick != nil {
          nativeTrayIcon?.setContextMenuTrigger(.rightClicked)
        } else {
          nativeTrayIcon?.setContextMenuTrigger(.clicked)
        }
      #else
        nativeTrayIcon?.setContextMenuTrigger(.none)
      #endif
    }
  #endif

  public init(length: CGFloat) {
    self.length = length
    super.init()
    self.button?.ownerStatusItem = self
    #if !os(macOS)
      if let tray = NativeAPI.TrayIcon.create() {
        self.nativeTrayIcon = tray
        let defaultTooltip = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
          ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
          ?? Bundle.main.executableURL?.deletingPathExtension().lastPathComponent
          ?? ProcessInfo.processInfo.processName
        if !defaultTooltip.isEmpty {
          tray.setTooltip(defaultTooltip)
        }
        _ = tray.setVisible(true)
        listenerId = tray.addListener { [weak self] event in
          MainActor.assumeIsolated {
            guard let self else { return }
            switch event {
            case .clicked:
              if let onLeftClick = self.onLeftClick {
                onLeftClick()
              } else if let menu = self.menu {
                menu.delegate?.menuNeedsUpdate(menu)
                #if !os(Linux)
                  _ = self.nativeTrayIcon?.openContextMenu()
                #endif
              } else {
                _ = self.button?.sendAction(self.button?.action, to: self.button?.target)
              }
            case .rightClicked:
              if let menu = self.menu {
                menu.delegate?.menuNeedsUpdate(menu)
                #if !os(Linux)
                  _ = self.nativeTrayIcon?.openContextMenu()
                #endif
              }
            default:
              break
            }
          }
        }
      }
    #endif
  }

  public func syncButtonAppearance() {
    #if !os(macOS)
      if let nsImg = button?.image, let img = nsImg.toNativeImage() {
        nativeTrayIcon?.setIconTemplate(nsImg.isTemplate)
        nativeTrayIcon?.setIcon(img)
      }
      if let tip = button?.toolTip, !tip.isEmpty {
        nativeTrayIcon?.setTooltip(tip)
      } else if let title = button?.title, !title.isEmpty {
        nativeTrayIcon?.setTitle(title)
        nativeTrayIcon?.setTooltip(title)
      }
    #endif
  }

  internal func _disposeNativeTrayIcon() {
    #if !os(macOS)
      if let lid = listenerId {
        _ = nativeTrayIcon?.removeListener(lid)
        listenerId = nil
      }
      nativeTrayIcon?.dispose()
      nativeTrayIcon = nil
    #endif
  }
}

@MainActor
open class NSStatusBar: NSObject, @unchecked Sendable {
  public static let system = NSStatusBar()
  public static let variableLength: CGFloat = -1
  public static let squareLength: CGFloat = -2
  public var thickness: CGFloat { 24 }

  private var activeItems: [NSStatusItem] = []

  public func statusItem(withLength length: CGFloat) -> NSStatusItem {
    let item = NSStatusItem(length: length)
    activeItems.append(item)
    return item
  }

  public func removeStatusItem(_ item: NSStatusItem) {
    item.isVisible = false
    item._disposeNativeTrayIcon()
    activeItems.removeAll { $0 === item }
  }

  internal func _removeAllItemsForTermination() {
    let items = activeItems
    activeItems.removeAll()
    for item in items {
      item._disposeNativeTrayIcon()
    }
  }
}

open class NSSavePanel: NSPanel {
  public var message: String = ""
  public var prompt: String = "Save"
  public var nameFieldLabel: String = "Save As:"
  public var nameFieldStringValue: String = ""
  public var directoryURL: URL?
  public var canCreateDirectories: Bool = true
  public var showsHiddenFiles: Bool = false
  public var isExtensionHidden: Bool = false
  #if !os(macOS)
    public var allowedContentTypes: [UTType] = []
  #endif
  public internal(set) var url: URL?

  public convenience init() {
    self.init(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: true
    )
  }

  open func runModal() -> NSModalResponse {
    #if !os(macOS)
      guard let dialog = NativeAPI.FileDialog.create(.saveFile) else { return .cancel }
      dialog.setModality(.application)
      if !nameFieldStringValue.isEmpty {
        _ = dialog.setSuggestedFileName(nameFieldStringValue)
      }
      let exts = allowedContentTypes.compactMap(\.preferredFilenameExtension)
      if !exts.isEmpty { _ = dialog.setFileTypes(exts) }
      guard dialog.open(), dialog.result == .accepted, let first = dialog.paths.first else {
        return .cancel
      }
      self.url = URL(fileURLWithPath: first)
      return .OK
    #else
      return .cancel
    #endif
  }

  open func begin(completionHandler handler: @escaping (NSModalResponse) -> Void) {
    let result = runModal()
    handler(result)
  }

  open func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSModalResponse) -> Void) {
    begin(completionHandler: handler)
  }
}

open class NSOpenPanel: NSSavePanel {
  public var canChooseFiles: Bool = true
  public var canChooseDirectories: Bool = false
  public var allowsMultipleSelection: Bool = false
  public var resolvesAliases: Bool = true
  public var treatsFilePackagesAsDirectories: Bool = false
  public private(set) var urls: [URL] = []

  open override func runModal() -> NSModalResponse {
    #if !os(macOS)
      let mode: NativeAPI.FileDialogMode
      if canChooseDirectories && !canChooseFiles {
        mode = .selectFolder
      } else if allowsMultipleSelection {
        mode = .openFiles
      } else {
        mode = .openFile
      }
      guard let dialog = NativeAPI.FileDialog.create(mode) else { return .cancel }
      dialog.setModality(.application)
      let exts = allowedContentTypes.compactMap(\.preferredFilenameExtension)
      if !exts.isEmpty { _ = dialog.setFileTypes(exts) }
      guard dialog.open(), dialog.result == .accepted, !dialog.paths.isEmpty else {
        return .cancel
      }
      self.urls = dialog.paths.map { URL(fileURLWithPath: $0) }
      self.url = self.urls.first
      return .OK
    #else
      return .cancel
    #endif
  }
}

@MainActor
open class NSAlert: NSObject {
  public enum Style: UInt, Sendable {
    case warning = 0
    case informational = 1
    case critical = 2
  }

  public var alertStyle: Style = .informational
  public var messageText: String = ""
  public var informativeText: String = ""
  public var icon: NSImage?
  private var buttonTitles: [String] = []

  @discardableResult
  public func addButton(withTitle title: String) -> NSButton {
    buttonTitles.append(title)
    return NSButton(title: title, target: nil, action: nil)
  }

  public func runModal() -> NSModalResponse {
    #if !os(macOS)
      guard let dialog = NativeAPI.MessageDialog.create(messageText, message: informativeText) else {
        return .alertFirstButtonReturn
      }
      dialog.setModality(.application)
      let primary = buttonTitles.indices.contains(0) ? buttonTitles[0] : "OK"
      let secondary = buttonTitles.indices.contains(1) ? buttonTitles[1] : ""
      let close = buttonTitles.indices.contains(2) ? buttonTitles[2] : ""
      _ = dialog.setButtons(primary, secondary: secondary, close: close)
      _ = dialog.open()
      switch dialog.result {
      case .primary: return .alertFirstButtonReturn
      case .secondary: return .alertSecondButtonReturn
      case .close: return .alertThirdButtonReturn
      case .none: return .cancel
      }
    #else
      return .alertFirstButtonReturn
    #endif
  }
}

open class NSSound: NSObject, @unchecked Sendable {
  public typealias Name = String
  public var isPlaying: Bool = false

  public init?(named name: Name) { super.init() }
  public init?(contentsOf url: URL, byReference byRef: Bool) { super.init() }
  public static func beep() {}
  @discardableResult public func play() -> Bool { false }
  @discardableResult public func stop() -> Bool { true }
}

@MainActor
open class NSSharingServicePicker: NSObject {
  public init(items: [Any]) { super.init() }
  public func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {}
}
