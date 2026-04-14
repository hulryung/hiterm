import AppKit
import GhosttyKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var ghosttyApp: GhosttyApp!
    private var windowControllers: [MainWindowController] = []
    private var selectTabItems: [NSMenuItem] = []

    var ghosttyAppInstance: GhosttyApp? { ghosttyApp }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        ghosttyApp = GhosttyApp()
        guard ghosttyApp.isReady else {
            print("Failed to initialize Ghostty app")
            NSApp.terminate(nil)
            return
        }

        // Initialize settings manager and load defaults.
        if let config = ghosttyApp.config {
            SettingsManager.shared.loadInitialSettings(from: config)
        }

        setupMainMenu()

        let wc = MainWindowController(ghosttyApp: ghosttyApp)
        windowControllers.append(wc)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        let wc = MainWindowController(ghosttyApp: ghosttyApp)
        windowControllers.append(wc)
        wc.showWindow(nil)
    }

    func newWindowWithTab(splitView: TerminalSplitView, title: String) {
        let wc = MainWindowController(ghosttyApp: ghosttyApp, existingTab: (splitView: splitView, title: title))
        windowControllers.append(wc)
        wc.showWindow(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About hiterm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit hiterm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Shell menu
        let shellMenuItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "New Tab", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t")
        shellMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeTab(_:)), keyEquivalent: "w")
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Split Horizontally", action: #selector(MainWindowController.splitHorizontally(_:)), keyEquivalent: "d")
        shellMenu.addItem(withTitle: "Split Vertically", action: #selector(MainWindowController.splitVertically(_:)), keyEquivalent: "D")
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .control]
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        // Tabs section
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Show Previous Tab", action: #selector(MainWindowController.previousTab(_:)), keyEquivalent: "[")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(withTitle: "Show Next Tab", action: #selector(MainWindowController.nextTab(_:)), keyEquivalent: "]")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        selectTabItems.removeAll()
        for i in 1...9 {
            let item = NSMenuItem(
                title: "Select Tab \(i)",
                action: #selector(MainWindowController.gotoTab(_:)),
                keyEquivalent: "\(i)")
            item.keyEquivalentModifierMask = [.command]
            item.tag = i
            windowMenu.addItem(item)
            selectTabItems.append(item)
        }

        // Splits section
        windowMenu.addItem(.separator())
        let splitItems: [(String, String, NSEvent.ModifierFlags, Int)] = [
            ("Select Split Above", "\u{F700}", [.command, .option], 2),
            ("Select Split Below", "\u{F701}", [.command, .option], 4),
            ("Select Split Left",  "\u{F702}", [.command, .option], 3),
            ("Select Split Right", "\u{F703}", [.command, .option], 5),
            ("Select Previous Split", "[", [.command], 0),
            ("Select Next Split",     "]", [.command], 1)
        ]
        for (title, key, mods, tag) in splitItems {
            let item = NSMenuItem(
                title: title,
                action: #selector(MainWindowController.gotoSplit(_:)),
                keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.tag = tag
            windowMenu.addItem(item)
        }

        windowMenu.delegate = self

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !selectTabItems.isEmpty, menu === selectTabItems.first?.menu else { return }
        let tabCount = (NSApp.keyWindow?.windowController as? MainWindowController)?.tabCount ?? 0
        for item in selectTabItems {
            item.isHidden = item.tag > tabCount
        }
    }
}
