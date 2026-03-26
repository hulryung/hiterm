import AppKit
import GhosttyKit

/// Manages the main terminal window with tabs and split panes.
class MainWindowController: NSWindowController, NSWindowDelegate {
    private let ghosttyApp: GhosttyApp
    private var tabs: [TabItem] = []
    private var currentTabIndex: Int = 0
    private var tabBarView: TabBarView!
    private var contentContainerView: NSView!
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
        window.tabbingMode = .disallowed

        super.init(window: window)
        window.delegate = self

        setupViews()
        createInitialTab()
        setupNotifications()
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
        contentContainerView.layer?.masksToBounds = true
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
        let splitView = TerminalSplitView(ghosttyApp: ghosttyApp)
        splitView.onSurfaceClosed = { [weak self] surface in
            self?.closeCurrentTab()
        }
        splitView.onTitleChanged = { [weak self] title in
            self?.updateTabTitle(for: splitView, title: title)
        }
        let tab = TabItem(splitView: splitView, title: "Terminal")
        tabs.append(tab)
        selectTab(at: 0, animated: false)
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
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
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermSwipePrevTab, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.currentTabIndex > 0 {
                    self.selectTab(at: self.currentTabIndex - 1)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermSwipeNextTab, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                if self.currentTabIndex < self.tabs.count - 1 {
                    self.selectTab(at: self.currentTabIndex + 1)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermSwipeBegan, object: nil, queue: .main
            ) { [weak self] _ in self?.swipePanBegan() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermSwipeMoved, object: nil, queue: .main
            ) { [weak self] notif in
                guard let delta = notif.userInfo?["delta"] as? CGFloat else { return }
                self?.swipePanMoved(delta: delta)
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermSwipeEnded, object: nil, queue: .main
            ) { [weak self] _ in self?.swipePanEnded() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermNewWindow, object: nil, queue: .main
            ) { _ in
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.newWindow(nil)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermCloseWindow, object: nil, queue: .main
            ) { [weak self] _ in self?.window?.close() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermEqualizeSplits, object: nil, queue: .main
            ) { [weak self] _ in self?.currentTab?.splitView.equalizeSplits() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermResizeSplit, object: nil, queue: .main
            ) { [weak self] notif in
                guard let direction = notif.userInfo?["direction"] as? ghostty_action_resize_split_direction_e,
                      let amount = notif.userInfo?["amount"] as? UInt16 else { return }
                self?.currentTab?.splitView.resizeFocusedSplit(direction: direction, amount: CGFloat(amount) / 100.0)
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermToggleSplitZoom, object: nil, queue: .main
            ) { [weak self] _ in self?.currentTab?.splitView.toggleZoom() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermMoveTab, object: nil, queue: .main
            ) { [weak self] notif in
                guard let self, let amount = notif.userInfo?["amount"] as? Int else { return }
                let newIndex = max(0, min(self.tabs.count - 1, self.currentTabIndex + Int(amount)))
                guard newIndex != self.currentTabIndex else { return }
                let tab = self.tabs.remove(at: self.currentTabIndex)
                self.tabs.insert(tab, at: newIndex)
                self.currentTabIndex = newIndex
                self.tabBarView.updateTabs(titles: self.tabs.map(\.title), selectedIndex: self.currentTabIndex)
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermResetWindowSize, object: nil, queue: .main
            ) { [weak self] _ in
                self?.window?.setFrame(NSRect(x: 0, y: 0, width: 900, height: 600), display: true)
                self?.window?.center()
            }
        )
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
        splitView.onTitleChanged = { [weak self] title in
            self?.updateTabTitle(for: splitView, title: title)
        }

