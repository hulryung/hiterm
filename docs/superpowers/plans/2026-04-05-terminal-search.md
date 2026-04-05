# Terminal Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add find-in-terminal (Cmd+F) search with match highlighting, navigation, and match counter.

**Architecture:** libghostty provides search engine, matching, and highlighting via C actions. hiterm adds 4 action handlers in GhosttyApp, a SearchState model, and a SearchOverlayView (AppKit NSView). Communication follows existing NotificationCenter pattern.

**Tech Stack:** Swift, AppKit, Combine (for debounce), GhosttyKit C API

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `hiterm/Views/SearchOverlayView.swift` | Create | Search UI overlay (text field, counter, nav buttons) |
| `hiterm/Core/GhosttyApp.swift` | Modify | Add 4 search action handlers + 4 notification names |
| `hiterm/Views/TerminalSurfaceView.swift` | Modify | Add SearchState property, notification observers, overlay lifecycle |

---

### Task 1: Add Search Notification Names and Action Handlers

**Files:**
- Modify: `hiterm/Core/GhosttyApp.swift:346-366` (Notification.Name extension)
- Modify: `hiterm/Core/GhosttyApp.swift:92-306` (handleAction switch)

- [ ] **Step 1: Add notification names**

Add 4 search notification names to the `Notification.Name` extension at the bottom of `GhosttyApp.swift`:

```swift
static let hitermStartSearch = Notification.Name("hitermStartSearch")
static let hitermEndSearch = Notification.Name("hitermEndSearch")
static let hitermSearchTotal = Notification.Name("hitermSearchTotal")
static let hitermSearchSelected = Notification.Name("hitermSearchSelected")
```

- [ ] **Step 2: Add START_SEARCH handler**

Add before the `default:` case in `handleAction()`:

```swift
case GHOSTTY_ACTION_START_SEARCH:
    if target.tag == GHOSTTY_TARGET_SURFACE {
        let surface = target.target.surface
        let needle = action.action.start_search.needle.flatMap { String(cString: $0) } ?? ""
        let surfaceUD = ghostty_surface_userdata(surface)
        NotificationCenter.default.post(
            name: .hitermStartSearch,
            object: nil,
            userInfo: ["needle": needle, "userdata": surfaceUD as Any]
        )
    }
    return true
```

- [ ] **Step 3: Add END_SEARCH handler**

Add after START_SEARCH case:

```swift
case GHOSTTY_ACTION_END_SEARCH:
    if target.tag == GHOSTTY_TARGET_SURFACE {
        let surface = target.target.surface
        let surfaceUD = ghostty_surface_userdata(surface)
        NotificationCenter.default.post(
            name: .hitermEndSearch,
            object: nil,
            userInfo: ["userdata": surfaceUD as Any]
        )
    }
    return true
```

- [ ] **Step 4: Add SEARCH_TOTAL handler**

```swift
case GHOSTTY_ACTION_SEARCH_TOTAL:
    if target.tag == GHOSTTY_TARGET_SURFACE {
        let surface = target.target.surface
        let total = action.action.search_total.total
        let surfaceUD = ghostty_surface_userdata(surface)
        NotificationCenter.default.post(
            name: .hitermSearchTotal,
            object: nil,
            userInfo: ["total": total, "userdata": surfaceUD as Any]
        )
    }
    return true
```

- [ ] **Step 5: Add SEARCH_SELECTED handler**

```swift
case GHOSTTY_ACTION_SEARCH_SELECTED:
    if target.tag == GHOSTTY_TARGET_SURFACE {
        let surface = target.target.surface
        let selected = action.action.search_selected.selected
        let surfaceUD = ghostty_surface_userdata(surface)
        NotificationCenter.default.post(
            name: .hitermSearchSelected,
            object: nil,
            userInfo: ["selected": selected, "userdata": surfaceUD as Any]
        )
    }
    return true
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -scheme hiterm build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add hiterm/Core/GhosttyApp.swift
git commit -m "Add search action handlers and notification names in GhosttyApp"
```

