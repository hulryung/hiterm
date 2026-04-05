import AppKit
import GhosttyKit
import Combine

/// Bridges @AppStorage settings to ghostty config.
/// When settings change, writes a config file and reloads ghostty.
class SettingsManager {
    static let shared = SettingsManager()

    private var observers: [AnyCancellable] = []
    private var fileWatcher: DispatchSourceFileSystemObject?

    /// Path to hiterm's user settings config file (~/.config/hiterm/config).
    var userConfigPath: String {
        let configDir = NSHomeDirectory() + "/.config/hiterm"
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        return configDir + "/config"
    }

    /// Mapping from @AppStorage keys to ghostty config keys.
    private let keyMap: [String: String] = [
        "fontFamily": "font-family",
        "fontSize": "font-size",
        "theme": "theme",
        "cursorStyle": "cursor-style",
        "scrollbackLines": "scrollback-limit",
        "windowOpacity": "background-opacity",
    ]

    private init() {
        // Migrate from old location if needed.
        migrateConfigIfNeeded()

        // Ensure config file exists.
        if !FileManager.default.fileExists(atPath: userConfigPath) {
            FileManager.default.createFile(atPath: userConfigPath, contents: nil)
        }

        Log.config.info("Config path: \(self.userConfigPath)")

        // Listen for UserDefaults changes on our keys.
        // Slider-driven keys (opacity) use DispatchQueue.main so the debounce
        // fires during event-tracking runloop mode (i.e. while dragging a slider).
        // Other keys use RunLoop.main with a longer debounce.
        let defaults = UserDefaults.standard
        let fastKeys: Set<String> = ["windowOpacity"]
        for key in keyMap.keys {
            if fastKeys.contains(key) {
                defaults.publisher(for: key)
                    .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self, !self.suppressSync else { return }
                        self.syncToConfig()
                    }
                    .store(in: &observers)
            } else {
                defaults.publisher(for: key)
                    .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                    .sink { [weak self] _ in
                        guard let self, !self.suppressSync else { return }
                        self.syncToConfig()
                    }
                    .store(in: &observers)
            }
        }

