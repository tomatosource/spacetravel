import Cocoa

class KeyCaptureWindowController: NSWindowController {
    var onKeySelected: ((CGKeyCode, String) -> Void)?
    private weak var tapManager: SpaceTapManager?
    private let captureView = KeyCaptureView()
    private let keyLabel = NSTextField(labelWithString: "")

    init(tapManager: SpaceTapManager) {
        self.tapManager = tapManager

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 110),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Trigger Key"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        keyLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        keyLabel.alignment = .center

        let hint = NSTextField(labelWithString: "Press any key  ·  Esc to cancel")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        captureView.onKeyDown = { [weak self] event in
            guard let self else { return }
            let code = CGKeyCode(event.keyCode)
            if code == 53 { self.close(); return } // Escape = cancel
            let name = Self.displayName(for: code, from: event)
            self.onKeySelected?(code, name)
            self.close()
        }

        for v in [captureView, keyLabel, hint] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        contentView.addSubview(captureView)
        captureView.addSubview(keyLabel)
        captureView.addSubview(hint)

        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: contentView.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            keyLabel.centerXAnchor.constraint(equalTo: captureView.centerXAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: captureView.centerYAnchor, constant: -10),

            hint.centerXAnchor.constraint(equalTo: captureView.centerXAnchor),
            hint.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 6),
        ])
    }

    func show(currentKeyName: String) {
        keyLabel.stringValue = currentKeyName
        tapManager?.isSuspended = true
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(captureView)
    }

    override func close() {
        tapManager?.isSuspended = false
        super.close()
    }

    // Maps a key code + optional event to a human-readable name.
    static func displayName(for keyCode: CGKeyCode, from event: NSEvent? = nil) -> String {
        let special: [CGKeyCode: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "⌫",
            53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            116: "PgUp", 121: "PgDn", 115: "Home", 119: "End",
        ]
        if let name = special[keyCode] { return name }
        if let chars = event?.charactersIgnoringModifiers,
           !chars.isEmpty,
           chars.rangeOfCharacter(from: .controlCharacters) == nil {
            return chars.uppercased()
        }
        return "Key \(keyCode)"
    }
}

private class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        onKeyDown?(event)
    }
}
