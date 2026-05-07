# SwiftTerm Fork — Extra Rows + Output Slide-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Patch a SwiftTerm fork to render N+2 rows (one above, one below the live viewport) and emit a `didAdvanceViewport` delegate event, then wire hiterm to play an 80ms slide-in animation when the viewport advances on output.

**Architecture:** Two repos. Fork SwiftTerm to `github.com/hulryung/SwiftTerm`, work on branch `hiterm/extra-rows`, push, and pin the resulting commit SHA in hiterm's `project.yml` SPM block. hiterm continues on `experiment/swiftterm`; the wrapper view sizes the surface to `(N+2)·rowHeight` tall, clips with `masksToBounds`, and animates a `+rowHeight → 0` `layer.transform` translation when SwiftTerm reports a viewport advance.

**Tech Stack:** Swift 5.10, AppKit, SwiftTerm fork (CoreGraphics drawing), `CABasicAnimation`, xcodegen, `gh` CLI for fork creation.

**Spec:** `docs/superpowers/specs/2026-05-07-swiftterm-fork-extra-rows-design.md`
**Parent spec:** `docs/superpowers/specs/2026-05-07-swiftterm-experiment-design.md`

---

## Notes for the implementer

1. **You will work in two repos**: hiterm at `/Users/dkkang/dev/hiterm` (existing, on branch `experiment/swiftterm`), and a SwiftTerm fork clone at `/Users/dkkang/dev/SwiftTerm` (you will create it). Always verify your `pwd` before running git commands. Tasks below mark which repo they target.
2. **The fork-patch tasks are exploratory**. SwiftTerm is ~50k lines of Swift across many files; the exact line numbers of the draw loop, line-feed handler, and delegate definition are not pinned in this plan. Each fork task tells you which file to read, which symbol to find, and the exact behavioral rule to apply. Show your read findings and the resulting diff in your task report.
3. **Do not "add appropriate handling"**. Every behavioral rule is stated explicitly. If the rule fails to apply at a site you find, escalate (BLOCKED with specifics) rather than improvise.
4. **Manual validation gate**. Tasks 14 is a user-in-the-loop gate. Implementer should build and prepare the launch command but stop before launching; the controller hands off to the user.
5. **Bundle ID**: hiterm Debug uses `com.hiterm.app.debug`, distinct from the user's installed `com.hiterm.app`. Launching Debug does not kill the installed app, but the controller still confirms with the user before each launch.

---

## Task 1: Create the SwiftTerm fork on GitHub

**Repo:** none (GitHub operation)

**Files:** none

- [ ] **Step 1: Verify `gh` CLI is authenticated**

Run:

```bash
gh auth status
```

Expected: `Logged in to github.com as <username>`. If not authenticated, ask the controller to run `gh auth login` interactively (you cannot complete an interactive login from a subagent).

- [ ] **Step 2: Confirm the GitHub username matches `hulryung`**

The spec assumes the fork lives at `github.com/hulryung/SwiftTerm`. Confirm with `gh api user --jq .login`. If the result is not `hulryung`, **STOP and ask the controller** before forking under a different account.

- [ ] **Step 3: Create the fork**

Run:

```bash
gh repo fork migueldeicaza/SwiftTerm --clone=false --remote=false
```

