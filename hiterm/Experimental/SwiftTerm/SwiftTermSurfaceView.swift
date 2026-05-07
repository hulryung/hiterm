import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's LocalProcessTerminalView that runs `/bin/zsh -l`,
/// uses a hard-coded monospaced font, and closes its window when the child
/// process exits. PTY, ANSI parsing, default key/mouse handling, and
/// rendering all come from the base class.
final class SwiftTermSurfaceView: LocalProcessTerminalView, LocalProcessTerminalViewDelegate {

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        processDelegate = self
        let resolved = NSFont(name: "MesloLGS NF", size: 13)
            ?? NSFont(name: "D2CodingLigature Nerd Font Mono", size: 13)
            ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        font = resolved
        Log.swiftterm.info("SwiftTermSurfaceView configured (font=\(resolved.fontName, privacy: .public) 13)")
    }

    /// Called by the experiment window controller once the view is in a window.
    func startZsh() {
        Log.swiftterm.info("Starting /bin/zsh -l")
        startProcess(executable: "/bin/zsh", args: ["-l"], environment: nil)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        Log.swiftterm.debug("Grid resized: \(newCols)x\(newRows)")
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        source.window?.title = "hiterm — SwiftTerm Experiment — \(title)"
    }

    // `hostCurrentDirectoryUpdate` is satisfied by the base class's
    // implementation (same signature as the protocol) — redeclaring it here
    // would require `override`, but the base method is `public`, not `open`.

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Log.swiftterm.info("zsh terminated (exitCode=\(exitCode ?? -1)), closing window")
        DispatchQueue.main.async { source.window?.close() }
    }
}
