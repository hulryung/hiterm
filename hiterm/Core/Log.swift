import os
import Foundation

/// Centralized logging for hiterm using Apple's unified logging (os.Logger).
///
/// Usage:
///   Log.config.debug("File watcher triggered")
///   Log.surface.info("Size updated: \(width)x\(height)")
///   Log.ghostty.error("Failed to create surface")
///
/// View logs:
///   log stream --predicate 'subsystem=="com.hiterm.app"' --level debug
///   log stream --predicate 'subsystem=="com.hiterm.app" && category=="config"' --level debug
///
/// Verbose mode (environment variable):
///   HITERM_DEBUG=all open hiterm.app
///   HITERM_DEBUG=config,surface open hiterm.app
enum Log {
    private static let subsystem = "com.hiterm.app"

    /// Config loading, file watching, settings sync.
    static let config = Logger(subsystem: subsystem, category: "config")
    /// Terminal surface lifecycle, size/scale updates, rendering.
    static let surface = Logger(subsystem: subsystem, category: "surface")
    /// Keyboard, mouse, gesture input handling.
    static let input = Logger(subsystem: subsystem, category: "input")
    /// Window management, tabs, splits, settings UI.
    static let ui = Logger(subsystem: subsystem, category: "ui")
    /// GhosttyApp lifecycle, actions, callbacks.
    static let ghostty = Logger(subsystem: subsystem, category: "ghostty")
    /// SwiftTerm experiment surface, window, and pixel-scroll layer.
    static let swiftterm = Logger(subsystem: subsystem, category: "swiftterm")

    // MARK: - Verbose Debug Flag

    /// Categories enabled for verbose logging via HITERM_DEBUG environment variable.
    /// Set HITERM_DEBUG=all for everything, or HITERM_DEBUG=config,surface for specific modules.
    private static let verboseCategories: Set<String> = {
        guard let value = ProcessInfo.processInfo.environment["HITERM_DEBUG"] else { return [] }
        if value == "all" { return ["config", "surface", "input", "ui", "ghostty", "swiftterm"] }
        return Set(value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }()

    /// Check if verbose logging is enabled for a category.
    static func isVerbose(_ category: String) -> Bool {
        verboseCategories.contains(category)
    }
}
