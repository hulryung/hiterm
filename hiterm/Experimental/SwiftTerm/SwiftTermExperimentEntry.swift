import AppKit
import Foundation

enum SwiftTermExperimentEntry {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HITERM_BACKEND"] == "swiftterm"
    }

    /// Held at module scope so the controller and its window are not deallocated.
    private static var controller: SwiftTermExperimentWindowController?

    static func openWindow() {
        Log.swiftterm.info("Entering SwiftTerm experiment path")
        NSApp.setActivationPolicy(.regular)
        let wc = SwiftTermExperimentWindowController()
        controller = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
