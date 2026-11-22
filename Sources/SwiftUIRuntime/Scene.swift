import Foundation

public protocol Scene {
  associatedtype Body: Scene

  @SceneBuilder var body: Body { get }
}

public struct TupleScene<First: Scene, Second: Scene>: Scene {
  public typealias Body = EmptyScene
  public let first: First
  public let second: Second

  public init(_ first: First, _ second: Second) {
    self.first = first
    self.second = second
  }

  public var body: EmptyScene { EmptyScene() }
}

extension TupleScene: _CompositeScene {
  public var _childScenes: [any Scene] { [first, second] }
}

public protocol _CompositeScene {
  var _childScenes: [any Scene] { get }
}

@resultBuilder
public enum SceneBuilder {
  public static func buildBlock() -> EmptyScene {
    EmptyScene()
  }

  public static func buildBlock<S: Scene>(_ scene: S) -> S {
    scene
  }

  public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> TupleScene<S0, S1> {
    TupleScene(s0, s1)
  }

  public static func buildBlock<S0: Scene, S1: Scene, S2: Scene>(
    _ s0: S0, _ s1: S1, _ s2: S2
  ) -> TupleScene<TupleScene<S0, S1>, S2> {
    TupleScene(TupleScene(s0, s1), s2)
  }

  public static func buildBlock<S0: Scene, S1: Scene, S2: Scene, S3: Scene>(
    _ s0: S0, _ s1: S1, _ s2: S2, _ s3: S3
  ) -> TupleScene<TupleScene<TupleScene<S0, S1>, S2>, S3> {
    TupleScene(TupleScene(TupleScene(s0, s1), s2), s3)
  }

  public static func buildBlock<S0: Scene, S1: Scene, S2: Scene, S3: Scene, S4: Scene>(
    _ s0: S0, _ s1: S1, _ s2: S2, _ s3: S3, _ s4: S4
  ) -> TupleScene<TupleScene<TupleScene<TupleScene<S0, S1>, S2>, S3>, S4> {
    TupleScene(TupleScene(TupleScene(TupleScene(s0, s1), s2), s3), s4)
  }
}

public struct EmptyScene: Scene {
  public typealias Body = EmptyScene

  public init() {}

  public var body: EmptyScene { EmptyScene() }
}

@MainActor @preconcurrency public protocol App {
  associatedtype Body: Scene

  @SceneBuilder var body: Body { get }

  init()
}

// MARK: - Window Scenes (WindowGroup, Window, Settings)

public protocol _WindowScene {
  var _windowTitle: String { get }
  var _windowID: String? { get }
  var _isSingleInstanceWindow: Bool { get }
  var _opensAtLaunch: Bool { get }
  var _applicationIdentifier: String? { get }
  var _defaultSize: Size { get }
  func _makeRootView() -> AnyView
  func _makeRootView(for value: Any) -> AnyView?
}

extension _WindowScene {
  public var _windowID: String? { nil }
  public var _isSingleInstanceWindow: Bool { false }
  public var _opensAtLaunch: Bool { true }
  public var _applicationIdentifier: String? { nil }
  public func _makeRootView(for value: Any) -> AnyView? { _makeRootView() }
}

public struct WindowGroup<Content: View>: Scene {
  public typealias Body = EmptyScene

  public let title: String
  public let id: String?
  public var _applicationIdentifier: String?
  public var _defaultSize = Size(width: 480, height: 320)
  private let content: () -> Content
  private let valueContent: ((Any) -> AnyView?)?

  public init(
    _ title: String = "",
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.id = nil
    self.content = content
    self.valueContent = nil
  }

  public init(
    _ title: String = "",
    id: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.id = id
    self.content = content
    self.valueContent = nil
  }

  public init(
    _ titleKey: LocalizedStringKey,
    id: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = titleKey.resolved()
    self.id = id
    self.content = content
    self.valueContent = nil
  }

