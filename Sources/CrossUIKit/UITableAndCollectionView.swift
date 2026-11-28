import Foundation

// MARK: - Modern Cell Content & Background Configurations

public protocol UIContentConfiguration {
  @MainActor func makeContentView() -> any UIView & UIContentView
  @MainActor func updated(for state: any UIConfigurationState) -> Self
}

@MainActor
public protocol UIContentView: NSObjectProtocol {
  var configuration: any UIContentConfiguration { get set }
}

public protocol UIConfigurationState {
  var traitCollection: UITraitCollection { get set }
}

public struct UICellConfigurationState: UIConfigurationState, Hashable, Sendable {
  public var traitCollection: UITraitCollection
  public var isDisabled: Bool = false
  public var isHighlighted: Bool = false
  public var isSelected: Bool = false
  public var isFocused: Bool = false
  public var isEditing: Bool = false
  public var isExpanded: Bool = false
  public var isSwiped: Bool = false
  public var isReordering: Bool = false

  public init(traitCollection: UITraitCollection) {
    self.traitCollection = traitCollection
  }
}

public struct UIListContentConfiguration: UIContentConfiguration, Equatable {
  public struct TextProperties: Equatable {
    public var font: UIFont = .preferredFont(forTextStyle: .body)
    public var color: UIColor = .label
    public var alignment: TextAlignment = .natural
    public var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    public var numberOfLines: Int = 0

    public enum TextAlignment: Int, Sendable {
      case natural = 0
      case center = 1
      case justified = 2
    }
  }

  public struct ImageProperties: Equatable {
    public var preferredSymbolConfiguration: UIImage.SymbolConfiguration?
    public var tintColor: UIColor?
    public var cornerRadius: CGFloat = 0
    public var maximumSize: CGSize = .zero
  }

  public var image: UIImage?
  public var imageProperties = ImageProperties()
  public var text: String?
  public var attributedText: NSAttributedString?
  public var textProperties = TextProperties()
  public var secondaryText: String?
  public var secondaryAttributedText: NSAttributedString?
  public var secondaryTextProperties = TextProperties()
  public var axesPreservingSuperviewLayoutMargins: UIAxis = [.horizontal]
  public var directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
  public var imageToTextPadding: CGFloat = 12
  public var textToSecondaryTextVerticalPadding: CGFloat = 3
  public var prefersSideBySideTextAndSecondaryText: Bool = false

  public static func cell() -> UIListContentConfiguration { UIListContentConfiguration() }
  public static func subtitleCell() -> UIListContentConfiguration {
    var cfg = UIListContentConfiguration()
    cfg.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
    cfg.secondaryTextProperties.color = .secondaryLabel
    return cfg
  }
  public static func valueCell() -> UIListContentConfiguration {
    var cfg = subtitleCell()
    cfg.prefersSideBySideTextAndSecondaryText = true
    return cfg
  }
  public static func sidebarCell() -> UIListContentConfiguration { UIListContentConfiguration() }
  public static func sidebarHeader() -> UIListContentConfiguration {
    var cfg = UIListContentConfiguration()
    cfg.textProperties.font = .preferredFont(forTextStyle: .subheadline)
    cfg.textProperties.color = .secondaryLabel
    return cfg
  }
  public static func groupedHeader() -> UIListContentConfiguration { sidebarHeader() }
  public static func groupedFooter() -> UIListContentConfiguration { sidebarHeader() }
  public static func plainHeader() -> UIListContentConfiguration { sidebarHeader() }
  public static func plainFooter() -> UIListContentConfiguration { sidebarHeader() }

  @MainActor
  public func makeContentView() -> any UIView & UIContentView {
    UIListContentView(configuration: self)
  }

  @MainActor
  public func updated(for state: any UIConfigurationState) -> UIListContentConfiguration {
    self
  }
}

@MainActor
public final class UIListContentView: UIView, UIContentView {
  private var typedConfiguration: UIListContentConfiguration
  public let textLabel = UILabel(frame: .zero)
  public let secondaryTextLabel = UILabel(frame: .zero)
  public let imageView = UIImageView(frame: .zero)

