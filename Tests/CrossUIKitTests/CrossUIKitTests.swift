@testable import CrossAppKit
@testable import CrossUIKit
import Foundation
import XCTest

final class CrossUIKitTests: XCTestCase {
  func testGeometryAndIndexPathExtensions() {
    let insets = UIEdgeInsets(top: 4, left: 8, bottom: 12, right: 16)
    let rect = CGRect(x: 0, y: 0, width: 100, height: 80).inset(by: insets)
    XCTAssertEqual(rect, CGRect(x: 8, y: 4, width: 76, height: 64))

    let dir = CrossUIKit.NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 14, trailing: 18)
    XCTAssertEqual(dir.leading, 10)
    XCTAssertEqual(dir.trailing, 18)

    let rowPath = IndexPath(row: 5, section: 2)
    XCTAssertEqual(rowPath.section, 2)
    XCTAssertEqual(rowPath.row, 5)

    let itemPath = IndexPath(item: 9, section: 1)
    XCTAssertEqual(itemPath.section, 1)
    XCTAssertEqual(itemPath.item, 9)
  }

  func testTraitCollectionScopingAndDynamicUIColor() throws {
    let dynamicColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.95)
        : UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.85)
    }

    let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    let darkTraits = lightTraits.modifyingTraits { mutable in
      mutable.userInterfaceStyle = .dark
      mutable.preferredContentSizeCategory = .accessibilityLarge
    }
    XCTAssertEqual(darkTraits.userInterfaceStyle, .dark)
    XCTAssertEqual(darkTraits.preferredContentSizeCategory, .accessibilityLarge)

    var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
    XCTAssertTrue(dynamicColor.resolvedColor(with: lightTraits).getRed(&lr, green: &lg, blue: &lb, alpha: &la))
    XCTAssertEqual(lr, 0.1, accuracy: 0.001)
    XCTAssertEqual(lg, 0.2, accuracy: 0.001)
    XCTAssertEqual(lb, 0.3, accuracy: 0.001)
    XCTAssertEqual(la, 0.85, accuracy: 0.001)

    var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
    darkTraits.performAsCurrent {
      XCTAssertEqual(UITraitCollection.current.userInterfaceStyle, .dark)
      _ = dynamicColor.getRed(&dr, green: &dg, blue: &db, alpha: &da)
    }
    XCTAssertEqual(dr, 0.9, accuracy: 0.001)
    XCTAssertEqual(dg, 0.8, accuracy: 0.001)
    XCTAssertEqual(db, 0.7, accuracy: 0.001)
    XCTAssertEqual(da, 0.95, accuracy: 0.001)

    // Verify .colorset lookup from a temporary bundle
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("crossuikit-colorset-\(UUID().uuidString)")
    let colorset = tmp.appendingPathComponent("Assets.xcassets/AccentPulse.colorset")
    try FileManager.default.createDirectory(at: colorset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let contentsJSON = """
    {
      "colors" : [
        {
          "color" : {
            "color-space" : "srgb",
            "components" : { "alpha" : "1.0", "red" : "0.20", "green" : "0.40", "blue" : "0.80" }
          },
          "idiom" : "universal"
        },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
          "color" : {
            "color-space" : "srgb",
            "components" : { "alpha" : "1.0", "red" : "0.50", "green" : "0.70", "blue" : "0.95" }
          },
          "idiom" : "universal"
        }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try contentsJSON.write(
      to: colorset.appendingPathComponent("Contents.json"),
      atomically: true,
      encoding: .utf8
    )

    let bundle = try XCTUnwrap(Bundle(url: tmp))
    let loaded = try XCTUnwrap(UIColor(named: "AccentPulse", in: bundle, compatibleWith: nil))
    var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
    _ = loaded.resolvedColor(with: darkTraits).getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
    XCTAssertEqual(cr, 0.50, accuracy: 0.01)
    XCTAssertEqual(cg, 0.70, accuracy: 0.01)
    XCTAssertEqual(cb, 0.95, accuracy: 0.01)
  }

  func testUIFontTextStyleAndUIFontMetrics() {
    let headline = UIFont.preferredFont(forTextStyle: .headline)
    XCTAssertEqual(headline.pointSize, 17, accuracy: 0.01)
    XCTAssertEqual(headline.fontDescriptor.weight, .semibold)

    let xlTraits = UITraitCollection(preferredContentSizeCategory: .accessibilityMedium)
    let baseBody = UIFont.systemFont(ofSize: 16, weight: .regular)
    let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseBody, compatibleWith: xlTraits)
    XCTAssertGreaterThan(scaled.pointSize, baseBody.pointSize)
  }

  func testUIImageXCAassetsAndUIGraphicsImageRenderer() throws {
    let prevLookup = UIImage.symbolLookupHandler
    let prevRenderer = UIImage.offscreenRenderer
    defer {
      UIImage.symbolLookupHandler = prevLookup
      UIImage.offscreenRenderer = prevRenderer
    }

    nonisolated(unsafe) var recordedOps: [_OffscreenDrawOp] = []
    UIImage.symbolLookupHandler = { $0 == "sparkles" }
    UIImage.offscreenRenderer = { _, _, ops in
      recordedOps = ops
      return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    let symCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    let sym = try XCTUnwrap(UIImage(systemName: "sparkles", withConfiguration: symCfg))
    XCTAssertTrue(sym.isSymbolImage)
    XCTAssertNil(UIImage(systemName: "nonexistent.custom.glyph"))

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48))
    let rendered = renderer.image { _ in
      UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).setFill()
      UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 60, height: 44), cornerRadius: 8).fill()
      sym.draw(in: CGRect(x: 16, y: 12, width: 24, height: 24))
    }

    XCTAssertEqual(rendered.size, CGSize(width: 64, height: 48))
    XCTAssertNotNil(rendered.pngData())
    XCTAssertEqual(recordedOps.count, 2)
  }

  @MainActor
  func testUIViewHierarchyHitTestingCoordinateConversionAndAutoresizing() async {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let child = UIView(frame: CGRect(x: 20, y: 30, width: 260, height: 140))
    child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let badge = UIView(frame: CGRect(x: 210, y: 100, width: 40, height: 30))
    badge.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]

    root.addSubview(child)
    child.addSubview(badge)

    XCTAssertTrue(badge.isDescendant(of: root))
    let ptInRoot = badge.convert(CGPoint(x: 5, y: 5), to: root)
    XCTAssertEqual(ptInRoot, CGPoint(x: 235, y: 135))
    XCTAssertTrue(root.hitTest(CGPoint(x: 235, y: 135), with: nil) === badge)

    root.frame = CGRect(x: 0, y: 0, width: 400, height: 260)
    XCTAssertEqual(child.frame, CGRect(x: 20, y: 30, width: 360, height: 200))
    XCTAssertEqual(badge.frame.origin.x, 310, accuracy: 0.5)
    XCTAssertEqual(badge.frame.origin.y, 160, accuracy: 0.5)
  }

  @MainActor
  func testAutoLayoutAnchorSolverAndUIStackView() async {
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
    let header = UIView()
    header.translatesAutoresizingMaskIntoConstraints = false
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    let leftTile = UIView()
    let rightTile = UIView()
    stack.addArrangedSubview(leftTile)
    stack.addArrangedSubview(rightTile)

    container.addSubview(header)
    container.addSubview(stack)

    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      header.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      header.heightAnchor.constraint(equalToConstant: 40),

      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
    ])

    container.layoutIfNeeded()

    XCTAssertEqual(header.frame.origin.x, 20, accuracy: 1.0)
    XCTAssertEqual(header.frame.origin.y, 16, accuracy: 1.0)
    XCTAssertEqual(header.frame.size.width, 360, accuracy: 1.0)
    XCTAssertEqual(header.frame.size.height, 40, accuracy: 1.0)

    XCTAssertEqual(stack.frame.origin.x, 20, accuracy: 1.0)
    XCTAssertEqual(stack.frame.origin.y, 68, accuracy: 1.0)
    XCTAssertEqual(stack.frame.size.width, 360, accuracy: 1.0)
    XCTAssertEqual(stack.frame.size.height, 152, accuracy: 1.0)

    XCTAssertEqual(leftTile.frame.size.width, 175, accuracy: 1.0)
    XCTAssertEqual(rightTile.frame.origin.x, 185, accuracy: 1.0)
    XCTAssertEqual(rightTile.frame.size.width, 175, accuracy: 1.0)
  }

  @MainActor
  func testUIControlUIActionAndGestureRecognizer() async {
    var actionCount = 0
    let button = UIButton(
      type: .system,
      primaryAction: UIAction(title: "Run") { _ in
        actionCount += 1
      }
    )
    button.sendActions(for: .primaryActionTriggered)
    XCTAssertEqual(actionCount, 1)

    var tapLocation: CGPoint = .zero
    let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let tap = UITapGestureRecognizer { recognizer in
      tapLocation = recognizer.location(in: hostView)
    }
    hostView.addGestureRecognizer(tap)
    tap._fireRecognized(at: CGPoint(x: 42, y: 58))
    XCTAssertEqual(tapLocation, CGPoint(x: 42, y: 58))
  }

  @MainActor
  func testNavigationControllerTabBarControllerAndDiffableDataSource() async {
    let firstVC = UIViewController()
    firstVC.title = "Home"
    let secondVC = UIViewController()
    secondVC.title = "Detail"

    let nav = UINavigationController(rootViewController: firstVC)
    XCTAssertEqual(nav.viewControllers.count, 1)
    nav.pushViewController(secondVC, animated: false)
    XCTAssertEqual(nav.viewControllers.count, 2)
    XCTAssertTrue(nav.topViewController === secondVC)
    let popped = nav.popViewController(animated: false)
    XCTAssertTrue(popped === secondVC)
    XCTAssertEqual(nav.viewControllers.count, 1)

    let tab = UITabBarController()
    tab.setViewControllers([nav, secondVC], animated: false)
    tab.selectedIndex = 1
    XCTAssertTrue(tab.selectedViewController === secondVC)

    let tableView = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), style: .insetGrouped)
    let dataSource = UITableViewDiffableDataSource<String, String>(tableView: tableView) { tv, indexPath, item in
      let cell = tv.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
      var cfg = cell.defaultContentConfiguration()
      cfg.text = item
      cell.contentConfiguration = cfg
      return cell
    }
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

    var snapshot = CrossUIKit.NSDiffableDataSourceSnapshot<String, String>()
    snapshot.appendSections(["Main", "Secondary"])
    snapshot.appendItems(["Alpha", "Beta"], toSection: "Main")
    snapshot.appendItems(["Gamma"], toSection: "Secondary")
    dataSource.apply(snapshot, animatingDifferences: false)

    XCTAssertEqual(tableView.numberOfSections, 2)
    XCTAssertEqual(tableView.numberOfRows(inSection: 0), 2)
    XCTAssertEqual(dataSource.itemIdentifier(for: IndexPath(row: 1, section: 0)), "Beta")
    XCTAssertEqual(dataSource.indexPath(for: "Gamma"), IndexPath(row: 0, section: 1))
  }
}