  public init<D: Codable & Hashable>(
    _ title: String = "",
    id: String? = nil,
    for type: D.Type,
    @ViewBuilder content: @escaping (Binding<D?>) -> Content
  ) {
    self.title = title
    self.id = id
    self.content = { content(.constant(nil)) }
    self.valueContent = { raw in
      guard let typed = raw as? D else { return nil }
      var box: D? = typed
      let binding = Binding<D?>(get: { box }, set: { box = $0 })
      return AnyView(content(binding))
    }
  }

  public var body: EmptyScene { EmptyScene() }

  /// Native desktop identity, independent of the visible window title.
  public func applicationIdentifier(_ identifier: String) -> Self {
    var copy = self
    copy._applicationIdentifier = identifier
    return copy
  }

  public func defaultSize(width: Double, height: Double) -> Self {
    var copy = self
    copy._defaultSize = Size(width: width, height: height)
    return copy
  }

  public func defaultSize(_ size: CGSize) -> Self {
    defaultSize(width: Double(size.width), height: Double(size.height))
  }
}

extension WindowGroup: _WindowScene {
  public var _windowTitle: String { title }
  public var _windowID: String? { id }

  public func _makeRootView() -> AnyView {
    AnyView(content())
  }

  public func _makeRootView(for value: Any) -> AnyView? {
    valueContent?(value) ?? AnyView(content())
  }
}

/// Single-instance named window scene opened programmatically via `@Environment(\.openWindow)`.
public struct Window<Content: View>: Scene, _WindowScene {
  public typealias Body = EmptyScene

  public let title: String
  public let id: String
  public var _defaultSize = Size(width: 520, height: 380)
  private let content: () -> Content

  public init(
    _ title: String,
    id: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.id = id
    self.content = content
  }

  public init(
    _ titleKey: LocalizedStringKey,
    id: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = titleKey.resolved()
    self.id = id
    self.content = content
  }

  public var body: EmptyScene { EmptyScene() }
  public var _windowTitle: String { title }
  public var _windowID: String? { id }
  public var _isSingleInstanceWindow: Bool { true }
  public var _opensAtLaunch: Bool { false }

  public func defaultSize(width: Double, height: Double) -> Self {
    var copy = self
    copy._defaultSize = Size(width: width, height: height)
    return copy
  }

  public func defaultSize(_ size: CGSize) -> Self {
    defaultSize(width: Double(size.width), height: Double(size.height))
  }

  public func _makeRootView() -> AnyView {
    AnyView(content())
  }
}

/// Declarative preferences / settings scene (`Settings { ... }`).
public struct Settings<Content: View>: Scene, _WindowScene {
  public typealias Body = EmptyScene
  public static var windowID: String { "__crossswift_settings" }

  public var _defaultSize = Size(width: 560, height: 420)
  private let content: () -> Content

  public init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  public var body: EmptyScene { EmptyScene() }
  public var _windowTitle: String { "Settings" }
  public var _windowID: String? { Self.windowID }
  public var _isSingleInstanceWindow: Bool { true }
  public var _opensAtLaunch: Bool { false }

  public func defaultSize(width: Double, height: Double) -> Self {
    var copy = self
    copy._defaultSize = Size(width: width, height: height)
    return copy
  }

  public func _makeRootView() -> AnyView {
    AnyView(content())
  }
}

// MARK: - OpenWindowAction & DismissWindowAction

public struct OpenWindowAction: Sendable {
  let handler: @MainActor @Sendable (String?, Any?) -> Void

  public init(handler: @escaping @MainActor @Sendable (String?, Any?) -> Void) {
    self.handler = handler
  }

  @MainActor
  public func callAsFunction(id: String) {
    handler(id, nil)
  }

  @MainActor
  public func callAsFunction<D: Codable & Hashable>(id: String, value: D) {
    handler(id, value)
  }

  @MainActor
  public func callAsFunction<D: Codable & Hashable>(value: D) {
    handler(nil, value)
  }
}

public struct DismissWindowAction: Sendable {
  let handler: @MainActor @Sendable (String?) -> Void

