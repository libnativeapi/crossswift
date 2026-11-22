import QuartzCore
import SwiftUI
import UIKit

// MARK: - Native UITextField via UIViewRepresentable

struct UIKitSearchFieldRepresentable: UIViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var onSubmit: () -> Void

  final class Coordinator: NSObject, UITextFieldDelegate {
    var parent: UIKitSearchFieldRepresentable

    init(parent: UIKitSearchFieldRepresentable) {
      self.parent = parent
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
      parent.onSubmit()
      return true
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> UITextField {
    let tf = UITextField()
    tf.borderStyle = .roundedRect
    tf.placeholder = placeholder
    tf.font = UIFont.preferredFont(forTextStyle: .body)
    tf.textColor = .label
    tf.delegate = context.coordinator
    tf.addAction(
      UIAction { [weak tf, weak coord = context.coordinator] _ in
        guard let tf, let coord else { return }
        let updated = tf.text ?? ""
        if coord.parent.text != updated {
          coord.parent.text = updated
        }
      },
      for: .editingChanged
    )
    return tf
  }

  func updateUIView(_ uiView: UITextField, context: Context) {
    context.coordinator.parent = self
    if uiView.placeholder != placeholder {
      uiView.placeholder = placeholder
    }
    if uiView.text != text {
      uiView.text = text
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 320, height: 34)
  }
}

// MARK: - Native UIButton via UIViewRepresentable

struct UIKitActionButtonRepresentable: UIViewRepresentable {
  let title: String
  let action: () -> Void

  final class ActionHolder {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
  }

  func makeCoordinator() -> ActionHolder {
    ActionHolder(action: action)
  }

  func makeUIView(context: Context) -> UIButton {
    var config = UIButton.Configuration.borderedProminent()
    config.title = title
    let button = UIButton(
      configuration: config,
      primaryAction: UIAction(title: title) { [weak holder = context.coordinator] _ in
        holder?.action()
      }
    )
    return button
  }

  func updateUIView(_ uiView: UIButton, context: Context) {
    context.coordinator.action = action
    if uiView.currentTitle != title {
      uiView.setTitle(title, for: .normal)
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
    let intrinsic = uiView.intrinsicContentSize
    return CGSize(
      width: proposal.width ?? max(120, intrinsic.width),
      height: max(34, intrinsic.height)
    )
  }
}

// MARK: - Programmatic Auto Layout UIViewController via UIViewControllerRepresentable

final class UIKitInspectorCardController: UIViewController, UITextViewDelegate {
  private let headerLabel = UILabel()
  private let metricsLabel = UILabel()
  private let notesTextView = UITextView()
  private let stampButton = UIButton(type: .system)
  private let rootStack = UIStackView()

  var onNotesChanged: ((String) -> Void)?
  var onStampTapped: (() -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .secondarySystemBackground
    view.layer.cornerRadius = 12

    headerLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    headerLabel.textColor = .label
    headerLabel.text = "UIViewController + UIStackView + NSLayoutConstraint"

    metricsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    metricsLabel.textColor = .secondaryLabel
    metricsLabel.text = "Trait style: automatic · Auto Layout active"

    notesTextView.font = UIFont.systemFont(ofSize: 14)
    notesTextView.textColor = .label
    notesTextView.backgroundColor = .systemBackground
    notesTextView.delegate = self

    stampButton.setTitle("Append Timestamp via UIAction", for: .normal)
    stampButton.addAction(
      UIAction { [weak self] _ in
        self?.onStampTapped?()
      },
      for: .primaryActionTriggered
    )

    rootStack.axis = .vertical
    rootStack.spacing = 8
    rootStack.alignment = .fill
    rootStack.distribution = .fill
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    notesTextView.translatesAutoresizingMaskIntoConstraints = false
    stampButton.translatesAutoresizingMaskIntoConstraints = false

    rootStack.addArrangedSubview(headerLabel)
    rootStack.addArrangedSubview(metricsLabel)
    rootStack.addArrangedSubview(notesTextView)
    rootStack.addArrangedSubview(stampButton)
    view.addSubview(rootStack)

    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
      rootStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      rootStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      rootStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
      notesTextView.heightAnchor.constraint(equalToConstant: 96),
      stampButton.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  func apply(notes: String, filterQuery: String, stampCount: Int) {
    if notesTextView.text != notes {
      notesTextView.text = notes
    }
    let styleName = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
    let filterDesc = filterQuery.isEmpty ? "none" : filterQuery
    metricsLabel.text = "Trait: \(styleName) · Filter: \(filterDesc) · Stamps: \(stampCount)"
  }

  func textViewDidChange(_ textView: UITextView) {
    onNotesChanged?(textView.text ?? "")
  }
}

struct UIKitInspectorControllerRepresentable: UIViewControllerRepresentable {
  @Binding var notes: String
  let filterQuery: String
  let stampCount: Int
  let onStamp: () -> Void

  func makeUIViewController(context: Context) -> UIKitInspectorCardController {
    let vc = UIKitInspectorCardController()
    vc.preferredContentSize = CGSize(width: 520, height: 210)
    vc.onNotesChanged = { updated in
      if notes != updated {
        notes = updated
      }
    }
    vc.onStampTapped = onStamp
    return vc
  }

  func updateUIViewController(_ uiViewController: UIKitInspectorCardController, context: Context) {
    uiViewController.onNotesChanged = { updated in
      if notes != updated {
        notes = updated
      }
    }
    uiViewController.onStampTapped = onStamp
    uiViewController.apply(notes: notes, filterQuery: filterQuery, stampCount: stampCount)
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiViewController: UIKitInspectorCardController,
    context: Context
  ) -> CGSize? {
    CGSize(width: proposal.width ?? 560, height: 214)
  }
}
