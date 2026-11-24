#if os(Windows)
  import CSwiftUIWindowsTestSupport
  import CrossAppKit
  import Foundation
  import NativeAPI
  import Testing
  import WinSDK

  @testable import CrossSwiftUI
  @testable import SwiftUIRuntime

  @Suite("Windows Native Popup Windows", .serialized)
  @MainActor
  struct WindowsPopupTests {
    private func findNode(
      in root: Element,
      matching predicate: (Element) -> Bool
    ) -> Element? {
      if predicate(root) { return root }
      for child in root.children {
        if let found = findNode(in: child, matching: predicate) { return found }
      }
      return nil
    }

    private func collectNodes(
      in root: Element,
      matching predicate: (Element) -> Bool,
      into out: inout [Element]
    ) {
      if predicate(root) { out.append(root) }
      for child in root.children {
        collectNodes(in: child, matching: predicate, into: &out)
      }
    }

    @Test("Popover escapes compact host window in an owned borderless tool popup window")
    func popoverEscapesSmallHostWindowBounds() throws {
      final class Model: ObservableObject {
        @Published var open = false
      }
      struct CompactPopoverView: SwiftUIRuntime.View {
        @ObservedObject var model: Model
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.VStack {
            SwiftUIRuntime.Button("Open") { model.open = true }
              .frame(width: 90, height: 28)
              .popover(isPresented: $model.open, arrowEdge: .top) {
                SwiftUIRuntime.VStack(spacing: 8) {
                  SwiftUIRuntime.Text("Wide Popover Content")
                  SwiftUIRuntime.Button("Action") {}
                }
                .padding(16)
                .frame(width: 300, height: 220)
              }
          }
          .frame(width: 180, height: 90)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 240, y: 200, width: 180, height: 90))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = Model()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(CompactPopoverView(model: model)),
        size: .init(width: 180, height: 90)
      )
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text) ?? false
      }
      backend.interactionHandler = { [weak renderer] id, interaction in
        renderer?.interact(id, interaction)
      }
      renderer.mount()
      #expect(backend.activePopupSnapshots.isEmpty)

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      let snapshots = backend.activePopupSnapshots
      #expect(snapshots.count == 1)
      let popup = try #require(snapshots.first)
      let hostRect = try #require(backend.hostWindowRectPx)

      #expect(popup.isVisible)
      #expect(popup.isPopupStyle)
      #expect(popup.isToolWindow)
      #expect(!popup.hasAppWindow)
      #expect(popup.ownerHwnd == backend.rootHwnd)
      #expect(popup.style == .popover)
      // Popup window must freely escape the compact 180x90 host window bounds!
      #expect(popup.width > hostRect.width)
      #expect(popup.height > hostRect.height)
      let popupRight = popup.left + popup.width
      let hostRight = hostRect.left + hostRect.width
      let popupBottom = popup.top + popup.height
      let hostBottom = hostRect.top + hostRect.height
      #expect(popupRight > hostRight || popup.left < hostRect.left)
      #expect(popupBottom > hostBottom || popup.top < hostRect.top)
    }

    @Test("Popover flips arrowEdge upward when host anchor sits near bottom of screen")
    func popoverFlipsNearScreenBottomEdge() throws {
      final class Model: ObservableObject {
        @Published var open = false
      }
      struct EdgePopoverView: SwiftUIRuntime.View {
        @ObservedObject var model: Model
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.Button("Anchor") { model.open = true }
            .frame(width: 100, height: 28)
            .popover(isPresented: $model.open, arrowEdge: .top) {
              SwiftUIRuntime.Text("Flipped Popover")
                .frame(width: 240, height: 220)
            }
            .frame(width: 200, height: 60)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let display = try #require(NativeAPI.DisplayManager.shared.getPrimary())
      let workArea = display.workArea

      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      let nearBottomY = max(workArea.y + 40, workArea.y + workArea.height - 70)
      window.setBounds(NativeAPI.Rectangle(x: workArea.x + 260, y: nearBottomY, width: 200, height: 60))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = Model()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(EdgePopoverView(model: model)),
        size: .init(width: 200, height: 60)
      )
      renderer.mount()

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      let popup = try #require(backend.activePopupSnapshots.first)
      #expect(popup.isVisible)
      // Preferred .top (below anchor) overflows bottom of monitor -> flips to .bottom (above anchor).
      #expect(popup.placement.resolvedEdge == .bottom)
      let hostRect = try #require(backend.hostWindowRectPx)
      #expect(popup.top < hostRect.top)
    }

    @Test("Clicking buttons, editing TextField, and rendering LazyVGrid icons inside popup updates live SwiftUI state")
    func interactiveControlsInsidePopupUpdateLiveState() throws {
      final class PickerModel: ObservableObject {
        @Published var open = false
        @Published var selectedIcon = "star"
        @Published var search = ""
        @Published var clickCount = 0
      }

      let symbols = ["star", "heart", "bolt", "globe", "leaf", "flag"]

      struct InteractivePopoverScene: SwiftUIRuntime.View {
        @ObservedObject var model: PickerModel
        let symbols: [String]
        var columns: [GridItem] {
          Array(repeating: GridItem(.fixed(30), spacing: 6), count: 3)
        }
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.VStack {
            SwiftUIRuntime.Button("Pick Icon") { model.open = true }
              .frame(width: 110, height: 28)
              .popover(isPresented: $model.open, arrowEdge: .bottom) {
                SwiftUIRuntime.VStack(alignment: .leading, spacing: 8) {
                  SwiftUIRuntime.TextField("Filter icons", text: $model.search)
                    .frame(width: 180, height: 26)
                  SwiftUIRuntime.LazyVGrid(columns: columns, spacing: 6) {
                    SwiftUIRuntime.ForEach(symbols, id: \.self) { sym in
                      SwiftUIRuntime.Button {
                        model.selectedIcon = sym
                        model.clickCount += 1
                      } label: {
                        SwiftUIRuntime.Image(systemName: sym)
                          .font(.system(size: 14))
                          .frame(width: 30, height: 26)
                      }
                      .buttonStyle(.plain)
                    }
                  }
                  SwiftUIRuntime.Button("Increment") {
                    model.clickCount += 10
                  }
                }
                .padding(10)
                .frame(width: 220)
              }
          }
          .frame(width: 240, height: 120)
          .preferredColorScheme(.dark)
        }
      }

      // Ensure SF symbol asset resolver is installed.
      _ = NSHostingView(rootView: SwiftUIRuntime.EmptyView())
      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 300, y: 260, width: 240, height: 120))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = PickerModel()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(InteractivePopoverScene(model: model, symbols: symbols)),
        size: .init(width: 240, height: 120)
      )
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text) ?? false
      }
      backend.interactionHandler = { [weak renderer] id, interaction in
        renderer?.interact(id, interaction)
      }
      renderer.mount()

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      #expect(backend.activePopupSnapshots.count == 1)
      let tree = try #require(renderer.tree)
      let popupContent = try #require(
        tree.children.first { $0.popupPresentationIndex == 0 && $0.popupPresentationRole == .content })

      // 1. Verify all 6 LazyVGrid icons materialized inside the popup window and render non-blank pixels.
      var iconButtons: [Element] = []
      collectNodes(in: popupContent, matching: { $0.kind == .styledButton }, into: &iconButtons)
      #expect(iconButtons.count == 6)
      for btn in iconButtons {
        let native = try #require(backend.nativeButton(btn.id))
        let handle = try #require(native.nativeObject)
        #expect(control_print_distinct_pixels(handle) > 6)
      }

      // 2. Activate a grid icon button inside the popup -> updates live SwiftUI state without dismissing popover.
      let boltBtn = iconButtons[2]
      backend.activate(boltBtn.id)
      pump_pending_win32_messages()
      #expect(model.selectedIcon == "bolt")
      #expect(model.clickCount == 1)
      #expect(model.open)
      #expect(backend.activePopupSnapshots.count == 1)

      // 3. Activate a plain Button inside the popup -> updates live state with zero stale closures.
      let incNode = try #require(
        findNode(in: popupContent) { $0.kind == .button && $0.props.text == "Increment" })
      backend.activate(incNode.id)
      pump_pending_win32_messages()
      #expect(model.clickCount == 11)

      // 4. Edit TextField inside the popup -> updates live @Published binding while keeping popup open.
      let editNode = try #require(findNode(in: popupContent) { $0.kind == .textField })
      backend.replaceText(editNode.id, with: "globe")
      pump_pending_win32_messages()
      #expect(model.search == "globe")
      #expect(backend.activePopupSnapshots.count == 1)
    }

    @Test("Menu dismisses on action, contextMenu dismisses on Escape, and popover dismisses on outside click and owner hide")
    func dismissalPathsForMenuContextMenuAndPopover() throws {
      final class StateModel: ObservableObject {
        @Published var chosen = "none"
        @Published var popoverOpen = false
      }
      struct DismissalScene: SwiftUIRuntime.View {
        @ObservedObject var model: StateModel
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.VStack(spacing: 12) {
            SwiftUIRuntime.Menu("Actions") {
              SwiftUIRuntime.Button("Duplicate") { model.chosen = "Duplicate" }
              SwiftUIRuntime.Button("Archive") { model.chosen = "Archive" }
            }
            SwiftUIRuntime.Text("Right-click Target")
              .frame(width: 140, height: 30)
              .contextMenu {
                SwiftUIRuntime.Button("Inspect") { model.chosen = "Inspect" }
              }
            SwiftUIRuntime.Button("Details") { model.popoverOpen = true }
              .popover(isPresented: $model.popoverOpen, arrowEdge: .top) {
                SwiftUIRuntime.Text("Details Body").frame(width: 180, height: 90)
              }
          }
          .padding(12)
          .frame(width: 260, height: 180)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 240, y: 200, width: 260, height: 180))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = StateModel()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(DismissalScene(model: model)),
        size: .init(width: 260, height: 180)
      )
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text) ?? false
      }
      backend.interactionHandler = { [weak renderer] id, interaction in
        renderer?.interact(id, interaction)
      }
      renderer.mount()

      // 1. Open Menu -> activate item -> state updates & popup dismisses automatically (dismissOnAction).
      let initialTree = try #require(renderer.tree)
      let menuBtn = try #require(findNode(in: initialTree) {
        $0.kind == .styledButton && findNode(in: $0) { $0.props.text == "Actions" } != nil
      })
      backend.activate(menuBtn.id)
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)
      #expect(backend.activePopupSnapshots[0].style == .menuPopover)

      let menuOpenTree = try #require(renderer.tree)
      let dupBtn = try #require(findNode(in: menuOpenTree) {
        $0.kind == .styledButton && findNode(in: $0) { $0.props.text == "Duplicate" } != nil
      })
      backend.activate(dupBtn.id)
      pump_pending_win32_messages()
      #expect(model.chosen == "Duplicate")
      #expect(backend.activePopupSnapshots.isEmpty)

      // 2. Open .contextMenu via secondary click -> press Escape inside popup -> dismisses cleanly.
      let afterMenuTree = try #require(renderer.tree)
      let ctxNode = try #require(findNode(in: afterMenuTree) {
        $0.secondaryAction != nil
      })
      _ = renderer.input(
        event: 9,
        point: CGPoint(x: ctxNode.frame.minX + 10, y: ctxNode.frame.minY + 10)
      )
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)
      #expect(backend.activePopupSnapshots[0].style == .contextMenu)

      let popupBackend = try #require(backend.activePopupBackends.first)
      let escHandled = popupBackend.inputHandler?(nil, 6, .zero, 27, [], "") ?? false
      #expect(escHandled)
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.isEmpty)

      // 3. Open .popover -> outside click on host surface -> dismisses cleanly.
      model.popoverOpen = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)

      backend.pointer(event: 2, at: CGPoint(x: 4, y: 4))
      pump_pending_win32_messages()
      #expect(!model.popoverOpen)
      #expect(backend.activePopupSnapshots.isEmpty)

      // 4. Re-open .popover -> hide parent window -> popup dismisses automatically.
      model.popoverOpen = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)

      window.hide()
      pump_pending_win32_messages()
      #expect(!model.popoverOpen)
      #expect(backend.activePopupSnapshots.isEmpty)
    }

    @Test("Switching popovers and opening popovers from a floating NSPanel editor work cleanly")
    func floatingPanelAndSwitchingPopovers() throws {
      final class SwitchModel: ObservableObject {
        @Published var firstOpen = false
        @Published var secondOpen = false
      }
      struct EditorPanelView: SwiftUIRuntime.View {
        @ObservedObject var model: SwitchModel
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.HStack(spacing: 12) {
            SwiftUIRuntime.Button("First") {
              model.secondOpen = false
              model.firstOpen = true
            }
            .popover(isPresented: $model.firstOpen, arrowEdge: .bottom) {
              SwiftUIRuntime.Text("Popover A").frame(width: 220, height: 140)
            }
            SwiftUIRuntime.Button("Second") {
              model.firstOpen = false
              model.secondOpen = true
            }
            .popover(isPresented: $model.secondOpen, arrowEdge: .top) {
              SwiftUIRuntime.Text("Popover B").frame(width: 260, height: 160)
            }
          }
          .padding(16)
          .frame(width: 240, height: 100)
          .preferredColorScheme(.dark)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()

      let model = SwitchModel()
      let hosting = NSHostingView(rootView: EditorPanelView(model: model))
      hosting.setFrameSize(NSSize(width: 240, height: 100))

      let panel = CrossAppKit.NSPanel(
        contentRect: NSRect(x: 280, y: 260, width: 240, height: 100),
        styleMask: [.borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      panel.isFloatingPanel = true
      panel.level = .floating
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.contentView = hosting
      defer { panel.close() }

      panel.makeKeyAndOrderFront(nil)
      pump_pending_win32_messages()

      let backend = try #require(hosting.backend)
      let renderer = try #require(hosting.renderer)

      // Open Popover A from floating NSPanel: inherits topmost & owner.
      model.firstOpen = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      let snapA = try #require(backend.activePopupSnapshots.first)
      #expect(snapA.isVisible)
      #expect(snapA.ownerHwnd == backend.rootHwnd)
      #expect(snapA.isTopmost)

      // Switch to Popover B: replaces Popover A with a new popup HWND.
      model.firstOpen = false
      model.secondOpen = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      #expect(backend.activePopupSnapshots.count == 1)
      let snapB = try #require(backend.activePopupSnapshots.first)
      #expect(snapB.isVisible)
      #expect(snapB.hwnd != snapA.hwnd)
      #expect(snapB.ownerHwnd == backend.rootHwnd)
      #expect(snapB.width > snapA.width)
    }

    @Test("Modal sheet and alert stay in-window without creating popup windows")
    func sheetAndAlertStayInWindow() throws {
      final class ModalModel: ObservableObject {
        @Published var showSheet = false
        @Published var showAlert = false
      }
      struct ModalScene: SwiftUIRuntime.View {
        @ObservedObject var model: ModalModel
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.VStack {
            SwiftUIRuntime.Text("Main Window")
          }
          .frame(width: 380, height: 260)
          .sheet(isPresented: $model.showSheet) {
            SwiftUIRuntime.Text("Sheet Body").frame(width: 240, height: 140)
          }
          .alert("Alert Title", isPresented: $model.showAlert) {
            SwiftUIRuntime.Button("OK") {}
          }
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 240, y: 200, width: 380, height: 260))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = ModalModel()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(ModalScene(model: model)),
        size: .init(width: 380, height: 260)
      )
      renderer.mount()

      model.showSheet = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.isEmpty)
      let sheetTree = try #require(renderer.tree)
      #expect(sheetTree.hasActivePresentation)

      model.showSheet = false
      model.showAlert = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.isEmpty)
      let alertTree = try #require(renderer.tree)
      #expect(alertTree.hasActivePresentation)
    }

    @Test("Nested popup inside a popover preserves two-level ownership, reuses HWNDs, and unwinds cleanly on Escape")
    func nestedPopupInsidePopoverAndEscapeUnwind() throws {
      final class NestedModel: ObservableObject {
        @Published var outerOpen = false
        @Published var innerOpen = false
        @Published var picked = "none"
        @Published var tick = 0
      }
      struct NestedPopupScene: SwiftUIRuntime.View {
        @ObservedObject var model: NestedModel
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.Button("Open Outer") { model.outerOpen = true }
            .frame(width: 110, height: 28)
            .popover(isPresented: $model.outerOpen, arrowEdge: .top) {
              SwiftUIRuntime.VStack(spacing: 8) {
                SwiftUIRuntime.Text("Tick \(model.tick)")
                SwiftUIRuntime.Button("Open Inner") { model.innerOpen = true }
                  .frame(width: 100, height: 26)
                  ._menuPopover(isPresented: $model.innerOpen, arrowEdge: .top) {
                    SwiftUIRuntime.VStack(alignment: .leading, spacing: 2) {
                      SwiftUIRuntime.Button("Option A") { model.picked = "A" }
                        .buttonStyle(.plain)
                    }
                    .padding(6)
                    .frame(width: 140, height: 40)
                  }
              }
              .padding(12)
              .frame(width: 220, height: 110)
            }
            .frame(width: 200, height: 90)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 260, y: 200, width: 200, height: 90))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = NestedModel()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(NestedPopupScene(model: model)),
        size: .init(width: 200, height: 90)
      )
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text) ?? false
      }
      renderer.mount()

      model.outerOpen = true
      model.innerOpen = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      let snaps = backend.activePopupSnapshots
      #expect(snaps.count == 2)
      #expect(snaps[0].ownerHwnd == backend.rootHwnd)
      #expect(snaps[1].ownerHwnd == snaps[0].hwnd)

      // Re-rendering while nested popup is open reuses both HWNDs without recreation.
      model.tick = 1
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      let snapsAfterRender = backend.activePopupSnapshots
      #expect(snapsAfterRender.count == 2)
      #expect(snapsAfterRender[0].hwnd == snaps[0].hwnd)
      #expect(snapsAfterRender[1].hwnd == snaps[1].hwnd)

      // Escape on the inner popup dismisses ONLY the inner popup, keeping the outer popover open.
      let innerBackend = try #require(backend.activePopupBackends.last)
      #expect(innerBackend.inputHandler?(nil, 6, .zero, 27, [], "") == true)
      pump_pending_win32_messages()
      #expect(model.outerOpen)
      #expect(!model.innerOpen)
      #expect(backend.activePopupSnapshots.count == 1)

      // Second Escape on the outer popup dismisses the outer popover cleanly.
      let outerBackend = try #require(backend.activePopupBackends.first)
      #expect(outerBackend.inputHandler?(nil, 6, .zero, 27, [], "") == true)
      pump_pending_win32_messages()
      #expect(!model.outerOpen)
      #expect(backend.activePopupSnapshots.isEmpty)
    }

    @Test("Pointer tap gesture and scroll wheel inside popup translate coordinates accurately outside host bounds")
    func pointerTapAndScrollWheelInsideEscapingPopup() throws {
      final class ScrollTapModel: ObservableObject {
        @Published var open = false
        @Published var tapped = 0
      }
      struct EscapingScrollScene: SwiftUIRuntime.View {
        @ObservedObject var model: ScrollTapModel
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.Button("Open") { model.open = true }
            .frame(width: 80, height: 26)
            .popover(isPresented: $model.open, arrowEdge: .top) {
              SwiftUIRuntime.VStack(spacing: 4) {
                SwiftUIRuntime.Text("Tap Header")
                  .frame(width: 240, height: 32)
                  .onTapGesture { model.tapped += 1 }
                SwiftUIRuntime.ScrollView {
                  SwiftUIRuntime.VStack(spacing: 4) {
                    SwiftUIRuntime.ForEach(0..<20, id: \.self) { idx in
                      SwiftUIRuntime.Text("Row \(idx)")
                        .frame(width: 240, height: 24)
                    }
                  }
                }
                .frame(width: 240, height: 140)
              }
              .padding(8)
              .frame(width: 260, height: 196)
            }
            .frame(width: 140, height: 60)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 260, y: 200, width: 140, height: 60))
      window.show()
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = ScrollTapModel()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(EscapingScrollScene(model: model)),
        size: .init(width: 140, height: 60)
      )
      backend.inputHandler = { [weak renderer] id, event, point, value, modifiers, text in
        renderer?.input(
          id: id, event: event, point: point, value: value, modifiers: modifiers, text: text) ?? false
      }
      renderer.mount()

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()

      let popupBackend = try #require(backend.activePopupBackends.first)
      let placement = try #require(backend.activePopupPlacements.first)

      // Tap near the right side of the header (x = 220, well past the 140pt host window width!).
      let headerPt = CGPoint(x: placement.contentRect.minX + 220, y: placement.contentRect.minY + 20)
      _ = popupBackend.inputHandler?(nil, 2, headerPt, 0, [], "")
      _ = popupBackend.inputHandler?(nil, 3, headerPt, 0, [], "")
      pump_pending_win32_messages()
      #expect(model.tapped == 1)

      // Wheel scroll inside the ScrollView below the header (y = 110, well past the 60pt host window height!).
      let scrollPt = CGPoint(x: placement.contentRect.minX + 200, y: placement.contentRect.minY + 110)
      #expect(popupBackend.inputHandler?(nil, 5, scrollPt, -120, [], "") == true)
      renderer.renderIfNeeded()
      let scrolledTree = try #require(renderer.tree)
      let scrollNode = try #require(findNode(in: scrolledTree) { $0.kind == .scroll })
      #expect(scrollNode.props.scrollOffset.y > 0)
    }

    @Test("Activating an unrelated window dismisses the open popup")
    func activatingExternalWindowDismissesPopup() throws {
      final class Model: ObservableObject {
        @Published var open = false
      }
      struct SimplePopover: SwiftUIRuntime.View {
        @ObservedObject var model: Model
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.Button("Open") { model.open = true }
            .popover(isPresented: $model.open, arrowEdge: .top) {
              SwiftUIRuntime.Text("Transient").frame(width: 180, height: 80)
            }
            .frame(width: 220, height: 100)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let hostWin = try #require(NativeAPI.Window.create())
      let externalWin = try #require(NativeAPI.Window.create())
      defer {
        _ = externalWin.close()
        _ = hostWin.close()
      }
      hostWin.setBounds(NativeAPI.Rectangle(x: 240, y: 200, width: 220, height: 100))
      hostWin.show()
      externalWin.setBounds(NativeAPI.Rectangle(x: 620, y: 200, width: 200, height: 100))
      pump_pending_win32_messages()

      let backend = try #require(WindowsDrawingBackend(window: hostWin))
      let model = Model()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(SimplePopover(model: model)),
        size: .init(width: 220, height: 100)
      )
      renderer.mount()

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)

      // Showing & focusing an unrelated top-level window deactivates the popup -> dismisses cleanly.
      externalWin.show()
      externalWin.focus()
      pump_pending_win32_messages()
      #expect(!model.open)
      #expect(backend.activePopupSnapshots.isEmpty)
    }

    @Test("Hidden host window keeps in-window fallback and promotes to owned popup when shown")
    func hiddenHostWindowFallbackAndDeferredPromotion() throws {
      final class Model: ObservableObject {
        @Published var open = false
      }
      struct DeferredScene: SwiftUIRuntime.View {
        @ObservedObject var model: Model
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.VStack(spacing: 12) {
            SwiftUIRuntime.Button("Underneath") {}
            SwiftUIRuntime.Button("Trigger") { model.open = true }
              .popover(isPresented: $model.open, arrowEdge: .bottom) {
                SwiftUIRuntime.Text("Deferred Popover")
                  .frame(width: 220, height: 120)
              }
          }
          .padding(16)
          .frame(width: 240, height: 160)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 260, y: 200, width: 240, height: 160))

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = Model()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(DeferredScene(model: model)),
        size: .init(width: 240, height: 160)
      )
      renderer.mount()

      // Host window is still hidden -> no orphan top-level popup window appears on desktop.
      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.isEmpty)

      // Showing the host window promotes the active popover to an owned top-level popup window.
      window.show()
      pump_pending_win32_messages()
      let snapshots = backend.activePopupSnapshots
      #expect(snapshots.count == 1)
      let promoted = try #require(snapshots.first)
      #expect(promoted.isVisible)
      #expect(promoted.ownerHwnd == backend.rootHwnd)
    }

    @Test("Dismissing a popup window does not post WM_QUIT to the host message loop")
    func dismissingPopupDoesNotPostQuitMessage() throws {
      final class Model: ObservableObject {
        @Published var open = false
      }
      struct MenuHost: SwiftUIRuntime.View {
        @ObservedObject var model: Model
        var body: some SwiftUIRuntime.View {
          SwiftUIRuntime.Button("Menu") { model.open = true }
            .frame(width: 90, height: 28)
            ._menuPopover(isPresented: $model.open, arrowEdge: .bottom) {
              SwiftUIRuntime.Button("Item") {}
                .frame(width: 140, height: 28)
            }
            .padding(16)
            .frame(width: 220, height: 120)
        }
      }

      WindowsDrawingBackend.prepareApplication()
      _ = NativeAPI.Application.shared.isRunning()
      let window = try #require(NativeAPI.Window.create())
      defer { _ = window.close() }
      window.setBounds(NativeAPI.Rectangle(x: 240, y: 200, width: 220, height: 120))
      window.show()
      pump_pending_win32_messages()

      // Drain any stale WM_QUIT left by earlier test teardowns before checking ours.
      var staleQuit = MSG()
      while PeekMessageW(&staleQuit, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_REMOVE)) {}

      let backend = try #require(WindowsDrawingBackend(window: window))
      let model = Model()
      let renderer = Renderer(
        backend: backend,
        root: AnyView(MenuHost(model: model)),
        size: .init(width: 220, height: 120)
      )
      renderer.mount()

      model.open = true
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.count == 1)

      // Dismissing the popup destroys its transient HWND; it must NEVER post WM_QUIT.
      model.open = false
      renderer.renderIfNeeded()
      pump_pending_win32_messages()
      #expect(backend.activePopupSnapshots.isEmpty)

      var quitMsg = MSG()
      let receivedQuit = PeekMessageW(
        &quitMsg, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_REMOVE))
      #expect(!receivedQuit, "Dismissing a popup must not post WM_QUIT to the app message loop")
    }
  }
#endif