        let tab = TabItem(splitView: splitView, title: "Terminal")
        tabs.append(tab)
        selectTab(at: tabs.count - 1)
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
    }

    private func updateTabTitle(for splitView: TerminalSplitView, title: String) {
        guard let index = tabs.firstIndex(where: { $0.splitView === splitView }) else { return }
        tabs[index].title = title
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
        if index == currentTabIndex {
            window?.title = title
        }
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
        selectTab(at: newIndex, animated: false)
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
    }

    private var isAnimatingTabSwitch = false

    func selectTab(at index: Int, animated: Bool = true) {
        guard index >= 0, index < tabs.count, !isAnimatingTabSwitch else { return }

        let previousIndex = currentTabIndex
        let oldSplit = (previousIndex < tabs.count) ? tabs[previousIndex].splitView : nil
        currentTabIndex = index
        let newSplit = tabs[index].splitView
        let containerWidth = contentContainerView.bounds.width

        if oldSplit !== newSplit || newSplit.superview == nil {
            if animated, let oldSplit, oldSplit !== newSplit, containerWidth > 0 {
                isAnimatingTabSwitch = true
                let goingRight = index > previousIndex

                // Position new tab next to current tab.
                newSplit.translatesAutoresizingMaskIntoConstraints = true
                newSplit.frame = NSRect(
                    x: goingRight ? containerWidth : -containerWidth,
                    y: 0,
                    width: containerWidth,
                    height: contentContainerView.bounds.height
                )
                newSplit.autoresizingMask = [.height]
                contentContainerView.addSubview(newSplit)

                // Ensure old tab also uses frame positioning.
                oldSplit.translatesAutoresizingMaskIntoConstraints = true
                oldSplit.frame = NSRect(
                    x: 0, y: 0,
                    width: containerWidth,
                    height: contentContainerView.bounds.height
                )

                // Animate bounds.origin.x to slide both tabs.
                let targetX: CGFloat = goingRight ? containerWidth : -containerWidth
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    contentContainerView.animator().bounds.origin.x = targetX
                }, completionHandler: { [weak self] in
                    guard let self else { return }
                    // Reset: remove old tab, reset bounds, position new tab properly.
                    oldSplit.removeFromSuperview()
                    self.contentContainerView.bounds.origin.x = 0

                    newSplit.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        newSplit.topAnchor.constraint(equalTo: self.contentContainerView.topAnchor),
                        newSplit.leadingAnchor.constraint(equalTo: self.contentContainerView.leadingAnchor),
                        newSplit.trailingAnchor.constraint(equalTo: self.contentContainerView.trailingAnchor),
                        newSplit.bottomAnchor.constraint(equalTo: self.contentContainerView.bottomAnchor),
                    ])
                    self.isAnimatingTabSwitch = false
                })
            } else {
                // No animation: just swap views.
                if oldSplit !== newSplit {
                    oldSplit?.removeFromSuperview()
                }
                contentContainerView.bounds.origin.x = 0
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

    // MARK: - Continuous Swipe Panning

    private var panStartIndex: Int = 0
    private var panPrevSplit: TerminalSplitView?
    private var panNextSplit: TerminalSplitView?
    private var isPanning = false

    private func swipePanBegan() {
        guard tabs.count > 1, !isAnimatingTabSwitch else { return }
        isPanning = true
        panStartIndex = currentTabIndex

        let containerWidth = contentContainerView.bounds.width
        let containerHeight = contentContainerView.bounds.height

        // Prepare previous tab (to the left).
        if currentTabIndex > 0 {
            let prev = tabs[currentTabIndex - 1].splitView
            prev.translatesAutoresizingMaskIntoConstraints = true
            prev.frame = NSRect(x: -containerWidth, y: 0, width: containerWidth, height: containerHeight)
            prev.autoresizingMask = [.height]
            contentContainerView.addSubview(prev)
            panPrevSplit = prev
        }

        // Prepare next tab (to the right).
        if currentTabIndex < tabs.count - 1 {
            let next = tabs[currentTabIndex + 1].splitView
            next.translatesAutoresizingMaskIntoConstraints = true
            next.frame = NSRect(x: containerWidth, y: 0, width: containerWidth, height: containerHeight)
            next.autoresizingMask = [.height]
            contentContainerView.addSubview(next)
            panNextSplit = next
        }

        // Current tab also needs frame positioning.
        let current = tabs[currentTabIndex].splitView
        current.translatesAutoresizingMaskIntoConstraints = true
        current.frame = NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight)
    }

    private func swipePanMoved(delta: CGFloat) {
        guard isPanning else { return }
        // delta is normalized (0..1 across trackpad). Scale to view width.
        let containerWidth = contentContainerView.bounds.width
        let offsetX = -delta * containerWidth * 2  // 2x for responsive feel

        // Clamp: don't pan past edges if no prev/next tab.
        let clampedX: CGFloat
        if panPrevSplit == nil && offsetX < 0 {
            clampedX = 0
        } else if panNextSplit == nil && offsetX > 0 {
            clampedX = 0
        } else {
            clampedX = offsetX
        }

        contentContainerView.bounds.origin.x = clampedX
    }

    private func swipePanEnded() {
        guard isPanning else { return }
        isPanning = false

        let containerWidth = contentContainerView.bounds.width
        let currentX = contentContainerView.bounds.origin.x
        let threshold = containerWidth * 0.3

        if currentX > threshold, panNextSplit != nil {
            // Commit: switch to next tab.
            isAnimatingTabSwitch = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentContainerView.animator().bounds.origin.x = containerWidth
            }, completionHandler: { [weak self] in
                self?.finishPanSwitch(to: self!.panStartIndex + 1)
            })
        } else if currentX < -threshold, panPrevSplit != nil {
            // Commit: switch to previous tab.
            isAnimatingTabSwitch = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentContainerView.animator().bounds.origin.x = -containerWidth
            }, completionHandler: { [weak self] in
                self?.finishPanSwitch(to: self!.panStartIndex - 1)
            })
        } else {
            // Snap back to original tab.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentContainerView.animator().bounds.origin.x = 0
            }, completionHandler: { [weak self] in
                self?.cleanupPanViews()
            })
        }
    }

    private func finishPanSwitch(to index: Int) {
        cleanupPanViews()
        currentTabIndex = index
        let newSplit = tabs[index].splitView

        // Reset bounds and set up the new tab properly.
        contentContainerView.bounds.origin.x = 0
        newSplit.translatesAutoresizingMaskIntoConstraints = false
        if newSplit.superview != contentContainerView {
            contentContainerView.addSubview(newSplit)
        }
        NSLayoutConstraint.activate([
            newSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        newSplit.focusedSurface.map { window?.makeFirstResponder($0) }
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
        window?.title = tabs[index].title
        isAnimatingTabSwitch = false
    }

    private func cleanupPanViews() {
        // Remove non-current tabs from superview.
        for (i, tab) in tabs.enumerated() where i != currentTabIndex {
            if tab.splitView.superview == contentContainerView {
                tab.splitView.removeFromSuperview()
            }
        }
        contentContainerView.bounds.origin.x = 0
        panPrevSplit = nil
        panNextSplit = nil
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
        // If the current tab is split, close only the focused pane.
        if let splitView = currentTab?.splitView,
           splitView.isSplit,
           let focused = splitView.focusedSurface {
            ghostty_surface_request_close(focused.surface!)
            return
        }
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

    // MARK: - Fullscreen

    func windowWillEnterFullScreen(_ notification: Notification) {
        tabBarView.isHidden = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        tabBarView.isHidden = false
    }
}
