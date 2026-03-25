# hiterm - Requirements Specification

## Project Overview

hiterm is a macOS-native terminal emulator built on libghostty.
It aims to provide iTerm2-level functionality with smooth scrolling and a modern UX.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift |
| UI Framework | AppKit + SwiftUI |
| Terminal Engine | libghostty (Zig, C ABI) |
| Rendering | Metal (built into libghostty) |
| Build System | xcodegen + Xcode |
| License | libghostty is MIT licensed |

## MVP (Phase 1)

### 1. Basic Terminal

- Terminal emulation powered by libghostty
- Default shell (zsh/bash) execution
- Keyboard input and mouse event handling
- Metal GPU-accelerated rendering
- 24-bit color, Unicode, and IME (Korean input) support

### 2. Smooth Scrolling

- Pixel-level smooth scrolling instead of line-by-line scrolling
- libghostty only supports line-level scrolling, so this is implemented at the UI layer
- Implementation approach:
  - Request over-rendering of 1-2 extra rows above/below the viewport
  - Apply sub-pixel offset via CALayer.bounds.origin.y
  - Synchronize frames using CVDisplayLink
  - Snap to nearest line boundary on scroll stop (spring animation)
  - Support momentum scrolling

### 3. Tabs

- Create, close, and switch between multiple tabs
- Custom tab bar UI
- Drag-to-reorder tabs
- Shortcuts: Cmd+T (new tab), Cmd+W (close), Cmd+Shift+[/] (switch)

### 4. Split Panes

- Horizontal and vertical splits
- Recursive SplitTree structure (inspired by Ghostty's pattern)
- Drag to adjust split ratio
- Shortcuts: Cmd+D (vertical), Cmd+Shift+D (horizontal), Cmd+Option+Arrow (focus)

### 5. Two-Finger Swipe Tab Switching

- Detect horizontal two-finger swipe via NSPanGestureRecognizer
- Slide animation between current and next/previous tab as swipe progresses
- Commit tab switch when threshold is exceeded; snap back otherwise
- UX identical to Safari tab swiping

### 6. Semantic Line Copy

- When a long line wraps across multiple visual rows in the terminal, copying should grab the single logical line, not multiple visual lines with embedded newlines
- Standard terminals insert line breaks at the wrap boundary, producing broken output when pasted
- hiterm should detect soft-wrapped lines and join them on copy so the clipboard contains the original single line
- This applies to both mouse selection copy and keyboard selection copy

### 7. Fullscreen Tabs as Separate Desktops

- When entering fullscreen, each tab becomes an independent macOS Space
- Set NSWindow.collectionBehavior to .fullScreenPrimary
- Detach each tab into its own NSWindow with .fullScreenAuxiliary
- macOS automatically places each window in a separate Space
- Merge all windows back into a single tabbed window on fullscreen exit

## Phase 2 (Future)

### 8. Session Management

- Abstract session types: local shell, SSH, serial
- Save and load session profiles

### 9. SSH Connections

- SSH connection management (save host/port/user/key)
- Auto-reconnect
- Port forwarding

### 10. Serial Connections

- Serial port connections
- Configuration: baud rate, parity, stop bits, flow control
- Built on IOKit or ORSSerialPort
