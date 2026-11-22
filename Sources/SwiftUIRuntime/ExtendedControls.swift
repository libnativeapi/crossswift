import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

// MARK: - NavigationPath & navigationDestination

/// Type-erased list of Hashable navigation values used with `NavigationStack(path:)`.
public struct NavigationPath: Equatable {
  struct Box: Equatable {
    let typeID: ObjectIdentifier
    let value: AnyHashable
    let raw: Any
    let label: String

    init<V: Hashable>(_ value: V) {
      self.typeID = ObjectIdentifier(V.self)
      self.value = AnyHashable(value)
      self.raw = value
      self.label = String(describing: value)
    }

    static func == (lhs: Box, rhs: Box) -> Bool {
      lhs.typeID == rhs.typeID && lhs.value == rhs.value
    }
  }

  var boxes: [Box] = []

  public init() {}

  public init<S: Sequence>(_ elements: S) where S.Element: Hashable {
    self.boxes = elements.map { Box($0) }
  }

  public var count: Int { boxes.count }
  public var isEmpty: Bool { boxes.isEmpty }

  public mutating func append<V: Hashable>(_ value: V) {
    boxes.append(Box(value))
  }

  public mutating func removeLast(_ k: Int = 1) {
    guard k > 0 else { return }
    let n = min(k, boxes.count)
    boxes.removeLast(n)
  }
}

final class _NavigationDestinationRegistry {
  var factories: [ObjectIdentifier: (Any) -> AnyView] = [:]

  func register<D: Hashable>(_ type: D.Type, builder: @escaping (D) -> AnyView) {
    factories[ObjectIdentifier(type)] = { raw in
      guard let value = raw as? D else { return AnyView(EmptyView()) }
      return builder(value)
    }
  }

  func resolve(typeID: ObjectIdentifier, value: Any) -> AnyView? {
    factories[typeID]?(value)
  }
}

private enum _NavigationDestinationRegistryKey: EnvironmentKey {
  static let defaultValue = _NavigationDestinationRegistry()
}

extension EnvironmentValues {
  var _navigationDestinations: _NavigationDestinationRegistry {
    get { self[_NavigationDestinationRegistryKey.self] }
    set { self[_NavigationDestinationRegistryKey.self] = newValue }
  }
}

private struct _NavigationDestinationModifier<Content: View, D: Hashable, Destination: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let dataType: D.Type
  let destination: (D) -> Destination
  var body: Never { fatalError("_NavigationDestinationModifier is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    EnvironmentValues.current._navigationDestinations.register(dataType) { value in
      AnyView(destination(value))
    }
    return _render(content, path: path)
  }
}

private struct _NavigationPresentedDestinationModifier<Content: View, Destination: View>: View {
  let content: Content
  let isPresented: Binding<Bool>
  let destination: () -> Destination
  @Environment(\._navigationActions) private var navActions
  @State private var didPush = false

  var body: some View {
    content
      .onChange(of: isPresented.wrappedValue) { _, newValue in
        if newValue && !didPush {
          didPush = true
          navActions.push?("", AnyView(destination()))
        } else if !newValue && didPush {
          didPush = false
          navActions.pop?()
        }
      }
  }
}

extension View {
  public func navigationDestination<D: Hashable, C: View>(
    for data: D.Type,
    @ViewBuilder destination: @escaping (D) -> C
  ) -> some View {
    _NavigationDestinationModifier(content: self, dataType: data, destination: destination)
  }

  public func navigationDestination<V: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder destination: @escaping () -> V
  ) -> some View {
    _NavigationPresentedDestinationModifier(
      content: self, isPresented: isPresented, destination: destination
    )
  }

  public func navigationDestination<D: Hashable, C: View>(
    item: Binding<D?>,
    @ViewBuilder destination: @escaping (D) -> C
  ) -> some View {
    let presented = Binding<Bool>(
      get: { item.wrappedValue != nil },
      set: { if !$0 { item.wrappedValue = nil } }
    )
    return _NavigationPresentedDestinationModifier(
      content: self,
      isPresented: presented,
      destination: {
        Group {
          if let val = item.wrappedValue {
            destination(val)
          }
        }
      }
    )
  }
}

// MARK: - DisclosureGroup

public struct DisclosureGroup<Label: View, Content: View>: View {
  let label: Label
  let content: () -> Content
  let externalExpanded: Binding<Bool>?
  @State private var internalExpanded = false