---

### Task 2: Create SearchOverlayView

**Files:**
- Create: `hiterm/Views/SearchOverlayView.swift`

- [ ] **Step 1: Create SearchOverlayView with full implementation**

Create `hiterm/Views/SearchOverlayView.swift`:

```swift
import AppKit
import Combine
import GhosttyKit

/// Floating search bar overlay for find-in-terminal.
class SearchOverlayView: NSView {

    /// The ghostty surface to send search commands to.
    private let surface: ghostty_surface_t

    private let searchField = NSTextField()
    private let counterLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()

    /// Current search needle — drives debounced search.
    @Published private var needle: String = ""
    private var cancellable: AnyCancellable?

    /// Updated by TerminalSurfaceView from notification callbacks.
    var total: Int? {
        didSet { updateCounter() }
    }
    var selected: Int? {
        didSet { updateCounter() }
    }

    init(surface: ghostty_surface_t, initialNeedle: String = "") {
        self.surface = surface
        super.init(frame: .zero)

        self.needle = initialNeedle
        setupViews()
        setupDebounce()

        if !initialNeedle.isEmpty {
            searchField.stringValue = initialNeedle
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Shadow
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 4
        layer?.shadowOpacity = 1

        // Search field
        searchField.placeholderString = "Search..."
        searchField.font = .systemFont(ofSize: 13)
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self

        // Counter label
        counterLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        counterLabel.textColor = .secondaryLabelColor
        counterLabel.alignment = .center
        counterLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Prev button
        prevButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")
        prevButton.bezelStyle = .inline
        prevButton.isBordered = false
        prevButton.target = self
        prevButton.action = #selector(prevMatch)
        prevButton.setContentHuggingPriority(.required, for: .horizontal)

        // Next button
        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")
        nextButton.bezelStyle = .inline
        nextButton.isBordered = false
        nextButton.target = self
        nextButton.action = #selector(nextMatch)
        nextButton.setContentHuggingPriority(.required, for: .horizontal)

        // Close button
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(endSearch)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        // Layout with stack view
        let stack = NSStackView(views: [searchField, counterLabel, prevButton, nextButton, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    private func setupDebounce() {
        cancellable = $needle
            .removeDuplicates()
            .map { needle -> AnyPublisher<String, Never> in
                if needle.isEmpty || needle.count >= 3 {
                    return Just(needle).eraseToAnyPublisher()
                } else {
                    return Just(needle)
                        .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
                        .eraseToAnyPublisher()
                }
            }
            .switchToLatest()
            .sink { [weak self] needle in
                self?.performSearch(needle)
            }
    }

    // MARK: - Search Commands

    private func performSearch(_ needle: String) {
        let action = "search:\(needle)"
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc private func prevMatch() {
        let action = "navigate_search:previous"
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc private func nextMatch() {
        let action = "navigate_search:next"
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    @objc private func endSearch() {
        let action = "end_search"
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    // MARK: - UI Updates

    private func updateCounter() {
        guard let total else {
            counterLabel.stringValue = ""
            return
        }
        if total == 0 {
            counterLabel.stringValue = "0"
        } else if let selected, selected >= 0 {
            counterLabel.stringValue = "\(selected + 1)/\(total)"
        } else {
            counterLabel.stringValue = "-/\(total)"
        }
    }

    @objc private func searchFieldChanged(_ sender: NSTextField) {
        needle = sender.stringValue
    }

    // MARK: - Focus

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }
}

// MARK: - NSTextFieldDelegate

extension SearchOverlayView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            // Enter → next match
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                prevMatch()
            } else {
                nextMatch()
            }
            return true

        case #selector(cancelOperation(_:)):
            // Esc → close search
            endSearch()
            return true

        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        needle = searchField.stringValue
    }
}
```

- [ ] **Step 2: Add file to project.yml**

