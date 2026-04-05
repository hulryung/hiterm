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