  public var configuration: any UIContentConfiguration {
    get { typedConfiguration }
    set {
      if let listCfg = newValue as? UIListContentConfiguration {
        typedConfiguration = listCfg
        applyConfiguration()
      }
    }
  }

  public init(configuration: UIListContentConfiguration) {
    self.typedConfiguration = configuration
    super.init(frame: .zero)
    addSubview(imageView)
    addSubview(textLabel)
    addSubview(secondaryTextLabel)
    applyConfiguration()
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func applyConfiguration() {
    imageView.image = typedConfiguration.image
    imageView.isHidden = typedConfiguration.image == nil
    textLabel.text = typedConfiguration.attributedText?.string ?? typedConfiguration.text
    textLabel.font = typedConfiguration.textProperties.font
    textLabel.textColor = typedConfiguration.textProperties.color
    secondaryTextLabel.text = typedConfiguration.secondaryAttributedText?.string ?? typedConfiguration.secondaryText
    secondaryTextLabel.font = typedConfiguration.secondaryTextProperties.font
    secondaryTextLabel.textColor = typedConfiguration.secondaryTextProperties.color
    secondaryTextLabel.isHidden = (secondaryTextLabel.text ?? "").isEmpty
    setNeedsLayout()
  }
}

public struct UIBackgroundConfiguration: Equatable {
  public var backgroundColor: UIColor?
  public var visualEffect: UIVisualEffect?
  public var image: UIImage?
  public var cornerRadius: CGFloat = 0
  public var backgroundInsets: NSDirectionalEdgeInsets = .zero
  public var strokeColor: UIColor?
  public var strokeWidth: CGFloat = 0

  public static func clear() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
  public static func listPlainCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
  public static func listGroupedCell() -> UIBackgroundConfiguration {
    var cfg = UIBackgroundConfiguration()
    cfg.backgroundColor = .secondarySystemGroupedBackground
    cfg.cornerRadius = 10
    return cfg
  }
  public static func listSidebarCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
  public static func listPlainHeaderFooter() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
  public static func listGroupedHeaderFooter() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }

  public func updated(for state: any UIConfigurationState) -> UIBackgroundConfiguration { self }
}

// MARK: - UITableView & Cells

@MainActor
open class UITableViewCell: UIView {
  public enum CellStyle: Int, Sendable {
    case `default` = 0
    case value1 = 1
    case value2 = 2
    case subtitle = 3
  }

  public enum SelectionStyle: Int, Sendable {
    case none = 0
    case blue = 1
    case gray = 2
    case `default` = 3
  }

  public enum AccessoryType: Int, Sendable {
    case none = 0
    case disclosureIndicator = 1
    case detailDisclosureButton = 2
    case checkmark = 3
    case detailButton = 4
  }

  public let reuseIdentifier: String?
  public let contentView: UIView = UIView(frame: .zero)
  public let textLabel: UILabel? = UILabel(frame: .zero)
  public let detailTextLabel: UILabel? = UILabel(frame: .zero)
  public let imageView: UIImageView? = UIImageView(frame: .zero)
  public var backgroundView: UIView?
  public var selectedBackgroundView: UIView?
  public var accessoryType: AccessoryType = .none
  public var accessoryView: UIView?
  public var selectionStyle: SelectionStyle = .default
  public var separatorInset: UIEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
  public var isSelected: Bool = false
  public var isHighlighted: Bool = false

  private var hostedContentView: (any UIView & UIContentView)?

  public var contentConfiguration: (any UIContentConfiguration)? {
    didSet {
      hostedContentView?.removeFromSuperview()
      hostedContentView = nil
      if let cfg = contentConfiguration {
        let made = cfg.makeContentView()
        made.frame = contentView.bounds
        made.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(made)
        hostedContentView = made
      }
    }
  }

