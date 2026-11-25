// The user-facing compatibility module.
//
// Unofficial; not affiliated with Apple.

@_exported import Foundation
@_exported import SwiftUIRuntime
#if os(WASI)
  @_exported import SwiftUIWeb

  public typealias URLSession = SwiftUIWeb.WebURLSession
  public typealias URLResponse = SwiftUIWeb.WebURLResponse
#elseif os(Android)
  @_exported import SwiftUIAndroid
#elseif CROSS_SWIFTUI_HARMONY
  @_exported import SwiftUIHarmony
  #if CROSS_SWIFTUI_HARMONY_DESKTOP
    @_exported import CrossSwiftUI
    @_exported import CrossAppKit
    @_exported import CrossUIKit
    @_exported import CrossFoundation
    @_exported import CoreGraphics
    @_exported import Combine

    extension SwiftUIRuntime.Path {
      public var cgPath: CGPath { CGPath(commands: self.commands) }
    }
  #endif
#else
  @_exported import CrossSwiftUI
  #if !os(macOS)
    @_exported import CrossAppKit
    @_exported import CrossUIKit
    @_exported import CrossFoundation
    @_exported import CoreGraphics
    import UniformTypeIdentifiers

    extension SwiftUIRuntime.Path {
      public var cgPath: CGPath { CGPath(commands: self.commands) }
    }

    extension SwiftUIRuntime.View {
      public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], any Error>) -> Void
      ) -> some View {
        fileImporter(
          isPresented: isPresented,
          allowedContentTypes: allowedContentTypes.compactMap(\.preferredFilenameExtension),
          allowsMultipleSelection: allowsMultipleSelection,
          onCompletion: onCompletion
        )
      }

      public func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, any Error>) -> Void
      ) -> some View {
        fileImporter(
          isPresented: isPresented,
          allowedContentTypes: allowedContentTypes.compactMap(\.preferredFilenameExtension),
          onCompletion: onCompletion
        )
      }
    }
  #endif
#endif
