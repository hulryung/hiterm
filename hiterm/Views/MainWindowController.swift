import AppKit
import GhosttyKit

/// Manages the main terminal window with tabs and split panes.
class MainWindowController: NSWindowController, NSWindowDelegate, SwipeTrackerDelegate {
    private let ghosttyApp: GhosttyApp
    private var tabs: [TabItem] = []
    private var currentTabIndex: Int = 0

    var tabCount: Int { tabs.count }
    private var tabBarView: TabBarView!
    private var contentContainerView: NSView!
    private var observers: [NSObjectProtocol] = []

    struct TabItem {
        let splitView: TerminalSplitView
        var title: String
    }

    /// Tab to adopt instead of creating a new one.
    private var pendingExistingTab: (splitView: TerminalSplitView, title: String)?

    init(ghosttyApp: GhosttyApp, existingTab: (splitView: TerminalSplitView, title: String)? = nil) {
        self.ghosttyApp = ghosttyApp
        self.pendingExistingTab = existingTab

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = existingTab?.title ?? "hiterm"
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
        applyWindowOpacity()
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
        tabBarView.onTabMoveToNewWindow = { [weak self] index in
            self?.moveTabToNewWindow(at: index)
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

    private let swipeTracker = SwipeTracker()

    private func createInitialTab() {
        swipeTracker.delegate = self

        let splitView: TerminalSplitView
        let title: String

        if let existing = pendingExistingTab {
            // Adopt an existing tab from another window.
            splitView = existing.splitView
            title = existing.title
            pendingExistingTab = nil
        } else {
            splitView = TerminalSplitView(ghosttyApp: ghosttyApp)
            title = "Terminal"
        }

        splitView.onSurfaceClosed = { [weak self] _ in
            self?.closeCurrentTab()
        }
        splitView.onTitleChanged = { [weak self] title in
            self?.updateTabTitle(for: splitView, title: title)
        }
        splitView.onSurfaceCreated = { [weak self] surface in
            surface.swipeTracker = self?.swipeTracker
        }
        // Set swipe tracker on the initial surface.
        if let surface = splitView.focusedSurface {
            surface.swipeTracker = swipeTracker
        }

        let tab = TabItem(splitView: splitView, title: title)
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
                forName: .hitermGotoTab, object: nil, queue: .main
            ) { [weak self] notif in
                guard let self,
                      let tab = notif.userInfo?["tab"] as? ghostty_action_goto_tab_e else { return }
                let rawValue = tab.rawValue
                if rawValue == GHOSTTY_GOTO_TAB_PREVIOUS.rawValue {
                    if self.currentTabIndex > 0 { self.selectTab(at: self.currentTabIndex - 1) }
                } else if rawValue == GHOSTTY_GOTO_TAB_NEXT.rawValue {
                    if self.currentTabIndex < self.tabs.count - 1 { self.selectTab(at: self.currentTabIndex + 1) }
                } else if rawValue == GHOSTTY_GOTO_TAB_LAST.rawValue {
                    self.selectTab(at: self.tabs.count - 1)
                } else if rawValue >= 1, rawValue <= Int32(self.tabs.count) {
                    self.selectTab(at: Int(rawValue) - 1)
                }
            }
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
                forName: .hitermGotoSplit, object: nil, queue: .main
            ) { [weak self] notif in
                guard let self,
                      let direction = notif.userInfo?["direction"] as? ghostty_action_goto_split_e else { return }
                self.currentTab?.splitView.navigateToSplit(direction: direction)
            }
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
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.applyWindowOpacity() }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .hitermConfigReloaded, object: nil, queue: .main
            ) { [weak self] _ in self?.forceWindowRecomposite() }
        )
    }

    // MARK: - Window Opacity

    private var lastAppliedOpacity: CGFloat = 1.0

    private func applyWindowOpacity() {
        guard let window else { return }
        let raw = UserDefaults.standard.double(forKey: "windowOpacity")
        let opacity = raw > 0 ? CGFloat(raw) : 1.0
        guard opacity != lastAppliedOpacity else { return }
        lastAppliedOpacity = opacity

        if opacity < 1.0 {
            window.isOpaque = false
            // Match Ghostty's approach: use near-transparent white instead of .clear
            // for better compositing with Terminal.app-like appearance.
            window.backgroundColor = .white.withAlphaComponent(0.001)
        } else {
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        }
        window.invalidateShadow()
        tabBarView.setOpacity(opacity)
    }

    /// Force macOS to re-composite a transparent window.
    /// Without this toggle, the window server can show stale compositing.
    /// (Same pattern as Ghostty's TerminalController.fixTabBar)
    private func forceWindowRecomposite() {
        guard let window, !window.isOpaque else { return }
        window.isOpaque = true
        window.isOpaque = false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        forceWindowRecomposite()
    }

    // MARK: - Tab Management

    private var currentTab: TabItem? {
        guard currentTabIndex < tabs.count else { return nil }
        return tabs[currentTabIndex]
    }

    func createNewTab() {
        // Inherit config (including CWD) from the current tab's focused surface.
        var inheritedConfig: ghostty_surface_config_s? = nil
        if let currentSurface = currentTab?.splitView.focusedSurface?.surface {
            inheritedConfig = ghostty_surface_inherited_config(currentSurface, GHOSTTY_SURFACE_CONTEXT_TAB)
        }
        let splitView = TerminalSplitView(ghosttyApp: ghosttyApp, baseConfig: inheritedConfig)
        splitView.onSurfaceClosed = { [weak self] _ in
            self?.closeCurrentTab()
        }
        splitView.onTitleChanged = { [weak self] title in
            self?.updateTabTitle(for: splitView, title: title)
        }
        splitView.onSurfaceCreated = { [weak self] surface in
            surface.swipeTracker = self?.swipeTracker
        }
        // Set swipe tracker on the initial surface of the new tab.
        if let surface = splitView.focusedSurface {
            surface.swipeTracker = swipeTracker
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

    func moveTabToNewWindow(at index: Int) {
        guard index < tabs.count, tabs.count > 1 else { return }

        let tab = tabs.remove(at: index)
        let newIndex = min(index, tabs.count - 1)

        // Remove the split view from this window's container.
        tab.splitView.removeFromSuperview()

        // Show the new current tab.
        let newSplit = tabs[newIndex].splitView
        newSplit.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(newSplit)
        NSLayoutConstraint.activate([
            newSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])
        currentTabIndex = newIndex
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
        window?.title = tabs[newIndex].title

        // Create a new window with the detached tab.
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.newWindowWithTab(splitView: tab.splitView, title: tab.title)
    }

    private func closeCurrentTab() {
        closeTab(at: currentTabIndex)
    }

    func closeTab(at index: Int) {
        guard index < tabs.count else { return }

        // Cancel any in-progress animations.
        keyAnimTimer?.invalidate()
        keyAnimTimer = nil
        keyAnimContainerView?.removeFromSuperview()
        keyAnimContainerView = nil
        isAnimatingTabSwitch = false

        let tab = tabs[index]
        let closingSplit = tab.splitView

        tabs.remove(at: index)

        if tabs.isEmpty {
            closingSplit.removeFromSuperview()
            window?.close()
            return
        }

        let newIndex = min(index, tabs.count - 1)
        let newSplit = tabs[newIndex].splitView

        // Place new tab underneath the closing tab.
        newSplit.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(newSplit, positioned: .below, relativeTo: closingSplit)
        NSLayoutConstraint.activate([
            newSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        currentTabIndex = newIndex
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
        window?.title = tabs[newIndex].title

        // Move closing tab to window's contentView as an overlay
        // (outside Auto Layout so it won't be resized during animation).
        let frameInWindow = closingSplit.convert(closingSplit.bounds, to: window?.contentView)
        closingSplit.removeFromSuperview()
        closingSplit.translatesAutoresizingMaskIntoConstraints = true
        closingSplit.frame = frameInWindow
        closingSplit.autoresizingMask = []
        window?.contentView?.addSubview(closingSplit)

        // Animate closing tab sliding down + fade.
        var timer: Timer?
        var progress: CGFloat = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            progress += 0.08
            if progress >= 1.0 {
                timer?.invalidate()
                closingSplit.removeFromSuperview()
                newSplit.focusedSurface.map { self?.window?.makeFirstResponder($0) }
                return
            }
            let ease = progress * progress
            closingSplit.frame.origin.y = frameInWindow.origin.y - frameInWindow.height * ease
            closingSplit.alphaValue = 1.0 - ease
        }
    }

    private var isAnimatingTabSwitch = false
    private var keyAnimTimer: Timer?
    private var keyAnimContainerView: NSView?
    private var keyAnimBaseIndex: Int = 0  // index when container was created
    private var keyAnimCurrentX: CGFloat = 0
    private var keyAnimTargetIndex: Int = 0

    func selectTab(at index: Int, animated: Bool = true) {
        guard index >= 0, index < tabs.count else { return }

        if isAnimatingTabSwitch && animated {
            // Already animating: just retarget. Don't touch tab bar until finish.
            keyAnimTargetIndex = index
            return
        }

        let previousIndex = currentTabIndex
        let oldSplit = (previousIndex < tabs.count) ? tabs[previousIndex].splitView : nil
        let newSplit = tabs[index].splitView
        // Don't update currentTabIndex yet for animated path — let keyAnimTick do it.
        let containerWidth = contentContainerView.bounds.width

        if oldSplit !== newSplit || newSplit.superview == nil {
            if animated, oldSplit !== newSplit, containerWidth > 0 {
                isAnimatingTabSwitch = true
                keyAnimBaseIndex = previousIndex
                keyAnimTargetIndex = index
                keyAnimCurrentX = 0

                // Create container with all tabs.
                let height = contentContainerView.bounds.height
                let container = NSView(frame: NSRect(
                    x: -CGFloat(previousIndex) * containerWidth,
                    y: 0,
                    width: containerWidth * CGFloat(tabs.count),
                    height: height
                ))
                container.wantsLayer = true

                // Add container FIRST so there's no blank frame.
                contentContainerView.addSubview(container)

                // Move non-current tabs first, current tab last
                // to minimize visual disruption.
                for (i, tab) in tabs.enumerated() where i != previousIndex {
                    let sv = tab.splitView
                    sv.removeFromSuperview()
                    sv.translatesAutoresizingMaskIntoConstraints = true
                    sv.frame = NSRect(x: CGFloat(i) * containerWidth, y: 0, width: containerWidth, height: height)
                    sv.autoresizingMask = [.height]
                    container.addSubview(sv)
                }
                // Move current tab last.
                let currentSv = tabs[previousIndex].splitView
                currentSv.removeFromSuperview()
                currentSv.translatesAutoresizingMaskIntoConstraints = true
                currentSv.frame = NSRect(x: CGFloat(previousIndex) * containerWidth, y: 0, width: containerWidth, height: height)
                currentSv.autoresizingMask = [.height]
                container.addSubview(currentSv)

                keyAnimContainerView = container

                // Start timer-based animation.
                keyAnimTimer?.invalidate()
                keyAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    self?.keyAnimTick()
                }
                // Don't update tab bar during animation — only on finish.
                return
            } else {
                // No animation: just swap views.
                currentTabIndex = index
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
        // Force layout so the surface gets correct size immediately.
        contentContainerView.layoutSubtreeIfNeeded()
        newSplit.layoutSubtreeIfNeeded()

        newSplit.focusedSurface.map { window?.makeFirstResponder($0) }
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)

        window?.title = tabs[index].title
    }

    private func keyAnimTick() {
        guard let container = keyAnimContainerView else {
            finishKeyAnim()
            return
        }
        let width = contentContainerView.bounds.width
        guard width > 0 else { return }

        // Target position: offset from base index to target index.
        let targetX = CGFloat(keyAnimBaseIndex - keyAnimTargetIndex) * width
        let distance = targetX - keyAnimCurrentX

        // Move 20% of remaining distance per frame (fast ease-out).
        if abs(distance) < 1.0 {
            keyAnimCurrentX = targetX
        } else {
            keyAnimCurrentX += distance * 0.2
        }
        container.frame.origin.x = -CGFloat(keyAnimBaseIndex) * width + keyAnimCurrentX

        // Update tab bar when 30% of the way to the target.
        let progress = targetX != 0 ? abs(keyAnimCurrentX / targetX) : 1.0
        if progress > 0.3 {
            let targetIdx = keyAnimTargetIndex
            if targetIdx != currentTabIndex {
                currentTabIndex = targetIdx
                tabBarView.updateSelection(targetIdx)
                window?.title = tabs[targetIdx].title
            }
        }

        // Animation complete.
        if abs(keyAnimCurrentX - targetX) < 1.0 {
            finishKeyAnim()
        }
    }

    private func finishKeyAnim() {
        keyAnimTimer?.invalidate()
        keyAnimTimer = nil

        let targetIndex = keyAnimTargetIndex
        let targetSplit = tabs[targetIndex].splitView

        // Move target to contentContainerView before removing container.
        targetSplit.removeFromSuperview()
        targetSplit.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(targetSplit)
        NSLayoutConstraint.activate([
            targetSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            targetSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            targetSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            targetSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        keyAnimContainerView?.removeFromSuperview()
        keyAnimContainerView = nil
        contentContainerView.bounds.origin.x = 0

        contentContainerView.layoutSubtreeIfNeeded()
        targetSplit.layoutSubtreeIfNeeded()

        currentTabIndex = targetIndex
        isAnimatingTabSwitch = false

        // Defer focus change to avoid mid-layout flicker.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tabs[targetIndex].splitView.focusedSurface.map { self.window?.makeFirstResponder($0) }
        }
        tabBarView.updateSelection(currentTabIndex)
        window?.title = tabs[targetIndex].title
    }

    // MARK: - SwipeTrackerDelegate

    private var swipeContainerView: NSView?
    private var swipeStartIndex: Int = 0

    var swipeTabCount: Int { tabs.count }
    var swipeCurrentIndex: Int { swipeStartIndex }
    var swipeTabWidth: CGFloat { contentContainerView.bounds.width }

    func swipeBeganSession() {
        guard tabs.count > 1, !isAnimatingTabSwitch else { return }
        swipeStartIndex = currentTabIndex

        let width = contentContainerView.bounds.width
        let height = contentContainerView.bounds.height

        // Create container with all tabs positioned horizontally.
        let container = NSView(frame: NSRect(
            x: -CGFloat(currentTabIndex) * width,
            y: 0,
            width: width * CGFloat(tabs.count),
            height: height
        ))

        for (i, tab) in tabs.enumerated() {
            let sv = tab.splitView
            sv.removeFromSuperview()
            sv.translatesAutoresizingMaskIntoConstraints = true
            sv.frame = NSRect(x: CGFloat(i) * width, y: 0, width: width, height: height)
            sv.autoresizingMask = [.height]
            container.addSubview(sv)
        }

        contentContainerView.addSubview(container)
        swipeContainerView = container
    }

    func swipeSetOffset(_ offset: CGFloat) {
        guard let container = swipeContainerView else { return }
        let width = contentContainerView.bounds.width
        var frame = container.frame
        frame.origin.x = -CGFloat(swipeStartIndex) * width + offset
        container.frame = frame

        // Update tab bar early: when offset crosses 50% of tab width,
        // show the target tab as selected.
        guard width > 0 else { return }
        let tabOffset = -offset / width
        let visualIndex = swipeStartIndex + Int(tabOffset.rounded())
        let clampedIndex = max(0, min(tabs.count - 1, visualIndex))
        if clampedIndex != currentTabIndex {
            currentTabIndex = clampedIndex
            tabBarView.updateSelection(clampedIndex)
            window?.title = tabs[clampedIndex].title
        }
    }

    func swipeEndSession(targetIndex: Int) {
        guard targetIndex >= 0, targetIndex < tabs.count else {
            swipeCancelSession()
            return
        }

        currentTabIndex = targetIndex
        let newSplit = tabs[targetIndex].splitView

        // Detach target from the swipe container first.
        newSplit.removeFromSuperview()

        // Add target to content container BEFORE removing the swipe container
        // to avoid a blank frame flash.
        newSplit.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(newSplit)
        NSLayoutConstraint.activate([
            newSplit.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            newSplit.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            newSplit.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            newSplit.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor),
        ])

        // Now remove the swipe container (other tabs get detached).
        swipeContainerView?.removeFromSuperview()
        swipeContainerView = nil

        newSplit.focusedSurface.map { window?.makeFirstResponder($0) }
        tabBarView.updateTabs(titles: tabs.map(\.title), selectedIndex: currentTabIndex)
        window?.title = tabs[targetIndex].title
    }

    func swipeCancelSession() {
        swipeEndSession(targetIndex: swipeStartIndex)
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

    @objc func gotoTab(_ sender: NSMenuItem) {
        let index = sender.tag - 1
        guard index >= 0, index < tabs.count else { return }
        selectTab(at: index, animated: true)
    }

    @objc func gotoSplit(_ sender: NSMenuItem) {
        let direction: ghostty_action_goto_split_e
        switch sender.tag {
        case 0: direction = GHOSTTY_GOTO_SPLIT_PREVIOUS
        case 1: direction = GHOSTTY_GOTO_SPLIT_NEXT
        case 2: direction = GHOSTTY_GOTO_SPLIT_UP
        case 3: direction = GHOSTTY_GOTO_SPLIT_LEFT
        case 4: direction = GHOSTTY_GOTO_SPLIT_DOWN
        case 5: direction = GHOSTTY_GOTO_SPLIT_RIGHT
        default: return
        }
        currentTab?.splitView.navigateToSplit(direction: direction)
    }

    // MARK: - Fullscreen

    // MARK: - Fullscreen

    func windowWillEnterFullScreen(_ notification: Notification) {
        tabBarView.setFullscreen(true)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        tabBarView.setFullscreen(false)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
    }
}
