#if os(Windows)
  import CSwiftUIWindows
  import Foundation
  import NativeAPI
  import SwiftUIRuntime

  /// Manages native owned borderless transparent top-level popup windows on Windows
  /// for `.popover`, `._menuPopover` (`Menu`/`Picker`), and `.contextMenu`.
  internal final class WindowsPopupController {
    internal final class PopupEntry {
      let presentationID: ObjectIdentifier?
      let style: PresentationStyle
      let window: NativeAPI.Window
      let hwnd: UnsafeMutableRawPointer
      let ownerHwnd: UnsafeMutableRawPointer
      let backend: WindowsDrawingBackend
      var meta: PopupPresentationMetadata
      var placement: PopupPlacement
      var panelOriginInTree: SwiftUIRuntime.Point
      var lastContentElement: Element
      var isDark: Bool
      var isShown = false
      var lastBoundsPx: (x: Int32, y: Int32, w: Int32, h: Int32)?

      init(
        presentationID: ObjectIdentifier?,
        style: PresentationStyle,
        window: NativeAPI.Window,
        hwnd: UnsafeMutableRawPointer,
        ownerHwnd: UnsafeMutableRawPointer,
        backend: WindowsDrawingBackend,
        meta: PopupPresentationMetadata,
        placement: PopupPlacement,
        panelOriginInTree: SwiftUIRuntime.Point,
        lastContentElement: Element,
        isDark: Bool
      ) {
        self.presentationID = presentationID
        self.style = style
        self.window = window
        self.hwnd = hwnd
        self.ownerHwnd = ownerHwnd
        self.backend = backend
        self.meta = meta
        self.placement = placement
        self.panelOriginInTree = panelOriginInTree
        self.lastContentElement = lastContentElement
        self.isDark = isDark
      }

      var treeOffset: (dx: Double, dy: Double) {
        (
          panelOriginInTree.x - placement.contentRect.minX,
          panelOriginInTree.y - placement.contentRect.minY
        )
      }
    }

    private weak var hostBackend: WindowsDrawingBackend?
    private var attachedOwnerHwnd: UnsafeMutableRawPointer?
    internal private(set) var entries: [PopupEntry] = []
    private var retiredEntries: [PopupEntry] = []
    private var isSyncing = false
    private var activeEventDepth = 0
    private var retireCleanupScheduled = false

    internal init(hostBackend: WindowsDrawingBackend) {
      self.hostBackend = hostBackend
    }

    deinit {
      tearDown()
    }

    internal var hasActivePopups: Bool { !entries.isEmpty }

    internal var hasActiveBlockingPopup: Bool {
      entries.contains { !$0.meta.allowsBackgroundInteraction }
    }

    internal var activeWindows: [NativeAPI.Window] { entries.map(\.window) }
    internal var activePlacements: [PopupPlacement] { entries.map(\.placement) }
    internal var activeBackends: [WindowsDrawingBackend] { entries.map(\.backend) }

    internal func ensureOwnerAttached(_ ownerHwnd: UnsafeMutableRawPointer) {
      if attachedOwnerHwnd == ownerHwnd { return }
      if let old = attachedOwnerHwnd {
        sui_popup_owner_detach(old)
      }
      attachedOwnerHwnd = ownerHwnd
      sui_popup_owner_attach(
        ownerHwnd,
        Self.ownerEventTrampoline,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }

    internal func sync(root: Element, ownerHwnd: UnsafeMutableRawPointer) {
      guard let hostBackend else { return }
      ensureOwnerAttached(ownerHwnd)

      let metas = root.popupPresentations
      if metas.isEmpty {
        closeAll(restoreFocus: true)
        return
      }

      isSyncing = true
      defer {
        isSyncing = false
        syncOwnerPopupList()
      }

      var previousEntries = entries
      var updatedEntries: [PopupEntry] = []
      updatedEntries.reserveCapacity(metas.count)

      for (index, meta) in metas.enumerated() {
        guard let contentElement = root.children.first(where: {
          $0.popupPresentationIndex == index && $0.popupPresentationRole == .content
        }) else { continue }

        let parentSurface: UnsafeMutableRawPointer?
        let parentWindowObj: NativeAPI.Window?
        let parentHwnd: UnsafeMutableRawPointer
        let anchorInSurface: Rect

        if let parentIdx = meta.parentPresentationIndex, parentIdx < updatedEntries.count {
          let parentEntry = updatedEntries[parentIdx]
          parentSurface = parentEntry.backend.surfaceHandle
          parentWindowObj = parentEntry.window
          parentHwnd = parentEntry.hwnd
          anchorInSurface = Rect(
            x: meta.anchorRect.minX + parentEntry.placement.contentRect.minX,
            y: meta.anchorRect.minY + parentEntry.placement.contentRect.minY,
            width: meta.anchorRect.width,
            height: meta.anchorRect.height
          )
        } else {
          parentSurface = hostBackend.surfaceHandle
          parentWindowObj = hostBackend.hostWindow
          parentHwnd = ownerHwnd
          anchorInSurface = meta.anchorRect
        }

        guard let parentSurface else { continue }
        var metrics = sui_popup_metrics()
        guard sui_popup_measure_anchor(
          parentSurface,
          anchorInSurface.minX,
          anchorInSurface.minY,
          anchorInSurface.width,
          anchorInSurface.height,
          &metrics
        ) != 0 else { continue }

        let anchorInWork = Rect(
          x: metrics.anchor_x,
          y: metrics.anchor_y,
          width: metrics.anchor_w,
          height: metrics.anchor_h
        )
        let workArea = Rect(
          x: metrics.work_x,
          y: metrics.work_y,
          width: metrics.work_w,
          height: metrics.work_h
        )
        let placement = computePopupPlacement(
          style: meta.style,
          anchorRect: anchorInWork,
          anchorPoint: meta.anchorPoint,
          contentSize: meta.contentSize,
          preferredEdge: meta.preferredEdge,
          workArea: workArea
        )

        let scale = max(1.0, metrics.scale)
        let pxX = Int32(metrics.work_px_left) + Int32((placement.windowRect.minX * scale).rounded())
        let pxY = Int32(metrics.work_px_top) + Int32((placement.windowRect.minY * scale).rounded())
        let pxW = max(1, Int32((placement.windowRect.width * scale).rounded()))
        let pxH = max(1, Int32((placement.windowRect.height * scale).rounded()))
        let isDark = meta.colorScheme == .dark

        let entry: PopupEntry
        if index < previousEntries.count,
          previousEntries[index].presentationID == meta.presentationID,
          previousEntries[index].style == meta.style,
          previousEntries[index].ownerHwnd == parentHwnd
        {
          entry = previousEntries[index]
          entry.meta = meta
          entry.placement = placement
          entry.panelOriginInTree = contentElement.frame.origin
          entry.lastContentElement = contentElement
          if entry.isDark != isDark {
            entry.isDark = isDark
            entry.backend.setWindowShadow(enabled: true, isDark: isDark)
            sui_popup_configure(
              entry.hwnd, parentHwnd, entry.backend.surfaceHandle, isDark ? 1 : 0,
              Self.popupEventTrampoline, Unmanaged.passUnretained(self).toOpaque())
          }
          entry.backend.environmentTransform = { env in
            env.colorScheme = meta.colorScheme
          }
        } else {
          // Switching popups or opening a fresh popup at this depth: retire stale ones from `index` onward.
          if index < previousEntries.count {
            let stale = Array(previousEntries[index...])
            previousEntries.removeSubrange(index...)
            for old in stale.reversed() {
              retire(old, restoreFocus: false)
            }
          }
          guard let created = createEntry(
            meta: meta,
            placement: placement,
            panelOriginInTree: contentElement.frame.origin,
            contentElement: contentElement,
            parentWindow: parentWindowObj,
            parentHwnd: parentHwnd,
            boundsPx: (pxX, pxY, pxW, pxH),
            isDark: isDark,
            schedulesUpdates: hostBackend.schedulesUpdatesFlag
          ) else { continue }
          entry = created
        }

        updatedEntries.append(entry)

        let popupRoot = buildPopupRoot(
          contentElement: contentElement,
          meta: meta,
          placement: placement,
          index: index
        )

        // Register popup HWNDs with owner BEFORE activating so WM_ACTIVATE(WA_INACTIVE)
        // on the owner sees the popup as part of its family and does not dismiss.
        let tailEntries = (index + 1 < previousEntries.count) ? Array(previousEntries[(index + 1)...]) : []
        entries = updatedEntries + tailEntries
        syncOwnerPopupList()

        let boundsChanged = entry.lastBoundsPx.map {
          $0.x != pxX || $0.y != pxY || $0.w != pxW || $0.h != pxH
        } ?? true

        if entry.isShown {
          if boundsChanged {
            entry.lastBoundsPx = (pxX, pxY, pxW, pxH)
            sui_popup_set_bounds_px(entry.hwnd, parentHwnd, pxX, pxY, pxW, pxH, 1, 0)
          }
          entry.backend.didRender(popupRoot)
          if !hostBackend.schedulesUpdatesFlag {
            entry.backend.flushSyncPaint()
          }
        } else {
          entry.lastBoundsPx = (pxX, pxY, pxW, pxH)
          sui_popup_set_bounds_px(entry.hwnd, parentHwnd, pxX, pxY, pxW, pxH, 0, 0)
          entry.backend.didRender(popupRoot)
          entry.isShown = true
          sui_popup_set_bounds_px(entry.hwnd, parentHwnd, pxX, pxY, pxW, pxH, 1, 1)
          entry.backend.flushSyncPaint()
          entry.backend.applyPendingFocusIfNeeded()
        }
      }

      if previousEntries.count > updatedEntries.count {
        let extra = Array(previousEntries[updatedEntries.count...])
        entries = updatedEntries
        for (offset, old) in extra.reversed().enumerated() {
          retire(old, restoreFocus: offset == 0)
        }
      } else {
        entries = updatedEntries
      }
    }

    internal func closeAll(restoreFocus: Bool) {
      guard !entries.isEmpty else {
        syncOwnerPopupList()
        return
      }
      let closing = entries
      entries.removeAll()
      syncOwnerPopupList()
      for (offset, entry) in closing.reversed().enumerated() {
        retire(entry, restoreFocus: restoreFocus && offset == 0)
      }
    }

    internal func tearDown() {
      isSyncing = true
      let closing = entries
      entries.removeAll()
      if let owner = attachedOwnerHwnd {
        sui_popup_owner_set_popups(owner, nil, 0, 0)
        sui_popup_owner_detach(owner)
        attachedOwnerHwnd = nil
      }
      for entry in closing.reversed() {
        sui_popup_unconfigure(entry.hwnd)
        clearEntryHandlers(entry)
        entry.window.hide()
        _ = entry.window.close()
      }
      for entry in retiredEntries {
        sui_popup_unconfigure(entry.hwnd)
        clearEntryHandlers(entry)
        entry.window.hide()
        _ = entry.window.close()
      }
      retiredEntries.removeAll()
      isSyncing = false
    }

    internal func dismissTopmost() {
      guard !entries.isEmpty else { return }
      dismissPopups(from: entries.count - 1)
    }

    internal func dismissAll() {
      guard !entries.isEmpty else { return }
      dismissPopups(from: 0)
    }

    internal func nativeButton(_ id: NodeID) -> NativeAPI.Button? {
      for entry in entries.reversed() {
        if let button = entry.backend.nativeButton(id) { return button }
      }
      return nil
    }

    internal func nativeTextField(_ id: NodeID) -> NativeAPI.TextField? {
      for entry in entries.reversed() {
        if let field = entry.backend.nativeTextField(id) { return field }
      }
      return nil
    }

    internal func hostedNativeView(_ id: NodeID) -> NativeAPI.View? {
      for entry in entries.reversed() {
        if let view = entry.backend.hostedNativeView(id) { return view }
      }
      return nil
    }

    @discardableResult
    internal func activate(_ id: NodeID) -> Bool {
      for entry in entries.reversed() {
        if entry.backend.nativeButton(id) != nil {
          activeEventDepth += 1
          defer { activeEventDepth -= 1 }
          entry.backend.activate(id)
          return true
        }
      }
      return false
    }

    @discardableResult
    internal func replaceText(_ id: NodeID, with text: String) -> Bool {
      for entry in entries.reversed() {
        if entry.backend.nativeTextField(id) != nil {
          activeEventDepth += 1
          defer { activeEventDepth -= 1 }
          entry.backend.replaceText(id, with: text)
          return true
        }
      }
      return false
    }

    internal func pointerLocationInTreeCoordinates() -> CGPoint? {
      for entry in entries.reversed() {
        if let local = entry.backend.pointerLocation(fallback: .zero) {
          let offset = entry.treeOffset
          return CGPoint(x: Double(local.x) + offset.dx, y: Double(local.y) + offset.dy)
        }
      }
      return nil
    }

    // MARK: - Private

    private func createEntry(
      meta: PopupPresentationMetadata,
      placement: PopupPlacement,
      panelOriginInTree: SwiftUIRuntime.Point,
      contentElement: Element,
      parentWindow: NativeAPI.Window?,
      parentHwnd: UnsafeMutableRawPointer,
      boundsPx: (x: Int32, y: Int32, w: Int32, h: Int32),
      isDark: Bool,
      schedulesUpdates: Bool
    ) -> PopupEntry? {
      guard let popupWindow = NativeAPI.Window.create(),
        let popupHwnd = popupWindow.nativeObject
      else { return nil }

      _ = popupWindow.setFrameless(true)
      popupWindow.setResizable(false)
      popupWindow.setMinimizable(false)
      popupWindow.setMaximizable(false)
      popupWindow.setClosable(false)
      popupWindow.setVisibleInTaskbar(false)
      popupWindow.setHasShadow(false)
      _ = popupWindow.setCornerPreference(.doNotRound)
      popupWindow.setBackgroundColor(NativeAPI.Color(r: 0, g: 0, b: 0, a: 0))
      if let parentWindow {
        _ = popupWindow.setParentWindow(parentWindow)
      }

      // Move onto the owner's monitor and size before creating/rasterizing the surface
      // so initial DPI and client dimensions are exact on frame 1.
      sui_popup_configure(
        popupHwnd, parentHwnd, nil, isDark ? 1 : 0,
        Self.popupEventTrampoline, Unmanaged.passUnretained(self).toOpaque())
      sui_popup_set_bounds_px(
        popupHwnd, parentHwnd, boundsPx.x, boundsPx.y, boundsPx.w, boundsPx.h, 0, 0)

      guard let popupBackend = WindowsDrawingBackend(
        window: popupWindow, schedulesUpdates: schedulesUpdates)
      else {
        sui_popup_unconfigure(popupHwnd)
        _ = popupWindow.close()
        return nil
      }

      popupBackend.usesNativePopupWindows = false
      popupBackend.setBackgroundColor(.clear)
      popupBackend.setWindowShadow(enabled: true, isDark: isDark)
      popupBackend.environmentTransform = { env in
        env.colorScheme = meta.colorScheme
      }
      popupBackend.canAcquireControlFocus = { true }

      sui_popup_configure(
        popupHwnd, parentHwnd, popupBackend.surfaceHandle, isDark ? 1 : 0,
        Self.popupEventTrampoline, Unmanaged.passUnretained(self).toOpaque())

      let entry = PopupEntry(
        presentationID: meta.presentationID,
        style: meta.style,
        window: popupWindow,
        hwnd: popupHwnd,
        ownerHwnd: parentHwnd,
        backend: popupBackend,
        meta: meta,
        placement: placement,
        panelOriginInTree: panelOriginInTree,
        lastContentElement: contentElement,
        isDark: isDark
      )

      wireHandlers(for: entry)
      return entry
    }

    private func wireHandlers(for entry: PopupEntry) {
      let popupBackend = entry.backend

      popupBackend.transactionHandler = { [weak self] work in
        guard let self, let host = self.hostBackend else {
          work()
          return
        }
        self.activeEventDepth += 1
        defer { self.activeEventDepth -= 1 }
        if let tx = host.transactionHandler {
          tx(work)
        } else {
          work()
        }
      }

      popupBackend.animationTickHandler = { [weak self] in
        guard let self, let host = self.hostBackend else { return false }
        self.activeEventDepth += 1
        defer { self.activeEventDepth -= 1 }
        return host.animationTickHandler?() ?? false
      }

      popupBackend.tapHandler = { [weak self] id in
        guard let self, let host = self.hostBackend else { return }
        self.activeEventDepth += 1
        defer { self.activeEventDepth -= 1 }
        host.tapHandler?(id)
      }

      popupBackend.interactionHandler = { [weak self] id, interaction in
        guard let self, let host = self.hostBackend else { return }
        self.activeEventDepth += 1
        defer { self.activeEventDepth -= 1 }
        host.interactionHandler?(id, interaction)
      }

      popupBackend.inputHandler = { [weak self, weak entry] id, event, point, value, modifiers, text in
        guard let self, let entry, let host = self.hostBackend else { return false }
        self.activeEventDepth += 1
        defer { self.activeEventDepth -= 1 }

        // Escape dismisses the popup cleanly (topmost popup first for nested stacks).
        if event == 6 && value == 27 && modifiers.isEmpty {
          if let entryIndex = self.entries.firstIndex(where: { $0 === entry }) {
            self.dismissPopups(from: entryIndex)
            return true
          }
        }

        let translatedPoint: CGPoint
        if event == 10 || event == 7 {
          translatedPoint = .zero
        } else {
          let offset = entry.treeOffset
          translatedPoint = CGPoint(
            x: Double(point.x) + offset.dx,
            y: Double(point.y) + offset.dy
          )
        }
        return host.inputHandler?(id, event, translatedPoint, value, modifiers, text) ?? false
      }
    }

    private func clearEntryHandlers(_ entry: PopupEntry) {
      entry.backend.tapHandler = nil
      entry.backend.interactionHandler = nil
      entry.backend.inputHandler = nil
      entry.backend.transactionHandler = nil
      entry.backend.animationTickHandler = nil
      entry.backend.onResize = nil
      entry.backend.onPreInput = nil
    }

    private func retire(_ entry: PopupEntry, restoreFocus: Bool) {
      sui_popup_unconfigure(entry.hwnd)
      clearEntryHandlers(entry)
      if restoreFocus {
        sui_popup_restore_owner_focus(entry.hwnd, entry.ownerHwnd)
      }
      entry.window.hide()
      if activeEventDepth > 0 {
        retiredEntries.append(entry)
        scheduleRetiredCleanup()
      } else {
        _ = entry.window.close()
      }
    }

    private func scheduleRetiredCleanup() {
      guard !retireCleanupScheduled else { return }
      retireCleanupScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.retireCleanupScheduled = false
        guard self.activeEventDepth == 0 else {
          self.scheduleRetiredCleanup()
          return
        }
        let victims = self.retiredEntries
        self.retiredEntries.removeAll()
        for entry in victims {
          _ = entry.window.close()
        }
      }
    }

    private func syncOwnerPopupList() {
      guard let owner = attachedOwnerHwnd else { return }
      let hwnds: [UnsafeMutableRawPointer?] = entries.map { Optional($0.hwnd) }
      let blocks = hasActiveBlockingPopup ? 1 : 0
      if hwnds.isEmpty {
        sui_popup_owner_set_popups(owner, nil, 0, 0)
      } else {
        hwnds.withUnsafeBufferPointer { buf in
          sui_popup_owner_set_popups(owner, buf.baseAddress, Int32(buf.count), Int32(blocks))
        }
      }
    }

    private func dismissPopups(from startIndex: Int) {
      guard startIndex >= 0, startIndex < entries.count else { return }
      let dismissClosures = entries[startIndex...].reversed().compactMap { $0.meta.dismiss }
      guard !dismissClosures.isEmpty else { return }
      let run = {
        for dismiss in dismissClosures {
          dismiss()
        }
      }
      if let tx = hostBackend?.transactionHandler {
        tx(run)
      } else {
        run()
      }
    }

    private func repositionAllForOwnerMove() {
      guard !isSyncing, !entries.isEmpty, let hostBackend, let ownerHwnd = attachedOwnerHwnd else {
        return
      }
      isSyncing = true
      defer { isSyncing = false }

      for (index, entry) in entries.enumerated() {
        let meta = entry.meta
        let parentSurface: UnsafeMutableRawPointer?
        let parentHwnd: UnsafeMutableRawPointer
        let anchorInSurface: Rect

        if let parentIdx = meta.parentPresentationIndex, parentIdx < index {
          let parentEntry = entries[parentIdx]
          parentSurface = parentEntry.backend.surfaceHandle
          parentHwnd = parentEntry.hwnd
          anchorInSurface = Rect(
            x: meta.anchorRect.minX + parentEntry.placement.contentRect.minX,
            y: meta.anchorRect.minY + parentEntry.placement.contentRect.minY,
            width: meta.anchorRect.width,
            height: meta.anchorRect.height
          )
        } else {
          parentSurface = hostBackend.surfaceHandle
          parentHwnd = ownerHwnd
          anchorInSurface = meta.anchorRect
        }

        guard let parentSurface else { continue }
        var metrics = sui_popup_metrics()
        guard sui_popup_measure_anchor(
          parentSurface,
          anchorInSurface.minX,
          anchorInSurface.minY,
          anchorInSurface.width,
          anchorInSurface.height,
          &metrics
        ) != 0 else { continue }

        let placement = computePopupPlacement(
          style: meta.style,
          anchorRect: Rect(
            x: metrics.anchor_x, y: metrics.anchor_y,
            width: metrics.anchor_w, height: metrics.anchor_h),
          anchorPoint: meta.anchorPoint,
          contentSize: meta.contentSize,
          preferredEdge: meta.preferredEdge,
          workArea: Rect(
            x: metrics.work_x, y: metrics.work_y,
            width: metrics.work_w, height: metrics.work_h)
        )
        let scale = max(1.0, metrics.scale)
        let pxX = Int32(metrics.work_px_left) + Int32((placement.windowRect.minX * scale).rounded())
        let pxY = Int32(metrics.work_px_top) + Int32((placement.windowRect.minY * scale).rounded())
        let pxW = max(1, Int32((placement.windowRect.width * scale).rounded()))
        let pxH = max(1, Int32((placement.windowRect.height * scale).rounded()))

        let previousPlacement = entry.placement
        entry.placement = placement
        entry.lastBoundsPx = (pxX, pxY, pxW, pxH)
        sui_popup_set_bounds_px(entry.hwnd, parentHwnd, pxX, pxY, pxW, pxH, 1, 0)
        if previousPlacement.resolvedEdge != placement.resolvedEdge
          || abs(previousPlacement.arrowCenter - placement.arrowCenter) > 0.5
          || abs(previousPlacement.windowRect.width - placement.windowRect.width) > 0.5
          || abs(previousPlacement.windowRect.height - placement.windowRect.height) > 0.5
        {
          let popupRoot = buildPopupRoot(
            contentElement: entry.lastContentElement,
            meta: meta,
            placement: placement,
            index: index
          )
          entry.backend.didRender(popupRoot)
        }
      }
    }

    private func buildPopupRoot(
      contentElement: Element,
      meta: PopupPresentationMetadata,
      placement: PopupPlacement,
      index: Int
    ) -> Element {
      let dx = placement.contentRect.minX - contentElement.frame.minX
      let dy = placement.contentRect.minY - contentElement.frame.minY
      var contentCopy = translatedPopupElement(contentElement, dx: dx, dy: dy)

      if !meta.drawsPopoverChrome {
        // Outer drop shadow is rendered by the popup's window shadow layer so it is never clipped.
        contentCopy.props.shadows = []
      }

      var children: [Element] = []
      if meta.drawsPopoverChrome {
        let bubble = makePopoverBubbleElement(
          placement: placement,
          colorScheme: meta.colorScheme,
          id: NodeID(rawValue: -1000 - index)
        )
        children.append(bubble)
      }
      children.append(contentCopy)

      return Element(
        id: NodeID(rawValue: -1 - index),
        kind: .zStack,
        children: children,
        frame: Rect(origin: .zero, size: placement.windowRect.size)
      )
    }

    private func handlePopupEvent(event: Int32, otherHwnd: UnsafeMutableRawPointer?) {
      guard !isSyncing else { return }
      activeEventDepth += 1
      defer { activeEventDepth -= 1 }

      if event == 1 {
        // A popup window was deactivated.
        if let otherHwnd,
          let keptIndex = entries.firstIndex(where: { $0.hwnd == otherHwnd })
        {
          // Focus moved to a popup in our stack (e.g. parent popup -> child popup or child -> parent).
          if keptIndex + 1 < entries.count {
            dismissPopups(from: keptIndex + 1)
          }
          return
        }
        dismissAll()
      }
    }

    private func handleOwnerEvent(event: Int32, otherHwnd: UnsafeMutableRawPointer?) {
      guard !isSyncing else { return }
      activeEventDepth += 1
      defer { activeEventDepth -= 1 }

      switch event {
      case 2:
        // Owner clicked while popup is open (outside click).
        dismissAll()
      case 3:
        // Owner deactivated to a non-popup window.
        if let otherHwnd, entries.contains(where: { $0.hwnd == otherHwnd }) {
          return
        }
        dismissAll()
      case 4:
        // Owner hidden, minimized, closed, or destroyed.
        dismissAll()
      case 5:
        // Owner moved or resized.
        repositionAllForOwnerMove()
      case 6:
        // Owner became visible; defer promotion until ShowWindow finishes activating the owner.
        hostBackend?.scheduleDeferredPopupResync()
      default:
        break
      }
    }

    private static let popupEventTrampoline: sui_popup_event_callback = { context, event, other in
      guard let context else { return }
      let controller = Unmanaged<WindowsPopupController>.fromOpaque(context).takeUnretainedValue()
      controller.handlePopupEvent(event: event, otherHwnd: other)
    }

    private static let ownerEventTrampoline: sui_popup_event_callback = { context, event, other in
      guard let context else { return }
      let controller = Unmanaged<WindowsPopupController>.fromOpaque(context).takeUnretainedValue()
      controller.handleOwnerEvent(event: event, otherHwnd: other)
    }
  }

  internal struct WindowsPopupWindowSnapshot {
    let hwnd: UnsafeMutableRawPointer
    let ownerHwnd: UnsafeMutableRawPointer?
    let isVisible: Bool
    let isPopupStyle: Bool
    let isToolWindow: Bool
    let hasAppWindow: Bool
    let isTopmost: Bool
    let left: Int
    let top: Int
    let width: Int
    let height: Int
    let style: PresentationStyle
    let placement: PopupPlacement
  }

  extension WindowsDrawingBackend {
    internal var rootHwnd: UnsafeMutableRawPointer? {
      surfaceHandle.flatMap { sui_surface_root_hwnd($0) }
    }

    internal var hostWindowRectPx: (left: Int, top: Int, width: Int, height: Int)? {
      guard let hwnd = rootHwnd else { return nil }
      var info = sui_popup_window_info()
      guard sui_popup_get_window_info(hwnd, &info) != 0 else { return nil }
      return (Int(info.left), Int(info.top), Int(info.width), Int(info.height))
    }

    internal var activePopupSnapshots: [WindowsPopupWindowSnapshot] {
      guard let entries = popupController?.entries else { return [] }
      return entries.compactMap { entry in
        var info = sui_popup_window_info()
        guard sui_popup_get_window_info(entry.hwnd, &info) != 0 else { return nil }
        return WindowsPopupWindowSnapshot(
          hwnd: entry.hwnd,
          ownerHwnd: info.owner_hwnd,
          isVisible: info.is_visible != 0,
          isPopupStyle: info.is_popup_style != 0,
          isToolWindow: info.is_tool_window != 0,
          hasAppWindow: info.has_app_window != 0,
          isTopmost: info.is_topmost != 0,
          left: Int(info.left),
          top: Int(info.top),
          width: Int(info.width),
          height: Int(info.height),
          style: entry.style,
          placement: entry.placement
        )
      }
    }
  }
#endif
