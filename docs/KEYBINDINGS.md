# hiterm - Keybindings Reference

## Overview

Keybindings come from two layers:

1. **libghostty** — Built-in defaults registered at the config level. These are handled internally by libghostty and fire actions via `action_cb`.
2. **hiterm** — App-level shortcuts for tab/split/window management. These must be implemented in the AppKit UI layer (menus, responder chain).

On macOS, libghostty uses `super` (Cmd) as the primary modifier. Notably, **tab, split, and window management shortcuts are NOT registered by libghostty on macOS** — the Ghostty macOS app handles those at the AppKit level, and hiterm must do the same.

## libghostty Built-in Defaults (macOS)

These are registered automatically when config is initialized. hiterm does not need to implement these — libghostty handles them internally.

### Clipboard

| Shortcut | Action |
|----------|--------|
| Cmd+C | Copy to clipboard |
| Cmd+V | Paste from clipboard |

### Font Size

| Shortcut | Action |
|----------|--------|
| Cmd+= | Increase font size |
| Cmd++ | Increase font size (dedicated plus key) |
| Cmd+- | Decrease font size |
| Cmd+0 | Reset font size |

### Config

| Shortcut | Action |
|----------|--------|
| Cmd+, | Open config file |
| Cmd+Shift+, | Reload config |

### Tab Navigation

| Shortcut | Action |
|----------|--------|
| Ctrl+Tab | Next tab |
| Ctrl+Shift+Tab | Previous tab |
| Cmd+1~8 | Go to tab N |

### Selection

| Shortcut | Action |
|----------|--------|
| Shift+Left | Expand selection left |
| Shift+Right | Expand selection right |
| Shift+Up | Expand selection up |
| Shift+Down | Expand selection down |
| Shift+PageUp | Expand selection page up |
| Shift+PageDown | Expand selection page down |
| Shift+Home | Expand selection to start |
| Shift+End | Expand selection to end |

### Screen Dump

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+J | Write screen to file (paste path) |
| Cmd+Shift+Alt+J | Write screen to file (open) |
| Ctrl+Cmd+Shift+J | Write screen to file (copy path) |

## hiterm App-Level Shortcuts (to implement)

These are NOT provided by libghostty on macOS. hiterm must handle them via AppKit menus or the responder chain.

### Tabs

| Shortcut | Action |
|----------|--------|
| Cmd+T | New tab |
| Cmd+W | Close tab / surface |
| Cmd+Shift+[ | Previous tab |
| Cmd+Shift+] | Next tab |

### Split Panes

| Shortcut | Action |
|----------|--------|
| Cmd+D | Vertical split (right) |
| Cmd+Shift+D | Horizontal split (down) |
| Cmd+Option+Up | Focus split above |
| Cmd+Option+Down | Focus split below |
| Cmd+Option+Left | Focus split left |
| Cmd+Option+Right | Focus split right |
| Cmd+Shift+Enter | Toggle split zoom |

### Split Resizing

| Shortcut | Action |
|----------|--------|
| Cmd+Ctrl+Shift+Up | Resize split up |
| Cmd+Ctrl+Shift+Down | Resize split down |
| Cmd+Ctrl+Shift+Left | Resize split left |
| Cmd+Ctrl+Shift+Right | Resize split right |

### Window

| Shortcut | Action |
|----------|--------|
| Cmd+N | New window |
| Cmd+Shift+W | Close window |
| Cmd+Q | Quit |
| Cmd+Ctrl+F | Toggle fullscreen |

### Search

| Shortcut | Action |
|----------|--------|
| Cmd+F | Start search |
| Escape | End search |

### Scrolling

| Shortcut | Action |
|----------|--------|
| Shift+Home | Scroll to top |
| Shift+End | Scroll to bottom |
| Shift+PageUp | Scroll page up |
| Shift+PageDown | Scroll page down |

### Gestures

| Gesture | Action |
|---------|--------|
| Two-finger swipe left | Next tab |
| Two-finger swipe right | Previous tab |

## Notes

- libghostty's default keybindings can be overridden via the ghostty config file (`keybind` option).
- `keybind=clear` removes all defaults — use with caution.
- The `Cmd+1~8` tab navigation is registered by libghostty and fires `goto_tab` via `action_cb`. hiterm's `action_cb` handler must respond to it.
- `Ctrl+Tab` / `Ctrl+Shift+Tab` for tab switching is also registered by libghostty (`next_tab` / `previous_tab` actions).