  public init(
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.externalExpanded = isExpanded
    self.content = content
    self.label = label()
  }

  public init(
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.externalExpanded = nil
    self.content = content
    self.label = label()
  }

  public init(
    _ titleKey: LocalizedStringKey,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.externalExpanded = isExpanded
    self.content = content
    self.label = Text(titleKey)
  }

  public init(
    _ titleKey: LocalizedStringKey,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.externalExpanded = nil
    self.content = content
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.externalExpanded = isExpanded
    self.content = content
    self.label = Text(verbatim: String(title))
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    @ViewBuilder content: @escaping () -> Content
  ) where Label == Text {
    self.externalExpanded = nil
    self.content = content
    self.label = Text(verbatim: String(title))
  }

  public var body: some View {
    let expanded = externalExpanded?.wrappedValue ?? internalExpanded
    VStack(alignment: .leading, spacing: 6) {
      Button {
        if let externalExpanded {
          externalExpanded.wrappedValue.toggle()
        } else {
          internalExpanded.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: 14)
          label
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if expanded {
        VStack(alignment: .leading, spacing: 4) {
          content()
        }
        .padding(.leading, 18)
      }
    }
  }
}

// MARK: - Gauge

public enum GaugeStyleKind: Sendable, Equatable {
  case automatic
  case linearCapacity
  case accessoryLinear
  case accessoryLinearCapacity
  case accessoryCircular
  case accessoryCircularCapacity
}

public struct GaugeStyle: Sendable, Equatable {
  public let kind: GaugeStyleKind
  public init(_ kind: GaugeStyleKind) { self.kind = kind }

  public static let automatic = GaugeStyle(.automatic)
  public static let linearCapacity = GaugeStyle(.linearCapacity)
  public static let accessoryLinear = GaugeStyle(.accessoryLinear)
  public static let accessoryLinearCapacity = GaugeStyle(.accessoryLinearCapacity)
  public static let accessoryCircular = GaugeStyle(.accessoryCircular)
  public static let accessoryCircularCapacity = GaugeStyle(.accessoryCircularCapacity)
}

private enum GaugeStyleKey: EnvironmentKey {
  static let defaultValue = GaugeStyle.automatic
}

extension EnvironmentValues {
  public var gaugeStyle: GaugeStyle {
    get { self[GaugeStyleKey.self] }
    set { self[GaugeStyleKey.self] = newValue }
  }
}

extension View {
  public func gaugeStyle(_ style: GaugeStyle) -> some View {
    environment(\.gaugeStyle, style)
  }
}

public struct Gauge<Label: View, CurrentValueLabel: View, BoundsLabel: View, MarkedValueLabels: View>: View {
  let fraction: Double
  let label: Label
  let currentValueLabel: CurrentValueLabel
  let minimumValueLabel: BoundsLabel
  let maximumValueLabel: BoundsLabel
  let hasBounds: Bool
  @Environment(\.gaugeStyle) private var style

  public init<V: BinaryFloatingPoint>(
    value: V,
    in bounds: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label
  ) where CurrentValueLabel == EmptyView, BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    let span = Double(bounds.upperBound - bounds.lowerBound)
    self.fraction = span > 0 ? min(1, max(0, (Double(value) - Double(bounds.lowerBound)) / span)) : 0
    self.label = label()
    self.currentValueLabel = EmptyView()
    self.minimumValueLabel = EmptyView()
    self.maximumValueLabel = EmptyView()
    self.hasBounds = false
  }