  public var backgroundConfiguration: UIBackgroundConfiguration? {
    didSet {
      if let bg = backgroundConfiguration?.backgroundColor {
        backgroundColor = bg
      }
    }
  }

  public func defaultContentConfiguration() -> UIListContentConfiguration {
    .cell()
  }

  public required init(style: CellStyle, reuseIdentifier: String?) {
    self.reuseIdentifier = reuseIdentifier
    super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
    contentView.frame = bounds
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(contentView)
    if let tl = textLabel { contentView.addSubview(tl) }
    if let dl = detailTextLabel { contentView.addSubview(dl) }
    if let iv = imageView { contentView.addSubview(iv) }
  }

  public convenience override init(frame: CGRect) {
    self.init(style: .default, reuseIdentifier: nil)
    self.frame = frame
  }

  public required init?(coder: NSCoder) {
    self.reuseIdentifier = nil
    super.init(coder: coder)
    addSubview(contentView)
  }

  open func prepareForReuse() {}
  open func setSelected(_ selected: Bool, animated: Bool) { isSelected = selected }
  open func setHighlighted(_ highlighted: Bool, animated: Bool) { isHighlighted = highlighted }
}

@MainActor
open class UITableViewHeaderFooterView: UIView {
  public let reuseIdentifier: String?
  public let contentView = UIView(frame: .zero)
  public let textLabel: UILabel? = UILabel(frame: .zero)
  public var contentConfiguration: (any UIContentConfiguration)?
  public var backgroundConfiguration: UIBackgroundConfiguration?

  public required init(reuseIdentifier: String?) {
    self.reuseIdentifier = reuseIdentifier
    super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 28))
    addSubview(contentView)
  }

  public required init?(coder: NSCoder) {
    self.reuseIdentifier = nil
    super.init(coder: coder)
  }

  public func defaultContentConfiguration() -> UIListContentConfiguration {
    .groupedHeader()
  }

  open func prepareForReuse() {}
}

@MainActor
open class UIContextualAction: NSObject {
  public enum Style: Int, Sendable {
    case normal = 0
    case destructive = 1
  }

  public typealias Handler = (UIContextualAction, UIView, @escaping (Bool) -> Void) -> Void

  public let style: Style
  public var title: String?
  public var backgroundColor: UIColor = .systemRed
  public var image: UIImage?
  public let handler: Handler

  public init(style: Style, title: String?, handler: @escaping Handler) {
    self.style = style
    self.title = title
    self.handler = handler
    super.init()
  }
}

@MainActor
open class UISwipeActionsConfiguration: NSObject {
  public let actions: [UIContextualAction]
  public var performsFirstActionWithFullSwipe: Bool = true

  public init(actions: [UIContextualAction]) {
    self.actions = actions
    super.init()
  }
}

@MainActor
public protocol UITableViewDataSource: NSObjectProtocol {
  func numberOfSections(in tableView: UITableView) -> Int
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
}

extension UITableViewDataSource {
  public func numberOfSections(in tableView: UITableView) -> Int { 1 }
  public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
  public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
  public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { false }
  public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
}

extension UITableViewCell {
  public enum EditingStyle: Int, Sendable {
    case none = 0
    case delete = 1
    case insert = 2
  }
}

@MainActor
public protocol UITableViewDelegate: UIScrollViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
  func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
  func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
  func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
  func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
}

extension UITableViewDelegate {
  public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
  public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {}
  public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    UITableView.automaticDimension
  }
  public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
  public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    UITableView.automaticDimension
  }
  public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
  public func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
}

@MainActor
open class UITableView: UIScrollView {
  public enum Style: Int, Sendable {
    case plain = 0
    case grouped = 1
    case insetGrouped = 2
  }

  public enum ScrollPosition: Int, Sendable {
    case none = 0
    case top = 1
    case middle = 2
    case bottom = 3
  }

  public enum RowAnimation: Int, Sendable {
    case fade = 0
    case right = 1
    case left = 2
    case top = 3
    case bottom = 4
    case none = 5
    case middle = 6
    case automatic = 100
  }

