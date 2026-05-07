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
        let h = rowHeight

        while accumulatedPixelOffset >= h {
            if !tryScrollTerminal(linesUp: 1) {
                // Reached top of scrollback; drop the residual so the layer
                // does not wobble at sub-row offsets while no actual scrolling
                // is happening.
                accumulatedPixelOffset = 0
                break
            }
            accumulatedPixelOffset -= h
        }
        while accumulatedPixelOffset <= -h {
            if !tryScrollTerminal(linesUp: -1) {
                accumulatedPixelOffset = 0
                break
            }
            accumulatedPixelOffset += h
        }

        // Sub-row residual at a hard boundary still needs clamping: if the
        // user keeps pushing into the boundary, accumulator < rowHeight will
        // never trigger a terminal scroll, but applyLayerTranslation() would
        // still shift the layer — that is the trembling we want to avoid.
        if accumulatedPixelOffset > 0 && isAtTopOfScrollback() {
            accumulatedPixelOffset = 0
        } else if accumulatedPixelOffset < 0 && isAtBottomOfScrollback() {
            accumulatedPixelOffset = 0
        }

        applyLayerTranslation()

        Log.swiftterm.debug("scrollWheel delta=\(delta) accum=\(self.accumulatedPixelOffset) pos=\(self.surface.scrollPosition)")
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

    /// SwiftTerm 1.13.0: instead of calling `terminal.getTopVisibleRow()` +
    /// `terminal.scrollTo(row:)` + `surface.queuePendingDisplay()` (the last
    /// is internal to SwiftTerm), use the public `scrollUp(lines:)` /
    /// `scrollDown(lines:)` on the terminal view, which clamp to bounds,
    /// call `scrollTo(row:)` internally, and trigger a redraw.
    ///
    /// Returns `true` if the terminal actually scrolled. We detect movement
    /// via the public `scrollPosition` property
    /// (AppleTerminalView.swift:1796), which is derived from `yDisp` and
    /// returns 0 at the top of scrollback, 1 at the live bottom. Comparing
    /// it before/after is sufficient to know whether SwiftTerm clamped.
    @discardableResult
    private func tryScrollTerminal(linesUp: Int) -> Bool {
        let before = surface.scrollPosition
        if linesUp > 0 {
            surface.scrollUp(lines: linesUp)
        } else if linesUp < 0 {
            surface.scrollDown(lines: -linesUp)
        } else {
            return false
        }
        return surface.scrollPosition != before
    }

    /// At top of scrollback: oldest line shown, no more older lines exist.
    /// `scrollPosition == 0` matches `yDisp <= 0` per AppleTerminalView.swift:1799.
    private func isAtTopOfScrollback() -> Bool {
        return surface.scrollPosition <= 0
    }

    /// At bottom of scrollback: viewport pinned to the live tail.
    /// `scrollPosition == 1` matches `yDisp >= maxScrollback` per
    /// AppleTerminalView.swift:1804. Also true when there is no scrollback
    /// at all (alternate buffer or empty history) — in that case there is
    /// nowhere to scroll, so clamping is correct.
    private func isAtBottomOfScrollback() -> Bool {
        return surface.scrollPosition >= 1 || !surface.canScroll
    }

    private func applyLayerTranslation() {
        guard let layer = surface.layer else { return }
        // SwiftTerm 1.13.0: translating via `bounds.origin.y` competes with the
        // surface's internal `setNeedsDisplay` / `draw(_:)` cycle on row commits,
        // producing visible micro-stutter at slow scroll. `transform`-based
        // translation is applied late in the render pipeline and does not
        // interact with bounds/layout, so it survives redraws cleanly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, -accumulatedPixelOffset, 0)
        CATransaction.commit()
    }
}
