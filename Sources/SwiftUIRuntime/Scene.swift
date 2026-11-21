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

public struct WindowGroup<Content: View>: Scene {
  public typealias Body = EmptyScene

  public let title: String
  public var _applicationIdentifier: String?
  public var _defaultSize = Size(width: 480, height: 320)
  private let content: () -> Content

  public init(
    _ title: String = "",
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.content = content
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
}

public protocol _WindowScene {
  var _windowTitle: String { get }
  var _applicationIdentifier: String? { get }
  var _defaultSize: Size { get }
  func _makeRootView() -> AnyView
}

extension _WindowScene { public var _applicationIdentifier: String? { nil } }

extension WindowGroup: _WindowScene {
  public var _windowTitle: String { title }

  public func _makeRootView() -> AnyView {
    AnyView(content())
  }
}

// MARK: - MenuBarExtra & Commands

public enum MenuBarExtraStyle: Sendable {
  case menu
  case window
}

public protocol _MenuBarExtraScene {
  var _isInserted: Binding<Bool>? { get }
  var _title: String { get }
  func _makeContentView() -> AnyView
  func _makeLabelView() -> AnyView
}

public struct MenuBarExtra<Label: View, Content: View>: Scene, _MenuBarExtraScene {
  public typealias Body = EmptyScene

  public let _isInserted: Binding<Bool>?
  public let _title: String
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

  public func menuBarExtraStyle(_ style: MenuBarExtraStyle) -> Self { self }

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

public struct EmptyCommands: Commands {
  public typealias Body = EmptyCommands
  public init() {}
  public var body: EmptyCommands { EmptyCommands() }
}

public struct TupleCommands: Commands {
  public typealias Body = EmptyCommands
  public let children: [any Commands]
  public init(_ children: [any Commands]) { self.children = children }
  public var body: EmptyCommands { EmptyCommands() }
}

public struct CommandGroup<Content: View>: Commands {
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
}

@resultBuilder
public enum CommandsBuilder {
  public static func buildBlock() -> EmptyCommands { EmptyCommands() }
  public static func buildBlock<C: Commands>(_ c: C) -> C { c }
  public static func buildBlock(_ components: any Commands...) -> TupleCommands {
    TupleCommands(components)
  }
}

extension Scene {
  public func commands<Content: Commands>(@CommandsBuilder content: () -> Content) -> Self {
    _ = content()
    return self
  }
}
