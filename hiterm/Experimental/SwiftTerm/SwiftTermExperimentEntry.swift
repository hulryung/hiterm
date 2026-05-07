import AppKit
import Foundation

/// Decides whether AppDelegate should enter the SwiftTerm experiment path,
/// and opens the experiment window when it should.
enum SwiftTermExperimentEntry {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HITERM_BACKEND"] == "swiftterm"
    }

    static func openWindow() {
        // Implemented in Task 7.
    }
}
