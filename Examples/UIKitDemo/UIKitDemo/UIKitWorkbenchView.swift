import SwiftUI
import UIKit

enum WorkbenchTab: Int, CaseIterable, Identifiable {
  case hosting = 0
  case traits = 1
  case graphics = 2
  case services = 3

  var id: Int { rawValue }

  var titleKey: String {
    switch self {
    case .hosting: return "uikit.tab.hosting"
    case .traits: return "uikit.tab.traits"
    case .graphics: return "uikit.tab.graphics"
    case .services: return "uikit.tab.services"
    }
  }

  var iconName: String {
    switch self {
    case .hosting: return "rectangle.3.group"
    case .traits: return "paintpalette"
    case .graphics: return "paintbrush.pointed"
    case .services: return "iphone.gen3"
    }
  }
}

struct UIKitWorkbenchView: View {
  @State private var selectedTab: WorkbenchTab = .hosting
  @State private var filterQuery: String = "UIWindowScene"
  @State private var inspectorNotes: String =
    "Hosted via UIHostingController inside UIWindowScene.\nEdit this UITextView or tap the UIButton below to test two-way UIKit <-> SwiftUI state sync."
  @State private var stampCount: Int = 1
  @State private var simulatedDarkTraits: Bool = false
  @State private var dynamicScale: Double = 1.0
  @State private var chartSampleCount: Int = 5
  @State private var clipboardDraft: String = "CrossUIKit clipboard payload"
  @State private var clipboardReadback: String = "(not read yet)"
  @State private var lastFeedbackLog: String = "Ready"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WorkbenchHeaderBar(selectedTab: $selectedTab)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          switch selectedTab {
          case .hosting:
            HostingTabContent(
              filterQuery: $filterQuery,
              inspectorNotes: $inspectorNotes,
              stampCount: $stampCount
            )
          case .traits:
            TraitsAndTypographyTabContent(
              simulatedDarkTraits: $simulatedDarkTraits,
              dynamicScale: $dynamicScale
            )
          case .graphics:
            GraphicsAndSymbolsTabContent(chartSampleCount: $chartSampleCount)
          case .services:
            ServicesAndDeviceTabContent(
              clipboardDraft: $clipboardDraft,
              clipboardReadback: $clipboardReadback,
              lastFeedbackLog: $lastFeedbackLog
            )
          }
        }
        .padding(20)
      }
    }
    .background(Color(uiColor: .systemGroupedBackground))
  }
}

// MARK: - Header & Tab Strip

struct WorkbenchHeaderBar: View {
  @Binding var selectedTab: WorkbenchTab

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(uiImage: UIImage(resource: .studioBadge))
          .resizable()
          .frame(width: 38, height: 38)
        VStack(alignment: .leading, spacing: 2) {
          Text(LocalizedStringKey("uikit.title"))
            .font(Font(UIFont.systemFont(ofSize: 20, weight: .bold)))
            .foregroundStyle(Color(uiColor: .label))
          Text(LocalizedStringKey("uikit.subtitle"))
            .font(Font(UIFont.preferredFont(forTextStyle: .subheadline)))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        Spacer()
        Text("iOS SDK -> Desktop Native")
          .font(Font(UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color(uiColor: UIColor(resource: .brandTint)).opacity(0.14))
          .foregroundStyle(Color(uiColor: UIColor(resource: .brandTint)))
          .clipShape(Capsule())
      }

      HStack(spacing: 8) {
        TabPillButton(tab: .hosting, selectedTab: $selectedTab)
        TabPillButton(tab: .traits, selectedTab: $selectedTab)
        TabPillButton(tab: .graphics, selectedTab: $selectedTab)
        TabPillButton(tab: .services, selectedTab: $selectedTab)
        Spacer()
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
  }
}

struct TabPillButton: View {
  let tab: WorkbenchTab
  @Binding var selectedTab: WorkbenchTab

