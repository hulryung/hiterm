import AppKit
import GhosttyKit

/// Wraps the ghostty_app_t lifecycle and manages runtime callbacks.
class GhosttyApp {
    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?

    var isReady: Bool { app != nil }

    init() {
        // Create and finalize config
        guard let cfg = ghostty_config_new() else { return }
        ghostty_config_load_default_files(cfg)
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
        runtime.confirm_read_clipboard_cb = { _, _, state, _ in
            // Auto-confirm clipboard reads
            guard let state else { return }
        }
        runtime.write_clipboard_cb = { ud, loc, content, count, confirm in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            app.writeClipboard(location: loc, content: content, count: count)
        }
        runtime.close_surface_cb = { ud, processAlive in
            guard let ud else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()
            app.closeSurface(userdata: ud, processAlive: processAlive)
        }

        self.app = ghostty_app_new(&runtime, cfg)
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
                NotificationCenter.default.post(
                    name: .hitermSetTitle,
                    object: surface,
                    userInfo: ["title": title]
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

        default:
            return false
        }
    }

    private func readClipboard(location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) -> Bool {
        let pasteboard = NSPasteboard.general
        guard let str = pasteboard.string(forType: .string) else { return false }

        if let surface = state.map({ ghostty_surface_t(mutating: $0) }) {
            str.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
            }
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

    private func closeSurface(userdata: UnsafeMutableRawPointer, processAlive: Bool) {
        NotificationCenter.default.post(
            name: .hitermCloseSurface,
            object: nil,
            userInfo: ["processAlive": processAlive]
        )
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
}
