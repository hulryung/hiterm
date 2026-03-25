import AppKit
import GhosttyKit

/// NSView that hosts a single ghostty terminal surface with Metal rendering.
class TerminalSurfaceView: NSView, NSTextInputClient {
    private let ghosttyApp: GhosttyApp
    private(set) var surface: ghostty_surface_t?
    var title: String = "hiterm" {
        didSet { onTitleChanged?(title) }
    }
    var onTitleChanged: ((String) -> Void)?
    var onClosed: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var markedText = NSMutableAttributedString()


    init(ghosttyApp: GhosttyApp, frame: NSRect = NSRect(x: 0, y: 0, width: 800, height: 600)) {
        self.ghosttyApp = ghosttyApp
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSetTitle(_:)),
            name: .hitermSetTitle,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseSurface(_:)),
            name: .hitermCloseSurface,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    // MARK: - Surface Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tryCreateSurface()
    }

    override func layout() {
        super.layout()
        tryCreateSurface()
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface else { return }
        let scaleFactor = window?.backingScaleFactor ?? 2.0
        // Tell libghostty to render for our full frame (which is taller than the clip).
        ghostty_surface_set_size(
            surface,
            UInt32(bounds.width * scaleFactor),
            UInt32(bounds.height * scaleFactor)
        )
        ghostty_surface_set_content_scale(surface, scaleFactor, scaleFactor)
    }

    private func tryCreateSurface() {
        guard window != nil,
              surface == nil,
              let app = ghosttyApp.app,
              bounds.width > 0, bounds.height > 0 else { return }
        createSurface(app: app)
    }

    private func createSurface(app: ghostty_app_t) {
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()

        if let screen = window?.screen ?? NSScreen.main {
            cfg.scale_factor = screen.backingScaleFactor
        } else {
            cfg.scale_factor = 2.0
        }

        cfg.font_size = 0 // use config default
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        self.surface = ghostty_surface_new(app, &cfg)

        if let surface {
            let size = frame.size
            let scaleFactor = window?.backingScaleFactor ?? 2.0
            ghostty_surface_set_size(
                surface,
                UInt32(size.width * scaleFactor),
                UInt32(size.height * scaleFactor)
            )
            ghostty_surface_set_focus(surface, true)
        }
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { surface.map { ghostty_surface_set_focus($0, true) } }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { surface.map { ghostty_surface_set_focus($0, false) } }
        return result
    }

    // MARK: - Keyboard Input

    /// Non-nil when inside keyDown; collects text from insertText during interpretKeyEvents.
    private var keyTextAccumulator: [String]?

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let markedTextBefore = markedText.length > 0

        // Begin accumulating text from interpretKeyEvents (IME).
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([event])

        // Sync preedit (composing) state to libghostty after IME processing.
        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            // IME produced composed text — send each piece via ghostty_surface_key.
            for text in list {
                keyAction(action, event: event, text: text, composing: false)
            }
        } else {
            // No composed text — send raw key event.
            // composing=true if we have preedit or just cleared it.
            let composing = markedText.length > 0 || markedTextBefore
            let text = ghosttyCharacters(from: event)
            keyAction(action, event: event, text: text, composing: composing)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.mods = Self.ghosttyMods(from: event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = 0
        ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier keys changed — libghostty handles this via key events.
    }

    override func doCommand(by selector: Selector) {
        // Suppress NSBeep for unhandled selectors (e.g., insertNewline: for Enter).
    }

    /// Build and send a key event to libghostty.
    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        text: String?,
        composing: Bool
    ) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = Self.ghosttyMods(from: event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = composing

        // consumed_mods: assume shift/option contributed to text, ctrl/cmd did not.
        keyEvent.consumed_mods = Self.ghosttyMods(
            from: event.modifierFlags.subtracting([.control, .command])
        )

        // unshifted_codepoint: codepoint with no modifiers applied.
        keyEvent.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEvent.unshifted_codepoint = codepoint.value
            }
        }

        // Only embed text if it's a printable character (>= 0x20).
        if let text, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20 {
            text.withCString { ptr in
                keyEvent.text = ptr
                ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Extract characters suitable for libghostty from an NSEvent.
    private func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            // Control characters: strip control modifier and re-derive.
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            // Function keys (PUA range): don't send.
            if scalar.value >= 0xF700, scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }

    /// Sync preedit (composing) state to libghostty.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }

        // Composition is done — clear preedit.
        unmarkText()

        // If inside keyDown, accumulate for later dispatch.
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
            return
        }

        // Outside keyDown (e.g., paste) — send directly.
        guard let surface else { return }
        let len = chars.utf8CString.count
        if len > 0 {
            chars.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: v)
        case let v as String:
            markedText = NSMutableAttributedString(string: v)
        default:
            return
        }

        // If not inside keyDown, sync preedit immediately (e.g., keyboard layout change).
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func hasMarkedText() -> Bool {
        return markedText.length > 0
    }

    func markedRange() -> NSRange {
        if markedText.length == 0 { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        return NSRange(location: NSNotFound, length: 0)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else {
            return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)

        // ghostty_surface_ime_point returns point coordinates with top-left origin.
        // Convert to AppKit bottom-left origin (matching Ghostty's implementation).
        let viewRect = NSRect(
            x: x,
            y: frame.size.height - y,
            width: w,
            height: max(h, 1)
        )

        let winRect = convert(viewRect, to: nil)
        guard let window else { return winRect }
        return window.convertToScreen(winRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePos(event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2; y *= 2
        }

        var mods: Int32 = event.hasPreciseScrollingDeltas ? 1 : 0
        let momentum: Int32
        switch event.momentumPhase {
        case .began: momentum = 1
        case .stationary: momentum = 2
        case .changed: momentum = 3
        case .ended: momentum = 4
        case .cancelled: momentum = 5
        case .mayBegin: momentum = 6
        default: momentum = 0
        }
        mods |= (momentum << 1)
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    private func sendMousePos(event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    // MARK: - Copy / Paste

    @objc func copy(_ sender: Any?) {
        guard let surface else { return }
        guard ghostty_surface_has_selection(surface) else { return }

        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return }
        defer { ghostty_surface_free_text(surface, &text) }

        if let ptr = text.text, text.text_len > 0 {
            let str = String(cString: ptr)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(str, forType: .string)
        }
    }

    @objc func paste(_ sender: Any?) {
        guard let surface else { return }
        let pasteboard = NSPasteboard.general
        guard let str = pasteboard.string(forType: .string) else { return }
        let len = str.utf8CString.count
        if len > 0 {
            str.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }
    }

    // MARK: - Modifier Translation

    static func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    // MARK: - Notifications

    @objc private func handleSetTitle(_ notification: Notification) {
        guard let notifSurface = notification.object as? UnsafeMutableRawPointer,
              notifSurface == surface else { return }
        if let title = notification.userInfo?["title"] as? String {
            self.title = title
        }
    }

    @objc private func handleCloseSurface(_ notification: Notification) {
        // Check if this notification is for us (compare userdata pointer).
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let notifPtr = notification.object as? UnsafeMutableRawPointer,
              notifPtr == selfPtr else { return }
        onClosed?()
    }
}
