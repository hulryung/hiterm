import AppKit

/// Translucent overlay drawn on top of `TerminalSplitView` during a pane
/// drag. Shows a tinted rect on the source pane ("picked up") and a stronger
/// tint on the drop-target pane. Owns no logic — frames are set from outside.
class PaneDragOverlay: NSView {
    private let sourceLayer = CALayer()
    private let targetLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        sourceLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        sourceLayer.borderColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        sourceLayer.borderWidth = 1
        sourceLayer.cornerRadius = 4
        sourceLayer.isHidden = true

        targetLayer.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.30).cgColor
        targetLayer.borderColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
        targetLayer.borderWidth = 2
        targetLayer.cornerRadius = 4
        targetLayer.isHidden = true

        layer?.addSublayer(sourceLayer)
        layer?.addSublayer(targetLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Non-interactive: events pass through to underlying views.
        return nil
    }

    func setSourceFrame(_ rect: NSRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            sourceLayer.frame = rect
            sourceLayer.isHidden = false
        } else {
            sourceLayer.isHidden = true
        }
        CATransaction.commit()
    }

    func setTargetFrame(_ rect: NSRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect {
            targetLayer.frame = rect
            targetLayer.isHidden = false
        } else {
            targetLayer.isHidden = true
        }
        CATransaction.commit()
    }
}
