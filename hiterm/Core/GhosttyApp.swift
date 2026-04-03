import AppKit
import GhosttyKit

/// Wraps the ghostty_app_t lifecycle and manages runtime callbacks.
class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    var isReady: Bool { app != nil }

    init() {
        Log.ghostty.info("GhosttyApp init starting")
        // Create and finalize config — hiterm-only, do NOT load ghostty defaults.
        guard let cfg = ghostty_config_new() else {
            Log.ghostty.error("ghostty_config_new() failed")
            return
        }

        // Load hiterm-specific config (smooth scroll shader).
        if let configPath = Bundle.main.path(forResource: "ghostty-config", ofType: nil) {
            ghostty_config_load_file(cfg, configPath)
        }

        // Load user settings (from Settings UI).
        let userConfig = SettingsManager.shared.userConfigPath
        if FileManager.default.fileExists(atPath: userConfig) {
            ghostty_config_load_file(cfg, userConfig)
        }

        ghostty_config_finalize(cfg)
        self.config = cfg

        // Create runtime config with callbacks
        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = { ud in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async { app.wakeup() }
        }
        runtime.action_cb = { ghosttyApp, target, action in
            guard let ud = ghostty_app_userdata(ghosttyApp) else { return false }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            return app.handleAction(target: target, action: action)
        }
        runtime.read_clipboard_cb = { ud, loc, state in
            guard let ud else { return false }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            return app.readClipboard(location: loc, state: state)
        }
        runtime.confirm_read_clipboard_cb = { _, _, _, _ in
            // Auto-confirm clipboard reads
        }
        runtime.write_clipboard_cb = { ud, loc, content, count, _ in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            app.writeClipboard(location: loc, content: content, count: count)
        }
        runtime.close_surface_cb = { ud, processAlive in
            guard let ud else { return }
            // ud is the surface's userdata (TerminalSurfaceView pointer).
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .hitermCloseSurface,
                    object: ud,
                    userInfo: ["processAlive": processAlive]
                )
            }
        }

        self.app = ghostty_app_new(&runtime, cfg)
        if self.app != nil {
            Log.ghostty.info("GhosttyApp init complete")
        } else {
            Log.ghostty.error("ghostty_app_new() returned nil")
        }
    }

    deinit {
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }

    // MARK: - Runtime Callbacks

    private func wakeup() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_NEW_TAB:
            NotificationCenter.default.post(name: .hitermNewTab, object: nil)
            return true

        case GHOSTTY_ACTION_NEW_SPLIT:
            let direction = action.action.new_split
            NotificationCenter.default.post(
                name: .hitermNewSplit,
                object: nil,
                userInfo: ["direction": direction]
            )
            return true

        case GHOSTTY_ACTION_CLOSE_TAB:
            NotificationCenter.default.post(name: .hitermCloseTab, object: nil)
            return true

        case GHOSTTY_ACTION_GOTO_TAB:
            let tab = action.action.goto_tab
            NotificationCenter.default.post(
                name: .hitermGotoTab,
                object: nil,
                userInfo: ["tab": tab]
            )
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            let split = action.action.goto_split
            NotificationCenter.default.post(
                name: .hitermGotoSplit,
                object: nil,
                userInfo: ["direction": split]
            )
            return true

        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            NotificationCenter.default.post(name: .hitermToggleFullscreen, object: nil)
            return true

        case GHOSTTY_ACTION_SET_TITLE:
            if target.tag == GHOSTTY_TARGET_SURFACE {
                let surface = target.target.surface
                let title = action.action.set_title.title.flatMap { String(cString: $0) } ?? ""
                // Pass surface pointer as userdata via userInfo (not object)
                // because NotificationCenter can lose UnsafeMutableRawPointer as object.
                let surfaceUD = ghostty_surface_userdata(surface)
                NotificationCenter.default.post(
                    name: .hitermSetTitle,
                    object: nil,
                    userInfo: ["title": title, "userdata": surfaceUD as Any]
                )
            }
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            return true

        case GHOSTTY_ACTION_RENDER:
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            if target.tag == GHOSTTY_TARGET_SURFACE {
                let shape = action.action.mouse_shape
                NotificationCenter.default.post(
                    name: .hitermMouseShape,
                    object: target.target.surface,
                    userInfo: ["shape": shape]
                )
            }
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            let visible = action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE
            if visible {
                NSCursor.unhide()
            } else {
                NSCursor.hide()
            }
            return true

        case GHOSTTY_ACTION_SCROLLBAR:
            return true

        case GHOSTTY_ACTION_SIZE_LIMIT:
            return true

        case GHOSTTY_ACTION_INITIAL_SIZE:
            return true

        case GHOSTTY_ACTION_PRESENT_TERMINAL:
            return true

        case GHOSTTY_ACTION_PWD:
            if target.tag == GHOSTTY_TARGET_SURFACE {
                let surface = target.target.surface
                if let pwdPtr = action.action.pwd.pwd {
                    var pwd = String(cString: pwdPtr)
                    // Show only last path component for cleaner tab title.
                    if let lastComponent = pwd.split(separator: "/").last {
                        pwd = String(lastComponent)
                    }
                    let surfaceUD = ghostty_surface_userdata(surface)
                    NotificationCenter.default.post(
                        name: .hitermSetTitle,
                        object: nil,
                        userInfo: ["title": pwd, "userdata": surfaceUD as Any]
                    )
                }
            }
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            return true

        case GHOSTTY_ACTION_OPEN_CONFIG:
            return true

        case GHOSTTY_ACTION_RELOAD_CONFIG:
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            NotificationCenter.default.post(name: .hitermNewWindow, object: nil)
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            NotificationCenter.default.post(name: .hitermCloseWindow, object: nil)
            return true

        case GHOSTTY_ACTION_QUIT:
            NSApp.terminate(nil)
            return true

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            NotificationCenter.default.post(name: .hitermEqualizeSplits, object: nil)
            return true

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            let resize = action.action.resize_split
            NotificationCenter.default.post(
                name: .hitermResizeSplit,
                object: nil,
                userInfo: ["direction": resize.direction, "amount": resize.amount]
            )
            return true

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            NotificationCenter.default.post(name: .hitermToggleSplitZoom, object: nil)
            return true

        case GHOSTTY_ACTION_MOVE_TAB:
            let amount = action.action.move_tab.amount
            NotificationCenter.default.post(
                name: .hitermMoveTab,
                object: nil,
                userInfo: ["amount": amount]
            )
            return true

        case GHOSTTY_ACTION_RESET_WINDOW_SIZE:
            NotificationCenter.default.post(name: .hitermResetWindowSize, object: nil)
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            if let urlPtr = action.action.open_url.url {
                let len = action.action.open_url.len
                let url = String(cString: urlPtr)
                if let nsUrl = URL(string: url) {
                    NSWorkspace.shared.open(nsUrl)
                }
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        case GHOSTTY_ACTION_TOGGLE_MAXIMIZE:
            NSApp.keyWindow?.zoom(nil)
            return true

        case GHOSTTY_ACTION_SET_TAB_TITLE:
            return true

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            return true

        case GHOSTTY_ACTION_KEY_SEQUENCE:
            return true

        case GHOSTTY_ACTION_READONLY:
            return true

        case GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD:
            return true

        case GHOSTTY_ACTION_PROGRESS_REPORT:
            return true

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            return true

        default:
            return false
        }
    }

    private func readClipboard(location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let str = pasteboard.string(forType: .string) else { return false }

        // The `ud` parameter in the callback is the surface's userdata (our TerminalSurfaceView).
        // We need to find the surface from it. The `state` is an opaque completion token
        // that must be passed back to ghostty_surface_complete_clipboard_request.
        // Since we receive `ud` (GhosttyApp userdata, i.e. self), we need to find the
        // focused surface through the notification system or by storing a reference.
        // For now, find the surface via the key window's first responder.
        guard let surfaceView = NSApp.keyWindow?.firstResponder as? TerminalSurfaceView,
              let surface = surfaceView.surface else { return false }

        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
        }
        return true
    }

    private func writeClipboard(
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int
    ) {
        guard let content, count > 0 else { return }
        let firstContent = content.pointee
        guard let data = firstContent.data else { return }
        let str = String(cString: data)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(str, forType: .string)
    }

}