Expected: `✓ Created fork hulryung/SwiftTerm` (or "already exists" — that's fine, proceed).

- [ ] **Step 4: Verify the fork is reachable**

```bash
gh repo view hulryung/SwiftTerm --json url --jq .url
```

Expected: `https://github.com/hulryung/SwiftTerm`.

No commit in this task.

---

## Task 2: Clone the fork locally and create the working branch

**Repo:** SwiftTerm fork (about to be created)

**Files:** none — clone operation

- [ ] **Step 1: Clone the fork to `/Users/dkkang/dev/SwiftTerm`**

Run:

```bash
test -d /Users/dkkang/dev/SwiftTerm && echo "ALREADY-EXISTS" || git clone https://github.com/hulryung/SwiftTerm /Users/dkkang/dev/SwiftTerm
```

If `ALREADY-EXISTS`: change into it and verify it's the right remote with `git -C /Users/dkkang/dev/SwiftTerm remote get-url origin`. If the URL is the upstream (`migueldeicaza/SwiftTerm`), update it: `git -C /Users/dkkang/dev/SwiftTerm remote set-url origin https://github.com/hulryung/SwiftTerm` and `git -C /Users/dkkang/dev/SwiftTerm fetch origin`.

- [ ] **Step 2: Add `upstream` remote**

```bash
git -C /Users/dkkang/dev/SwiftTerm remote add upstream https://github.com/migueldeicaza/SwiftTerm 2>/dev/null || true
git -C /Users/dkkang/dev/SwiftTerm fetch upstream
```

- [ ] **Step 3: Check out from upstream main, then create `hiterm/extra-rows`**

Find which branch hiterm 1.13.0 is on. The Package.resolved in hiterm pins commit `8e7a1e154f470e19c709a00a8768df348ba5fc43`. Use that as the branch base so the fork patches against the same revision hiterm currently consumes.

```bash
git -C /Users/dkkang/dev/SwiftTerm switch -c hiterm/extra-rows 8e7a1e154f470e19c709a00a8768df348ba5fc43
```

Expected: `Switched to a new branch 'hiterm/extra-rows'`.

- [ ] **Step 4: Verify the working tree builds**

Run:

```bash
cd /Users/dkkang/dev/SwiftTerm && swift build 2>&1 | tail -10
```

Expected: `Build complete!` (may take a few minutes; SwiftTerm has many sources). If swift build fails on this baseline (no patches yet), report BLOCKED — the upstream commit itself is broken and we need a different baseline.

No commit in this task.

---

## Task 3: Survey the SwiftTerm draw code and the viewport-advance call site

**Repo:** SwiftTerm fork (`/Users/dkkang/dev/SwiftTerm`)

**Files:** read-only (no edits in this task)

This task produces the architectural understanding the next two tasks will edit against. Output is a written report in your task summary, not a commit.

- [ ] **Step 1: Locate the cross-platform draw loop**

```bash
grep -n "for.*0.*\.\.<.*\.rows" /Users/dkkang/dev/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift
```

Identify the for-loop that iterates over rows for drawing. Note the line number and the expression used (`for row in 0..<terminal.rows` or similar).

- [ ] **Step 2: Locate the y-coordinate mapping for a row**

In the same draw function, find where `row` becomes a y-pixel coordinate. Common pattern: `let y = CGFloat(row) * cellDimension.height` or `y = ... - row * cellHeight`. Note the exact expression.

- [ ] **Step 3: Locate cursor draw and selection draw**

```bash
grep -n "drawCursor\|cursor\|selection" /Users/dkkang/dev/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift | head -30
```

Find the conditional that decides which row gets the cursor and which rows are inside the selection. Note where these tie into the row index used in Step 2.

- [ ] **Step 4: Locate the line-feed (output advance) site in `Terminal.swift`**

```bash
grep -n "func feed\|cmdLineFeed\|lineFeed\|advance.*viewport\|scroll.*1\|yDisp" /Users/dkkang/dev/SwiftTerm/Sources/SwiftTerm/Terminal.swift | head -30
```

Find the function that processes a `\n` from the data stream and causes the terminal to scroll the viewport up by one. The patch in Task 6 will call our new delegate from this site (or wherever in the view that "after viewport advanced" can be cleanly detected — could also be in `AppleTerminalView`'s redraw queue once it sees the scroll happened).

- [ ] **Step 5: Locate `TerminalViewDelegate`**

```bash
grep -rn "protocol TerminalViewDelegate" /Users/dkkang/dev/SwiftTerm/Sources/SwiftTerm/
```

Note the file and line. The new `didAdvanceViewport(source:by:)` will go here.

- [ ] **Step 6: Locate buffer access for "rows above viewport" and "rows past live tail"**

```bash
grep -n "yDisp\|yBase\|buffer.lines\|getLine" /Users/dkkang/dev/SwiftTerm/Sources/SwiftTerm/Terminal.swift | head -40
```

Identify the public properties/methods that can return:
- A buffer line at index `yDisp - 1` (one row above current viewport top), or `nil`/blank if `yDisp == 0`.
- A buffer line at index `yBase + rows` (one row below current viewport bottom), or `nil`/blank if no such line exists.

The draw code in Step 1 likely already computes a buffer line for each viewport row from `yDisp + row`. The patch extends this expression to cover row = -1 and row = rows.

- [ ] **Step 7: Report**

In your task report, list:

```
- Draw loop site: AppleTerminalView.swift:<line>, expression: <code>
- Y mapping: <expression>, file:<line>
- Cursor draw site: <file:line>
- Selection draw site: <file:line>
- Line-feed site (best place to call delegate): <file:line>
- TerminalViewDelegate definition: <file:line>
- Buffer access for above/below: <expression(s)>
- Concerns / surprises:
```

If anything is structured differently than this plan assumes (e.g., draw code is inside `MacTerminalView.swift` and not `AppleTerminalView.swift`, or there is no central draw loop), report the actual structure and stop — the controller will adapt the plan rather than have you guess.

No commit in this task.

---

## Task 4: Add `extraRowsAbove` / `extraRowsBelow` properties (no draw changes yet)

**Repo:** SwiftTerm fork

**Files:**
- Modify: the file that declares `TerminalView` or `AppleTerminalView` — the same class that hosts the draw loop you found in Task 3.

- [ ] **Step 1: Add the public properties**

Add to the class (likely `AppleTerminalView` or its parent), near other public configuration properties:

```swift
/// Number of rows to render above the live viewport, sourced from scrollback.
/// Default 0 preserves existing behavior. Cursor and selection are not drawn
/// in this region; mouse hit-testing clamps to the viewport.
public var extraRowsAbove: Int = 0

/// Number of rows to render below the live viewport, sourced from buffer
/// lines past the live tail (e.g. lines just appended by output but not yet
/// promoted into the viewport).
public var extraRowsBelow: Int = 0
```

- [ ] **Step 2: Build to confirm no regressions**

```bash
cd /Users/dkkang/dev/SwiftTerm && swift build 2>&1 | tail -5
```

Expected: `Build complete!`. The properties are unused; adding them alone must not break the build.

- [ ] **Step 3: Commit**

```bash
cd /Users/dkkang/dev/SwiftTerm
git add -A
git commit -m "Add extraRowsAbove/Below properties (no behavior yet)"
```

---

## Task 5: Patch the draw loop to iterate extra rows

**Repo:** SwiftTerm fork

**Files:** the draw-function file from Task 3 (likely `Sources/SwiftTerm/Apple/AppleTerminalView.swift`).

This task has the highest implementation risk. **Read the draw function in full before editing.** The patch is conceptually simple but the surrounding code may impose constraints.

**Behavioral rule:**
- Replace the row iteration `for row in 0..<terminal.rows` with `for row in -extraRowsAbove ..< (terminal.rows + extraRowsBelow)`.
- Replace the y mapping `y = row * cellHeight` (or whatever you found) with `y = (row + extraRowsAbove) * cellHeight`. The visual offset of the entire drawing area shifts down by `extraRowsAbove * cellHeight`, so the viewport's first visible row sits at `y = extraRowsAbove * cellHeight` in the view's coordinate space.
- For row indices outside `0..<terminal.rows`, the buffer line index used to fetch row data must be `yDisp + row` (which becomes `yDisp - 1` for `row = -1` and `yBase + terminal.rows` for `row = terminal.rows` — verify these expressions match the buffer access pattern you found in Task 3 Step 6). If the buffer doesn't have a line there, draw an empty (background-only) row.

- [ ] **Step 1: Apply the loop bounds change**

Edit the draw function. Show the diff in your report.

- [ ] **Step 2: Apply the y mapping change**

Same function. Show the diff.

- [ ] **Step 3: Handle out-of-range buffer access**

Where the draw function fetches a buffer line for the current `row`, wrap or branch the access so out-of-range row indices yield a blank row (background fill, no glyphs). Use the existing "blank row" rendering path if there is one (e.g., after end-of-text); otherwise emit a background-color fill rect for that y-range and `continue` the loop.

- [ ] **Step 4: Build**

```bash
cd /Users/dkkang/dev/SwiftTerm && swift build 2>&1 | tail -10
```

Expected: `Build complete!`. If the buffer access path can't gracefully blank-fill, report BLOCKED with what you found.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Draw extra rows above and below the live viewport"
```

---

## Task 6: Skip cursor and selection in extra rows; clamp hit-testing

**Repo:** SwiftTerm fork

**Files:** same draw file plus any mouse / hit-test files identified in Task 3.

**Behavioral rules:**
- Cursor: only draw if the cursor's row index is in `0..<terminal.rows`. The cursor row should NOT shift visually due to extra rows — its y is computed in the same shifted space.
- Selection: a selected cell only fills its background when its row index is in `0..<terminal.rows`. Selection rendering for `row < 0` or `row >= terminal.rows` is skipped entirely.
- Mouse hit-testing: when converting a click's y coordinate to a row index, clamp the result to `0..<terminal.rows`. A click in the extra-row gutter is treated as a click on the nearest viewport row.

- [ ] **Step 1: Cursor**

Find the cursor-draw site from Task 3. Wrap with a guard:

```swift
if row >= 0 && row < terminal.rows {
    // ... existing cursor draw ...
}
```

(Adapt to the actual variable name and the actual flow — the cursor may be drawn outside the row loop. If so, use the cursor's row as `cursorRow` and apply the same guard.)

- [ ] **Step 2: Selection**

Same approach for the selection background draw — guard on `row` being in the viewport range.

- [ ] **Step 3: Hit-test**

Find the file/function that converts an `NSPoint` to a `(row, col)` pair. After computing `row`, clamp:

```swift
let row = max(0, min(terminal.rows - 1, computedRow))
```

If `cellDimension.height` was used to compute `row`, remember to subtract `extraRowsAbove * cellHeight` from the y first, OR recognize that the y you receive is in the wrapper's coordinate space which (in hiterm's wrapper) already excludes the extra-row gutters. In your report, document which coordinate space the hit-test sees and adjust accordingly.

- [ ] **Step 4: Build**

```bash
cd /Users/dkkang/dev/SwiftTerm && swift build 2>&1 | tail -10
```

Expected: `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Suppress cursor/selection in extra-row regions; clamp hit-testing to viewport"
```

---

## Task 7: Add `didAdvanceViewport` to `TerminalViewDelegate` and call it from the line-feed path

**Repo:** SwiftTerm fork

**Files:** the file declaring `TerminalViewDelegate` (from Task 3 Step 5), plus the line-feed call site file (Task 3 Step 4).

- [ ] **Step 1: Add the delegate method with a default implementation**

In the file declaring `TerminalViewDelegate`, add to the protocol:

```swift
/// Called immediately after the viewport advances by N rows due to terminal
/// output (typically a line feed). `lines` is positive (1 for a typical line
/// feed). NOT called for programmatic scroll, IME, or user-driven scrollback
/// navigation. Default implementation does nothing — adopters opt in.
func didAdvanceViewport(source: TerminalView, by lines: Int)
```

In the same file, add a protocol extension with a default empty implementation so existing adopters do not break:

```swift
public extension TerminalViewDelegate {
    func didAdvanceViewport(source: TerminalView, by lines: Int) {}
}
```

- [ ] **Step 2: Call the delegate from the line-feed site**

In the line-feed site (Task 3 Step 4), at the point where the viewport has just advanced (i.e. yBase has just incremented and the new bottom row is in place), call:

```swift
delegate?.didAdvanceViewport(source: self, by: 1)
```

Use the actual delegate property name and type from the surrounding code. If the line-feed handler lives on `Terminal` (the model) rather than `TerminalView`, you may need to plumb the call through a callback. **In that case, prefer to call from the `TerminalView` redraw path** at the moment the view notices the advance (e.g. wherever `setNeedsDisplay` is called in response to a scroll). Document your choice in the commit message.

- [ ] **Step 3: Build**

```bash
cd /Users/dkkang/dev/SwiftTerm && swift build 2>&1 | tail -10
```

Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add didAdvanceViewport delegate hook for output-driven scroll"
```

---

## Task 8: Push the fork branch and capture the commit SHA

**Repo:** SwiftTerm fork

**Files:** none

- [ ] **Step 1: Push**

```bash
cd /Users/dkkang/dev/SwiftTerm
git push -u origin hiterm/extra-rows
```

Expected: branch published successfully.

- [ ] **Step 2: Capture the head SHA**

```bash
git -C /Users/dkkang/dev/SwiftTerm rev-parse HEAD
```

Record the SHA. You will use it in Task 9.

In your task report, output:

```
Fork branch: hulryung/SwiftTerm @ hiterm/extra-rows
Head SHA: <40-char SHA>
```

No commit in this task.

---

## Task 9: Point hiterm at the fork

**Repo:** hiterm (`/Users/dkkang/dev/hiterm`)

**Files:**
- Modify: `project.yml` — `packages.SwiftTerm` block

- [ ] **Step 1: Update `project.yml`**

Replace the `packages:` block to point to the fork and pin by revision. Find the existing block:

```yaml
packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.2.0"
```

Replace with:

```yaml
packages:
  SwiftTerm:
    url: https://github.com/hulryung/SwiftTerm
    revision: <SHA-from-task-8>
```

Where `<SHA-from-task-8>` is the actual 40-char SHA captured in Task 8.

- [ ] **Step 2: Regenerate the Xcode project**

```bash
cd /Users/dkkang/dev/hiterm && xcodegen generate
```

- [ ] **Step 3: Resolve packages and build**

```bash
cd /Users/dkkang/dev/hiterm
xcodebuild -resolvePackageDependencies -scheme hiterm 2>&1 | tail -5
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. SPM should now fetch from the fork.

- [ ] **Step 4: Commit**

```bash
cd /Users/dkkang/dev/hiterm
git add project.yml hiterm.xcodeproj
git commit -m "Point SwiftTerm SPM dependency at hulryung fork (extra-rows branch)"
```

---

## Task 10: Enable extra rows in the surface and resize the wrapper layout

**Repo:** hiterm

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift`
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift`

- [ ] **Step 1: Set extra rows in `SwiftTermSurfaceView.configure()`**

In `SwiftTermSurfaceView.swift`, inside `configure()`, after the `font = resolved` line (around line 25), add:

```swift
        extraRowsAbove = 1
        extraRowsBelow = 1
```

- [ ] **Step 2: Add layout in `SwiftTermPixelScrollLayer`**

In `SwiftTermPixelScrollLayer.swift`, replace the existing `surface.autoresizingMask = [.width, .height]` line in `init(frame:)` with explicit layout management. The new structure:

In `init(frame: NSRect)`, change:

```swift
        addSubview(surface)
        surface.autoresizingMask = [.width, .height]
        surface.wantsLayer = true
```

to:

```swift
        addSubview(surface)
        // surface frame is laid out manually in layout() because it must extend
        // one rowHeight above and below the wrapper bounds to expose the
        // SwiftTerm fork's extraRowsAbove/Below regions.
        surface.wantsLayer = true
        layer?.masksToBounds = true
```

Then add a `layout()` override after `viewDidMoveToWindow()`:

```swift
    override func layout() {
        super.layout()
        let h = rowHeight
        var f = bounds
        f.size.height += 2 * h
        f.origin.y = -h
        surface.frame = f
    }
```

Also force a re-layout when the wrapper's size changes. Add at the end of `init(frame:)`:

```swift
        postsFrameChangedNotifications = true
```

And add at the end of `viewDidMoveToWindow()` (after the existing scroll monitor setup):

```swift
        needsLayout = true
```

- [ ] **Step 3: Build**

```bash
cd /Users/dkkang/dev/hiterm
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift
git commit -m "Enable SwiftTerm extra rows and lay out surface bigger than wrapper"
```

---

## Task 11: Wire the `didAdvanceViewport` callback through the surface

**Repo:** hiterm

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift`

- [ ] **Step 1: Adopt the new delegate method**

In `SwiftTermSurfaceView.swift`, add a method to the existing `// MARK: - LocalProcessTerminalViewDelegate` section (after `processTerminated`):

```swift
    func didAdvanceViewport(source: TerminalView, by lines: Int) {
        Log.swiftterm.debug("Viewport advanced by \(lines)")
        if let wrapper = superview as? SwiftTermPixelScrollLayer {
            wrapper.handleViewportAdvance(lines: lines)
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If the build fails because `didAdvanceViewport` is not in the protocol, double-check the SPM revision in `project.yml` matches the fork SHA from Task 8 (Task 7 added the protocol method).

- [ ] **Step 3: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermSurfaceView.swift
git commit -m "Forward didAdvanceViewport from surface to scroll-layer wrapper"
```

---

## Task 12: Implement the slide-in animation in the wrapper

**Repo:** hiterm

**Files:**
- Modify: `hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift`

- [ ] **Step 1: Add animation state and the public handler**

In `SwiftTermPixelScrollLayer.swift`, add a stored property next to `accumulatedPixelOffset` (around line 25):

```swift
    private var isAnimatingAdvance: Bool = false
```

Add `CAAnimationDelegate` conformance to the class declaration (line 21):

```swift
final class SwiftTermPixelScrollLayer: NSView, CAAnimationDelegate {
```

Add a new method, after `applyLayerTranslation()` (end of file):

```swift
    // MARK: - Output-driven advance animation

    /// Called by SwiftTermSurfaceView when SwiftTerm's `didAdvanceViewport`
    /// fires. Plays an 80ms slide-in: the surface layer is translated +rowHeight
    /// (visually showing the prior viewport with the just-appended line drawn
    /// in extraRowsBelow), then animated back to identity. Bursts of multi-line
    /// or rapid advances skip the animation so output throughput is unaffected.
    func handleViewportAdvance(lines: Int) {
        guard lines == 1, !isAnimatingAdvance else { return }
        guard let layer = surface.layer else { return }
        let h = rowHeight
        isAnimatingAdvance = true

        let from = CATransform3DMakeTranslation(0, h, 0)
        let to = CATransform3DIdentity

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: to)
        anim.duration = 0.08
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.delegate = self

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = to
        layer.add(anim, forKey: "advanceSlide")
        CATransaction.commit()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        isAnimatingAdvance = false
        // Re-apply user-scroll translation in case the user scrolled during animation.
        applyLayerTranslation()
    }
```

- [ ] **Step 2: Coordinate with the user-scroll transform**

The user-scroll path calls `applyLayerTranslation()` which writes `layer.transform` from `accumulatedPixelOffset`. During an advance animation, that write would clobber the animation. Update `applyLayerTranslation()` (find the existing method around line 168) to bail out when an advance is in flight:

Replace:

```swift
    private func applyLayerTranslation() {
        guard let layer = surface.layer else { return }
        // SwiftTerm 1.13.0: translating via `bounds.origin.y` competes with the
        // surface's internal `setNeedsDisplay` / `draw(_:)` cycle on row commits,
        // producing visible micro-stutter at slow scroll. `transform`-based
        // translation is applied late in the render pipeline and does not
        // interact with bounds/layout, so it survives redraws cleanly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, -accumulatedPixelOffset, 0)
        CATransaction.commit()
    }
```

with:

```swift
    private func applyLayerTranslation() {
        guard let layer = surface.layer else { return }
        // While an output-advance animation is running, leave the layer
        // transform alone so the animation's interpolated value stays visible.
        // The animationDidStop callback re-invokes this method to resume
        // user-scroll translation.
        if isAnimatingAdvance { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, -accumulatedPixelOffset, 0)
        CATransaction.commit()
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add hiterm/Experimental/SwiftTerm/SwiftTermPixelScrollLayer.swift
git commit -m "Play 80ms slide-in animation when SwiftTerm reports viewport advance"
```

---

## Task 13: Mouse hit-test sanity check inside hiterm

**Repo:** hiterm

**Files:** read-only check

The fork patch (Task 6) clamps hit-testing to viewport rows. Verify that when hiterm passes mouse events to the SwiftTerm surface, the click on the extra-row gutter is interpreted as the nearest viewport row and not as a row outside the grid.

- [ ] **Step 1: Build**

(Already built in Task 12.)

- [ ] **Step 2: Manual click test (controller-driven)**

This step is checked at gate 14 below; no separate launch. Document in your report that this is the expected behavior to verify there.

No commit in this task.

---

## Task 14: Manual validation gate — extra rows visible + slide-in works

**Repo:** hiterm

**Files:** none — runtime check

This is a **gate**. Do not proceed to Task 15 until all checks pass. The implementer should prepare the launch command and stop; the controller hands off to the user.

- [ ] **Step 1: Confirm with the user before launching Debug**

Send: "About to launch the Debug build (`com.hiterm.app.debug`) for SwiftTerm fork extra-rows validation. The installed `com.hiterm.app` is unaffected. OK to proceed?"

Wait for confirmation.

- [ ] **Step 2: Build and capture the app path**

```bash
cd /Users/dkkang/dev/hiterm
xcodebuild -scheme hiterm -configuration Debug build 2>&1 | tail -3
APP_PATH=$(xcodebuild -scheme hiterm -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')
echo "$APP_PATH/hiterm.app"
```

- [ ] **Step 3: Launch the experiment path**

```bash
HITERM_BACKEND=swiftterm "$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Hand off to the user to verify each criterion:

1. Window opens with zsh prompt. (As before.)
2. Run `seq 1 200`, then scroll back manually with the trackpad. At sub-row offsets, an extra row peeks from the top edge (proving extraRowsAbove is being drawn).
3. Type `echo hi` and press Return. The new prompt+output line slides into view from below over ~80ms instead of appearing instantly.
4. Type `seq 1 5` quickly. The first line animates; subsequent lines appear without stutter or duplicate frames.
5. Run `cat /usr/share/dict/words | head -200`. Burst output appears at full speed without stutter.
6. Cursor is never visible inside the extra-row gutters at top/bottom.
7. Try clicking inside the very top edge of the wrapper (the extra-row region) — the click should select the nearest viewport row, not a row "outside" the grid.

- [ ] **Step 4: Regression check**

```bash
"$APP_PATH/hiterm.app/Contents/MacOS/hiterm" &
```

Expected: existing ghostty UI unchanged. Quit.

- [ ] **Step 5: Record results in the spec**

Append to `docs/superpowers/specs/2026-05-07-swiftterm-fork-extra-rows-design.md` under a new `## Result` heading:

```markdown
## Result (recorded YYYY-MM-DD)

- Extra row visible during user scroll: PASS / FAIL — <observation>
- Single-line slide-in: PASS / FAIL — <observation>
- Burst output unaffected: PASS / FAIL — <observation>
- Cursor not in extra-row gutters: PASS / FAIL
- Hit-test clamps to viewport: PASS / FAIL
- Regression (ghostty path): PASS / FAIL
- Notes: <SwiftTerm patch surprises, perf feel, anything else>

Decision: <bring forward to migration spec> | <abandon, preserve fork branch and revisit>
```

- [ ] **Step 6: Commit the result**

```bash
cd /Users/dkkang/dev/hiterm
git add docs/superpowers/specs/2026-05-07-swiftterm-fork-extra-rows-design.md
git commit -m "Record SwiftTerm fork + slide-in PoC results"
```

If any check fails, **stop**. Do not proceed to Task 15. Report which check failed and what was observed; the controller decides whether to debug, adjust the patch, or abandon the approach.

---

## Task 15: Push branches

**Repo:** both

**Files:** none

- [ ] **Step 1: Confirm with the user before pushing**

Send: "About to push `experiment/swiftterm` (hiterm) updates to origin. The SwiftTerm fork branch was already pushed in Task 8. OK to push hiterm?"

Wait for confirmation.

- [ ] **Step 2: Push hiterm**

```bash
cd /Users/dkkang/dev/hiterm
git push origin experiment/swiftterm
```

- [ ] **Step 3: Stop**

Per the spec: production migration is out of scope. Do not start replacing the ghostty path on this branch.

---

## Self-Review Checklist

Reviewed the plan against the spec:

- ✅ **Fork on hulryung/SwiftTerm with `hiterm/extra-rows` branch**: Tasks 1, 2, 8.
- ✅ **`extraRowsAbove` / `extraRowsBelow` properties added**: Task 4.
- ✅ **Draw loop iterates over extra rows; y mapping shifted**: Task 5.
- ✅ **Cursor / selection skipped in extra rows; hit-test clamped**: Task 6.
- ✅ **`didAdvanceViewport(source:by:)` delegate hook added and called**: Task 7.
- ✅ **hiterm SPM URL switched to fork + revision pin**: Task 9.
- ✅ **Surface enables extras; wrapper resizes & clips**: Task 10.
- ✅ **Surface forwards `didAdvanceViewport` to wrapper**: Task 11.
- ✅ **Wrapper plays 80ms slide-in animation, coordinates with user-scroll transform**: Task 12.
- ✅ **Manual validation against all 7 acceptance criteria**: Task 14.
- ✅ **Result recorded in spec**: Task 14 Step 5.
- ✅ **Branches preserved (fork pushed Task 8; hiterm pushed Task 15)**.

Placeholder scan: `<SHA-from-task-8>` and `YYYY-MM-DD` are intentional fill-ins at execution time, not abstract TODOs. No "add appropriate handling" — every behavioral rule is stated explicitly. Type/method consistency: `extraRowsAbove`/`extraRowsBelow` (props), `didAdvanceViewport(source:by:)` (delegate), `handleViewportAdvance(lines:)` (wrapper), `isAnimatingAdvance` (state), `applyLayerTranslation()` (existing) — all consistent across tasks. The fork-task code-show rules are relaxed where the SwiftTerm source is read at execution time; each such task gives the file-and-symbol target plus the exact behavioral rule to apply, and demands the implementer report the actual diff.
