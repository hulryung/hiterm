import AppKit

/// Custom tab bar with close buttons and new tab button.
class TabBarView: NSView {
    var onTabSelected: ((Int) -> Void)?
    var onTabClosed: ((Int) -> Void)?
    var onNewTab: (() -> Void)?

    private var tabButtons: [TabButton] = []
    private let newTabButton = NSButton()
    private let logoIcon = NSImageView()
    private let logoLabel = NSTextField(labelWithString: "HI! TERM")
    private var selectedIndex: Int = 0

    private let defaultLeadingPad: CGFloat = 78
    private let trailingPad: CGFloat = 36
    private var isFullscreen = false
    private let tabSpacing: CGFloat = 2
    private let maxTabWidth: CGFloat = 200
    private let minTabWidth: CGFloat = 50

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

        // Logo icon + label (hidden by default, shown in fullscreen).
        if let appIcon = NSImage(named: "AppIcon") {
            logoIcon.image = appIcon
        }
        logoIcon.imageScaling = .scaleProportionallyUpOrDown
        logoIcon.isHidden = true
        addSubview(logoIcon)

        logoLabel.font = .systemFont(ofSize: 11, weight: .bold)
        logoLabel.textColor = NSColor(white: 0.45, alpha: 1.0)
        logoLabel.isEditable = false
        logoLabel.isBezeled = false
        logoLabel.drawsBackground = false
        logoLabel.isHidden = true
        addSubview(logoLabel)

        newTabButton.title = "+"
        newTabButton.bezelStyle = .inline
        newTabButton.isBordered = false
        newTabButton.font = .systemFont(ofSize: 16, weight: .light)
        newTabButton.contentTintColor = .secondaryLabelColor
        newTabButton.target = self
        newTabButton.action = #selector(newTabClicked)
        addSubview(newTabButton)
    }

    override func layout() {
        super.layout()
        layoutTabs()
    }

    private func layoutTabs() {
        // Logo: icon + "HI! TERM" in the leading 78px area.
        let iconSize: CGFloat = 20
        let iconX: CGFloat = 10
        let iconY = (bounds.height - iconSize) / 2
        logoIcon.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        logoLabel.sizeToFit()
        logoLabel.frame.origin = NSPoint(x: iconX + iconSize + 4, y: (bounds.height - logoLabel.frame.height) / 2)

        let btnSize: CGFloat = 28
        newTabButton.frame = NSRect(
            x: bounds.width - btnSize - 8,
            y: (bounds.height - btnSize) / 2,
            width: btnSize,
            height: btnSize
        )

        guard !tabButtons.isEmpty else { return }
        // In fullscreen, leading pad = logo width + padding. Otherwise, space for traffic lights.
        let leadingPad: CGFloat
        if isFullscreen {
            leadingPad = logoLabel.frame.maxX + 10
        } else {
            leadingPad = defaultLeadingPad
        }
        let count = CGFloat(tabButtons.count)
        let available = bounds.width - leadingPad - trailingPad - tabSpacing * (count - 1)
        let perTab = max(minTabWidth, min(maxTabWidth, available / count))
        let tabHeight: CGFloat = 28
        let tabY = (bounds.height - tabHeight) / 2

        for (i, button) in tabButtons.enumerated() {
            button.frame = NSRect(
                x: leadingPad + CGFloat(i) * (perTab + tabSpacing),
                y: tabY,
                width: perTab,
                height: tabHeight
            )
        }
    }

    func setFullscreen(_ fullscreen: Bool) {
        isFullscreen = fullscreen
        logoIcon.isHidden = !fullscreen
        logoLabel.isHidden = !fullscreen
        layoutTabs()
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
            for (i, button) in tabButtons.enumerated() {
                button.updateTitle(titles[i])
                button.updateSelected(i == selectedIndex)
            }
            layoutTabs()
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
            addSubview(button)
        }
        layoutTabs()
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
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        addSubview(titleLabel)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = !isSelected
        addSubview(closeButton)

        let click = NSClickGestureRecognizer(target: self, action: #selector(tabClicked))
        addGestureRecognizer(click)
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let closeSize: CGFloat = 16
        closeButton.frame = NSRect(x: bounds.width - closeSize - 6, y: (h - closeSize) / 2, width: closeSize, height: closeSize)
        titleLabel.sizeToFit()
        let labelH = titleLabel.frame.height
        titleLabel.frame = NSRect(x: 10, y: (h - labelH) / 2, width: bounds.width - 36, height: labelH)
    }

    func updateTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    func updateSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = selected
            ? NSColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1.0).cgColor
            : NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0).cgColor
        titleLabel.textColor = selected ? .white : NSColor(white: 0.55, alpha: 1.0)
        closeButton.isHidden = !selected
        CATransaction.commit()
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