// MARK: - Notification Names

extension Notification.Name {
    static let hitermNewTab = Notification.Name("hitermNewTab")
    static let hitermCloseTab = Notification.Name("hitermCloseTab")
    static let hitermGotoTab = Notification.Name("hitermGotoTab")
    static let hitermNewSplit = Notification.Name("hitermNewSplit")
    static let hitermGotoSplit = Notification.Name("hitermGotoSplit")
    static let hitermToggleFullscreen = Notification.Name("hitermToggleFullscreen")
    static let hitermSetTitle = Notification.Name("hitermSetTitle")
    static let hitermMouseShape = Notification.Name("hitermMouseShape")
    static let hitermCloseSurface = Notification.Name("hitermCloseSurface")
    static let hitermSwipePrevTab = Notification.Name("hitermSwipePrevTab")
    static let hitermSwipeNextTab = Notification.Name("hitermSwipeNextTab")
    static let hitermNewWindow = Notification.Name("hitermNewWindow")
    static let hitermCloseWindow = Notification.Name("hitermCloseWindow")
    static let hitermEqualizeSplits = Notification.Name("hitermEqualizeSplits")
    static let hitermResizeSplit = Notification.Name("hitermResizeSplit")
    static let hitermToggleSplitZoom = Notification.Name("hitermToggleSplitZoom")
    static let hitermMoveTab = Notification.Name("hitermMoveTab")
    static let hitermResetWindowSize = Notification.Name("hitermResetWindowSize")
}
