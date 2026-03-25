import AppKit
import GhosttyKit

/// Manages the main terminal window with tabs and split panes.
class MainWindowController: NSWindowController, NSWindowDelegate {
    private let ghosttyApp: GhosttyApp
    private var tabs: [TabItem] = []
    private var currentTabIndex: Int = 0
    private var tabBarView: TabBarView!
    private var contentContainerView: NSView!
    private var swipeGestureRecognizer: NSPanGestureRecognizer?
    private var observers: [NSObjectProtocol] = []

    struct TabItem {
        let splitView: TerminalSplitView
        var title: String
    }

    init(ghosttyApp: GhosttyApp) {
        self.ghosttyApp = ghosttyApp

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "hiterm"
        window.minSize = NSSize(width: 400, height: 300)
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)

        // Enable full-screen with tabs as separate spaces
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        window.tabbingMode = .preferred

        super.init(window: window)
        window.delegate = self

        setupViews()
        createInitialTab()
        setupNotifications()
        setupSwipeGesture()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Setup

    private func setupViews() {
        guard let contentView = window?.contentView else { return }

        // Tab bar
        tabBarView = TabBarView()
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        tabBarView.onTabSelected = { [weak self] index in
            self?.selectTab(at: index)
        }
        tabBarView.onTabClosed = { [weak self] index in
            self?.closeTab(at: index)
        }
        tabBarView.onNewTab = { [weak self] in
            self?.createNewTab()
        }
        contentView.addSubview(tabBarView)

        // Content container
        contentContainerView = NSView()
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.wantsLayer = true
        contentView.addSubview(contentContainerView)

        NSLayoutConstraint.activate([
            tabBarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 38),

            contentContainerView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func createInitialTab() {
        createNewTab()
    }

    private func setupNotifications() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermNewTab, object: nil, queue: .main
            ) { [weak self] _ in self?.createNewTab() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermCloseTab, object: nil, queue: .main
            ) { [weak self] _ in self?.closeCurrentTab() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermNewSplit, object: nil, queue: .main
            ) { [weak self] notif in
                guard let direction = notif.userInfo?["direction"] as? ghostty_action_split_direction_e else { return }
                let splitDir: SplitContainer.Direction =
                    (direction == GHOSTTY_SPLIT_DIRECTION_RIGHT || direction == GHOSTTY_SPLIT_DIRECTION_LEFT)
                    ? .horizontal : .vertical
                self?.splitCurrentSurface(direction: splitDir)
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermToggleFullscreen, object: nil, queue: .main
            ) { [weak self] _ in self?.window?.toggleFullScreen(nil) }
        )
    }

    // MARK: - Swipe Gesture for Tab Switching

    private func setupSwipeGesture() {
        let gesture = NSPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        gesture.numberOfTouchesRequired = 2
        window?.contentView?.addGestureRecognizer(gesture)
        swipeGestureRecognizer = gesture
    }

    private var swipeStartX: CGFloat = 0
    private var swipeTransitioning = false

    @objc private func handleSwipe(_ gesture: NSPanGestureRecognizer) {
        guard tabs.count > 1 else { return }

        let translation = gesture.translation(in: window?.contentView)
        let velocity = gesture.velocity(in: window?.contentView)
        let threshold: CGFloat = 100

        switch gesture.state {
        case .began:
            swipeStartX = 0
            swipeTransitioning = false

        case .changed:
            let dx = translation.x
            // Animate the current tab sliding
            if let currentSplit = currentTab?.splitView {
                let progress = min(1.0, max(-1.0, dx / (contentContainerView.bounds.width * 0.5)))
                currentSplit.layer?.transform = CATransform3DMakeTranslation(dx, 0, 0)
                currentSplit.layer?.opacity = Float(1.0 - abs(progress) * 0.3)
            }

        case .ended, .cancelled:
            let dx = translation.x
            if abs(dx) > threshold || abs(velocity.x) > 500 {
                if dx > 0 {
                    selectTab(at: max(0, currentTabIndex - 1), animated: true)
                } else {
                    selectTab(at: min(tabs.count - 1, currentTabIndex + 1), animated: true)
                }
            } else {
                // Snap back
                if let currentSplit = currentTab?.splitView {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        currentSplit.animator().layer?.transform = CATransform3DIdentity
                        currentSplit.animator().layer?.opacity = 1.0
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - Tab Management

    private var currentTab: TabItem? {
        guard currentTabIndex < tabs.count else { return nil }
        return tabs[currentTabIndex]
    }

    func createNewTab() {
        let splitView = TerminalSplitView(ghosttyApp: ghosttyApp)
        splitView.onSurfaceClosed = { [weak self] surface in
            self?.closeCurrentTab()
        }

        let tab = TabItem(splitView: splitView, title: "Terminal \(tabs.count + 1)")
        tabs.append(tab)
        selectTab(at: tabs.count - 1)
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
    }

    private func closeCurrentTab() {
        closeTab(at: currentTabIndex)
    }

    func closeTab(at index: Int) {
        guard index < tabs.count else { return }
        let tab = tabs[index]
        tab.splitView.removeFromSuperview()
        tabs.remove(at: index)

        if tabs.isEmpty {
            window?.close()
            return
        }

        let newIndex = min(index, tabs.count - 1)
        selectTab(at: newIndex)
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
    }

    func selectTab(at index: Int, animated: Bool = false) {
        guard index >= 0, index < tabs.count else { return }

        let previousIndex = currentTabIndex
        let oldSplit = (previousIndex < tabs.count) ? tabs[previousIndex].splitView : nil
        currentTabIndex = index
        let newSplit = tabs[index].splitView

        if oldSplit !== newSplit || newSplit.superview == nil {
            if animated, let oldSplit, oldSplit !== newSplit {
                let direction: CGFloat = index > previousIndex ? -1 : 1
                newSplit.frame = contentContainerView.bounds
                newSplit.layer?.transform = CATransform3DMakeTranslation(
                    -direction * contentContainerView.bounds.width, 0, 0
                )
                contentContainerView.addSubview(newSplit)

                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    oldSplit.animator().layer?.transform = CATransform3DMakeTranslation(
                        direction * contentContainerView.bounds.width, 0, 0
                    )
                    newSplit.animator().layer?.transform = CATransform3DIdentity
                    newSplit.animator().layer?.opacity = 1.0
                }, completionHandler: {
                    oldSplit.removeFromSuperview()
                    oldSplit.layer?.transform = CATransform3DIdentity
                    oldSplit.layer?.opacity = 1.0
                })
            } else {
                if oldSplit !== newSplit {
                    oldSplit?.removeFromSuperview()
                }
                oldSplit?.layer?.transform = CATransform3DIdentity
                oldSplit?.layer?.opacity = 1.0
                if newSplit.superview == nil {
                    newSplit.translatesAutoresizingMaskIntoConstraints = false
                    contentContainerView.addSubview(newSplit)
                    NSLayoutConstraint.activate([
                        newSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
                        newSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
                        newSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
                        newSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
                    ])
                }
            }
        }
        newSplit.focusedSurface.map { window?.makeFirstResponder($0) }
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)

        window?.title = tabs[index].title
    }

    // MARK: - Split

    private func splitCurrentSurface(direction: SplitContainer.Direction) {
        currentTab?.splitView.split(direction: direction)
    }

    // MARK: - Menu Actions

    @objc func newTab(_ sender: Any?) {
        createNewTab()
    }

    @objc func closeTab(_ sender: Any?) {
        closeCurrentTab()
    }

    @objc func splitHorizontally(_ sender: Any?) {
        splitCurrentSurface(direction: .horizontal)
    }

    @objc func splitVertically(_ sender: Any?) {
        splitCurrentSurface(direction: .vertical)
    }

    @objc func previousTab(_ sender: Any?) {
        if currentTabIndex > 0 {
            selectTab(at: currentTabIndex - 1, animated: true)
        }
    }

    @objc func nextTab(_ sender: Any?) {
        if currentTabIndex < tabs.count - 1 {
            selectTab(at: currentTabIndex + 1, animated: true)
        }
    }

    // MARK: - Fullscreen: Tabs → Separate Spaces

    func windowWillEnterFullScreen(_ notification: Notification) {
        // Hide custom tab bar in fullscreen (each tab becomes its own space)
        tabBarView.isHidden = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        // In full screen, create separate windows for each tab
        // so macOS creates separate Spaces for each
        guard tabs.count > 1 else { return }

        for (i, tab) in tabs.enumerated() where i != currentTabIndex {
            let auxWindow = NSWindow(
                contentRect: window?.frame ?? .zero,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            auxWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            auxWindow.contentView = tab.splitView
            auxWindow.title = tab.title
            auxWindow.toggleFullScreen(nil)
        }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        tabBarView.isHidden = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Re-collect all tabs back into the main window
        selectTab(at: currentTabIndex)
    }
}
