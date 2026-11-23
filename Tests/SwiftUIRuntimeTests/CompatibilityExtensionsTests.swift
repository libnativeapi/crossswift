import Foundation
import XCTest

@testable import SwiftUIRuntime

private struct SumPreference: PreferenceKey {
  static let defaultValue = 0
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

final class CompatibilityExtensionsTests: XCTestCase {
  override func setUp() { StateRegistry.shared.reset() }

  private func render<V: View>(_ view: V, size: Size = .init(width: 300, height: 200)) -> Renderer {
    let renderer = Renderer(backend: FakeBackend(), root: AnyView(view), size: size)
    renderer.mount()
    return renderer
  }

  func testFittingViewSelectsAlternativeAndChangesOnResize() throws {
    let renderer = render(
      ViewThatFits(in: .horizontal) {
        Text("Wide").frame(width: 200, height: 30)
        Text("Compact").frame(width: 80, height: 30)
      }, size: .init(width: 100, height: 60))
    let compact = try XCTUnwrap(findNode(in: renderer.tree!, text: "Compact"))
    XCTAssertGreaterThan(compact.frame.width, 0)
    let layout = try XCTUnwrap(findNode(in: renderer.tree!, kind: .customLayout))
    XCTAssertEqual(layout.children[0].frame.width, 0)
    XCTAssertTrue(layout.children[0].props.clipped)
    renderer.resize(to: .init(width: 300, height: 60))
    XCTAssertGreaterThan(try XCTUnwrap(findNode(in: renderer.tree!, text: "Wide")).frame.width, 0)
    let resized = try XCTUnwrap(findNode(in: renderer.tree!, kind: .customLayout))
    XCTAssertEqual(resized.children[1].frame.width, 0)
    XCTAssertTrue(resized.children[1].props.clipped)
  }

  func testFittingViewFallsBackToLastAlternative() throws {
    let renderer = render(
      ViewThatFits {
        Text("First").frame(width: 200, height: 200)
        Text("Last").frame(width: 80, height: 80)
      }, size: .init(width: 50, height: 50))
    XCTAssertGreaterThan(try XCTUnwrap(findNode(in: renderer.tree!, text: "Last")).frame.width, 0)
  }

  func testUnselectedFittingCandidateDoesNotReceivePointerInput() {
    var wide = 0
    var compact = 0
    let renderer = render(
      ViewThatFits(in: .horizontal) {
        Button("Wide") { wide += 1 }.frame(width: 200, height: 40)
        Button("Compact") { compact += 1 }.frame(width: 80, height: 40)
      }, size: .init(width: 100, height: 40))
    _ = renderer.input(event: 2, point: .init(x: 90, y: 20))
    _ = renderer.input(event: 3, point: .init(x: 90, y: 20))
    XCTAssertEqual(wide, 0)
    _ = renderer.input(event: 2, point: .init(x: 40, y: 20))
    _ = renderer.input(event: 3, point: .init(x: 40, y: 20))
    XCTAssertEqual(compact, 1)
  }

