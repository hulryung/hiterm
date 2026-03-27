import AppKit

/// Custom tab bar with close buttons and new tab button.
class TabBarView: NSView {
    var onTabSelected: ((Int) -> Void)?
    var onTabClosed: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private var tabButtons: [TabButton] = []
    private let newTabButton = NSButton()
    private let stackView = NSStackView()
    private var selectedIndex: Int = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0).cgColor

        stackView.orientation = .horizontal
        stackView.spacing = 1
        stackView.alignment = .centerY
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        // New tab button
        newTabButton.title = "+"
        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.font = .systemFont(ofSize: 16, weight: .light)
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newTabButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 78),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: newTabButton.leadingAnchor, constant: -4),

            newTabButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),
        ])
    }

    func updateSelection(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        for (i, button) in tabButtons.enumerated() {
            button.updateSelected(i == index)
        }
    }

    func updateTabs(titles: [String], selectedIndex: Int) {
        self.selectedIndex = selectedIndex

        if tabButtons.count == titles.count {
            // Same number of tabs: update in-place (no flicker).
            for (i, button) in tabButtons.enumerated() {
                button.updateTitle(titles[i])
                button.updateSelected(i == selectedIndex)
            }
            return
        }

        // Tab count changed: rebuild.
        tabButtons.forEach { $0.removeFromSuperview() }
        tabButtons.removeAll()

        for (i, title) in titles.enumerated() {
            let button = TabButton(title: title, index: i, isSelected: i == selectedIndex)
            button.onSelected = { [weak self] idx in
                self?.onTabSelected?(idx)
            }
            button.onClosed = { [weak self] idx in
                self?.onTabClosed?(idx)
            }
            tabButtons.append(button)
            stackView.addArrangedSubview(button)
        }
    }

    @objc private func newTabClicked() {
        onNewTab?()
    }
}

// MARK: - Tab Button

class TabButton: NSView {
    var onSelected: ((Int) -> Void)?
    var onClosed: ((Int) -> Void)?

    private let index: Int
    private(set) var isSelected: Bool
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    init(title: String, index: Int, isSelected: Bool) {
        self.index = index
        self.isSelected = isSelected
        super.init(frame: .zero)
        setup(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setup(title: String) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected
            ? NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0).cgColor
            : NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0).cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        titleLabel.textColor = isSelected ? .white : NSColor(white: 0.55, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = !isSelected
        addSubview(closeButton)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tabClicked))
        addGestureRecognizer(click)
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    func updateSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = selected
            ? NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0).cgColor
            : NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0).cgColor
        titleLabel.textColor = selected ? .white : NSColor(white: 0.55, alpha: 1.0)
        closeButton.isHidden = !selected
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor(red: 0.22, green: 0.22, blue: 0.23, alpha: 1.0).cgColor
        }
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0).cgColor
        }
        closeButton.isHidden = !isSelected
    }

    @objc private func tabClicked() {
        onSelected?(index)
    }

    @objc private func closeTapped() {
        onClosed?(index)
    }
}
