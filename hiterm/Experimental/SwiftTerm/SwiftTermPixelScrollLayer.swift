import AppKit

/// Hosts a SwiftTermSurfaceView and (in Tasks 11–12) drives sub-row pixel
/// scroll by intercepting wheel events. At this stage it is a transparent
/// passthrough wrapper.
final class SwiftTermPixelScrollLayer: NSView {

    let surface: SwiftTermSurfaceView

    override init(frame: NSRect) {
        self.surface = SwiftTermSurfaceView(frame: frame)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(surface)
        surface.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(surface)
        return true
    }
}