  var body: some View {
    let isSelected = (selectedTab == tab)
    let brandColor = Color(uiColor: UIColor(resource: .brandTint))
    Button {
      selectedTab = tab
    } label: {
      HStack(spacing: 6) {
        Image(systemName: tab.iconName)
        Text(LocalizedStringKey(tab.titleKey))
          .font(Font(UIFont.systemFont(ofSize: 13, weight: .semibold)))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(isSelected ? brandColor : Color(uiColor: .tertiarySystemFill))
      .foregroundStyle(isSelected ? Color.white : Color(uiColor: .label))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Tab 1: Representables & Auto Layout

struct HostingTabContent: View {
  @Binding var filterQuery: String
  @Binding var inspectorNotes: String
  @Binding var stampCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SectionCard(
        title: "UIViewRepresentable (UITextField + UIButton + UIAction)",
        subtitle: "Live native controls hosted inside SwiftUI with Coordinator delegate & UIAction callbacks."
      ) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            UIKitSearchFieldRepresentable(
              text: $filterQuery,
              placeholder: "Filter UIKit symbols...",
              onSubmit: {
                stampCount += 1
              }
            )
            .frame(height: 34)

            UIKitActionButtonRepresentable(title: "Reset Filter") {
              filterQuery = ""
            }
            .frame(width: 132, height: 34)
          }

          Text("Bound SwiftUI @State query: \"\(filterQuery)\" · Note character count: \(inspectorNotes.count)")
            .font(Font(UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
      }

      SectionCard(
        title: "UIViewControllerRepresentable + Auto Layout Solver",
        subtitle: "Programmatic UIViewController with UIStackView, UILabel, UITextView, and NSLayoutConstraint anchors."
      ) {
        UIKitInspectorControllerRepresentable(
          notes: $inspectorNotes,
          filterQuery: filterQuery,
          stampCount: stampCount,
          onStamp: {
            stampCount += 1
            inspectorNotes += "\n[Stamp #\(stampCount)] UIAction dispatched from hosted UIViewController."
          }
        )
        .frame(height: 214)
      }
    }
  }
}

// MARK: - Tab 2: Traits, Dynamic UIColor & UIFont

struct TraitsAndTypographyTabContent: View {
  @Binding var simulatedDarkTraits: Bool
  @Binding var dynamicScale: Double

  private var previewTraits: UITraitCollection {
    let base = UITraitCollection.current
    return base.modifyingTraits { mutable in
      mutable.userInterfaceStyle = simulatedDarkTraits ? .dark : .light
      mutable.preferredContentSizeCategory = dynamicScale > 1.15 ? .accessibilityMedium : .large
    }
  }

  private var dynamicCardColor: UIColor {
    UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1.0)
        : UIColor(red: 0.93, green: 0.95, blue: 0.99, alpha: 1.0)
    }
  }

  var body: some View {
    let resolvedBrand = UIColor(resource: .brandTint).resolvedColor(with: previewTraits)
    let resolvedCard = dynamicCardColor.resolvedColor(with: previewTraits)
    let baseHeadline = UIFont.preferredFont(forTextStyle: .headline)
    let scaledBody = UIFont(name: baseHeadline.fontName, size: CGFloat(15.0 * dynamicScale))
      ?? UIFont.systemFont(ofSize: CGFloat(15.0 * dynamicScale))

    VStack(alignment: .leading, spacing: 16) {
      SectionCard(
        title: "UITraitCollection & Dynamic UIColor Resolution",
        subtitle: "Resolves .xcassets ColorResource and closure-based UIColor(dynamicProvider:) against custom traits."
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 14) {
            Button(simulatedDarkTraits ? "Simulated Trait: Dark" : "Simulated Trait: Light") {
              simulatedDarkTraits.toggle()
            }
            Button("Scale 1.0x") { dynamicScale = 1.0 }
            Button("Scale 1.25x") { dynamicScale = 1.25 }
            Spacer()
          }

          HStack(spacing: 12) {
            SwatchTile(title: "BrandTint (.xcassets)", uiColor: resolvedBrand)
            SwatchTile(title: "Dynamic Provider", uiColor: resolvedCard)
            SwatchTile(title: "systemIndigo", uiColor: UIColor.systemIndigo.resolvedColor(with: previewTraits))
            SwatchTile(title: "systemMint", uiColor: UIColor.systemMint.resolvedColor(with: previewTraits))
          }
        }
      }