  public init<V: BinaryFloatingPoint>(
    value: V,
    in bounds: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) where BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    let span = Double(bounds.upperBound - bounds.lowerBound)
    self.fraction = span > 0 ? min(1, max(0, (Double(value) - Double(bounds.lowerBound)) / span)) : 0
    self.label = label()
    self.currentValueLabel = currentValueLabel()
    self.minimumValueLabel = EmptyView()
    self.maximumValueLabel = EmptyView()
    self.hasBounds = false
  }

  public init<V: BinaryFloatingPoint>(
    value: V,
    in bounds: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel,
    @ViewBuilder minimumValueLabel: () -> BoundsLabel,
    @ViewBuilder maximumValueLabel: () -> BoundsLabel
  ) where MarkedValueLabels == EmptyView {
    let span = Double(bounds.upperBound - bounds.lowerBound)
    self.fraction = span > 0 ? min(1, max(0, (Double(value) - Double(bounds.lowerBound)) / span)) : 0
    self.label = label()
    self.currentValueLabel = currentValueLabel()
    self.minimumValueLabel = minimumValueLabel()
    self.maximumValueLabel = maximumValueLabel()
    self.hasBounds = true
  }

  public var body: some View {
    let tint = EnvironmentValues.current.tint
    let isCircular = style.kind == .accessoryCircular || style.kind == .accessoryCircularCapacity
    if isCircular {
      VStack(spacing: 4) {
        ZStack {
          Circle()
            .stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 5, lineCap: .round))
          Circle()
            .trim(from: 0, to: CGFloat(fraction))
            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .rotationEffect(.degrees(-90))
          if CurrentValueLabel.self != EmptyView.self {
            currentValueLabel.font(.caption)
          } else {
            Text(verbatim: "\(Int((fraction * 100).rounded()))%")
              .font(.caption)
          }
        }
        .frame(width: 48, height: 48)
        if Label.self != EmptyView.self {
          label.font(.caption)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 4) {
        if Label.self != EmptyView.self || CurrentValueLabel.self != EmptyView.self {
          HStack {
            if Label.self != EmptyView.self { label }
            Spacer()
            if CurrentValueLabel.self != EmptyView.self {
              currentValueLabel.foregroundStyle(.secondary)
            }
          }
        }
        HStack(spacing: 6) {
          if hasBounds {
            minimumValueLabel.font(.caption).foregroundStyle(.secondary)
          }
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.primary.opacity(0.14)).frame(height: 6)
              Capsule().fill(tint).frame(width: geo.size.width * CGFloat(fraction), height: 6)
            }
          }
          .frame(height: 6)
          if hasBounds {
            maximumValueLabel.font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

// MARK: - DatePicker

public struct DatePickerComponents: OptionSet, Sendable, Equatable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
  public static let date = DatePickerComponents(rawValue: 1 << 1)
}

public enum DatePickerStyleKind: Sendable, Equatable {
  case automatic
  case compact
  case graphical
  case field
  case stepperField
}

public struct DatePickerStyle: Sendable, Equatable {
  public let kind: DatePickerStyleKind
  public init(_ kind: DatePickerStyleKind) { self.kind = kind }
  public static let automatic = DatePickerStyle(.automatic)
  public static let compact = DatePickerStyle(.compact)
  public static let graphical = DatePickerStyle(.graphical)
  public static let field = DatePickerStyle(.field)
  public static let stepperField = DatePickerStyle(.stepperField)
}

private enum DatePickerStyleKey: EnvironmentKey {
  static let defaultValue = DatePickerStyle.automatic
}

extension EnvironmentValues {
  public var datePickerStyle: DatePickerStyle {
    get { self[DatePickerStyleKey.self] }
    set { self[DatePickerStyleKey.self] = newValue }
  }
}

extension View {
  public func datePickerStyle(_ style: DatePickerStyle) -> some View {
    environment(\.datePickerStyle, style)
  }
}

public struct DatePicker<Label: View>: View {
  let label: Label
  let selection: Binding<Date>
  let minDate: Date?
  let maxDate: Date?
  let displayedComponents: DatePickerComponents
  @Environment(\.datePickerStyle) private var style
  @State private var isExpanded = false

  public init(
    selection: Binding<Date>,
    displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.minDate = nil
    self.maxDate = nil
    self.displayedComponents = displayedComponents
    self.label = label()
  }

  public init(
    selection: Binding<Date>,
    in range: ClosedRange<Date>,
    displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.minDate = range.lowerBound
    self.maxDate = range.upperBound
    self.displayedComponents = displayedComponents
    self.label = label()
  }