  func testHorizontalScrollReaderUsesAnchorAndClamps() {
    var scrollTo: ((Int, UnitPoint) -> Void)?
    let renderer = render(
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 0) {
            ForEach(0..<10) { index in Text("Item").frame(width: 30, height: 20).id(index) }
          }
        }.onAppear { scrollTo = { proxy.scrollTo($0, anchor: $1) } }
      }, size: .init(width: 100, height: 30))
    scrollTo?(5, .center)
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.x, 115)
    scrollTo?(9, .leading)
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.x, 200)
    scrollTo?(0, .trailing)
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.x, 0)
  }

  func testTimelineScheduleRejectsNonFiniteIntervals() {
    XCTAssertTrue(AnimationTimelineSchedule.animation(minimumInterval: .infinity).interval.isFinite)
    XCTAssertGreaterThan(AnimationTimelineSchedule.animation(minimumInterval: -1).interval, 0)
    XCTAssertNotEqual(
      AnimationTimelineSchedule.animation(minimumInterval: 0.01),
      AnimationTimelineSchedule.animation(minimumInterval: 1))
  }

  func testScrollReaderCanRepeatTheSameTargetAfterManualScrolling() throws {
    var scrollTo: (() -> Void)?
    let renderer = render(
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            ForEach(0..<10) { index in Text("Row \(index)").frame(height: 30).id(index) }
          }
        }.onAppear { scrollTo = { proxy.scrollTo(9, anchor: .bottom) } }
      }, size: .init(width: 200, height: 100))
    scrollTo?()
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.y, 200)
    _ = renderer.input(event: 5, point: .init(x: 50, y: 50), value: 12000)
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.y, 0)
    scrollTo?()
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .scroll)?.props.scrollOffset.y, 200)
  }

  func testPreferenceTransformsReduceChildrenAndUpdateOverlay() throws {
    final class Model: SwiftUIRuntime.ObservableObject { @SwiftUIRuntime.Published var value = 3 }
    struct Content: View {
      @ObservedObject var model: Model
      var body: some View {
        VStack {
          Text("A").preference(key: SumPreference.self, value: model.value)
          Text("B").preference(key: SumPreference.self, value: 4)
        }
        .transformPreference(SumPreference.self) { $0 *= 2 }
        .transformPreference(SumPreference.self) { $0 += 1 }
        .overlayPreferenceValue(SumPreference.self) { Text("Total: \($0)") }
      }
    }
    let model = Model()
    let renderer = render(Content(model: model))
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "Total: 15"))
    model.value = 5
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "Total: 19"))
  }

  func testLocaleEnvironmentIsScopedAndRestored() {
    struct Probe: View {
      @Environment(\.locale) var locale
      var body: some View { Text(locale.identifier) }
    }
    let original = EnvironmentValues.current.locale
    let renderer = render(
      VStack {
        Probe().environment(\.locale, Locale(identifier: "ja_JP"))
        Probe()
      }.environment(\.locale, Locale(identifier: "en_US")))
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "ja_JP"))
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "en_US"))
    XCTAssertEqual(EnvironmentValues.current.locale, original)
  }

  func testAttributedLinkUsesScopedHandlerAndRunTracking() throws {
    guard #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) else {
      throw XCTSkip("AttributedString requires a newer Foundation")
    }
    var opened: URL?
    let url = URL(string: "https://example.com/docs")!
    var attributed = AttributedString("Docs")
    attributed.link = url
    let renderer = render(
      (Text("Go ") + Text(attributed)).kerning(2)
        .environment(
          \.openURL,
          OpenURLAction {
            opened = $0
            return .handled
          }))
    let link = try XCTUnwrap(findNode(in: renderer.tree!, text: "Docs"))
    XCTAssertTrue(link.props.underline)
    XCTAssertEqual(link.props.tracking, 2)
    renderer.performTap(link.id)
    XCTAssertEqual(opened, url)
  }

  func testAlertBlocksBackgroundAndDismissesAfterActionAndEscape() throws {
    final class Actions {
      var background = 0
      var confirm = 0
    }
    struct Content: View {
      @State var shown = true
      let actions: Actions
      var body: some View {
        Button("Background") { actions.background += 1 }
          .alert("Confirm", isPresented: $shown) {
            Button("Delete", role: .destructive) { actions.confirm += 1 }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("Are you sure?")
          }
      }
    }
    let actions = Actions()
    let renderer = render(Content(actions: actions), size: .init(width: 600, height: 400))
    let background = try XCTUnwrap(findNode(in: renderer.tree!, text: "Background"))
    renderer.performTap(background.id)
    XCTAssertEqual(actions.background, 0)
    let delete = try XCTUnwrap(findNode(in: renderer.tree!, text: "Delete"))
    XCTAssertEqual(delete.props.foreground, .red)
    let cancel = try XCTUnwrap(findNode(in: renderer.tree!, text: "Cancel"))
    XCTAssertLessThan(
      cancel.frame.minX, delete.frame.minX,
      "Cancel button should lead on the left of a two-action modal dialog")
    renderer.performTap(delete.id)
    XCTAssertEqual(actions.confirm, 1)
    XCTAssertNil(findNode(in: renderer.tree!, text: "Are you sure?"))
    let second = render(Content(actions: actions))
    XCTAssertTrue(second.input(event: 6, value: 27))
    XCTAssertNil(findNode(in: second.tree!, text: "Are you sure?"))
  }

  func testStyledButtonForwardsNativeHoverToMakeBodyModifiers() throws {
    struct HoverPillStyle: ButtonStyle {
      func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
      }
      struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        var body: some View {
          configuration.label
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Color.blue.opacity(hovered ? 0.28 : 0.20)))
            .onHover { hovered = $0 }
        }
      }
    }
    let renderer = render(
      Button("Save") {}.buttonStyle(HoverPillStyle()),
      size: .init(width: 200, height: 80))
    let styledBtn = try XCTUnwrap(findNode(in: renderer.tree!, kind: .styledButton))
    let initialShape = try XCTUnwrap(allNodes(renderer.tree!).first { $0.kind == .shape })
    XCTAssertEqual(initialShape.props.background?.opacity ?? 0, 0.20, accuracy: 0.01)

    renderer.interact(styledBtn.id, .hover(true))
    let hoveredShape = try XCTUnwrap(allNodes(renderer.tree!).first { $0.kind == .shape })
    XCTAssertEqual(hoveredShape.props.background?.opacity ?? 0, 0.28, accuracy: 0.01)

    renderer.interact(styledBtn.id, .hover(false))
    let unhoveredShape = try XCTUnwrap(allNodes(renderer.tree!).first { $0.kind == .shape })
    XCTAssertEqual(unhoveredShape.props.background?.opacity ?? 0, 0.20, accuracy: 0.01)
  }

  func testDialogViewThatFitsHorizontalActionButtonsShareWidthEqually() throws {
    struct PillDialogButtonStyle: ButtonStyle {
      let primary: Bool
      func makeBody(configuration: Configuration) -> some View {
        configuration.label
          .font(.system(size: 13, weight: primary ? .semibold : .medium))
          .lineLimit(1)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
          .background(Capsule().fill(primary ? Color.blue.opacity(0.24) : Color.white.opacity(0.08)))
      }
    }
    let dialog = VStack(alignment: .leading, spacing: 18) {
      Text("Relaunch Tinycast?")
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          Button("Cancel") {}.buttonStyle(PillDialogButtonStyle(primary: false))
          Button("Relaunch") {}.buttonStyle(PillDialogButtonStyle(primary: true))
        }
        VStack(spacing: 8) {
          Button("Relaunch") {}.buttonStyle(PillDialogButtonStyle(primary: true))
          Button("Cancel") {}.buttonStyle(PillDialogButtonStyle(primary: false))
        }
      }
    }
    .padding(16)
    .frame(width: 320, alignment: .leading)

    let renderer = render(dialog, size: .init(width: 400, height: 240))
    let fitting = try XCTUnwrap(findNode(in: renderer.tree!, kind: .customLayout))
    XCTAssertGreaterThan(fitting.children[0].frame.width, 0)
    XCTAssertEqual(fitting.children[1].frame.width, 0)
    XCTAssertTrue(fitting.children[1].props.clipped)
    let buttons = allNodes(fitting.children[0]).filter { $0.kind == .styledButton }
    XCTAssertEqual(buttons.count, 2)
    XCTAssertEqual(buttons[0].frame.minY, buttons[1].frame.minY, accuracy: 0.5)
    XCTAssertEqual(buttons[0].frame.height, 34, accuracy: 0.5)
    XCTAssertEqual(buttons[1].frame.height, 34, accuracy: 0.5)
    XCTAssertEqual(buttons[0].frame.width, buttons[1].frame.width, accuracy: 1.0)
    XCTAssertGreaterThan(buttons[0].frame.width, 130)
  }

  func testSaturationAndCompatibilityMetadataSurviveRendering() throws {
    let renderer = render(
      Text("Label").foregroundStyle(Color(red: 1, green: 0, blue: 0))
        .saturation(0).textSelection(.enabled).accessibilityIdentifier("summary"))
    let label = try XCTUnwrap(findNode(in: renderer.tree!, text: "Label"))
    let color = try XCTUnwrap(label.props.foreground)
    XCTAssertEqual(color.red, color.green, accuracy: 0.0001)
    XCTAssertEqual(color.green, color.blue, accuracy: 0.0001)
    XCTAssertTrue(label.props.selectableText)
    XCTAssertEqual(label.props.accessibilityIdentifier, "summary")
  }

  func testFocusBindingCanBeReadAndWrittenThroughProjection() throws {
    struct Content: View {
      @FocusState var focused: Bool
      var body: some View {
        Button($focused.wrappedValue ? "Focused" : "Unfocused") {
          $focused.wrappedValue.toggle()
        }
      }
    }
    let renderer = render(Content())
    renderer.performTap(try XCTUnwrap(findNode(in: renderer.tree!, text: "Unfocused")).id)
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "Focused"))
  }

  func testShapedBackgroundRetainsItsFillAndCornerRadius() throws {
    let renderer = render(Text("Card").background(.blue, in: RoundedRectangle(cornerRadius: 8)))
    let shape = try XCTUnwrap(allNodes(renderer.tree!).first { $0.props.background == .blue })
    XCTAssertEqual(shape.props.cornerRadius, 8)
    XCTAssertEqual(Angle.zero.radians, 0)
  }

  @MainActor
  func testTimelineTicksAndStopsWhenPaused() async throws {
    final class Model: SwiftUIRuntime.ObservableObject {
      @SwiftUIRuntime.Published var paused = false
    }
    struct Content: View {
      @ObservedObject var model: Model
      var body: some View {
        TimelineView(.animation(minimumInterval: 0.01, paused: model.paused)) {
          Text(String($0.date.timeIntervalSince1970))
        }
      }
    }
    let model = Model()
    let renderer = render(Content(model: model))
    let initial = findNode(in: renderer.tree!, kind: .text)?.props.text
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertNotEqual(findNode(in: renderer.tree!, kind: .text)?.props.text, initial)
    model.paused = true
    let paused = findNode(in: renderer.tree!, kind: .text)?.props.text
    try await Task.sleep(nanoseconds: 60_000_000)
    XCTAssertEqual(findNode(in: renderer.tree!, kind: .text)?.props.text, paused)
  }

  func testEntryMacroAndForEachBindingProjection() throws {
    let r1 = render(EntryProbe())
    XCTAssertNotNil(findNode(in: r1.tree!, text: "42-nil-none"))

    let r2 = render(
      EntryProbe()
        .environment(\.testEntryCount, 7)
        .environment(\.testEntryLabel, "ok")
        .environment(\.testEntryRef, NonSendableEntryBox(tag: "box"))
    )
    XCTAssertNotNil(findNode(in: r2.tree!, text: "7-ok-box"))

    let r3 = render(EntryListProbe())
    let btn = try XCTUnwrap(findNode(in: r3.tree!, text: "1:Alpha"))
    r3.performTap(btn.id)
    XCTAssertNotNil(findNode(in: r3.tree!, text: "1:Alpha!"))
  }
}