      SectionCard(
        title: "UIFont.TextStyle & UIFontMetrics",
        subtitle: "Bridges UIFont.preferredFont(forTextStyle:) and monospaced digit metrics directly to SwiftUI Font(uiFont)."
      ) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Large Title — UIFont.preferredFont(forTextStyle: .title2)")
            .font(Font(UIFont.preferredFont(forTextStyle: .title2)))
          Text("Scaled Body (\(String(format: "%.2fx", dynamicScale))) — lineHeight \(String(format: "%.1f", scaledBody.lineHeight)) pt")
            .font(Font(scaledBody))
          Text("0123456789 · UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)")
            .font(Font(UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
      }
    }
  }
}

struct SwatchTile: View {
  let title: String
  let uiColor: UIColor

  var body: some View {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    let _ = uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    let hex = String(
      format: "#%02X%02X%02X",
      Int((r * 255).rounded()),
      Int((g * 255).rounded()),
      Int((b * 255).rounded())
    )

    VStack(alignment: .leading, spacing: 6) {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(uiColor: uiColor))
        .frame(height: 44)
      Text(title)
        .font(Font(UIFont.systemFont(ofSize: 12, weight: .semibold)))
      Text(hex)
        .font(Font(UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)))
        .foregroundStyle(Color(uiColor: .secondaryLabel))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Tab 3: UIGraphicsImageRenderer, UIBezierPath & SF Symbols

struct GraphicsAndSymbolsTabContent: View {
  @Binding var chartSampleCount: Int

  private func renderChartImage(bars: Int) -> UIImage {
    let size = CGSize(width: 460, height: 150)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
      UIColor(red: 0.11, green: 0.14, blue: 0.21, alpha: 1.0).setFill()
      let bgPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
      bgPath.fill()

      let count = max(3, min(8, bars))
      let padX: CGFloat = 24
      let gap: CGFloat = 14
      let barW = (size.width - padX * 2 - CGFloat(count - 1) * gap) / CGFloat(count)
      let palette: [UIColor] = [.systemBlue, .systemCyan, .systemMint, .systemIndigo, .systemTeal, .systemOrange]

      for idx in 0..<count {
        let ratio = CGFloat(0.32 + Double((idx * 37 + count * 19) % 60) / 100.0)
        let barH = (size.height - 52) * ratio
        let rect = CGRect(
          x: padX + CGFloat(idx) * (barW + gap),
          y: size.height - 22 - barH,
          width: barW,
          height: barH
        )
        palette[idx % palette.count].setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
      }

      let caption = "UIGraphicsImageRenderer · \(count) vector bars" as NSString
      caption.draw(
        in: CGRect(x: 20, y: 10, width: 360, height: 22),
        withAttributes: [
          .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
          .foregroundColor: UIColor.white,
        ]
      )
      _ = ctx
    }
  }

