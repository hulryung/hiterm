# SwiftTerm Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On an isolated branch, prove or disprove that SwiftTerm gives hiterm pixel-level rendering/scroll control that libghostty does not expose, without disturbing the production ghostty path.

**Architecture:** Parallel experiment window. Add SwiftTerm via SPM. New code lives under `hiterm/Experimental/SwiftTerm/`. A single line in `AppDelegate` branches on `HITERM_BACKEND=swiftterm` and opens a stand-alone `NSWindow` containing one `SwiftTermPixelScrollLayer` wrapping one `SwiftTermSurfaceView` (SwiftTerm's `LocalProcessTerminalView`). The PoC payload is sub-row smooth scroll: a wrapper view intercepts wheel events, accumulates pixel offsets, translates the SwiftTerm view's layer, and advances SwiftTerm's scrollback by full rows when the accumulator crosses a row height.

**Tech Stack:** Swift 5.10, AppKit, `LocalProcessTerminalView` from `https://github.com/migueldeicaza/SwiftTerm` (SPM), `CVDisplayLink`, `os.Logger`. xcodegen for project generation.

**Spec:** `docs/superpowers/specs/2026-05-07-swiftterm-experiment-design.md`

**Testing approach:** This is a UI/PoC experiment touching SwiftTerm's `NSView`, `NSWindow` lifecycle, wheel events, and a display link. Per spec, no automated tests at PoC stage — instead, each integration milestone has an explicit **manual validation gate** with pass criteria. Do not skip the gates.

**Branch hygiene:** Every task ends with a commit. Commits are small. Never amend across tasks.

**Bundle-ID note:** Debug builds use `com.hiterm.app.debug`, which is distinct from the user's installed hiterm bundle. Launching Debug therefore does **not** kill the installed app. (Memory: `feedback_debug_launch.md` — that risk applied to a previous shared bundle id.) Still, before each manual launch, confirm the user is not in the middle of work in the production app.

---

## Task 1: Create the experiment branch

**Files:** none — branch operation only.

- [ ] **Step 1: Create and switch to the branch**

Run:

```bash
git switch -c experiment/swiftterm
```

Expected: `Switched to a new branch 'experiment/swiftterm'`.

- [ ] **Step 2: Verify clean starting state**

Run:

```bash
git status
```

Expected: `nothing to commit, working tree clean` (the spec/plan files committed earlier are already on `main`, which is the parent).

No commit in this task — branch creation alone.

---

## Task 2: Add SwiftTerm as an SPM dependency

**Files:**
- Modify: `project.yml` (add `packages` block and target `dependencies`)

- [ ] **Step 1: Edit `project.yml` to declare the SwiftTerm package**

Add a top-level `packages:` block (after the `settings:` block, before `targets:`):

```yaml
packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.2.0"
```

Note: pin to the latest `1.2.x` tag at time of implementation. If `1.2.x` is unavailable, use `from: "1.0.0"` and verify the resolved version still has `LocalProcessTerminalView`.

- [ ] **Step 2: Add the package to the `hiterm` target's `dependencies`**

Replace the existing `dependencies: []` line under `targets.hiterm` with:

```yaml
    dependencies:
      - package: SwiftTerm
```

- [ ] **Step 3: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `Generated project successfully` (or equivalent xcodegen success line).

- [ ] **Step 4: Verify the build still succeeds with the new dependency unused**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **`. SwiftTerm is fetched and linked but unused so far.

If SPM resolution fails, run `xcodebuild -resolvePackageDependencies -scheme hiterm` and re-try.

- [ ] **Step 5: Commit**

```bash
git add project.yml hiterm.xcodeproj
git commit -m "Add SwiftTerm SPM dependency for experiment branch"
```

---

## Task 3: Add the `swiftterm` log category

**Files:**
- Modify: `hiterm/Core/Log.swift:30` (add new logger), `hiterm/Core/Log.swift:38` (add to verbose-all set)

- [ ] **Step 1: Add the logger constant**

In `Log.swift`, after the existing `static let ghostty = ...` line (around line 30), insert:

```swift
    /// SwiftTerm experiment surface, window, and pixel-scroll layer.
    static let swiftterm = Logger(subsystem: subsystem, category: "swiftterm")
```

- [ ] **Step 2: Include `swiftterm` in the verbose-all category set**

Update the `if value == "all" ...` line (around line 38) from:

```swift
        if value == "all" { return ["config", "surface", "input", "ui", "ghostty"] }
```

to:

```swift
        if value == "all" { return ["config", "surface", "input", "ui", "ghostty", "swiftterm"] }
```

- [ ] **Step 3: Verify build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add hiterm/Core/Log.swift
git commit -m "Add swiftterm log category"
```

---

## Task 4: Create the experiment folder skeleton

**Files:**
- Create: `hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift` (stub)
- Create: `hiterm/Experimental/SwiftTerm/SwiftTermExperimentWindowController.swift` (stub)
- Create: `hiterm/Experimental/SwiftTerm/SwiftTermExperimentEntry.swift` (stub)
- Create: `hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift` (stub)

Stubs only — no logic yet. This task verifies the new folder is picked up by xcodegen and compiles cleanly.

- [ ] **Step 1: Create `SwiftTermSurfaceView.swift` with a minimal placeholder class**

```swift
import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's LocalProcessTerminalView that runs zsh and is the
/// rendering surface for the SwiftTerm experiment window. PTY, ANSI parsing,
/// and default key/mouse handling are inherited from the base class.
final class SwiftTermSurfaceView: LocalProcessTerminalView {
}
```

- [ ] **Step 2: Create `SwiftTermExperimentWindowController.swift` with a stub**

```swift
import AppKit

/// Owns the single NSWindow used by the SwiftTerm experiment. No tabs, no
/// splits, no search overlay.
final class SwiftTermExperimentWindowController: NSWindowController {
}
```

- [ ] **Step 3: Create `SwiftTermExperimentEntry.swift` with a stub**

```swift
import AppKit
import Foundation

/// Decides whether AppDelegate should enter the SwiftTerm experiment path,
/// and opens the experiment window when it should.
enum SwiftTermExperimentEntry {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HITERM_BACKEND"] == "swiftterm"
    }

    static func openWindow() {
        // Implemented in Task 7.
    }
}
```

- [ ] **Step 4: Create `SwiftTermPixelScrollLayer.swift` with a stub**

```swift
import AppKit

/// Wrapper view that hosts a SwiftTermSurfaceView and intercepts wheel events
/// to drive sub-row pixel-scroll. Implementation lands in Task 9–11.
final class SwiftTermPixelScrollLayer: NSView {
}
```

- [ ] **Step 5: Regenerate project and build**

Run:

```bash
xcodegen generate
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Confirms `Experimental/SwiftTerm/*.swift` are picked up by the source glob (`sources: - path: hiterm` already includes everything under `hiterm/`).

- [ ] **Step 6: Commit**

```bash
git add hiterm/Experimental hiterm.xcodeproj
git commit -m "Add SwiftTerm experiment skeleton files"
```

---

## Task 5: Implement `SwiftTermSurfaceView` (zsh + window-close on exit)

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift`

- [ ] **Step 1: Replace the stub with a working implementation**

Full file:

```swift
import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's LocalProcessTerminalView that runs `/bin/zsh -l`,
/// uses a hard-coded monospaced font, and closes its window when the child
/// process exits. PTY, ANSI parsing, default key/mouse handling, and
/// rendering all come from the base class.
final class SwiftTermSurfaceView: LocalProcessTerminalView, LocalProcessTerminalViewDelegate {

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        processDelegate = self
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        Log.swiftterm.info("SwiftTermSurfaceView configured (font=monospacedSystemFont 13)")
    }

    /// Called by the experiment window controller once the view is in a window.
    func startZsh() {
        Log.swiftterm.info("Starting /bin/zsh -l")
        startProcess(executable: "/bin/zsh", args: ["-l"], environment: nil)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        Log.swiftterm.debug("Grid resized: \(newCols)x\(newRows)")
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        source.window?.title = "hiterm — SwiftTerm Experiment — \(title)"
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        // Not used at PoC stage.
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Log.swiftterm.info("zsh terminated (exitCode=\(exitCode ?? -1)), closing window")
        DispatchQueue.main.async { source.window?.close() }
    }
}
```

- [ ] **Step 2: Verify build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If SwiftTerm's delegate signature has drifted (newer/older tag), update the protocol method signatures to match the resolved package version — do not invent missing arguments.

- [ ] **Step 3: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift
git commit -m "Implement SwiftTermSurfaceView (zsh, font, exit-on-terminate)"
```

---

## Task 6: Implement `SwiftTermExperimentWindowController`

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermExperimentWindowController.swift`

- [ ] **Step 1: Replace the stub with the full controller**

Full file:

```swift
import AppKit

/// Owns the single NSWindow used by the SwiftTerm experiment. Content view is
/// a SwiftTermSurfaceView (no scroll wrapper yet — Task 9 wraps it).
final class SwiftTermExperimentWindowController: NSWindowController, NSWindowDelegate {

    private let surface = SwiftTermSurfaceView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "hiterm — SwiftTerm Experiment"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = surface
        surface.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(surface)
        surface.startZsh()
        Log.swiftterm.info("Experiment window shown")
    }

    func windowWillClose(_ notification: Notification) {
        Log.swiftterm.info("Experiment window closing — terminating app")
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Verify build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermExperimentWindowController.swift
git commit -m "Implement SwiftTermExperimentWindowController"
```

---

## Task 7: Implement `SwiftTermExperimentEntry.openWindow()`

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermExperimentEntry.swift`

- [ ] **Step 1: Hold a strong reference to the controller and show the window**

Replace the file body so `openWindow()` is functional:

```swift
import AppKit
import Foundation

enum SwiftTermExperimentEntry {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HITERM_BACKEND"] == "swiftterm"
    }

    /// Held at module scope so the controller and its window are not deallocated.
    private static var controller: SwiftTermExperimentWindowController?

    static func openWindow() {
        Log.swiftterm.info("Entering SwiftTerm experiment path")
        NSApp.setActivationPolicy(.regular)
        let wc = SwiftTermExperimentWindowController()
        controller = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Verify build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermExperimentEntry.swift
git commit -m "Implement SwiftTermExperimentEntry.openWindow"
```

---

## Task 8: Wire `AppDelegate` to branch on `HITERM_BACKEND=swiftterm`

**Files:**
- Modify: `hiterm/App/AppDelegate.swift:11-32`

- [ ] **Step 1: Add the early return**

In `applicationDidFinishLaunching`, replace lines 11–32 (the entire body up to and including the `NSApp.activate(...)` call) with:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        if SwiftTermExperimentEntry.isEnabled {
            SwiftTermExperimentEntry.openWindow()
            return
        }

        NSApp.setActivationPolicy(.regular)

        ghosttyApp = GhosttyApp()
        guard ghosttyApp.isReady else {
            print("Failed to initialize Ghostty app")
            NSApp.terminate(nil)
            return
        }

        // Initialize settings manager and load defaults.
        if let config = ghosttyApp.config {
            SettingsManager.shared.loadInitialSettings(from: config)
        }

        setupMainMenu()

        let wc = MainWindowController(ghosttyApp: ghosttyApp)
        windowControllers.append(wc)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

The `SwiftTermExperimentEntry.isEnabled` branch is the only addition. Everything else is identical.

- [ ] **Step 2: Verify build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add hiterm/App/AppDelegate.swift
git commit -m "Branch AppDelegate on HITERM_BACKEND=swiftterm"
```

---

## Task 9: Manual validation gate 1 — zsh runs in the experiment window

**Files:** none — runtime check.

This is a **gate**. Do not proceed to Task 10 until all three checks pass.

- [ ] **Step 1: Confirm with the user before launching Debug**

Before launching, send the user a short message: "About to launch the Debug build (`com.hiterm.app.debug`) for SwiftTerm experiment validation. The installed `com.hiterm.app` is unaffected, but please save anything in flight there. OK to proceed?"

Wait for confirmation before continuing.

- [ ] **Step 2: Build and locate the Debug app**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -3
APP_PATH=$(xcodebuild -scheme hiterm -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')
echo "$APP_PATH/hiterm.app"
```

- [ ] **Step 3: Launch the experiment path and verify zsh**

Run:

```bash
HITERM_BACKEND=swiftterm "$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Expected results — verify each:

1. A window with title `hiterm — SwiftTerm Experiment` opens.
2. A zsh prompt appears in the window.
3. Typing `ls` and pressing Return produces output that scrolls within the view.
4. In another tail, `log stream --predicate 'subsystem=="com.hiterm.app" && category=="swiftterm"' --level debug` prints the lifecycle messages from Tasks 5–7.

Type `exit` and press Return — the window must close and the app must terminate.

- [ ] **Step 4: Regression check — ghostty path is unaffected**

Run (without the env var):

```bash
"$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Expected: the existing ghostty-backed window opens with the normal hiterm UI (tabs, splits available). Quit it with Cmd+Q.

- [ ] **Step 5: Commit a no-op marker if helpful, otherwise skip**

If any small cleanup was needed during validation, commit it. Otherwise no commit — gate is informational.

If any of Steps 3 or 4 fail: **stop**. Diagnose before proceeding. Common issues:
- SwiftTerm version mismatch in delegate signatures → fix Task 5 code.
- `processDelegate` not retained → make sure `self` is the delegate and the surface is retained by the window controller.

---

## Task 10: Wrap the surface in `SwiftTermPixelScrollLayer`

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift`
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermExperimentWindowController.swift` (use the wrapper as content view)

This task adds the wrapper view but **without** scroll behavior yet. It just hosts the surface 1:1. Validates that nothing breaks before introducing scroll logic.

- [ ] **Step 1: Implement the wrapper**

Full file `SwiftTermPixelScrollLayer.swift`:

```swift
import AppKit

/// Hosts a SwiftTermSurfaceView and (in Tasks 11–12) drives sub-row pixel
/// scroll by intercepting wheel events. At this stage it is a transparent
/// passthrough wrapper.
final class SwiftTermPixelScrollLayer: NSView {

    let surface: SwiftTermSurfaceView

    override init(frame: NSRect) {
        self.surface = SwiftTermSurfaceView(frame: frame)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(surface)
        surface.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(surface)
        return true
    }
}
```

- [ ] **Step 2: Switch the window controller to use the wrapper**

In `SwiftTermExperimentWindowController.swift`, replace the property declaration and `init` body so the wrapper is the content view:

```swift
    private let scrollLayer = SwiftTermPixelScrollLayer(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    private var surface: SwiftTermSurfaceView { scrollLayer.surface }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "hiterm — SwiftTerm Experiment"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = scrollLayer
        scrollLayer.autoresizingMask = [.width, .height]
    }
```

`showWindow(_:)` stays the same — it still calls `surface.startZsh()`.

- [ ] **Step 3: Build and re-run validation gate 1**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -3
HITERM_BACKEND=swiftterm "$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Expected: identical to Task 9 Step 3. Wheel scrolling still works via SwiftTerm's default handler (the wrapper does not intercept yet). Quit and continue.

- [ ] **Step 4: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift hiterm/Experimental/SwiftTerm/SwiftTermExperimentWindowController.swift
git commit -m "Host SwiftTerm surface inside SwiftTermPixelScrollLayer wrapper"
```

---

## Task 11: Intercept wheel events and apply sub-row layer translation

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift`

This is the heart of the PoC. Wheel events accumulate into a pixel offset; the surface's layer is translated by that offset; when the accumulator crosses one row height, advance SwiftTerm's scrollback by one line and subtract the row height.

- [ ] **Step 1: Replace the wrapper with the scroll-driving implementation**

Full file:

```swift
import AppKit
import SwiftTerm

/// Hosts a SwiftTermSurfaceView and drives sub-row pixel-resolution scroll.
///
/// Scroll model:
///   - `accumulatedPixelOffset` is in "pixels above the natural origin" — a
///     positive value means content has been pushed up by that many pixels.
///   - Each frame the surface's layer bounds origin is set so the visible
///     content is offset accordingly.
///   - When `|accumulatedPixelOffset| >= rowHeight`, advance SwiftTerm's
///     scrollback by one line and subtract `rowHeight` from the accumulator.
final class SwiftTermPixelScrollLayer: NSView {

    let surface: SwiftTermSurfaceView

    private var accumulatedPixelOffset: CGFloat = 0

    override init(frame: NSRect) {
        self.surface = SwiftTermSurfaceView(frame: frame)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(surface)
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(surface)
        return true
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        // SwiftTerm's wheel handling would consume this if we forwarded it.
        // We intercept here and drive the terminal scrollback ourselves.
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }

        // Trackpad scrolling reports inverted deltas vs. line-mode wheels in
        // some setups. Treat positive scrollingDeltaY as "user pushed content
        // up" (i.e. show older lines).
        accumulatedPixelOffset += delta

        commitFullRows()
        applyLayerTranslation()

        Log.swiftterm.debug("scrollWheel delta=\(delta) accum=\(self.accumulatedPixelOffset)")
    }

    private var rowHeight: CGFloat {
        let h = surface.cellDimension.height
        return h > 0 ? h : 18
    }

    private func commitFullRows() {
        let h = rowHeight
        while accumulatedPixelOffset >= h {
            scrollTerminal(linesUp: 1)
            accumulatedPixelOffset -= h
        }
        while accumulatedPixelOffset <= -h {
            scrollTerminal(linesUp: -1)
            accumulatedPixelOffset += h
        }
    }

    private func scrollTerminal(linesUp: Int) {
        // Move the visible region by N lines. Positive linesUp means show
        // older lines (scroll content up).
        let terminal: Terminal = surface.getTerminal()
        let current = terminal.getTopVisibleRow()
        let target = max(0, current - linesUp)
        terminal.scrollTo(row: target)
        surface.queuePendingDisplay()
    }

    private func applyLayerTranslation() {
        // Translate the surface's backing layer by the residual pixel offset.
        // bounds.origin.y > 0 shifts visible content up.
        guard let layer = surface.layer else { return }
        var bounds = layer.bounds
        bounds.origin.y = accumulatedPixelOffset
        // Disable implicit animation so the offset is applied this frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = bounds
        CATransaction.commit()
    }
}
```

**Notes on the SwiftTerm calls:**

- `surface.cellDimension.height` is SwiftTerm's row pixel height.
- `surface.getTerminal()` returns the underlying `Terminal` model.
- `terminal.getTopVisibleRow()` and `terminal.scrollTo(row:)` are the documented row-scrollback API. If the resolved SwiftTerm version exposes a different name (e.g., `scrollDown(by:)`/`scrollUp(by:)` on `TerminalView` directly), substitute the equivalent and **document the substitution in a single `// SwiftTerm vX.Y: ...` comment** so a future reader can re-verify. Do not invent methods.
- `surface.queuePendingDisplay()` schedules a redraw. If unavailable, call `surface.needsDisplay = true`.

- [ ] **Step 2: Build**

Run:

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If any of the SwiftTerm API names are wrong on the resolved version, fix per the substitution note above and rebuild.

- [ ] **Step 3: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift
git commit -m "Drive sub-row pixel scroll on SwiftTerm surface via wheel interception"
```

---

## Task 12: Manual validation gate 2 — sub-row scroll is visible

**Files:** none — runtime check.

This is the **central gate** of the experiment. Pass criteria here directly map to the spec's `## Exit Criteria`.

- [ ] **Step 1: Confirm with the user before launch (same protocol as Task 9 Step 1)**

- [ ] **Step 2: Launch and produce scrollback content**

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -3
HITERM_BACKEND=swiftterm "$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

In the experiment window, run something that produces multiple screens of output, e.g.:

```bash
seq 1 500
```

- [ ] **Step 3: Verify each pass criterion**

1. **Sub-row stop visible**: trackpad-scroll up *very slowly*. The content must visibly stop with a row partially clipped at the top edge — not snap to a row boundary. If you only ever see whole-row jumps, the wrapper is not driving translation.
2. **No flicker / tearing**: scroll continuously up and down for ~5 seconds. No rows should disappear or duplicate, and there should be no horizontal tearing.
3. **Inertial fast-swipe**: fling the trackpad. Content should keep scrolling smoothly with diminishing speed (this depends on whether macOS still delivers `momentumPhase` events to the wrapper — note the result either way).

Type `exit` to terminate zsh.

- [ ] **Step 4: Run the regression check**

Without the env var:

```bash
"$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Expected: ghostty UI unchanged, normal scroll behavior. Quit.

- [ ] **Step 5: Record results in the spec**

Append the outcome to `docs/superpowers/specs/2026-05-07-swiftterm-experiment-design.md` under a new `## Result` heading. Be specific:

```markdown
## Result (recorded YYYY-MM-DD)

- Sub-row stop: PASS / FAIL — <observation>
- No flicker: PASS / FAIL — <observation>
- Inertial fast-swipe: PASS / FAIL — <observation>
- Regression (ghostty path with no env var): PASS / FAIL
- Notes: <any caveats: SwiftTerm API substitutions made, rough perf feel, etc.>

Decision: <bring forward to a production migration spec> | <abandon the
SwiftTerm direction, branch preserved at experiment/swiftterm>.
```

- [ ] **Step 6: Commit the result**

```bash
git add docs/superpowers/specs/2026-05-07-swiftterm-experiment-design.md
git commit -m "Record SwiftTerm experiment results"
```

---

## Task 13: Final hygiene — preserve the branch

**Files:** none.

- [ ] **Step 1: Push the branch (do not merge)**

Run (only after confirming with the user that pushing this WIP branch is OK):

```bash
git push -u origin experiment/swiftterm
```

If the user declines the push, leave the branch local — that satisfies the spec's "branch preserved" requirement either way.

- [ ] **Step 2: Stop here**

Per the spec: a production migration is **out of scope**. Do not start replacing the ghostty path. If the experiment passed, the next step is a new spec/plan, not more code on this branch.

---

## Self-Review Checklist (for the plan author)

Reviewed against the spec:

- ✅ **Branch & dependency**: Tasks 1–2.
- ✅ **File layout under `hiterm/Experimental/SwiftTerm/`**: Tasks 4–7, 10–11.
- ✅ **Single AppDelegate edit**: Task 8.
- ✅ **Log.swiftterm category**: Task 3.
- ✅ **SwiftTermSurfaceView with zsh, hard-coded font, exit-on-terminate**: Task 5.
- ✅ **Single-window controller, no tabs/splits/menus**: Task 6.
- ✅ **Env-var-gated entry, ghostty path untouched without env var**: Tasks 7–8 + regression check in Tasks 9, 12.
- ✅ **Pixel-scroll PoC (sub-row offset, wheel interception, row commit, layer translation)**: Tasks 10–11.
- ✅ **Pass criteria per spec § Pixel-scroll PoC**: Task 12 Step 3.
- ✅ **Result memo appended to spec**: Task 12 Step 5.
- ✅ **Branch preserved**: Task 13.
- ✅ **No automated tests**: matches spec's manual-validation stance; gates are explicit.

No placeholders, no "TBD", no "similar to Task N", no undefined types. Method names referenced (`startProcess`, `processDelegate`, `cellDimension`, `getTerminal`, `scrollTo(row:)`, `getTopVisibleRow`, `queuePendingDisplay`) are all real SwiftTerm APIs as of the 1.2.x line; Task 11 includes an explicit substitution note for any version drift.
