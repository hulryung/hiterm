# hiterm

A macOS-native terminal emulator built on libghostty.

## Project Structure

```
hiterm/
├── ghostty/           # git submodule (hulryung/ghostty fork)
├── hiterm/
│   ├── App/           # App entry point, AppDelegate
│   ├── Core/          # GhosttyBridge, TerminalSurface, Config
│   ├── Views/         # TabBarView, SplitView, SmoothScrollLayer, MainWindowController
│   └── Input/         # KeyboardHandler, MouseHandler, GestureHandler
├── libs/
│   └── GhosttyKit/    # libghostty build output (gitignored .a)
│       ├── include/
│       │   ├── ghostty.h
│       │   └── module.modulemap
│       └── lib/
│           └── libghostty.a
├── scripts/
│   └── build-libghostty.sh
├── docs/              # Requirements, architecture, build guide, implementation plan
├── project.yml        # xcodegen project spec
└── CLAUDE.md
```

## Tech Stack

- **Language**: Swift
- **UI**: AppKit + SwiftUI
- **Terminal engine**: libghostty (C ABI, MIT licensed)
- **Rendering**: Metal (built into libghostty)
- **Build**: xcodegen → Xcode

## Building

### Prerequisites

```bash
brew install zig cmake ninja xcodegen
xcodebuild -downloadComponent MetalToolchain
```

### Build libghostty

The Ghostty source is managed as a **git submodule** at `ghostty/`. Use the build script:

```bash
git submodule update --init    # first time only
./scripts/build-libghostty.sh
```

This builds the full libghostty (Metal renderer, fonts, etc.) via xcframework and copies artifacts to `libs/GhosttyKit/`.

**Note**: `-Demit-xcframework=true` is required. Without it, only `libghostty-vt.a` (~6MB, no renderer) is produced.

### Build hiterm

```bash
xcodegen generate
xcodebuild -scheme hiterm build
```

## Key Architecture Decisions

- libghostty handles terminal emulation, Metal rendering, PTY, and font management
- Swift/AppKit handles UI shell: tabs, splits, gestures, window management
- Swift imports libghostty via `import GhosttyKit` (module.modulemap)
- Smooth scrolling is implemented at the UI layer (pixel offset on CALayer) since libghostty only supports line-level scrolling
- Fullscreen mode detaches tabs into separate NSWindows so macOS maps each to its own Space

## Required Frameworks

AppKit, Metal, CoreFoundation, CoreGraphics, CoreText, CoreVideo, QuartzCore, IOSurface, Carbon

## Coding Conventions

- Swift source files use standard Swift naming conventions
- One type per file where practical
- libghostty C types are wrapped in Swift classes/structs in Core/
- Callbacks from libghostty use `Unmanaged<T>` for userdata pointer bridging

## Debugging

hiterm uses Apple's unified logging (`os.Logger`) with per-module categories defined in `hiterm/Core/Log.swift`.

### Log Categories

| Category | Module | What it covers |
|----------|--------|----------------|
| `config` | SettingsManager | File watching, config sync/reload, import |
| `surface` | TerminalSurfaceView | Surface creation, size/scale updates |
| `input` | KeyboardHandler etc. | Key/mouse/gesture events |
| `ui` | Window/Tab/Split views | Window management, tabs, splits |
| `ghostty` | GhosttyApp | App lifecycle, actions, callbacks |

### Viewing Logs

```bash
# All hiterm logs (debug level)
log stream --predicate 'subsystem=="com.hiterm.app"' --level debug

# Single module only
log stream --predicate 'subsystem=="com.hiterm.app" && category=="config"' --level debug
log stream --predicate 'subsystem=="com.hiterm.app" && category=="surface"' --level debug

# Multiple modules
log stream --predicate 'subsystem=="com.hiterm.app" && (category=="config" || category=="surface")' --level debug
```

### Verbose Mode (Environment Variable)

```bash
# Verbose logging for specific modules
HITERM_DEBUG=config,surface open hiterm.app

# All modules verbose
HITERM_DEBUG=all open hiterm.app
```

Check verbose flag in code: `Log.isVerbose("config")`

### Adding New Logs

```swift
Log.config.debug("Detail message")     // debug: filtered by default, zero cost in Release
Log.config.info("Important event")     // info: visible in log stream
Log.config.error("Something failed")   // error: always visible
```

## Ghostty Source Reference

The Ghostty source is at `ghostty/` (submodule). Key files:
- `ghostty/include/ghostty.h` — C API definition
- `ghostty/macos/Sources/Ghostty/Ghostty.App.swift` — App initialization pattern
- `ghostty/macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — Surface/input handling pattern
- `ghostty/macos/Sources/Ghostty/Ghostty.Input.swift` — Modifier translation