  public init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
  ) where Label == Text {
    self.selection = selection
    self.minDate = nil
    self.maxDate = nil
    self.displayedComponents = displayedComponents
    self.label = Text(titleKey)
  }

  public init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    in range: ClosedRange<Date>,
    displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
  ) where Label == Text {
    self.selection = selection
    self.minDate = range.lowerBound
    self.maxDate = range.upperBound
    self.displayedComponents = displayedComponents
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Date>,
    displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
  ) where Label == Text {
    self.selection = selection
    self.minDate = nil
    self.maxDate = nil
    self.displayedComponents = displayedComponents
    self.label = Text(verbatim: String(title))
  }

  private func clamp(_ date: Date) -> Date {
    var result = date
    if let minDate, result < minDate { result = minDate }
    if let maxDate, result > maxDate { result = maxDate }
    return result
  }

  private func shift(_ component: Calendar.Component, by value: Int) {
    let cal = Calendar.current
    if let next = cal.date(byAdding: component, value: value, to: selection.wrappedValue) {
      selection.wrappedValue = clamp(next)
    }
  }

  private func formattedSummary(_ date: Date) -> String {
    let cal = Calendar.current
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    var parts: [String] = []
    if displayedComponents.contains(.date) {
      let y = comps.year ?? 2026
      let m = comps.month ?? 1
      let d = comps.day ?? 1
      parts.append(String(format: "%04d-%02d-%02d", y, m, d))
    }
    if displayedComponents.contains(.hourAndMinute) {
      let h = comps.hour ?? 0
      let minVal = comps.minute ?? 0
      parts.append(String(format: "%02d:%02d", h, minVal))
    }
    return parts.joined(separator: " ")
  }

  @ViewBuilder
  private func calendarGrid() -> some View {
    let cal = Calendar.current
    let current = selection.wrappedValue
    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: current)
    let year = comps.year ?? 2026
    let month = comps.month ?? 1
    let day = comps.day ?? 1
    let daysCount = cal.range(of: .day, in: .month, for: current)?.count ?? 30
    let tint = EnvironmentValues.current.tint

    VStack(spacing: 8) {
      if displayedComponents.contains(.date) {
        HStack {
          Button("‹") { shift(.month, by: -1) }.buttonStyle(.borderless)
          Spacer()
          Text(verbatim: String(format: "%04d-%02d", year, month)).font(.headline)
          Spacer()
          Button("›") { shift(.month, by: 1) }.buttonStyle(.borderless)
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 4) {
          ForEach(1...daysCount, id: \.self) { d in
            let isSelected = d == day
            Button {
              var next = comps
              next.day = d
              if let date = cal.date(from: next) {
                selection.wrappedValue = clamp(date)
              }
            } label: {
              Text(verbatim: "\(d)")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 26, height: 24)
                .background(isSelected ? tint : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
          }
        }
      }
      if displayedComponents.contains(.hourAndMinute) {
        HStack(spacing: 8) {
          Text("Time").font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("−1h") { shift(.hour, by: -1) }.buttonStyle(.bordered)
          Text(verbatim: String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0))
            .font(.body)
          Button("+1h") { shift(.hour, by: 1) }.buttonStyle(.bordered)
          Button("+15m") { shift(.minute, by: 15) }.buttonStyle(.bordered)
        }
      }
    }
    .padding(10)
    .frame(width: 240)
  }

  public var body: some View {
    if style.kind == .graphical {
      VStack(alignment: .leading, spacing: 6) {
        label
        calendarGrid()
      }
    } else {
      HStack(spacing: 8) {
        label
        Spacer()
        Button {
          isExpanded.toggle()
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "calendar")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
            Text(verbatim: formattedSummary(selection.wrappedValue))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExpanded) {
          calendarGrid()
        }
      }
    }
  }
}

// MARK: - ColorPicker

public struct ColorPicker<Label: View>: View {
  let label: Label
  let selection: Binding<Color>
  let supportsOpacity: Bool
  @State private var isPresented = false

  private static var presets: [Color] {
    [
      .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown,
      .black, .gray, .white,
    ]
  }

  public init(
    selection: Binding<Color>,
    supportsOpacity: Bool = true,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.supportsOpacity = supportsOpacity
    self.label = label()
  }