  public enum SeparatorStyle: Int, Sendable {
    case none = 0
    case singleLine = 1
  }

  public static let automaticDimension: CGFloat = -1

  public let style: Style
  public weak var dataSource: (any UITableViewDataSource)?
  private weak var tableDelegate: (any UITableViewDelegate)?
  public override var delegate: (any UIScrollViewDelegate)? {
    get { tableDelegate }
    set { tableDelegate = newValue as? any UITableViewDelegate }
  }

  public var rowHeight: CGFloat = 44
  public var estimatedRowHeight: CGFloat = 44
  public var sectionHeaderHeight: CGFloat = UITableView.automaticDimension
  public var sectionFooterHeight: CGFloat = UITableView.automaticDimension
  public var separatorStyle: SeparatorStyle = .singleLine
  public var separatorColor: UIColor? = .separator
  public var separatorInset: UIEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
  public var tableHeaderView: UIView?
  public var tableFooterView: UIView?
  public var backgroundView: UIView?
  public var allowsSelection: Bool = true
  public var allowsMultipleSelection: Bool = false
  public var isEditing: Bool = false

  private var registeredCellTypes: [String: UITableViewCell.Type] = [:]
  private var registeredHeaderTypes: [String: UITableViewHeaderFooterView.Type] = [:]
  private var mountedCells: [IndexPath: UITableViewCell] = [:]
  private var selectedPaths: [IndexPath] = []

  public var indexPathForSelectedRow: IndexPath? { selectedPaths.first }
  public var indexPathsForSelectedRows: [IndexPath]? { selectedPaths.isEmpty ? nil : selectedPaths }
  public var visibleCells: [UITableViewCell] { Array(mountedCells.values) }
  public var indexPathsForVisibleRows: [IndexPath]? { Array(mountedCells.keys).sorted() }

  public var numberOfSections: Int {
    dataSource?.numberOfSections(in: self) ?? 1
  }

  public init(frame: CGRect, style: Style) {
    self.style = style
    super.init(frame: frame)
    self.backgroundColor = style == .plain ? .systemBackground : .systemGroupedBackground
  }

  public convenience override init(frame: CGRect) {
    self.init(frame: frame, style: .plain)
  }

  public required init?(coder: NSCoder) {
    self.style = .plain
    super.init(coder: coder)
  }

  public func numberOfRows(inSection section: Int) -> Int {
    dataSource?.tableView(self, numberOfRowsInSection: section) ?? 0
  }

  public func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {
    if let typed = cellClass as? UITableViewCell.Type {
      registeredCellTypes[identifier] = typed
    }
  }

  public func register(_ aClass: AnyClass?, forHeaderFooterViewReuseIdentifier identifier: String) {
    if let typed = aClass as? UITableViewHeaderFooterView.Type {
      registeredHeaderTypes[identifier] = typed
    }
  }

  public func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? {
    if let cls = registeredCellTypes[identifier] {
      return cls.init(style: .default, reuseIdentifier: identifier)
    }
    return nil
  }

