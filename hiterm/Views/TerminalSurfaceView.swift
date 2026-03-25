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
    private var markedText: String = ""

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

        if let surface {
            let scaleFactor = window?.backingScaleFactor ?? 2.0
            ghostty_surface_set_size(
                surface,
                UInt32(bounds.width * scaleFactor),
                UInt32(bounds.height * scaleFactor)
            )
            ghostty_surface_set_content_scale(surface, scaleFactor, scaleFactor)
        }
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

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        interpretKeyEvents([event])

        // If interpretKeyEvents didn't produce text, send the raw key event
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = mods
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = false

        if let chars = event.characters, !chars.isEmpty {
            chars.withCString { ptr in
                keyEvent.text = ptr
                ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.mods = mods
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.text = nil
        keyEvent.composing = false
        ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifier keys changed - libghostty handles this via key events
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface else { return }
        guard let str = string as? String else { return }
        str.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(str.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let surface else { return }
        if let str = string as? String {
            markedText = str
            str.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(str.utf8.count))
            }
        }
    }

    func unmarkText() {
        guard let surface else { return }
        markedText = ""
        ghostty_surface_preedit(surface, nil, 0)
    }

    func hasMarkedText() -> Bool {
        return !markedText.isEmpty
    }

    func markedRange() -> NSRange {
        if markedText.isEmpty { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.utf16.count)
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
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let point = convert(NSPoint(x: x, y: frame.height - y - h), to: nil)
        let screenPoint = window?.convertPoint(toScreen: point) ?? point
        return NSRect(x: screenPoint.x, y: screenPoint.y, width: w, height: h)
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
            x *= 2
            y *= 2
        }

        // Build scroll mods: precision bit (bit 0) + momentum phase (bits 1-3)
        var scrollMods: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            scrollMods |= 1 // precision flag
        }

        let momentumPhase: Int32
        switch event.momentumPhase {
        case .began: momentumPhase = 1
        case .stationary: momentumPhase = 2
        case .changed: momentumPhase = 3
        case .ended: momentumPhase = 4
        case .cancelled: momentumPhase = 5
        case .mayBegin: momentumPhase = 6
        default: momentumPhase = 0
        }
        scrollMods |= (momentumPhase << 1)

        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
    }

    private func sendMousePos(event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = Self.ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
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
}
