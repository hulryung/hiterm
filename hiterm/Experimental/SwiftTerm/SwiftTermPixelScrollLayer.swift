import AppKit
import SwiftTerm

/// Hosts a SwiftTermSurfaceView and drives sub-row pixel-resolution scroll.
///
/// Scroll model:
///   - `accumulatedPixelOffset` is in "pixels above the natural origin" — a
///     positive value means content has been pushed up by that many pixels.
///   - Each frame the surface's layer bounds origin is set so the visible
///     content is offset accordingly.
///   - When `|accumulatedPixelOffset| >= rowHeight`, advance SwiftTerm's
///     scrollback by one line and subtract `rowHeight` from the accumulator.
///
/// SwiftTerm 1.13.0: `MacTerminalView.scrollWheel(with:)` is `public` (not
/// `open`) so we cannot subclass-override it across the module boundary, and
/// the base implementation consumes events without calling super. Instead we
/// install an `NSEvent.addLocalMonitorForEvents` while the view is in a
/// window — when a scroll event hits any view inside `surface`, we route it
/// through `scrollWheel(with:)` here and swallow the event before AppKit
/// dispatches it to SwiftTerm's own handler.
final class SwiftTermPixelScrollLayer: NSView {

    let surface: SwiftTermSurfaceView

    private var accumulatedPixelOffset: CGFloat = 0
    private var scrollMonitor: Any?

    override init(frame: NSRect) {
        self.surface = SwiftTermSurfaceView(frame: frame)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(surface)
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(surface)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        guard let window = window else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  event.window === window,
                  let contentView = window.contentView,
                  let hit = contentView.hitTest(event.locationInWindow),
                  hit === self.surface || hit.isDescendant(of: self.surface)
            else { return event }
            self.scrollWheel(with: event)
            return nil
        }
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }

        // Treat positive scrollingDeltaY as "user pushed content up" (show older lines).
        accumulatedPixelOffset += delta

        commitFullRows()
        applyLayerTranslation()

        Log.swiftterm.debug("scrollWheel delta=\(delta) accum=\(self.accumulatedPixelOffset)")
    }

    /// SwiftTerm 1.13.0: `cellDimension` is internal, so we cannot read row
    /// height directly. We approximate it from the configured font's
    /// bounding rect — close to what SwiftTerm uses internally for
    /// `cellDimension.height`. This may be off by a fraction of a point;
    /// Task 12 should verify by scrolling N row-heights and checking the
    /// content lands cleanly on a row boundary.
    private var rowHeight: CGFloat {
        let h = surface.font.boundingRectForFont.size.height
        return h > 0 ? h : 18
    }

    private func commitFullRows() {
        let h = rowHeight
        while accumulatedPixelOffset >= h {
            scrollTerminal(linesUp: 1)
            accumulatedPixelOffset -= h
        }
        while accumulatedPixelOffset <= -h {
            scrollTerminal(linesUp: -1)
            accumulatedPixelOffset += h
        }
    }

    /// SwiftTerm 1.13.0: instead of calling `terminal.getTopVisibleRow()` +
    /// `terminal.scrollTo(row:)` + `surface.queuePendingDisplay()` (the last
    /// is internal to SwiftTerm), use the public `scrollUp(lines:)` /
    /// `scrollDown(lines:)` on the terminal view, which clamp to bounds,
    /// call `scrollTo(row:)` internally, and trigger a redraw.
    private func scrollTerminal(linesUp: Int) {
        if linesUp > 0 {
            surface.scrollUp(lines: linesUp)
        } else if linesUp < 0 {
            surface.scrollDown(lines: -linesUp)
        }
    }

    private func applyLayerTranslation() {
        guard let layer = surface.layer else { return }
        var bounds = layer.bounds
        bounds.origin.y = accumulatedPixelOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = bounds
        CATransaction.commit()
    }
}