  var body: some View {
    let chartImage = renderChartImage(bars: chartSampleCount)
    let symbolCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

    VStack(alignment: .leading, spacing: 16) {
      SectionCard(
        title: "UIGraphicsImageRenderer + UIBezierPath Offscreen Canvas",
        subtitle: "Draws rounded bezier paths and attributed text into an offscreen 2x PNG backed by Image(uiImage:)."
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 10) {
            Button("4 Bars") { chartSampleCount = 4 }
            Button("6 Bars") { chartSampleCount = 6 }
            Button("8 Bars") { chartSampleCount = 8 }
            Spacer()
            Text("Image size: \(Int(chartImage.size.width))x\(Int(chartImage.size.height)) pt @ \(Int(chartImage.scale))x")
              .font(Font(UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)))
              .foregroundStyle(Color(uiColor: .secondaryLabel))
          }

          Image(uiImage: chartImage)
            .resizable()
            .frame(width: 460, height: 150)
        }
      }

      SectionCard(
        title: "UIImage(systemName:withConfiguration:) & Asset Catalog Symbols",
        subtitle: "Resolves SF Symbols through CrossSwiftUI's vector catalog alongside .xcassets StudioBadge."
      ) {
        HStack(spacing: 22) {
          if let sparkle = UIImage(systemName: "sparkles", withConfiguration: symbolCfg) {
            Image(uiImage: sparkle)
              .foregroundStyle(Color(uiColor: .systemIndigo))
          }
          if let cpu = UIImage(systemName: "cpu", withConfiguration: symbolCfg) {
            Image(uiImage: cpu)
              .foregroundStyle(Color(uiColor: .systemBlue))
          }
          if let check = UIImage(systemName: "checkmark.seal.fill", withConfiguration: symbolCfg) {
            Image(uiImage: check)
              .foregroundStyle(Color(uiColor: .systemGreen))
          }
          Image(uiImage: UIImage(resource: .studioBadge))
            .resizable()
            .frame(width: 28, height: 28)
          Spacer()
        }
      }
    }
  }
}

// MARK: - Tab 4: Pasteboard, Screen, Device, Haptics & Alert

struct ServicesAndDeviceTabContent: View {
  @Binding var clipboardDraft: String
  @Binding var clipboardReadback: String
  @Binding var lastFeedbackLog: String

  var body: some View {
    let screenBounds = UIScreen.main.bounds
    let screenScale = UIScreen.main.scale
    let device = UIDevice.current

    VStack(alignment: .leading, spacing: 16) {
      SectionCard(
        title: "UIPasteboard.general Round-Trip",
        subtitle: "Reads and writes the host system clipboard via UIPasteboard."
      ) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            TextField("Clipboard text", text: $clipboardDraft)
            Button("Copy to UIPasteboard") {
              UIPasteboard.general.string = clipboardDraft
              clipboardReadback = UIPasteboard.general.string ?? "(empty)"
            }
            Button("Read UIPasteboard") {
              clipboardReadback = UIPasteboard.general.string ?? "(empty)"
            }
          }
          Text("UIPasteboard.general.string -> \(clipboardReadback) (changeCount: \(UIPasteboard.general.changeCount))")
            .font(Font(UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
      }

      SectionCard(
        title: "UIScreen.main, UIDevice.current, Haptics & UIAlertController",
        subtitle: "Queries desktop display metrics through NativeAPI and presents native modal alerts."
      ) {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "UIScreen.main: \(Int(screenBounds.width))x\(Int(screenBounds.height)) pt @ \(String(format: "%.2fx", screenScale)) · UIDevice: \(device.systemName) \(device.systemVersion) (\(device.model))"
          )
          .font(Font(UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)))

          HStack(spacing: 12) {
            Button("Trigger UIImpactFeedbackGenerator") {
              let generator = UIImpactFeedbackGenerator(style: .medium)
              generator.prepare()
              generator.impactOccurred()
              lastFeedbackLog = "UIImpactFeedbackGenerator(.medium) fired"
            }

            Button("Present UIAlertController") {
              let alert = UIAlertController(
                title: "UIKit Compatibility Layer",
                message: "Presented natively via UIAlertController -> NativeAPI.MessageDialog.",
                preferredStyle: .alert
              )
              alert.addAction(
                UIAlertAction(title: "OK", style: .default) { _ in
                  lastFeedbackLog = "UIAlertController dismissed with OK"
                }
              )
              UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true)
            }
            Spacer()
          }

          Text("Status: \(lastFeedbackLog)")
            .font(Font(UIFont.systemFont(ofSize: 12)))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
      }
    }
  }
}

// MARK: - Reusable Section Card

struct SectionCard<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(Font(UIFont.systemFont(ofSize: 15, weight: .semibold)))
          .foregroundStyle(Color(uiColor: .label))
        Text(subtitle)
          .font(Font(UIFont.systemFont(ofSize: 12)))
          .foregroundStyle(Color(uiColor: .secondaryLabel))
      }
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