Add `hiterm/Views/SearchOverlayView.swift` to the sources in `project.yml` if needed (xcodegen auto-includes from directory).

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme hiterm build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add hiterm/Views/SearchOverlayView.swift
git commit -m "Add SearchOverlayView with debounced search, navigation, and match counter"
```

---

### Task 3: Integrate Search into TerminalSurfaceView

**Files:**
- Modify: `hiterm/Views/TerminalSurfaceView.swift`

- [ ] **Step 1: Add search state properties**

Add after the existing `var onClosed: (() -> Void)?` property (line 12):

```swift
private var searchOverlay: SearchOverlayView?
```

- [ ] **Step 2: Register search notification observers**

Add in `init()`, after the existing `addObserver` calls for `.hitermSetTitle` and `.hitermCloseSurface`:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleStartSearch(_:)),
    name: .hitermStartSearch,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleEndSearch(_:)),
    name: .hitermEndSearch,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleSearchTotal(_:)),
    name: .hitermSearchTotal,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleSearchSelected(_:)),
    name: .hitermSearchSelected,
    object: nil
)
```

- [ ] **Step 3: Add notification handler methods**

Add a new `// MARK: - Search` section before the existing `// MARK: - Notifications` section:

```swift
// MARK: - Search

@objc private func handleStartSearch(_ notification: Notification) {
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let ud = notification.userInfo?["userdata"] as? UnsafeMutableRawPointer,
          ud == selfPtr else { return }

    let needle = notification.userInfo?["needle"] as? String ?? ""

    if let existing = searchOverlay {
        // Already open — just re-focus.
        existing.focusSearchField()
        return
    }

    guard let surface else { return }
    let overlay = SearchOverlayView(surface: surface, initialNeedle: needle)
    overlay.translatesAutoresizingMaskIntoConstraints = false
    addSubview(overlay)

    NSLayoutConstraint.activate([
        overlay.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
    ])

    searchOverlay = overlay
    overlay.focusSearchField()
}

@objc private func handleEndSearch(_ notification: Notification) {
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let ud = notification.userInfo?["userdata"] as? UnsafeMutableRawPointer,
          ud == selfPtr else { return }

    searchOverlay?.removeFromSuperview()
    searchOverlay = nil
    window?.makeFirstResponder(self)
}

@objc private func handleSearchTotal(_ notification: Notification) {
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let ud = notification.userInfo?["userdata"] as? UnsafeMutableRawPointer,
          ud == selfPtr else { return }

    if let total = notification.userInfo?["total"] as? Int {
        searchOverlay?.total = total
    }
}

@objc private func handleSearchSelected(_ notification: Notification) {
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    guard let ud = notification.userInfo?["userdata"] as? UnsafeMutableRawPointer,
          ud == selfPtr else { return }

    if let selected = notification.userInfo?["selected"] as? Int {
        searchOverlay?.selected = selected
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -scheme hiterm build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add hiterm/Views/TerminalSurfaceView.swift
git commit -m "Integrate search overlay into TerminalSurfaceView with notification handling"
```

---

### Task 4: Manual Testing and Polish

- [ ] **Step 1: Run app and test search**

Run: `xcodebuild -scheme hiterm build && open build/Build/Products/Debug/hiterm.app` (or run from Xcode)

Test sequence:
1. Open hiterm, run `ls -la` or `cat` some file to produce output
2. Press `Cmd+F` — search overlay should appear at top-right
3. Type a search term — matches should highlight in terminal
4. Counter should show "1/N"
5. Press `Enter` — should navigate to next match, counter updates
6. Press `Shift+Enter` — should navigate to previous match
7. Press `Esc` — search overlay closes, focus returns to terminal
8. Test with splits: open a split, search should only appear on focused surface

- [ ] **Step 2: Fix any issues found during testing**

Address any layout, focus, or behavior issues.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "Terminal search: polish and fixes from manual testing"
```
