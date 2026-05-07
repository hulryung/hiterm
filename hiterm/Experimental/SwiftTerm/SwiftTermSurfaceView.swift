import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's LocalProcessTerminalView that runs zsh and is the
/// rendering surface for the SwiftTerm experiment window. PTY, ANSI parsing,
/// and default key/mouse handling are inherited from the base class.
final class SwiftTermSurfaceView: LocalProcessTerminalView {
}