  public func dequeueReusableCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
    if let cls = registeredCellTypes[identifier] {
      return cls.init(style: .default, reuseIdentifier: identifier)
    }
    return UITableViewCell(style: .default, reuseIdentifier: identifier)
  }

  public func dequeueReusableHeaderFooterView(withIdentifier identifier: String) -> UITableViewHeaderFooterView? {
    if let cls = registeredHeaderTypes[identifier] {
      return cls.init(reuseIdentifier: identifier)
    }
    return UITableViewHeaderFooterView(reuseIdentifier: identifier)
  }

  public func cellForRow(at indexPath: IndexPath) -> UITableViewCell? {
    mountedCells[indexPath]
  }

  public func indexPath(for cell: UITableViewCell) -> IndexPath? {
    mountedCells.first(where: { $0.value === cell })?.key
  }

  open func reloadData() {
    for (_, cell) in mountedCells {
      cell.removeFromSuperview()
    }
    mountedCells.removeAll()
    guard let ds = dataSource else { return }
    let sections = max(0, ds.numberOfSections(in: self))
    var y: CGFloat = tableHeaderView?.frame.height ?? 0
    let w = max(bounds.width, 320)
    for sec in 0..<sections {
      let rows = max(0, ds.tableView(self, numberOfRowsInSection: sec))
      for row in 0..<rows {
        let ip = IndexPath(row: row, section: sec)
        let cell = ds.tableView(self, cellForRowAt: ip)
        let customH = tableDelegate?.tableView(self, heightForRowAt: ip) ?? Self.automaticDimension
        let h = customH > 0 ? customH : (rowHeight > 0 ? rowHeight : 44)
        cell.frame = CGRect(x: 0, y: y, width: w, height: h)
        cell.isSelected = selectedPaths.contains(ip)
        mountedCells[ip] = cell
        addSubview(cell)
        y += h
      }
    }
    contentSize = CGSize(width: w, height: y)
  }

  public func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
    updates?()
    reloadData()
    completion?(true)
  }

  public func insertRows(at indexPaths: [IndexPath], with animation: RowAnimation) { reloadData() }
  public func deleteRows(at indexPaths: [IndexPath], with animation: RowAnimation) { reloadData() }
  public func reloadRows(at indexPaths: [IndexPath], with animation: RowAnimation) { reloadData() }
  public func insertSections(_ sections: IndexSet, with animation: RowAnimation) { reloadData() }
  public func deleteSections(_ sections: IndexSet, with animation: RowAnimation) { reloadData() }
  public func reloadSections(_ sections: IndexSet, with animation: RowAnimation) { reloadData() }

  public func selectRow(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
    if !allowsMultipleSelection {
      for old in selectedPaths { mountedCells[old]?.setSelected(false, animated: animated) }
      selectedPaths.removeAll()
    }
    if let ip = indexPath {
      if !selectedPaths.contains(ip) { selectedPaths.append(ip) }
      mountedCells[ip]?.setSelected(true, animated: animated)
    }
  }

  public func deselectRow(at indexPath: IndexPath, animated: Bool) {
    selectedPaths.removeAll { $0 == indexPath }
    mountedCells[indexPath]?.setSelected(false, animated: animated)
  }

  public func scrollToRow(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
    if let cell = mountedCells[indexPath] {
      scrollRectToVisible(cell.frame, animated: animated)
    }
  }
}

// MARK: - Diffable Data Source Snapshot & Table Diffable Data Source

public struct NSDiffableDataSourceSnapshot<
  SectionIdentifierType: Hashable & Sendable,
  ItemIdentifierType: Hashable & Sendable
>: Sendable {
  public private(set) var sectionIdentifiers: [SectionIdentifierType] = []
  private var itemsBySection: [SectionIdentifierType: [ItemIdentifierType]] = [:]

  public init() {}

  public var numberOfSections: Int { sectionIdentifiers.count }
  public var numberOfItems: Int { itemIdentifiers.count }

  public var itemIdentifiers: [ItemIdentifierType] {
    sectionIdentifiers.flatMap { itemsBySection[$0] ?? [] }
  }

  public func numberOfItems(inSection identifier: SectionIdentifierType) -> Int {
    itemsBySection[identifier]?.count ?? 0
  }

  public func itemIdentifiers(inSection identifier: SectionIdentifierType) -> [ItemIdentifierType] {
    itemsBySection[identifier] ?? []
  }

  public func sectionIdentifier(containingItem identifier: ItemIdentifierType) -> SectionIdentifierType? {
    sectionIdentifiers.first { itemsBySection[$0]?.contains(identifier) == true }
  }

  public mutating func appendSections(_ identifiers: [SectionIdentifierType]) {
    for sec in identifiers where !sectionIdentifiers.contains(sec) {
      sectionIdentifiers.append(sec)
      itemsBySection[sec] = []
    }
  }

  public mutating func appendItems(_ identifiers: [ItemIdentifierType], toSection sectionIdentifier: SectionIdentifierType? = nil) {
    guard let targetSec = sectionIdentifier ?? sectionIdentifiers.last else { return }
    var existing = itemsBySection[targetSec] ?? []
    for item in identifiers where !existing.contains(item) {
      existing.append(item)
    }
    itemsBySection[targetSec] = existing
  }

  public mutating func deleteItems(_ identifiers: [ItemIdentifierType]) {
    let toRemove = Set(identifiers)
    for sec in sectionIdentifiers {
      itemsBySection[sec]?.removeAll { toRemove.contains($0) }
    }
  }

  public mutating func deleteAllItems() {
    sectionIdentifiers.removeAll()
    itemsBySection.removeAll()
  }

  public mutating func reloadItems(_ identifiers: [ItemIdentifierType]) {}
  public mutating func reconfigureItems(_ identifiers: [ItemIdentifierType]) {}
}

