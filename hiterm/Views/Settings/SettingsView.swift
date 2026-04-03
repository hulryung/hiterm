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
    @State private var themes: [String] = []

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
        let searchPaths = [
            NSHomeDirectory() + "/dev/ghostty-src/zig-out/share/ghostty/themes",
            NSHomeDirectory() + "/.config/ghostty/themes",
            "/usr/local/share/ghostty/themes",
            "/opt/homebrew/share/ghostty/themes",
        ]
        for path in searchPaths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                themes = files.sorted()
                return
            }
        }
        themes = ["Dracula", "Solarized Dark", "Solarized Light", "Monokai",
                   "Nord", "Gruvbox Dark", "Gruvbox Light", "One Dark", "Tokyo Night"]
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

struct SearchablePicker<RowContent: View>: View {
    @Binding var selection: String
    let items: [String]
    let placeholder: String
    let rowContent: (String) -> RowContent

    @State private var searchText = ""
    @State private var isExpanded = false

    private var filteredItems: [String] {
        if searchText.isEmpty { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Selected value button
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
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
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredItems, id: \.self) { item in
                                Button(action: {
                                    selection = item
                                    searchText = ""
                                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded = false }
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
                                .background(item == selection ? Color.accentColor.opacity(0.1) : Color.clear)
                            }
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
    }
}
