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
    var onTitleChanged: ((String) -> Void)?
    var onSurfaceCreated: ((TerminalSurfaceView) -> Void)?

    var isSplit: Bool {
        if case .split = rootNode { return true }
        return false
    }

    init(ghosttyApp: GhosttyApp, baseConfig: ghostty_surface_config_s? = nil, frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600)) {
        self.ghosttyApp = ghosttyApp
        let surface = TerminalSurfaceView(ghosttyApp: ghosttyApp, baseConfig: baseConfig, frame: frame)
        self.rootNode = .leaf(surface)
        super.init(frame: frame)
        addSubview(surface)
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        surface.onClosed = { [weak self, weak surface] in
            guard let self, let surface else { return }
            self.handleSurfaceClosed(surface)
        }
        surface.onTitleChanged = { [weak self] title in
            self?.onTitleChanged?(title)
        }
        self.focusedSurface = surface
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Split Operations

    func split(direction: SplitContainer.Direction) {
        guard let focused = focusedSurface else { return }
        // Inherit config (including CWD) from the focused surface.
        var inheritedConfig: ghostty_surface_config_s? = nil
        if let focusedSurface = focused.surface {
            inheritedConfig = ghostty_surface_inherited_config(focusedSurface, GHOSTTY_SURFACE_CONTEXT_SPLIT)
        }
        let newSurface = TerminalSurfaceView(ghosttyApp: ghosttyApp, baseConfig: inheritedConfig)
        newSurface.onClosed = { [weak self, weak newSurface] in
            guard let self, let newSurface else { return }
            self.handleSurfaceClosed(newSurface)
        }
        newSurface.onTitleChanged = { [weak self] title in
            self?.onTitleChanged?(title)
        }
        onSurfaceCreated?(newSurface)

        let container = SplitContainer(
            direction: direction,
            ratio: 0.5,
            first: .leaf(focused),
            second: .leaf(newSurface)
        )

        rootNode = replaceLeaf(in: rootNode, target: focused, with: .split(container))
        addSubview(newSurface)

        let divider = makeDivider(for: container)
        dividerViews.append(divider)
        addSubview(divider)

        layoutSplits()
        focusedSurface = newSurface
    }

    private func makeDivider(for container: SplitContainer) -> DividerView {
        let divider = DividerView(direction: container.direction)
        divider.container = container
        divider.onDrag = { [weak self, weak container] ratio in
            guard let self, let container else { return }
            container.ratio = max(0.1, min(0.9, ratio))
            self.layoutSplits()
        }
        return divider
    }

    private func handleSurfaceClosed(_ surface: TerminalSurfaceView) {
        removeSurface(surface)
    }

    func removeSurface(_ surface: TerminalSurfaceView) {
        guard let sibling = findSibling(of: surface, in: rootNode) else {
            onSurfaceClosed?(surface)
            return
        }

        // Determine slide direction based on split direction and position.
        let container = findParentContainer(of: surface, in: rootNode)
        let isFirst = container.map { containsSurface(surface, in: $0.first) } ?? true
        let direction = container?.direction ?? .horizontal

        let closingFrame = surface.frame
        surface.translatesAutoresizingMaskIntoConstraints = true
        surface.autoresizingMask = []

        // Immediately update the tree and layout the sibling to fill the space.
        rootNode = replaceParentSplit(in: rootNode, removing: surface, replacingWith: sibling)
        dividerViews.forEach { $0.removeFromSuperview() }
        dividerViews.removeAll()
        rebuildDividers(rootNode)
        layoutSplits()

        if let firstLeaf = findFirstLeaf(in: rootNode) {
            focusedSurface = firstLeaf
        }

        // Animate the closing surface sliding away.
        surface.frame = closingFrame
        surface.wantsLayer = true
        addSubview(surface)

        var progress: CGFloat = 0
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            progress += 0.08
            if progress >= 1.0 {
                timer?.invalidate()
                surface.removeFromSuperview()
                return
            }
            let ease = progress * progress
            surface.alphaValue = 1.0 - ease

            switch direction {
            case .horizontal:
                // Left pane → slide left, right pane → slide right.
                let dx = isFirst ? -closingFrame.width * 0.3 * ease : closingFrame.width * 0.3 * ease
                surface.frame.origin.x = closingFrame.origin.x + dx
            case .vertical:
                // Top pane → slide up, bottom pane → slide down.
                let dy = isFirst ? closingFrame.height * 0.3 * ease : -closingFrame.height * 0.3 * ease
                surface.frame.origin.y = closingFrame.origin.y + dy
            }
        }
    }

    private func findParentContainer(of surface: TerminalSurfaceView, in node: SplitNode) -> SplitContainer? {
        guard case .split(let container) = node else { return nil }
        if case .leaf(let s) = container.first, s === surface { return container }
        if case .leaf(let s) = container.second, s === surface { return container }
        return findParentContainer(of: surface, in: container.first)
            ?? findParentContainer(of: surface, in: container.second)
    }

    func equalizeSplits() {
        equalizeSplitsNode(rootNode)
        layoutSplits()
    }

    private func equalizeSplitsNode(_ node: SplitNode) {
        if case .split(let container) = node {
            container.ratio = 0.5
            equalizeSplitsNode(container.first)
            equalizeSplitsNode(container.second)
        }
    }

    func navigateToSplit(direction: ghostty_action_goto_split_e) {
        guard let focused = focusedSurface else { return }

        // Collect all leaf surfaces with their frames.
        var leaves: [(surface: TerminalSurfaceView, frame: NSRect)] = []
        collectLeaves(rootNode, into: &leaves)

        guard leaves.count > 1 else { return }

        // Handle previous/next as sequential navigation.
        if direction == GHOSTTY_GOTO_SPLIT_PREVIOUS || direction == GHOSTTY_GOTO_SPLIT_NEXT {
            guard let idx = leaves.firstIndex(where: { $0.surface === focused }) else { return }
            let nextIdx: Int
            if direction == GHOSTTY_GOTO_SPLIT_NEXT {
                nextIdx = (idx + 1) % leaves.count
            } else {
                nextIdx = (idx - 1 + leaves.count) % leaves.count
            }
            focusedSurface = leaves[nextIdx].surface
            return
        }

        // Directional navigation: find nearest neighbor in the requested direction.
        let focusedFrame = focused.frame
        let cx = focusedFrame.midX
        let cy = focusedFrame.midY

        var bestSurface: TerminalSurfaceView?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (surface, frame) in leaves {
            guard surface !== focused else { continue }
            let sx = frame.midX
            let sy = frame.midY

            let isCandidate: Bool
            switch direction {
            case GHOSTTY_GOTO_SPLIT_LEFT:  isCandidate = sx < cx
            case GHOSTTY_GOTO_SPLIT_RIGHT: isCandidate = sx > cx
            case GHOSTTY_GOTO_SPLIT_UP:    isCandidate = sy > cy  // AppKit: y increases upward
            case GHOSTTY_GOTO_SPLIT_DOWN:  isCandidate = sy < cy
            default: isCandidate = false
            }

            if isCandidate {
                let dist = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy)
                if dist < bestDistance {
                    bestDistance = dist
                    bestSurface = surface
                }
            }
        }

        if let target = bestSurface {
            focusedSurface = target
        }
    }

    private func collectLeaves(_ node: SplitNode, into leaves: inout [(surface: TerminalSurfaceView, frame: NSRect)]) {
        switch node {
        case .leaf(let surface):
            leaves.append((surface: surface, frame: surface.frame))
        case .split(let container):
            collectLeaves(container.first, into: &leaves)
            collectLeaves(container.second, into: &leaves)
        }
    }

    func resizeFocusedSplit(direction: ghostty_action_resize_split_direction_e, amount: CGFloat) {
        guard let focused = focusedSurface else { return }
        rootNode = adjustRatio(in: rootNode, near: focused, direction: direction, amount: amount)
        layoutSplits()
    }

    private func adjustRatio(in node: SplitNode, near surface: TerminalSurfaceView,
                             direction: ghostty_action_resize_split_direction_e, amount: CGFloat) -> SplitNode {
        guard case .split(let container) = node else { return node }
        if containsSurface(surface, in: container.first) || containsSurface(surface, in: container.second) {
            let delta: CGFloat
            switch direction {
            case GHOSTTY_RESIZE_SPLIT_RIGHT, GHOSTTY_RESIZE_SPLIT_DOWN:
                delta = containsSurface(surface, in: container.first) ? amount : -amount
            default:
                delta = containsSurface(surface, in: container.first) ? -amount : amount
            }
            container.ratio = max(0.1, min(0.9, container.ratio + delta))
            return .split(container)
        }
        container.first = adjustRatio(in: container.first, near: surface, direction: direction, amount: amount)
        container.second = adjustRatio(in: container.second, near: surface, direction: direction, amount: amount)
        return .split(container)
    }

    private var zoomedNode: SplitNode?
    private var preZoomRootNode: SplitNode?

    func toggleZoom() {
        guard let focused = focusedSurface else { return }
        if preZoomRootNode != nil {
            // Unzoom: restore original tree.
            rootNode = preZoomRootNode!
            preZoomRootNode = nil
            // Re-add all surfaces from tree.
            addAllSurfaces(rootNode)
            dividerViews.forEach { $0.removeFromSuperview() }
            dividerViews.removeAll()
            rebuildDividers(rootNode)
            layoutSplits()
            focusedSurface = focused
        } else {
            // Zoom: save tree, show only focused.
            preZoomRootNode = rootNode
            // Remove all views.
            removeAllSurfaces(rootNode)
            dividerViews.forEach { $0.removeFromSuperview() }
            dividerViews.removeAll()
            // Show only focused.
            addSubview(focused)
            focused.frame = bounds
            focused.autoresizingMask = [.width, .height]
        }
    }

    private func removeAllSurfaces(_ node: SplitNode) {
        switch node {
        case .leaf(let surface): surface.removeFromSuperview()
        case .split(let c): removeAllSurfaces(c.first); removeAllSurfaces(c.second)
        }
    }

    private func addAllSurfaces(_ node: SplitNode) {
        switch node {
        case .leaf(let surface):
            if surface.superview == nil { addSubview(surface) }
        case .split(let c): addAllSurfaces(c.first); addAllSurfaces(c.second)
        }
    }

    private func rebuildDividers(_ node: SplitNode) {
        if case .split(let container) = node {
            let divider = makeDivider(for: container)
            dividerViews.append(divider)
            addSubview(divider)
            rebuildDividers(container.first)
            rebuildDividers(container.second)
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

            // Position the divider that belongs to this specific container.
            if let divider = dividerViews.first(where: { $0.container === container }) {
                divider.frame = dividerRect
                divider.parentRect = rect
            }
        }
    }

    private func splitRects(
        rect: NSRect,
        direction: SplitContainer.Direction,
        ratio: CGFloat
    ) -> (NSRect, NSRect, NSRect) {
        // Thicker divider hit area for easier grabbing.
        let dividerThickness: CGFloat = 3

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
    weak var container: SplitContainer?
    var onDrag: ((CGFloat) -> Void)?

    /// The parent container rect (in superview coordinates) that this divider
    /// splits. Set by the SplitView during layout. Used to compute drag ratio.
    var parentRect: NSRect = .zero

    init(direction: SplitContainer.Direction) {
        self.direction = direction
        super.init(frame: .zero)
        wantsLayer = true
        // Subtle visual: transparent hit area with a 1px line in the middle drawn via a sublayer.
        let line = CALayer()
        line.backgroundColor = NSColor.separatorColor.cgColor
        line.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(line)
        self.visualLine = line
    }

    private var visualLine: CALayer?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layout() {
        super.layout()
        // Draw the visual line at 1px in the middle of the hit area.
        guard let visualLine else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch direction {
        case .horizontal:
            let lineWidth: CGFloat = 1
            visualLine.frame = NSRect(x: (bounds.width - lineWidth) / 2, y: 0,
                                      width: lineWidth, height: bounds.height)
        case .vertical:
            let lineHeight: CGFloat = 1
            visualLine.frame = NSRect(x: 0, y: (bounds.height - lineHeight) / 2,
                                      width: bounds.width, height: lineHeight)
        }
        CATransaction.commit()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = direction == .horizontal ? .resizeLeftRight : .resizeUpDown
        addCursorRect(bounds, cursor: cursor)
    }

    // Required so mouseDragged is delivered to this view.
    override func mouseDown(with event: NSEvent) {
        // Intentionally empty — claims the mouse down so mouseDragged fires.
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview, parentRect.width > 0, parentRect.height > 0 else { return }
        let loc = superview.convert(event.locationInWindow, from: nil)
        let ratio: CGFloat
        switch direction {
        case .horizontal:
            ratio = (loc.x - parentRect.minX) / parentRect.width
        case .vertical:
            // AppKit y increases upward; first pane is on top.
            ratio = 1.0 - ((loc.y - parentRect.minY) / parentRect.height)
        }
        onDrag?(max(0.0, min(1.0, ratio)))
    }
}
