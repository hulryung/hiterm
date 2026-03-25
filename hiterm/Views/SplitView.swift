import AppKit
import GhosttyKit

/// Recursive split tree node for terminal split panes.
indirect enum SplitNode {
    case leaf(TerminalSurfaceView)
    case split(SplitContainer)
}

class SplitContainer {
    enum Direction {
        case horizontal // left | right
        case vertical   // top / bottom
    }

    let direction: Direction
    var ratio: CGFloat
    var first: SplitNode
    var second: SplitNode

    init(direction: Direction, ratio: CGFloat, first: SplitNode, second: SplitNode) {
        self.direction = direction
        self.ratio = ratio
        self.first = first
        self.second = second
    }
}

/// NSView that renders a SplitNode tree with draggable dividers.
class TerminalSplitView: NSView {
    private let ghosttyApp: GhosttyApp
    private(set) var rootNode: SplitNode
    private var dividerViews: [DividerView] = []

    var focusedSurface: TerminalSurfaceView? {
        didSet {
            if let surface = focusedSurface {
                window?.makeFirstResponder(surface)
            }
        }
    }

    var onSurfaceClosed: ((TerminalSurfaceView) -> Void)?

    init(ghosttyApp: GhosttyApp, frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600)) {
        self.ghosttyApp = ghosttyApp
        let surface = TerminalSurfaceView(ghosttyApp: ghosttyApp, frame: frame)
        self.rootNode = .leaf(surface)
        super.init(frame: frame)
        addSubview(surface)
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        self.focusedSurface = surface
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Split Operations

    func split(direction: SplitContainer.Direction) {
        guard let focused = focusedSurface else { return }
        let newSurface = TerminalSurfaceView(ghosttyApp: ghosttyApp)

        let container = SplitContainer(
            direction: direction,
            ratio: 0.5,
            first: .leaf(focused),
            second: .leaf(newSurface)
        )

        rootNode = replaceLeaf(in: rootNode, target: focused, with: .split(container))
        addSubview(newSurface)

        let divider = DividerView(direction: direction)
        divider.onDrag = { [weak self] ratio in
            self?.updateSplitRatio(for: focused, ratio: ratio)
        }
        dividerViews.append(divider)
        addSubview(divider)

        layoutSplits()
        focusedSurface = newSurface
    }

    func removeSurface(_ surface: TerminalSurfaceView) {
        guard let sibling = findSibling(of: surface, in: rootNode) else {
            onSurfaceClosed?(surface)
            return
        }

        rootNode = replaceParentSplit(in: rootNode, removing: surface, replacingWith: sibling)
        surface.removeFromSuperview()
        layoutSplits()

        if let firstLeaf = findFirstLeaf(in: rootNode) {
            focusedSurface = firstLeaf
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutSplits()
    }

    private func layoutSplits() {
        layoutNode(rootNode, in: bounds)
    }

    private func layoutNode(_ node: SplitNode, in rect: NSRect) {
        switch node {
        case .leaf(let surface):
            surface.frame = rect

        case .split(let container):
            let (firstRect, dividerRect, secondRect) = splitRects(
                rect: rect,
                direction: container.direction,
                ratio: container.ratio
            )

            layoutNode(container.first, in: firstRect)
            layoutNode(container.second, in: secondRect)

            // Position divider
            if let divider = dividerViews.first(where: { _ in true }) {
                divider.frame = dividerRect
            }
        }
    }

    private func splitRects(
        rect: NSRect,
        direction: SplitContainer.Direction,
        ratio: CGFloat
    ) -> (NSRect, NSRect, NSRect) {
        let dividerThickness: CGFloat = 1

        switch direction {
        case .horizontal:
            let splitX = rect.origin.x + rect.width * ratio
            let first = NSRect(x: rect.origin.x, y: rect.origin.y,
                             width: splitX - rect.origin.x - dividerThickness / 2,
                             height: rect.height)
            let divider = NSRect(x: splitX - dividerThickness / 2, y: rect.origin.y,
                               width: dividerThickness, height: rect.height)
            let second = NSRect(x: splitX + dividerThickness / 2, y: rect.origin.y,
                              width: rect.maxX - splitX - dividerThickness / 2,
                              height: rect.height)
            return (first, divider, second)

        case .vertical:
            let splitY = rect.origin.y + rect.height * (1 - ratio)
            let first = NSRect(x: rect.origin.x, y: splitY + dividerThickness / 2,
                             width: rect.width,
                             height: rect.maxY - splitY - dividerThickness / 2)
            let divider = NSRect(x: rect.origin.x, y: splitY - dividerThickness / 2,
                               width: rect.width, height: dividerThickness)
            let second = NSRect(x: rect.origin.x, y: rect.origin.y,
                              width: rect.width,
                              height: splitY - rect.origin.y - dividerThickness / 2)
            return (first, divider, second)
        }
    }

    // MARK: - Tree Helpers

    private func replaceLeaf(in node: SplitNode, target: TerminalSurfaceView, with replacement: SplitNode) -> SplitNode {
        switch node {
        case .leaf(let surface):
            if surface === target { return replacement }
            return node
        case .split(let container):
            container.first = replaceLeaf(in: container.first, target: target, with: replacement)
            container.second = replaceLeaf(in: container.second, target: target, with: replacement)
            return .split(container)
        }
    }

    private func findSibling(of surface: TerminalSurfaceView, in node: SplitNode) -> SplitNode? {
        switch node {
        case .leaf:
            return nil
        case .split(let container):
            if case .leaf(let s) = container.first, s === surface { return container.second }
            if case .leaf(let s) = container.second, s === surface { return container.first }
            return findSibling(of: surface, in: container.first) ?? findSibling(of: surface, in: container.second)
        }
    }

    private func replaceParentSplit(in node: SplitNode, removing surface: TerminalSurfaceView, replacingWith replacement: SplitNode) -> SplitNode {
        switch node {
        case .leaf:
            return node
        case .split(let container):
            if case .leaf(let s) = container.first, s === surface { return replacement }
            if case .leaf(let s) = container.second, s === surface { return replacement }
            container.first = replaceParentSplit(in: container.first, removing: surface, replacingWith: replacement)
            container.second = replaceParentSplit(in: container.second, removing: surface, replacingWith: replacement)
            return .split(container)
        }
    }

    private func findFirstLeaf(in node: SplitNode) -> TerminalSurfaceView? {
        switch node {
        case .leaf(let surface): return surface
        case .split(let container): return findFirstLeaf(in: container.first)
        }
    }

    private func updateSplitRatio(for surface: TerminalSurfaceView, ratio: CGFloat) {
        rootNode = updateRatio(in: rootNode, near: surface, ratio: ratio)
        layoutSplits()
    }

    private func updateRatio(in node: SplitNode, near surface: TerminalSurfaceView, ratio: CGFloat) -> SplitNode {
        switch node {
        case .leaf: return node
        case .split(let container):
            if containsSurface(surface, in: container.first) || containsSurface(surface, in: container.second) {
                container.ratio = max(0.1, min(0.9, ratio))
                return .split(container)
            }
            container.first = updateRatio(in: container.first, near: surface, ratio: ratio)
            container.second = updateRatio(in: container.second, near: surface, ratio: ratio)
            return .split(container)
        }
    }

    private func containsSurface(_ surface: TerminalSurfaceView, in node: SplitNode) -> Bool {
        switch node {
        case .leaf(let s): return s === surface
        case .split(let container):
            return containsSurface(surface, in: container.first) || containsSurface(surface, in: container.second)
        }
    }
}

// MARK: - Divider View

class DividerView: NSView {
    let direction: SplitContainer.Direction
    var onDrag: ((CGFloat) -> Void)?

    init(direction: SplitContainer.Direction) {
        self.direction = direction
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func resetCursorRects() {
        let cursor: NSCursor = direction == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let loc = superview.convert(event.locationInWindow, from: nil)
        let ratio: CGFloat
        if direction == .horizontal {
            ratio = loc.x / superview.bounds.width
        } else {
            ratio = 1.0 - (loc.y / superview.bounds.height)
        }
        onDrag?(ratio)
    }
}