  public init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Color>,
    supportsOpacity: Bool = true
  ) where Label == Text {
    self.selection = selection
    self.supportsOpacity = supportsOpacity
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Color>,
    supportsOpacity: Bool = true
  ) where Label == Text {
    self.selection = selection
    self.supportsOpacity = supportsOpacity
    self.label = Text(verbatim: String(title))
  }

  public var body: some View {
    let current = selection.wrappedValue
    let rBind = Binding<Double>(
      get: { current.red },
      set: { selection.wrappedValue = Color(red: $0, green: current.green, blue: current.blue, opacity: current.opacity) }
    )
    let gBind = Binding<Double>(
      get: { current.green },
      set: { selection.wrappedValue = Color(red: current.red, green: $0, blue: current.blue, opacity: current.opacity) }
    )
    let bBind = Binding<Double>(
      get: { current.blue },
      set: { selection.wrappedValue = Color(red: current.red, green: current.green, blue: $0, opacity: current.opacity) }
    )
    let aBind = Binding<Double>(
      get: { current.opacity },
      set: { selection.wrappedValue = Color(red: current.red, green: current.green, blue: current.blue, opacity: $0) }
    )

    HStack(spacing: 8) {
      label
      Spacer()
      Button {
        isPresented.toggle()
      } label: {
        RoundedRectangle(cornerRadius: 6)
          .fill(current)
          .frame(width: 28, height: 22)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.25), lineWidth: 1))
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isPresented) {
        VStack(alignment: .leading, spacing: 10) {
          LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 5), spacing: 6) {
            ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, swatch in
              Button {
                selection.wrappedValue = swatch
              } label: {
                Circle()
                  .fill(swatch)
                  .frame(width: 22, height: 22)
                  .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
              }
              .buttonStyle(.plain)
            }
          }
          VStack(spacing: 6) {
            HStack { Text("R").font(.caption); Slider(value: rBind, in: 0...1) }
            HStack { Text("G").font(.caption); Slider(value: gBind, in: 0...1) }
            HStack { Text("B").font(.caption); Slider(value: bBind, in: 0...1) }
            if supportsOpacity {
              HStack { Text("A").font(.caption); Slider(value: aBind, in: 0...1) }
            }
          }
        }
        .padding(12)
        .frame(width: 200)
      }
    }
  }
}

// MARK: - AsyncImage

public enum AsyncImagePhase {
  case empty
  case success(Image)
  case failure(any Error)

  public var image: Image? {
    if case .success(let img) = self { return img }
    return nil
  }

  public var error: (any Error)? {
    if case .failure(let err) = self { return err }
    return nil
  }
}

final class _AsyncImageDiskCache {
  nonisolated(unsafe) static let shared = _AsyncImageDiskCache()
  private let lock = NSLock()
  private var pathsByURL: [URL: String] = [:]

  func cachedPath(for url: URL) -> String? {
    lock.lock()
    defer { lock.unlock() }
    if let path = pathsByURL[url], FileManager.default.fileExists(atPath: path) {
      return path
    }
    return nil
  }

  func store(data: Data, for url: URL) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("crossswift-async-images")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
    let fileURL = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    #if os(WASI)
      try data.write(to: fileURL)
    #else
      try data.write(to: fileURL, options: .atomic)
    #endif
    lock.lock()
    pathsByURL[url] = fileURL.path
    lock.unlock()
    return fileURL.path
  }
}

public struct AsyncImage<Content: View>: View {
  let url: URL?
  let scale: CGFloat
  let content: (AsyncImagePhase) -> Content
  @State private var phase: AsyncImagePhase = .empty

  public init(
    url: URL?,
    scale: CGFloat = 1,
    @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
  ) {
    self.url = url
    self.scale = scale
    self.content = content
  }

  public init<I: View, P: View>(
    url: URL?,
    scale: CGFloat = 1,
    @ViewBuilder content: @escaping (Image) -> I,
    @ViewBuilder placeholder: @escaping () -> P
  ) where Content == AnyView {
    self.url = url
    self.scale = scale
    self.content = { phase in
      if case .success(let image) = phase {
        return AnyView(content(image))
      }
      return AnyView(placeholder())
    }
  }

  public init(url: URL?, scale: CGFloat = 1) where Content == AnyView {
    self.url = url
    self.scale = scale
    self.content = { phase in
      if case .success(let image) = phase {
        return AnyView(image)
      }
      return AnyView(Color.secondary.opacity(0.15))
    }
  }

  public var body: some View {
    content(phase)
      .task(id: url) {
        guard let url else {
          phase = .empty
          return
        }
        if url.isFileURL {
          phase = .success(Image(url.path))
          return
        }
        if let cached = _AsyncImageDiskCache.shared.cachedPath(for: url) {
          phase = .success(Image(cached))
          return
        }
        #if os(WASI)
          // Browsers load remote URLs directly through <img src="...">.
          phase = .success(Image(url.absoluteString))
        #else
          do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            let path = try _AsyncImageDiskCache.shared.store(data: data, for: url)
            phase = .success(Image(path))
          } catch {
            if !Task.isCancelled {
              phase = .failure(error)
            }
          }
        #endif
      }
  }
}

// MARK: - Table & TableColumn

public struct TableColumn<RowValue: Identifiable> {
  public let title: String
  let cellView: (RowValue) -> AnyView
  let sortKey: ((RowValue) -> String)?

