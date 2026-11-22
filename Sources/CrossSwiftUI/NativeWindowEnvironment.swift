import CrossAppKit
import Foundation
import NativeAPI
import SwiftUIRuntime

private struct NativeWindowKey: EnvironmentKey {
  static let defaultValue: NativeAPI.Window? = nil
}

extension EnvironmentValues {
  /// The window whose content coordinates are returned by GeometryProxy.global.
  /// Supplied by the backend, including when a Renderer is embedded manually.
  public var nativeWindow: NativeAPI.Window? {
    get { self[NativeWindowKey.self] }
    set { self[NativeWindowKey.self] = newValue }
  }

  static func hosting(_ window: NativeAPI.Window) -> EnvironmentValues {
    var values = EnvironmentValues()
    values.nativeWindow = window
    values.openURL = OpenURLAction { url in
      NSWorkspace.shared.open(url) ? .handled : .discarded
    }
    values._fileDialogService = _FileDialogService(
      presentOpen: { allowedExtensions, allowsMultiple, completion in
        let mode: NativeAPI.FileDialogMode = allowsMultiple ? .openFiles : .openFile
        guard let dialog = NativeAPI.FileDialog.create(mode) else {
          completion(.failure(FileDialogUnavailableError()))
          return
        }
        dialog.setModality(.application)
        if !allowedExtensions.isEmpty {
          _ = dialog.setFileTypes(allowedExtensions)
        }
        if dialog.open(), dialog.result == .accepted {
          completion(.success(dialog.paths.map { URL(fileURLWithPath: $0) }))
        } else {
          completion(.success([]))
        }
      },
      presentSave: { suggestedName, payload, completion in
        guard let dialog = NativeAPI.FileDialog.create(.saveFile) else {
          completion(.failure(FileDialogUnavailableError()))
          return
        }
        dialog.setModality(.application)
        if let suggestedName, !suggestedName.isEmpty {
          _ = dialog.setSuggestedFileName(suggestedName)
        }
        if dialog.open(), dialog.result == .accepted, let path = dialog.paths.first {
          let destURL = URL(fileURLWithPath: path)
          if let payload {
            do {
              try payload.write(to: destURL, options: .atomic)
            } catch {
              completion(.failure(error))
              return
            }
          }
          completion(.success(destURL))
        } else {
          completion(.failure(FileDialogUnavailableError()))
        }
      }
    )
    return values
  }
}
