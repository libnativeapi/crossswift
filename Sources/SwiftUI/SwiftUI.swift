// The user-facing compatibility module.
//
// Unofficial; not affiliated with Apple.

@_exported import Foundation
@_exported import SwiftUIRuntime
#if os(WASI)
  @_exported import SwiftUIWeb
#elseif os(Android)
  @_exported import SwiftUIAndroid
#elseif CROSS_SWIFTUI_HARMONY
  @_exported import SwiftUIHarmony
#else
  @_exported import CrossSwiftUI
  #if !os(macOS)
    @_exported import CrossAppKit
    @_exported import CrossUIKit
    @_exported import CrossFoundation
    @_exported import CoreGraphics

    extension SwiftUIRuntime.Path {
      public var cgPath: CGPath { CGPath(commands: self.commands) }
    }
  #endif
#endif