  public init<V: View>(
    _ title: String,
    @ViewBuilder content: @escaping (RowValue) -> V
  ) {
    self.title = title
    self.cellView = { AnyView(content($0)) }
    self.sortKey = nil
  }

  public init(
    _ title: String,
    value keyPath: KeyPath<RowValue, String>
  ) {
    self.title = title
    self.cellView = { row in AnyView(Text(verbatim: row[keyPath: keyPath])) }
    self.sortKey = { row in row[keyPath: keyPath] }
  }
}

@resultBuilder
public enum TableColumnBuilder<RowValue: Identifiable> {
  public static func buildExpression(_ column: TableColumn<RowValue>) -> [TableColumn<RowValue>] {
    [column]
  }
  public static func buildBlock(_ columns: [TableColumn<RowValue>]...) -> [TableColumn<RowValue>] {
    columns.flatMap { $0 }
  }
  public static func buildOptional(_ columns: [TableColumn<RowValue>]?) -> [TableColumn<RowValue>] {
    columns ?? []
  }
  public static func buildEither(first columns: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] {
    columns
  }
  public static func buildEither(second columns: [TableColumn<RowValue>]) -> [TableColumn<RowValue>] {
    columns
  }
  public static func buildArray(_ columns: [[TableColumn<RowValue>]]) -> [TableColumn<RowValue>] {
    columns.flatMap { $0 }
  }
}

public struct Table<RowValue: Identifiable>: View {
  let rows: [RowValue]
  let columns: [TableColumn<RowValue>]
  let singleSelection: Binding<RowValue.ID?>?
  let multiSelection: Binding<Set<RowValue.ID>>?
  @State private var sortColumnIndex: Int? = nil
  @State private var sortAscending: Bool = true

  public init(
    _ data: [RowValue],
    @TableColumnBuilder<RowValue> columns: () -> [TableColumn<RowValue>]
  ) {
    self.rows = data
    self.columns = columns()
    self.singleSelection = nil
    self.multiSelection = nil
  }

  public init(
    _ data: [RowValue],
    selection: Binding<RowValue.ID?>,
    @TableColumnBuilder<RowValue> columns: () -> [TableColumn<RowValue>]
  ) {
    self.rows = data
    self.columns = columns()
    self.singleSelection = selection
    self.multiSelection = nil
  }

  public init(
    _ data: [RowValue],
    selection: Binding<Set<RowValue.ID>>,
    @TableColumnBuilder<RowValue> columns: () -> [TableColumn<RowValue>]
  ) {
    self.rows = data
    self.columns = columns()
    self.singleSelection = nil
    self.multiSelection = selection
  }

  private func sortedRows() -> [RowValue] {
    guard let idx = sortColumnIndex, idx >= 0, idx < columns.count,
      let keyFn = columns[idx].sortKey
    else { return rows }
    return rows.sorted { lhs, rhs in
      let a = keyFn(lhs)
      let b = keyFn(rhs)
      return sortAscending ? a < b : a > b
    }
  }

  private func isSelected(_ id: RowValue.ID) -> Bool {
    if let singleSelection { return singleSelection.wrappedValue == id }
    if let multiSelection { return multiSelection.wrappedValue.contains(id) }
    return false
  }

  private func select(_ id: RowValue.ID) {
    if let singleSelection {
      singleSelection.wrappedValue = id
    } else if let multiSelection {
      if multiSelection.wrappedValue.contains(id) {
        multiSelection.wrappedValue.remove(id)
      } else {
        multiSelection.wrappedValue.insert(id)
      }
    }
  }

