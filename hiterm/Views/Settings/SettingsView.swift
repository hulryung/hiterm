import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case keybindings = "Keybindings"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            KeybindingsSettingsView()
                .tabItem { Label("Keybindings", systemImage: "keyboard") }
                .tag(SettingsTab.keybindings)
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("shell") private var shell = "/bin/bash"
    @AppStorage("scrollbackLines") private var scrollbackLines = 10000
    @AppStorage("cursorStyle") private var cursorStyle = "block"
    @State private var showImportConfirm = false
    @State private var showImportResult = false
    @State private var importSuccess = false

    var body: some View {
        Form {
            Section("Shell") {
                LabeledContent("Path") {
                    TextField("", text: $shell)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
            }

            Section("Scrollback") {
                LabeledContent("Lines") {
                    TextField("", value: $scrollbackLines, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            Section("Cursor") {
                LabeledContent("Style") {
                    Picker("", selection: $cursorStyle) {
                        Text("Block").tag("block")
                        Text("Bar").tag("bar")
                        Text("Underline").tag("underline")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }

            Section("Config File") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit config directly")
                        Text("~/.config/hiterm/config")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Open in Editor") {
                        let path = SettingsManager.shared.userConfigPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
            }

            Section("Import") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Ghostty")
                        Text("~/.config/ghostty/config")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Import...") {
                        showImportConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Import Ghostty Settings", isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Import", role: .destructive) {
                importSuccess = SettingsManager.shared.importFromGhostty()
                showImportResult = true
            }
        } message: {
            Text("This will overwrite your current hiterm settings (font, theme, cursor, etc.) with values from Ghostty's config. This cannot be undone.")
        }
        .alert(importSuccess ? "Import Complete" : "Import Failed", isPresented: $showImportResult) {
            Button("OK") {}
        } message: {
            Text(importSuccess
                ? "Ghostty settings have been imported. Restart hiterm to apply all changes."
                : "Could not find Ghostty config at ~/.config/ghostty/config")
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage("fontFamily") private var fontFamily = "JetBrains Mono"
    @AppStorage("fontSize") private var fontSize = 14.0
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("windowOpacity") private var windowOpacity = 1.0

    @State private var monoFonts: [String] = []
    @State private var allFonts: [String] = []
    @AppStorage("fontMonoOnly") private var monoOnly = true
    @State private var themes: [String] = []
    @State private var themesDir: String?

    var body: some View {
        Form {
            Section("Font") {
                LabeledContent("Family") {
                    SearchablePicker(
                        selection: $fontFamily,
                        items: monoFonts,
                        placeholder: "Search fonts…"
                    ) { font in
                        HStack(spacing: 8) {
                            Text("Ag")
                                .font(.custom(font, size: 13))
                                .frame(width: 28, alignment: .center)
                                .foregroundColor(.secondary)
                            Text(font).font(.system(size: 12))
                        }
                    }
                    .frame(width: 280)
                }

                LabeledContent("Size") {
                    HStack(spacing: 8) {
                        TextField("", value: $fontSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Stepper("", value: $fontSize, in: 8...36, step: 1)
                            .labelsHidden()
                        Text("pt")
                            .foregroundColor(.secondary)
                    }
                }

                // Preview
                HStack {
                    Spacer()
                    Text("The quick brown fox jumps over the lazy dog")
                        .font(.custom(fontFamily, size: fontSize))
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    Spacer()
                }
            }

            Section("Theme") {
                LabeledContent("Color theme") {
                    SearchablePicker(
                        selection: $theme,
                        items: themes,
                        placeholder: "Search themes…"
                    ) { theme in
                        Text(theme).font(.system(size: 12))
                    }
                    .frame(width: 280)
                }

                ThemePreviewView(themeName: theme, themesDir: themesDir)
            }

            Section("Window") {
                LabeledContent("Opacity") {
                    HStack(spacing: 8) {
                        Slider(value: $windowOpacity, in: 0.3...1.0, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int(windowOpacity * 100))%")
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadMonoFonts()
            loadThemes()
        }
    }

    private func loadMonoFonts() {
        let manager = NSFontManager.shared
        monoFonts = manager.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 13) else { return false }
            return font.isFixedPitch
                || family.localizedCaseInsensitiveContains("mono")
                || family.localizedCaseInsensitiveContains("code")
                || family.localizedCaseInsensitiveContains("consol")
                || family.localizedCaseInsensitiveContains("courier")
                || family.localizedCaseInsensitiveContains("menlo")
                || family.localizedCaseInsensitiveContains("terminal")
        }.sorted()
    }

    private func loadThemes() {
        var searchPaths: [String] = []

        // App bundle themes (bundled during build from libghostty resources).
        if let bundlePath = Bundle.main.resourcePath {
            searchPaths.append(bundlePath + "/ghostty/themes")
        }

        // User custom themes and system-installed ghostty themes.
        searchPaths.append(contentsOf: [
            NSHomeDirectory() + "/.config/ghostty/themes",
            "/usr/local/share/ghostty/themes",
            "/opt/homebrew/share/ghostty/themes",
        ])

        for path in searchPaths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                let themeFiles = files.filter { !$0.hasPrefix(".") }
                if !themeFiles.isEmpty {
                    themes = themeFiles.sorted()
                    themesDir = path
                    return
                }
            }
        }
        themes = []
    }
}

// MARK: - Theme Preview

private struct ThemeColors {
    var background: NSColor = .black
    var foreground: NSColor = .white
    var cursor: NSColor = .white
    var palette: [NSColor] = Array(repeating: .white, count: 16)

    static func parse(from path: String) -> ThemeColors? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var colors = ThemeColors()
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background": colors.background = NSColor(hex: value) ?? .black
            case "foreground": colors.foreground = NSColor(hex: value) ?? .white
            case "cursor-color": colors.cursor = NSColor(hex: value) ?? .white
            case "palette":
                let sub = value.split(separator: "=", maxSplits: 1)
                if sub.count == 2,
                   let idx = Int(sub[0].trimmingCharacters(in: .whitespaces)),
                   (0..<16).contains(idx),
                   let c = NSColor(hex: String(sub[1].trimmingCharacters(in: .whitespaces))) {
                    colors.palette[idx] = c
                }
            default: break
            }
        }
        return colors
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255,
            green: CGFloat((val >> 8) & 0xFF) / 255,
            blue: CGFloat(val & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct ThemePreviewView: View {
    let themeName: String
    let themesDir: String?
    @AppStorage("fontFamily") private var fontFamily = "JetBrains Mono"

    private var colors: ThemeColors {
        guard let dir = themesDir else { return ThemeColors() }
        return ThemeColors.parse(from: "\(dir)/\(themeName)") ?? ThemeColors()
    }

    var body: some View {
        let c = colors
        let font = Font.custom(fontFamily, size: 11)
        let bg = Color(nsColor: c.background)
        let fg = Color(nsColor: c.foreground)

        VStack(alignment: .leading, spacing: 0) {
            // Line 1: prompt
            HStack(spacing: 0) {
                Text("~/projects ").font(font).foregroundColor(Color(nsColor: c.palette[4]))
                Text("$ ").font(font).foregroundColor(Color(nsColor: c.palette[2]))
                Text("ls -la").font(font).foregroundColor(fg)
            }
            .padding(.bottom, 2)

            // Line 2-4: file listing
            HStack(spacing: 0) {
                Text("drwxr-xr-x  ").font(font).foregroundColor(fg)
                Text("Documents/").font(font).foregroundColor(Color(nsColor: c.palette[4]))
            }
            HStack(spacing: 0) {
                Text("-rw-r--r--  ").font(font).foregroundColor(fg)
                Text("README.md").font(font).foregroundColor(fg)
            }
            HStack(spacing: 0) {
                Text("-rwxr-xr-x  ").font(font).foregroundColor(fg)
                Text("build.sh").font(font).foregroundColor(Color(nsColor: c.palette[2]))
            }
            .padding(.bottom, 2)

            // Line 5: prompt with cursor
            HStack(spacing: 0) {
                Text("~/projects ").font(font).foregroundColor(Color(nsColor: c.palette[4]))
                Text("$ ").font(font).foregroundColor(Color(nsColor: c.palette[2]))
                Text(" ")
                    .font(font)
                    .background(Color(nsColor: c.cursor))
                    .frame(width: 7)
            }

            // Palette bar
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: c.palette[i]))
                        .frame(width: 16, height: 8)
                }
                Spacer().frame(width: 6)
                ForEach(8..<16, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: c.palette[i]))
                        .frame(width: 16, height: 8)
                }
            }
            .padding(.top, 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Keybindings

struct KeybindingsSettingsView: View {
    var body: some View {
        Form {
            Section("Tab Navigation") {
                KeybindingRow(action: "Next Tab", shortcut: "Cmd + →")
                KeybindingRow(action: "Previous Tab", shortcut: "Cmd + ←")
                KeybindingRow(action: "New Tab", shortcut: "Cmd + T")
                KeybindingRow(action: "Close Tab/Pane", shortcut: "Cmd + W")
            }

            Section("Split Panes") {
                KeybindingRow(action: "Split Horizontal", shortcut: "Cmd + D")
                KeybindingRow(action: "Split Vertical", shortcut: "Cmd + Shift + D")
            }

            Section("Window") {
                KeybindingRow(action: "New Window", shortcut: "Cmd + N")
                KeybindingRow(action: "Toggle Fullscreen", shortcut: "Ctrl + Cmd + F")
                KeybindingRow(action: "Settings", shortcut: "Cmd + ,")
            }
        }
        .formStyle(.grouped)
    }
}

struct KeybindingRow: View {
    let action: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
        }
    }
}

// MARK: - Searchable Picker (reusable)

/// Manages keyboard navigation state for SearchablePicker.
/// Uses a class so NSEvent monitor closures can read/write current state by reference.
private class PickerKeyHandler: ObservableObject {
    @Published var highlightedIndex = 0
    @Published var scrollTarget: String?
    var filteredItems: [String] = []
    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    private var monitor: Any?

    func install() {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.filteredItems.isEmpty else { return event }

            switch event.keyCode {
            case 125: // Down arrow
                let newIndex = min(self.highlightedIndex + 1, self.filteredItems.count - 1)
                self.highlightedIndex = newIndex
                self.onSelect?(self.filteredItems[newIndex])
                self.scrollTarget = self.filteredItems[newIndex]
                return nil
            case 126: // Up arrow
                let newIndex = max(self.highlightedIndex - 1, 0)
                self.highlightedIndex = newIndex
                self.onSelect?(self.filteredItems[newIndex])
                self.scrollTarget = self.filteredItems[newIndex]
                return nil
            case 36: // Return
                self.onDismiss?()
                return nil
            case 53: // Escape
                self.onDismiss?()
                return nil
            default:
                return event
            }
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func syncHighlight(to selection: String) {
        if let idx = filteredItems.firstIndex(of: selection) {
            highlightedIndex = idx
        } else {
            highlightedIndex = 0
        }
    }

    deinit { remove() }
}

struct SearchablePicker<RowContent: View>: View {
    @Binding var selection: String
    let items: [String]
    let placeholder: String
    let rowContent: (String) -> RowContent

    @State private var searchText = ""
    @State private var isExpanded = false
    @StateObject private var keyHandler = PickerKeyHandler()

    private var filteredItems: [String] {
        if searchText.isEmpty { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Selected value button
            Button(action: { toggleExpanded() }) {
                HStack {
                    Text(selection)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    // Search field
                    TextField(placeholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(6)

                    Divider()

                    // Scrollable list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element) { index, item in
                                    Button(action: {
                                        selection = item
                                        searchText = ""
                                        collapse()
                                    }) {
                                        HStack {
                                            rowContent(item)
                                            Spacer()
                                            if item == selection {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .background(
                                        index == keyHandler.highlightedIndex
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.clear
                                    )
                                    .id(item)
                                }
                            }
                        }
                        .onAppear {
                            updateKeyHandler()
                            if filteredItems.contains(selection) {
                                proxy.scrollTo(selection, anchor: .center)
                            }
                        }
                        .onChange(of: keyHandler.scrollTarget) { target in
                            if let target {
                                proxy.scrollTo(target, anchor: .center)
                                keyHandler.scrollTarget = nil
                            }
                        }
                        .onChange(of: searchText) { _ in
                            updateKeyHandler()
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .padding(.top, 2)
            }
        }
        .onDisappear { keyHandler.remove() }
    }

    private func updateKeyHandler() {
        keyHandler.filteredItems = filteredItems
        keyHandler.syncHighlight(to: selection)
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        if isExpanded {
            updateKeyHandler()
            keyHandler.onSelect = { item in selection = item }
            keyHandler.onDismiss = { collapse() }
            keyHandler.install()
        } else {
            keyHandler.remove()
        }
    }

    private func collapse() {
        searchText = ""
        withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
        keyHandler.remove()
    }
}