@MainActor
open class UITableViewDiffableDataSource<
  SectionIdentifierType: Hashable & Sendable,
  ItemIdentifierType: Hashable & Sendable
>: NSObject, UITableViewDataSource {
  public typealias CellProvider = @MainActor (UITableView, IndexPath, ItemIdentifierType) -> UITableViewCell?

  private weak var tableView: UITableView?
  private let cellProvider: CellProvider
  private var currentSnapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
  public var defaultRowAnimation: UITableView.RowAnimation = .automatic

  public init(tableView: UITableView, cellProvider: @escaping CellProvider) {
    self.tableView = tableView
    self.cellProvider = cellProvider
    super.init()
    tableView.dataSource = self
  }

  public func apply(
    _ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>,
    animatingDifferences: Bool = true,
    completion: (() -> Void)? = nil
  ) {
    currentSnapshot = snapshot
    tableView?.reloadData()
    completion?()
  }

  public func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
    currentSnapshot
  }

  public func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
    guard currentSnapshot.sectionIdentifiers.indices.contains(indexPath._crossSection) else { return nil }
    let sec = currentSnapshot.sectionIdentifiers[indexPath._crossSection]
    let items = currentSnapshot.itemIdentifiers(inSection: sec)
    return items.indices.contains(indexPath.row) ? items[indexPath.row] : nil
  }

  public func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? {
    for (secIdx, sec) in currentSnapshot.sectionIdentifiers.enumerated() {
      let items = currentSnapshot.itemIdentifiers(inSection: sec)
      if let rowIdx = items.firstIndex(of: itemIdentifier) {
        return IndexPath(row: rowIdx, section: secIdx)
      }
    }
    return nil
  }

  public func numberOfSections(in tableView: UITableView) -> Int {
    currentSnapshot.numberOfSections
  }

  public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard currentSnapshot.sectionIdentifiers.indices.contains(section) else { return 0 }
    return currentSnapshot.numberOfItems(inSection: currentSnapshot.sectionIdentifiers[section])
  }

  public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    if let item = itemIdentifier(for: indexPath),
       let cell = cellProvider(tableView, indexPath, item)
    {
      return cell
    }
    return UITableViewCell(style: .default, reuseIdentifier: nil)
  }
}

// MARK: - UICollectionView

open class UICollectionViewLayout: NSObject {
  public weak var collectionView: UICollectionView?
  open func invalidateLayout() {}
  open func prepare() {}
  open var collectionViewContentSize: CGSize { .zero }
}

open class UICollectionViewFlowLayout: UICollectionViewLayout {
  public enum ScrollDirection: Int, Sendable {
    case vertical = 0
    case horizontal = 1
  }

  public static let automaticSize = CGSize(width: -1, height: -1)

  public var minimumLineSpacing: CGFloat = 10
  public var minimumInteritemSpacing: CGFloat = 10
  public var itemSize: CGSize = CGSize(width: 50, height: 50)
  public var estimatedItemSize: CGSize = .zero
  public var scrollDirection: ScrollDirection = .vertical
  public var headerReferenceSize: CGSize = .zero
  public var footerReferenceSize: CGSize = .zero
  public var sectionInset: UIEdgeInsets = .zero
}