  public var body: some View {
    let displayed = sortedRows()
    let tint = EnvironmentValues.current.tint
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
          Button {
            if col.sortKey != nil {
              if sortColumnIndex == idx {
                sortAscending.toggle()
              } else {
                sortColumnIndex = idx
                sortAscending = true
              }
            }
          } label: {
            HStack(spacing: 4) {
              Text(verbatim: col.title)
                .font(.caption)
                .foregroundStyle(.secondary)
              if sortColumnIndex == idx {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                  .font(.system(size: 9))
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
        }
      }
      .background(Color.primary.opacity(0.05))
      Divider()
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(displayed.enumerated()), id: \.element.id) { rowIdx, row in
            let selected = isSelected(row.id)
            Button {
              select(row.id)
            } label: {
              HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                  col.cellView(row)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .foregroundStyle(selected ? Color.white : Color.primary)
              .background(
                selected
                  ? tint
                  : (rowIdx % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

// MARK: - ShareLink

public struct ShareLink<Label: View>: View {
  let itemURL: URL?
  let itemText: String
  let label: Label
  @Environment(\.openURL) private var openURL

  public init(item: URL, @ViewBuilder label: () -> Label) {
    self.itemURL = item
    self.itemText = item.absoluteString
    self.label = label()
  }

  public init(_ titleKey: LocalizedStringKey, item: URL) where Label == SwiftUIRuntime.Label<Text, Image> {
    self.itemURL = item
    self.itemText = item.absoluteString
    self.label = SwiftUIRuntime.Label(titleKey, systemImage: "square.and.arrow.up")
  }

  public init(item: String, @ViewBuilder label: () -> Label) {
    self.itemURL = URL(string: item)
    self.itemText = item
    self.label = label()
  }

  public init(_ titleKey: LocalizedStringKey, item: String) where Label == SwiftUIRuntime.Label<Text, Image> {
    self.itemURL = URL(string: item)
    self.itemText = item
    self.label = SwiftUIRuntime.Label(titleKey, systemImage: "square.and.arrow.up")
  }

  public var body: some View {
    Button {
      if let itemURL {
        _ = openURL(itemURL)
      }
    } label: {
      label
    }
  }
}

// MARK: - File Importer / File Exporter Environment Hook

public struct _FileDialogService: Sendable {
  public let presentOpen: (@MainActor @Sendable ([String], Bool, @escaping (Result<[URL], any Error>) -> Void) -> Void)?
  public let presentSave: (@MainActor @Sendable (String?, Data?, @escaping (Result<URL, any Error>) -> Void) -> Void)?

  public init(
    presentOpen: (@MainActor @Sendable ([String], Bool, @escaping (Result<[URL], any Error>) -> Void) -> Void)? = nil,
    presentSave: (@MainActor @Sendable (String?, Data?, @escaping (Result<URL, any Error>) -> Void) -> Void)? = nil
  ) {
    self.presentOpen = presentOpen
    self.presentSave = presentSave
  }
}

private enum _FileDialogServiceKey: EnvironmentKey {
  static let defaultValue = _FileDialogService()
}

extension EnvironmentValues {
  public var _fileDialogService: _FileDialogService {
    get { self[_FileDialogServiceKey.self] }
    set { self[_FileDialogServiceKey.self] = newValue }
  }
}

public struct FileDialogUnavailableError: Error, LocalizedError {
  public init() {}
  public var errorDescription: String? { "No native file dialog provider is attached." }
}

private struct _FileImporterModifier<Content: View>: View {
  let content: Content
  let isPresented: Binding<Bool>
  let allowedExtensions: [String]
  let allowsMultiple: Bool
  let onCompletion: (Result<[URL], any Error>) -> Void
  @Environment(\._fileDialogService) private var service
  @State private var activeRequest = false

  var body: some View {
    content
      .onChange(of: isPresented.wrappedValue) { _, presented in
        guard presented, !activeRequest else { return }
        activeRequest = true
        if let presentOpen = service.presentOpen {
          presentOpen(allowedExtensions, allowsMultiple) { result in
            activeRequest = false
            isPresented.wrappedValue = false
            onCompletion(result)
          }
        } else {
          activeRequest = false
          isPresented.wrappedValue = false
          onCompletion(.failure(FileDialogUnavailableError()))
        }
      }
  }
}

private struct _FileExporterModifier<Content: View>: View {
  let content: Content
  let isPresented: Binding<Bool>
  let defaultFilename: String?
  let payload: Data?
  let onCompletion: (Result<URL, any Error>) -> Void
  @Environment(\._fileDialogService) private var service
  @State private var activeRequest = false

  var body: some View {
    content
      .onChange(of: isPresented.wrappedValue) { _, presented in
        guard presented, !activeRequest else { return }
        activeRequest = true
        if let presentSave = service.presentSave {
          presentSave(defaultFilename, payload) { result in
            activeRequest = false
            isPresented.wrappedValue = false
            onCompletion(result)
          }
        } else {
          activeRequest = false
          isPresented.wrappedValue = false
          onCompletion(.failure(FileDialogUnavailableError()))
        }
      }
  }
}

extension View {
  public func fileImporter(
    isPresented: Binding<Bool>,
    allowedContentTypes: [String] = [],
    allowsMultipleSelection: Bool = false,
    onCompletion: @escaping (Result<[URL], any Error>) -> Void
  ) -> some View {
    _FileImporterModifier(
      content: self,
      isPresented: isPresented,
      allowedExtensions: allowedContentTypes,
      allowsMultiple: allowsMultipleSelection,
      onCompletion: onCompletion
    )
  }

  public func fileImporter(
    isPresented: Binding<Bool>,
    allowedContentTypes: [String] = [],
    onCompletion: @escaping (Result<URL, any Error>) -> Void
  ) -> some View {
    fileImporter(
      isPresented: isPresented,
      allowedContentTypes: allowedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let first = urls.first {
          onCompletion(.success(first))
        } else {
          onCompletion(.failure(FileDialogUnavailableError()))
        }
      case .failure(let error):
        onCompletion(.failure(error))
      }
    }
  }

  public func fileExporter(
    isPresented: Binding<Bool>,
    data: Data?,
    defaultFilename: String? = nil,
    onCompletion: @escaping (Result<URL, any Error>) -> Void
  ) -> some View {
    _FileExporterModifier(
      content: self,
      isPresented: isPresented,
      defaultFilename: defaultFilename,
      payload: data,
      onCompletion: onCompletion
    )
  }
}

// MARK: - RedactionReasons, RefreshAction, SwipeActions

public struct RedactionReasons: OptionSet, Sendable, Equatable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let placeholder = RedactionReasons(rawValue: 1 << 0)
  public static let privacy = RedactionReasons(rawValue: 1 << 1)
}

private enum RedactionReasonsKey: EnvironmentKey {
  static let defaultValue: RedactionReasons = []
}

extension EnvironmentValues {
  public var redactionReasons: RedactionReasons {
    get { self[RedactionReasonsKey.self] }
    set { self[RedactionReasonsKey.self] = newValue }
  }
}

public struct RefreshAction: Sendable {
  let action: @MainActor @Sendable () async -> Void

  public init(action: @escaping @MainActor @Sendable () async -> Void) {
    self.action = action
  }

  @MainActor
  public func callAsFunction() async {
    await action()
  }
}

private enum RefreshActionKey: EnvironmentKey {
  static let defaultValue: RefreshAction? = nil
}

extension EnvironmentValues {
  public var refresh: RefreshAction? {
    get { self[RefreshActionKey.self] }
    set { self[RefreshActionKey.self] = newValue }
  }
}

private struct _RedactedModifierView<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let reasons: RedactionReasons
  var body: Never { fatalError("_RedactedModifierView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let old = EnvironmentValues.current.redactionReasons
    EnvironmentValues.current.redactionReasons = reasons
    defer { EnvironmentValues.current.redactionReasons = old }
    var el = _render(content, path: path)
    if !reasons.isEmpty {
      applyRedaction(&el)
    }
    return el
  }

  private func applyRedaction(_ node: inout Element) {
    if node.kind == .text, !node.props.text.isEmpty {
      node.props.background = Color.primary.opacity(0.16)
      node.props.foreground = .clear
      node.props.cornerRadius = max(node.props.cornerRadius, 4)
    }
    for i in node.children.indices {
      applyRedaction(&node.children[i])
    }
  }
}

private struct _SwipeActionsModifierView<Content: View, Actions: View>: View {
  let content: Content
  let edge: HorizontalEdge
  let actions: Actions
  @State private var revealed = false

  var body: some View {
    HStack(spacing: 0) {
      if edge == .leading && revealed {
        actions
      }
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .gesture(
          DragGesture(minimumDistance: 20)
            .onEnded { value in
              if edge == .trailing {
                if value.translation.width < -28 { revealed = true }
                else if value.translation.width > 20 { revealed = false }
              } else {
                if value.translation.width > 28 { revealed = true }
                else if value.translation.width < -20 { revealed = false }
              }
            }
        )
      if edge == .trailing && revealed {
        actions
      }
    }
  }
}

extension View {
  public func redacted(reason: RedactionReasons) -> some View {
    _RedactedModifierView(content: self, reasons: reason)
  }

  public func unredacted() -> some View {
    environment(\.redactionReasons, [])
  }

  public func refreshable(action: @escaping @MainActor @Sendable () async -> Void) -> some View {
    environment(\.refresh, RefreshAction(action: action))
  }

  public func swipeActions<T: View>(
    edge: HorizontalEdge = .trailing,
    allowsFullSwipe: Bool = true,
    @ViewBuilder content: () -> T
  ) -> some View {
    _SwipeActionsModifierView(content: self, edge: edge, actions: content())
  }
}