        // Watch config file for external edits.
        startFileWatcher()
    }

    /// Flag to prevent reload loops when we write the file ourselves.
    private var suppressFileWatch = false
    /// Flag to prevent syncToConfig loops when reloadGhosttyConfig triggers UserDefaults changes.
    private var suppressSync = false

    private func startFileWatcher() {
        let path = userConfigPath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Log.config.error("File watcher: failed to open \(path)")
            return
        }

        Log.config.info("File watcher: watching \(path) (fd=\(fd))")

        // Watch for write (in-place edit), delete, rename (atomic save), and revoke.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Log.config.debug("File watcher: event=\(event.rawValue)")

            if self.suppressFileWatch {
                Log.config.debug("File watcher: event suppressed (self-write)")
                // Still restart watcher if file was replaced.
                if event.contains(.delete) || event.contains(.rename) {
                    source.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.startFileWatcher()
                    }
                }
                return
            }

            Log.config.info("File watcher: change detected, reloading config")
            self.suppressSync = true
            self.reloadGhosttyConfig()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.suppressSync = false
            }

            // If the file was replaced (atomic save), restart the watcher
            // on the new file since the old fd is now invalid.
            if event.contains(.delete) || event.contains(.rename) {
                Log.config.debug("File watcher: file replaced, restarting watcher")
                source.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.startFileWatcher()
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileWatcher = source
    }

    /// Keys managed by the Settings UI — these are always written from @AppStorage.
    private let managedKeys: Set<String> = [
        "font-family", "font-size", "cursor-style",
        "scrollback-limit", "background-opacity", "theme",
    ]

    /// Write current @AppStorage values to the hiterm config file
    /// and reload ghostty config. Preserves non-UI settings already in the file.
    func syncToConfig(extraLines: [String]? = nil) {
        let defaults = UserDefaults.standard
        var lines: [String] = []

        // Font
        let fontFamily = defaults.string(forKey: "fontFamily") ?? "JetBrains Mono"
        lines.append("font-family = \(fontFamily)")

        let fontSize = defaults.double(forKey: "fontSize")
        if fontSize > 0 {
            lines.append("font-size = \(Int(fontSize))")
        }

        // Cursor
        let cursorStyle = defaults.string(forKey: "cursorStyle") ?? "block"
        lines.append("cursor-style = \(cursorStyle)")

        // Scrollback
        let scrollback = defaults.integer(forKey: "scrollbackLines")
        if scrollback > 0 {
            lines.append("scrollback-limit = \(scrollback)")
        }

        // Opacity
        let opacity = defaults.double(forKey: "windowOpacity")
        if opacity > 0 {
            lines.append("background-opacity = \(String(format: "%.2f", opacity))")
        }

        // Theme
        let theme = defaults.string(forKey: "theme") ?? ""
        if !theme.isEmpty && theme != "dark" {
            lines.append("theme = \(theme)")
        }

        // Preserve non-UI settings from existing config file.
        if let existing = try? String(contentsOfFile: userConfigPath, encoding: .utf8) {
            for line in existing.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                if !managedKeys.contains(key) {
                    lines.append(trimmed)
                }
            }
        }

        // Append extra lines from import (replaces any duplicates from above).
        if let extra = extraLines {
            let extraKeys = Set(extra.compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1)
                return parts.first.map { String($0).trimmingCharacters(in: .whitespaces) }
            })
            lines = lines.filter { line in
                let parts = line.split(separator: "=", maxSplits: 1)
                guard let key = parts.first.map({ String($0).trimmingCharacters(in: .whitespaces) }) else { return true }
                return !extraKeys.contains(key)
            }
            lines.append(contentsOf: extra)
        }

        // Write config file (suppress file watcher to avoid reload loop).
        let content = lines.joined(separator: "\n") + "\n"
        suppressFileWatch = true
        do {
            try content.write(toFile: userConfigPath, atomically: true, encoding: .utf8)
            Log.config.info("syncToConfig: wrote \(lines.count) lines to config")
        } catch {
            Log.config.error("syncToConfig: failed to write config: \(error)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressFileWatch = false
        }

        // Reload ghostty config.
        reloadGhosttyConfig()
    }

    /// Reload ghostty config from files and apply to the running app.
    func reloadGhosttyConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let ghosttyApp = appDelegate.ghosttyAppInstance else {
            Log.config.warning("reloadGhosttyConfig: app delegate or ghostty app not available")
            return
        }

        guard let cfg = ghostty_config_new() else {
            Log.config.error("reloadGhosttyConfig: ghostty_config_new() failed")
            return
        }

        // Load our bundle config (shader settings) — no ghostty defaults.
        if let bundleConfig = Bundle.main.path(forResource: "ghostty-config", ofType: nil) {
            ghostty_config_load_file(cfg, bundleConfig)
        }

        // Load user settings on top.
        ghostty_config_load_file(cfg, userConfigPath)

        ghostty_config_finalize(cfg)

        if let app = ghosttyApp.app {
            ghostty_app_update_config(app, cfg)
            Log.config.info("reloadGhosttyConfig: config applied to running app")
            NotificationCenter.default.post(name: .hitermConfigReloaded, object: nil)
        }

        ghostty_config_free(cfg)
    }

    /// Load initial settings from ghostty config into @AppStorage.
    func loadInitialSettings(from config: ghostty_config_t) {
        let defaults = UserDefaults.standard

        // Only set defaults if user hasn't customized yet.
        if defaults.object(forKey: "fontFamily") == nil {
            defaults.set("JetBrains Mono", forKey: "fontFamily")
        }
        if defaults.object(forKey: "fontSize") == nil {
            defaults.set(14.0, forKey: "fontSize")
        }
        if defaults.object(forKey: "cursorStyle") == nil {
            defaults.set("block", forKey: "cursorStyle")
        }
        if defaults.object(forKey: "scrollbackLines") == nil {
            defaults.set(10000, forKey: "scrollbackLines")
        }
        if defaults.object(forKey: "windowOpacity") == nil {
            defaults.set(1.0, forKey: "windowOpacity")
        }
        if defaults.object(forKey: "theme") == nil {
            defaults.set("dark", forKey: "theme")
        }
    }

    /// Migrate config from old ~/Library/Application Support/hiterm/config location.
    private func migrateConfigIfNeeded() {
        let oldDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        let oldPath = (oldDir as NSString).appendingPathComponent("hiterm/config")
        let newPath = userConfigPath

        guard FileManager.default.fileExists(atPath: oldPath),
              !FileManager.default.fileExists(atPath: newPath) else { return }

        try? FileManager.default.copyItem(atPath: oldPath, toPath: newPath)
        try? FileManager.default.removeItem(atPath: oldPath)
        Log.config.info("Migrated config from \(oldPath) to \(newPath)")
    }

    /// Path to Ghostty's user config file.
    static var ghosttyConfigPath: String {
        NSHomeDirectory() + "/.config/ghostty/config"
    }

    /// Ghostty config keys to skip during import.
    /// These are platform-specific or have no meaning in hiterm.
    private static let skipKeys: Set<String> = [
        // Linux/Windows platform-specific
        "gtk-single-instance", "gtk-tabs-location", "gtk-wide-tabs",
        "gtk-adwaita", "gtk-toolbar-style",
        "x11-direct-color",
        "wayland-app-id",
        "linux-cgroup",
        // macOS app-specific (hiterm manages these itself)
        "macos-non-native-fullscreen", "macos-titlebar-style",
        "macos-titlebar-proxy-icon", "macos-option-as-alt",
        "macos-window-shadow", "macos-auto-secure-input",
        "macos-secure-input-indication", "macos-icon",
        "macos-icon-frame", "macos-icon-ghost-color",
        "macos-icon-screen-color",
        // Shell integration handled by hiterm
        "shell-integration", "shell-integration-features",
        // Config management
        "config-file",
    ]

    /// Import settings from Ghostty's config file, overwriting current hiterm settings.
    /// Imports all settings except platform-specific ones (gtk-*, x11-*, macos-*, etc.).
    func importFromGhostty() -> Bool {
        let path = Self.ghosttyConfigPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }

        let defaults = UserDefaults.standard
        let uiKeyMap: [String: (String) -> Void] = [
            "font-family": { defaults.set($0, forKey: "fontFamily") },
            "font-size": { defaults.set(Double($0) ?? 14.0, forKey: "fontSize") },
            "cursor-style": { defaults.set($0, forKey: "cursorStyle") },
            "scrollback-limit": { defaults.set(Int($0) ?? 10000, forKey: "scrollbackLines") },
            "background-opacity": { defaults.set(Double($0) ?? 1.0, forKey: "windowOpacity") },
            "theme": { defaults.set($0, forKey: "theme") },
            "command": { defaults.set($0, forKey: "shell") },
        ]

        var extraLines: [String] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if Self.skipKeys.contains(key) { continue }

            if let apply = uiKeyMap[key] {
                apply(value)
            }
            if !managedKeys.contains(key) {
                extraLines.append("\(key) = \(value)")
            }
        }

        Log.config.info("importFromGhostty: imported \(extraLines.count) extra settings from Ghostty")
        syncToConfig(extraLines: extraLines)
        return true
    }
}

// KVO publisher for UserDefaults
extension UserDefaults {
    func publisher(for key: String) -> AnyPublisher<Any?, Never> {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: self)
            .map { _ in self.object(forKey: key) }
            .eraseToAnyPublisher()
    }
}