private struct EntryProbe: View {
  @Environment(\.testEntryCount) var count
  @Environment(\.testEntryLabel) var label
  @Environment(\.testEntryRef) var ref
  var body: some View {
    Text("\(count)-\(label ?? "nil")-\(ref?.tag ?? "none")")
  }
}

private struct EntryItem: Identifiable {
  let id: Int
  var name: String
}

private struct EntryListProbe: View {
  @State var items: [EntryItem] = [
    EntryItem(id: 1, name: "Alpha"),
    EntryItem(id: 2, name: "Beta"),
  ]
  var body: some View {
    VStack {
      #if os(Windows)
        // Swift 6.4.2+Asserts on Windows hits a LocalDiscriminator ASTVerifier
        // assertion on `{ $item in }` closure parameter wrappers.
        ForEach($items) { item in
          Button("\(item.wrappedValue.id):\(item.wrappedValue.name)") {
            item.wrappedValue.name = "\(item.wrappedValue.name)!"
          }
        }
      #else
        ForEach($items) { $item in
          let id = item.id
          Button("\(id):\(item.name)") {
            item.name = "\(item.name)!"
          }
        }
      #endif
    }
  }
}

private final class NonSendableEntryBox {
  var tag: String
  init(tag: String) { self.tag = tag }
}

extension EnvironmentValues {
  /// Doc comment before `@Entry` to verify trivia skipping.
  @Entry fileprivate var testEntryCount = 42
  @Entry fileprivate var testEntryLabel: String?
  @Entry fileprivate var testEntryRef: NonSendableEntryBox?
  @Entry fileprivate var testEntryArray: [Int] = []
}
