import AppKit

/// Owns the single NSWindow used by the SwiftTerm experiment. Content view is
/// a SwiftTermSurfaceView (no scroll wrapper yet — Task 9 wraps it).
final class SwiftTermExperimentWindowController: NSWindowController, NSWindowDelegate {

    private let surface = SwiftTermSurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "hiterm — SwiftTerm Experiment"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = surface
        surface.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(surface)
        surface.startZsh()
        Log.swiftterm.info("Experiment window shown")
    }

    func windowWillClose(_ notification: Notification) {
        Log.swiftterm.info("Experiment window closing — terminating app")
        NSApp.terminate(nil)
    }
}