  public init(handler: @escaping @MainActor @Sendable (String?) -> Void) {
    self.handler = handler
  }

  @MainActor
  public func callAsFunction() {
    handler(nil)
  }

  @MainActor
  public func callAsFunction(id: String) {
    handler(id)
  }
}

private enum OpenWindowActionKey: EnvironmentKey {
  static let defaultValue = OpenWindowAction { _, _ in }
}

private enum DismissWindowActionKey: EnvironmentKey {
  static let defaultValue = DismissWindowAction { _ in }
}

extension EnvironmentValues {
  public var openWindow: OpenWindowAction {
    get { self[OpenWindowActionKey.self] }
    set { self[OpenWindowActionKey.self] = newValue }
  }

  public var dismissWindow: DismissWindowAction {
    get { self[DismissWindowActionKey.self] }
    set { self[DismissWindowActionKey.self] = newValue }
  }
}

// MARK: - MenuBarExtra & Commands

public enum MenuBarExtraStyle: Sendable, Equatable {
  case menu
  case window
}

public protocol _MenuBarExtraScene {
  var _isInserted: Binding<Bool>? { get }
  var _title: String { get }
  var _style: MenuBarExtraStyle { get }
  func _makeContentView() -> AnyView
  func _makeLabelView() -> AnyView
}

public struct MenuBarExtra<Label: View, Content: View>: Scene, _MenuBarExtraScene {
  public typealias Body = EmptyScene

  public let _isInserted: Binding<Bool>?
  public let _title: String
  public var _style: MenuBarExtraStyle = .menu
  private let contentBuilder: () -> Content
  private let labelBuilder: () -> Label

  public init(
    _ titleKey: String = "",
    isInserted: Binding<Bool>? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self._title = titleKey
    self._isInserted = isInserted
    self.contentBuilder = content
    self.labelBuilder = label
  }

  public init(
    isInserted: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self._title = ""
    self._isInserted = isInserted
    self.contentBuilder = content
    self.labelBuilder = label
  }

  public init(
    _ titleKey: String,
    systemImage: String,
    isInserted: Binding<Bool>? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Image {
    self._title = titleKey
    self._isInserted = isInserted
    self.contentBuilder = content
    self.labelBuilder = { Image(systemName: systemImage) }
  }

  public var body: EmptyScene { EmptyScene() }

  public func menuBarExtraStyle(_ style: MenuBarExtraStyle) -> Self {
    var copy = self
    copy._style = style
    return copy
  }

  public func _makeContentView() -> AnyView { AnyView(contentBuilder()) }
  public func _makeLabelView() -> AnyView { AnyView(labelBuilder()) }
}

public enum CommandGroupPlacement: Sendable {
  case appInfo
  case appSettings
  case appVisibility
  case appTermination
  case systemServices
  case newItem
  case saveItem
  case importExport
  case printItem
  case undoRedo
  case pasteboard
  case textEditing
  case textFormatting
  case toolbar
  case sidebar
  case windowSize
  case windowList
  case windowArrangement
  case help
}

public protocol Commands {
  associatedtype Body: Commands
  @CommandsBuilder var body: Body { get }
}

public struct _ResolvedCommandSection {
  public let title: String
  public let placement: CommandGroupPlacement?
  public let content: () -> AnyView

