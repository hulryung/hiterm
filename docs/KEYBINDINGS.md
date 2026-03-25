# hiterm - Keybindings Reference

## Overview

All default keybindings are registered by **libghostty** at the config level. When a keybinding is triggered, libghostty fires an action via `action_cb`. hiterm's job is to handle those actions (e.g. create a tab, open a split, etc.).

On macOS, libghostty uses `super` (Cmd) as the primary modifier.

## libghostty Built-in Defaults (macOS)

These are registered automatically when config is initialized.

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

### Tabs

| Shortcut | Action |
|----------|--------|
| Cmd+T | New tab (`new_tab`) |
| Cmd+W | Close surface (`close_surface`) |
| Cmd+Option+W | Close tab (`close_tab`) |
| Cmd+Shift+W | Close window (`close_window`) |
| Cmd+Shift+Option+W | Close all windows (`close_all_windows`) |
| Cmd+Shift+[ | Previous tab (`previous_tab`) |
| Cmd+Shift+] | Next tab (`next_tab`) |
| Ctrl+Tab | Next tab (`next_tab`) |
| Ctrl+Shift+Tab | Previous tab (`previous_tab`) |
| Cmd+1~8 | Go to tab N (`goto_tab`) |

### Split Panes

| Shortcut | Action |
|----------|--------|
| Cmd+D | Split right (`new_split: right`) |
| Cmd+Shift+D | Split down (`new_split: down`) |
| Cmd+[ | Focus previous split (`goto_split: previous`) |
| Cmd+] | Focus next split (`goto_split: next`) |
| Cmd+Option+Up | Focus split above (`goto_split: up`) |
| Cmd+Option+Down | Focus split below (`goto_split: down`) |
| Cmd+Option+Left | Focus split left (`goto_split: left`) |
| Cmd+Option+Right | Focus split right (`goto_split: right`) |

### Split Resizing

| Shortcut | Action |
|----------|--------|
| Cmd+Ctrl+Up | Resize split up |
| Cmd+Ctrl+Down | Resize split down |
| Cmd+Ctrl+Left | Resize split left |
| Cmd+Ctrl+Right | Resize split right |
| Cmd+Ctrl+= | Equalize splits |

### Window

| Shortcut | Action |
|----------|--------|
| Cmd+N | New window (`new_window`) |
| Cmd+Q | Quit (`quit`) |

### Selection

| Shortcut | Action |
|----------|--------|
| Cmd+A | Select all |
| Shift+Left | Expand selection left |
| Shift+Right | Expand selection right |
| Shift+Up | Expand selection up |
| Shift+Down | Expand selection down |
| Shift+PageUp | Expand selection page up |
| Shift+PageDown | Expand selection page down |
| Shift+Home | Expand selection to start |
| Shift+End | Expand selection to end |

### Scrolling

| Shortcut | Action |
|----------|--------|
| Cmd+Home | Scroll to top |
| Cmd+End | Scroll to bottom |
| Cmd+PageUp | Scroll page up |
| Cmd+PageDown | Scroll page down |
| Cmd+J | Scroll to selection |
| Cmd+Up | Jump to previous prompt |
| Cmd+Down | Jump to next prompt |
| Cmd+Shift+Up | Jump to previous prompt (alt) |
| Cmd+Shift+Down | Jump to next prompt (alt) |

### Search

| Shortcut | Action |
|----------|--------|
| Cmd+F | Start search |
| Cmd+E | Search selection |
| Cmd+Shift+F | End search |
| Escape | End search |

### Screen Dump

| Shortcut | Action |
|----------|--------|
| Cmd+Shift+J | Write screen to file (paste path) |
| Cmd+Shift+Option+J | Write screen to file (open) |
| Ctrl+Cmd+Shift+J | Write screen to file (copy path) |

### Terminal

| Shortcut | Action |
|----------|--------|
| Cmd+K | Clear screen |

### Undo / Redo

| Shortcut | Action |
|----------|--------|
| Cmd+Z | Undo |
| Cmd+Shift+Z | Redo |
| Cmd+Shift+T | Undo (alt) |

## hiterm-Only Shortcuts (not from libghostty)

These are gestures and behaviors that hiterm implements at the UI layer, not via libghostty keybindings.

| Gesture / Shortcut | Action |
|--------------------|--------|
| Two-finger swipe left | Next tab |
| Two-finger swipe right | Previous tab |

## Notes

- All keybindings above are registered by libghostty and delivered to hiterm as actions via `action_cb`. hiterm must implement the corresponding behavior (e.g. actually creating a tab when `new_tab` fires).
- libghostty's default keybindings can be overridden via the ghostty config file (`keybind` option).
- `keybind=clear` removes all defaults — use with caution.
- Source: `ghostty-src/src/config/Config.zig` lines 6426-7100 (`isDarwin` block at line 6885).
