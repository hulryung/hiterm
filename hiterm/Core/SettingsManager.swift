import AppKit
import GhosttyKit
import Combine

/// Bridges @AppStorage settings to ghostty config.
/// When settings change, writes a config file and reloads ghostty.
class SettingsManager {
    static let shared = SettingsManager()

    private var observers: [AnyCancellable] = []

    /// Path to hiterm's user settings config file.
    var userConfigPath: String {
        let dir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        let appDir = (dir as NSString).appendingPathComponent("hiterm")
        try? FileManager.default.createDirectory(atPath: appDir, withIntermediateDirectories: true)
        return (appDir as NSString).appendingPathComponent("config")
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
        // Ensure config file exists.
        if !FileManager.default.fileExists(atPath: userConfigPath) {
            FileManager.default.createFile(atPath: userConfigPath, contents: nil)
        }

        // Listen for UserDefaults changes on our keys.
        let defaults = UserDefaults.standard
        for key in keyMap.keys {
            defaults.publisher(for: key)
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.syncToConfig() }
                .store(in: &observers)
        }
    }

    /// Write current @AppStorage values to the hiterm config file
    /// and reload ghostty config.
    func syncToConfig() {
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

        // Write config file.
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: userConfigPath, atomically: true, encoding: .utf8)

        // Reload ghostty config.
        reloadGhosttyConfig()
    }

    /// Reload ghostty config from files and apply to the running app.
    func reloadGhosttyConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let ghosttyApp = appDelegate.ghosttyAppInstance else { return }

        guard let cfg = ghostty_config_new() else { return }
        ghostty_config_load_default_files(cfg)

        // Load our bundle config (shader settings).
        if let bundleConfig = Bundle.main.path(forResource: "ghostty-config", ofType: nil) {
            ghostty_config_load_file(cfg, bundleConfig)
        }

        // Load user settings on top.
        ghostty_config_load_file(cfg, userConfigPath)

        ghostty_config_finalize(cfg)

        if let app = ghosttyApp.app {
            ghostty_app_update_config(app, cfg)
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
}

// KVO publisher for UserDefaults
extension UserDefaults {
    func publisher(for key: String) -> AnyPublisher<Any?, Never> {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: self)
            .map { _ in self.object(forKey: key) }
            .eraseToAnyPublisher()
    }
}