open class UICollectionViewCompositionalLayoutConfiguration: NSObject {
  public var scrollDirection: UICollectionViewFlowLayout.ScrollDirection = .vertical
  public var interSectionSpacing: CGFloat = 0
}

open class UICollectionViewCompositionalLayout: UICollectionViewLayout {
  public var configuration: UICollectionViewCompositionalLayoutConfiguration = .init()

  public static func list(using configuration: UICollectionLayoutListConfiguration) -> UICollectionViewCompositionalLayout {
    UICollectionViewCompositionalLayout()
  }
}

public struct UICollectionLayoutListConfiguration {
  public enum Appearance: Int, Sendable {
    case plain = 0
    case grouped = 1
    case insetGrouped = 2
    case sidebar = 3
    case sidebarPlain = 4
  }

  public var appearance: Appearance
  public var showsSeparators: Bool = true
  public var backgroundColor: UIColor?

  public init(appearance: Appearance) {
    self.appearance = appearance
  }
}

@MainActor
open class UICollectionReusableView: UIView {
  public internal(set) var reuseIdentifier: String?
  public required override init(frame: CGRect) {
    super.init(frame: frame)
  }
  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
  open func prepareForReuse() {}
}

@MainActor
open class UICollectionViewCell: UICollectionReusableView {
  public let contentView = UIView(frame: .zero)
  public var isSelected: Bool = false
  public var isHighlighted: Bool = false
  public var backgroundView: UIView?
  public var selectedBackgroundView: UIView?
  private var hostedContentView: (any UIView & UIContentView)?

  public var contentConfiguration: (any UIContentConfiguration)? {
    didSet {
      hostedContentView?.removeFromSuperview()
      hostedContentView = nil
      if let cfg = contentConfiguration {
        let made = cfg.makeContentView()
        made.frame = contentView.bounds
        made.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(made)
        hostedContentView = made
      }
    }
  }

  public var backgroundConfiguration: UIBackgroundConfiguration?

  public required init(frame: CGRect) {
    super.init(frame: frame)
    contentView.frame = bounds
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(contentView)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    addSubview(contentView)
  }
}

@MainActor
open class UICollectionViewListCell: UICollectionViewCell {
  public func defaultContentConfiguration() -> UIListContentConfiguration {
    .cell()
  }
}

@MainActor
public protocol UICollectionViewDataSource: NSObjectProtocol {
  func numberOfSections(in collectionView: UICollectionView) -> Int
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
}

extension UICollectionViewDataSource {
  public func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
}

@MainActor
public protocol UICollectionViewDelegate: UIScrollViewDelegate {
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
  func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath)
}

extension UICollectionViewDelegate {
  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {}
  public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {}
}

@MainActor
open class UICollectionView: UIScrollView {
  public struct CellRegistration<Cell: UICollectionViewCell, Item> {
    public typealias Handler = @MainActor (Cell, IndexPath, Item) -> Void
    fileprivate let reuseID = UUID().uuidString
    fileprivate let handler: Handler

    public init(handler: @escaping Handler) {
      self.handler = handler
    }
  }

  public var collectionViewLayout: UICollectionViewLayout
  public weak var dataSource: (any UICollectionViewDataSource)?
  private weak var collectionDelegate: (any UICollectionViewDelegate)?
  public override var delegate: (any UIScrollViewDelegate)? {
    get { collectionDelegate }
    set { collectionDelegate = newValue as? any UICollectionViewDelegate }
  }
  public var backgroundView: UIView?
  public var allowsSelection: Bool = true
  public var allowsMultipleSelection: Bool = false

  private var registeredCellTypes: [String: UICollectionViewCell.Type] = [:]
  private var mountedCells: [IndexPath: UICollectionViewCell] = [:]
  private var selectedPaths: [IndexPath] = []

