import SwiftUI

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
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            KeybindingsSettingsView()
                .tabItem {
                    Label("Keybindings", systemImage: "keyboard")
                }
                .tag(SettingsTab.keybindings)
        }
        .frame(width: 480, height: 360)
        .padding()
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("shell") private var shell = "/bin/bash"
    @AppStorage("scrollbackLines") private var scrollbackLines = 10000
    @AppStorage("cursorStyle") private var cursorStyle = "block"

    var body: some View {
        Form {
            Section("Shell") {
                TextField("Shell path:", text: $shell)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Scrollback") {
                HStack {
                    Text("Lines:")
                    TextField("", value: $scrollbackLines, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            Section("Cursor") {
                Picker("Style:", selection: $cursorStyle) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage("fontFamily") private var fontFamily = "JetBrains Mono"
    @AppStorage("fontSize") private var fontSize = 14.0
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("windowOpacity") private var windowOpacity = 1.0

    var body: some View {
        Form {
            Section("Font") {
                HStack {
                    TextField("Family:", text: $fontFamily)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Size: \(Int(fontSize))pt", value: $fontSize, in: 8...36, step: 1)
                }
            }

            Section("Theme") {
                Picker("Color scheme:", selection: $theme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
            }

            Section("Window") {
                HStack {
                    Text("Opacity:")
                    Slider(value: $windowOpacity, in: 0.5...1.0, step: 0.05)
                    Text("\(Int(windowOpacity * 100))%")
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
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
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        }
    }
}