  public init(title: String, placement: CommandGroupPlacement?, content: @escaping () -> AnyView) {
    self.title = title
    self.placement = placement
    self.content = content
  }
}

public protocol _CommandSectionProvider {
  func _collectCommandSections() -> [_ResolvedCommandSection]
}

public struct EmptyCommands: Commands, _CommandSectionProvider {
  public typealias Body = EmptyCommands
  public init() {}
  public var body: EmptyCommands { EmptyCommands() }
  public func _collectCommandSections() -> [_ResolvedCommandSection] { [] }
}

public struct TupleCommands: Commands, _CommandSectionProvider {
  public typealias Body = EmptyCommands
  public let children: [any Commands]
  public init(_ children: [any Commands]) { self.children = children }
  public var body: EmptyCommands { EmptyCommands() }
  public func _collectCommandSections() -> [_ResolvedCommandSection] {
    children.flatMap { _collectSections(from: $0) }
  }
}

public func _collectSections(from commands: any Commands) -> [_ResolvedCommandSection] {
  if let provider = commands as? any _CommandSectionProvider {
    return provider._collectCommandSections()
  }
  let body = commands.body
  if body is EmptyCommands { return [] }
  return _collectSections(from: body)
}

public struct CommandGroup<Content: View>: Commands, _CommandSectionProvider {
  public typealias Body = EmptyCommands
  public let placement: CommandGroupPlacement
  private let content: () -> Content

  public init(replacing placement: CommandGroupPlacement, @ViewBuilder addition: @escaping () -> Content) {
    self.placement = placement
    self.content = addition
  }

  public init(after placement: CommandGroupPlacement, @ViewBuilder addition: @escaping () -> Content) {
    self.placement = placement
    self.content = addition
  }

  public init(before placement: CommandGroupPlacement, @ViewBuilder addition: @escaping () -> Content) {
    self.placement = placement
    self.content = addition
  }

  public var body: EmptyCommands { EmptyCommands() }

  public func _collectCommandSections() -> [_ResolvedCommandSection] {
    let sectionTitle: String
    switch placement {
    case .appInfo, .appSettings, .appVisibility, .appTermination, .systemServices:
      sectionTitle = "App"
    case .newItem, .saveItem, .importExport, .printItem:
      sectionTitle = "File"
    case .undoRedo, .pasteboard, .textEditing, .textFormatting:
      sectionTitle = "Edit"
    case .toolbar, .sidebar:
      sectionTitle = "View"
    case .windowSize, .windowList, .windowArrangement:
      sectionTitle = "Window"
    case .help:
      sectionTitle = "Help"
    }
    return [_ResolvedCommandSection(title: sectionTitle, placement: placement, content: { AnyView(content()) })]
  }
}

/// Top-level menu added to the application menu bar via `.commands { CommandMenu("Tools") { ... } }`.
public struct CommandMenu<Content: View>: Commands, _CommandSectionProvider {
  public typealias Body = EmptyCommands
  public let title: String
  private let content: () -> Content

  public init(_ name: String, @ViewBuilder content: @escaping () -> Content) {
    self.title = name
    self.content = content
  }

  public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
    self.title = nameKey.resolved()
    self.content = content
  }

  public var body: EmptyCommands { EmptyCommands() }

  public func _collectCommandSections() -> [_ResolvedCommandSection] {
    [_ResolvedCommandSection(title: title, placement: nil, content: { AnyView(content()) })]
  }
}

@resultBuilder
public enum CommandsBuilder {
  public static func buildBlock() -> EmptyCommands { EmptyCommands() }
  public static func buildBlock<C: Commands>(_ c: C) -> C { c }
  public static func buildBlock(_ components: any Commands...) -> TupleCommands {
    TupleCommands(components)
  }
}

public protocol _CommandsProvidingScene {
  var _baseScene: any Scene { get }
  func _makeCommandSections() -> [_ResolvedCommandSection]
}

public struct _ModifiedCommandsScene<Base: Scene, Content: Commands>: Scene, _CommandsProvidingScene, _CompositeScene {
  public typealias Body = EmptyScene
  let base: Base
  let commandsBuilder: () -> Content

  public var body: EmptyScene { EmptyScene() }
  public var _baseScene: any Scene { base }
  public var _childScenes: [any Scene] { [base] }

  public func _makeCommandSections() -> [_ResolvedCommandSection] {
    _collectSections(from: commandsBuilder())
  }
}

extension Scene {
  public func commands<Content: Commands>(
    @CommandsBuilder content: @escaping () -> Content
  ) -> _ModifiedCommandsScene<Self, Content> {
    _ModifiedCommandsScene(base: self, commandsBuilder: content)
  }
}