  public var indexPathsForSelectedItems: [IndexPath]? { selectedPaths }
  public var visibleCells: [UICollectionViewCell] { Array(mountedCells.values) }

  public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
    self.collectionViewLayout = layout
    super.init(frame: frame)
    layout.collectionView = self
  }

  public required init?(coder: NSCoder) {
    self.collectionViewLayout = UICollectionViewFlowLayout()
    super.init(coder: coder)
  }

  public func register(_ cellClass: AnyClass?, forCellWithReuseIdentifier identifier: String) {
    if let typed = cellClass as? UICollectionViewCell.Type {
      registeredCellTypes[identifier] = typed
    }
  }

  public func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
    let cell = registeredCellTypes[identifier]?.init(frame: .zero) ?? UICollectionViewCell(frame: .zero)
    cell.reuseIdentifier = identifier
    return cell
  }

  public func dequeueConfiguredReusableCell<Cell: UICollectionViewCell, Item>(
    using registration: CellRegistration<Cell, Item>,
    for indexPath: IndexPath,
    item: Item?
  ) -> Cell {
    let cell = Cell(frame: .zero)
    cell.reuseIdentifier = registration.reuseID
    if let item {
      registration.handler(cell, indexPath, item)
    }
    return cell
  }

  open func reloadData() {
    for (_, cell) in mountedCells { cell.removeFromSuperview() }
    mountedCells.removeAll()
    guard let ds = dataSource else { return }
    let sections = max(0, ds.numberOfSections(in: self))
    let w = max(bounds.width, 320)
    var y: CGFloat = 0
    for sec in 0..<sections {
      let count = max(0, ds.collectionView(self, numberOfItemsInSection: sec))
      for idx in 0..<count {
        let ip = IndexPath(indexes: [sec, idx])
        let cell = ds.collectionView(self, cellForItemAt: ip)
        let sz = (collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: w, height: 44)
        cell.frame = CGRect(x: 0, y: y, width: sz.width > 0 ? sz.width : w, height: max(32, sz.height))
        mountedCells[ip] = cell
        addSubview(cell)
        y += cell.frame.height
      }
    }
    contentSize = CGSize(width: w, height: y)
  }
}

@MainActor
open class UICollectionViewDiffableDataSource<
  SectionIdentifierType: Hashable & Sendable,
  ItemIdentifierType: Hashable & Sendable
>: NSObject, UICollectionViewDataSource {
  public typealias CellProvider = @MainActor (UICollectionView, IndexPath, ItemIdentifierType) -> UICollectionViewCell?

  private weak var collectionView: UICollectionView?
  private let cellProvider: CellProvider
  private var currentSnapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()

  public init(collectionView: UICollectionView, cellProvider: @escaping CellProvider) {
    self.collectionView = collectionView
    self.cellProvider = cellProvider
    super.init()
    collectionView.dataSource = self
  }

  public func apply(
    _ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>,
    animatingDifferences: Bool = true,
    completion: (() -> Void)? = nil
  ) {
    currentSnapshot = snapshot
    collectionView?.reloadData()
    completion?()
  }

  public func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
    currentSnapshot
  }

  public func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
    guard currentSnapshot.sectionIdentifiers.indices.contains(indexPath._crossSection) else { return nil }
    let sec = currentSnapshot.sectionIdentifiers[indexPath._crossSection]
    let items = currentSnapshot.itemIdentifiers(inSection: sec)
    return items.indices.contains(indexPath._crossItem) ? items[indexPath._crossItem] : nil
  }

  public func numberOfSections(in collectionView: UICollectionView) -> Int {
    currentSnapshot.numberOfSections
  }

  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    guard currentSnapshot.sectionIdentifiers.indices.contains(section) else { return 0 }
    return currentSnapshot.numberOfItems(inSection: currentSnapshot.sectionIdentifiers[section])
  }

  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    if let item = itemIdentifier(for: indexPath),
       let cell = cellProvider(collectionView, indexPath, item)
    {
      return cell
    }
    return UICollectionViewCell(frame: .zero)
  }
}
