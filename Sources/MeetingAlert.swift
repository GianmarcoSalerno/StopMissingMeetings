import AppKit

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class MeetingAlert: NSObject {
    private let title: String
    private let start: Date
    private let link: URL?
    private let onClose: (_ snoozed: Bool) -> Void
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var timer: Timer?
    private let speech = NSSpeechSynthesizer()
    private let shownAt = Date()

    init(title: String, start: Date, link: URL?, onClose: @escaping (Bool) -> Void) {
        self.title = title
        self.start = start
        self.link = link
        self.onClose = onClose
    }

    func show() {
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = NSColor(calibratedRed: 0.78, green: 0.08, blue: 0.08, alpha: 0.96)
            window.isOpaque = false
            window.contentView = makeContent()
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()
        NSApp.activate()

        updateCountdown()
        playSound()
        speech.startSpeaking("Meeting \(spokenWhen). \(title)")
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            ticks += 1
            self.updateCountdown()
            if ticks % 4 == 0 && Date().timeIntervalSince(self.shownAt) < 180 { self.playSound() }
        }
    }

    private var spokenWhen: String {
        let minutes = Int((start.timeIntervalSinceNow / 60).rounded())
        if minutes > 0 { return "in \(minutes) minute\(minutes == 1 ? "" : "s")" }
        return minutes == 0 ? "starting now" : "started \(-minutes) minute\(minutes == -1 ? "" : "s") ago"
    }

    private func updateCountdown() {
        let seconds = Int(start.timeIntervalSinceNow)
        let text = seconds > 0
            ? String(format: "Starts in %d:%02d", seconds / 60, seconds % 60)
            : String(format: "Started %d:%02d ago", -seconds / 60, -seconds % 60)
        countdownLabels.forEach { $0.stringValue = text }
    }

    private func playSound() {
        NSSound(contentsOfFile: "/System/Library/Sounds/Sosumi.aiff", byReference: true)?.play()
    }

    private func makeContent() -> NSView {
        let heading = label("⏰ MEETING", size: 72, weight: .heavy)
        let name = label(title, size: 44, weight: .bold)
        let countdown = label("", size: 32, weight: .medium)
        countdownLabels.append(countdown)

        var buttons: [NSButton] = []
        if link != nil { buttons.append(button("Join meeting", #selector(join), key: "\r")) }
        buttons.append(button("Snooze 1 min", #selector(snooze), key: ""))
        buttons.append(button("Dismiss", #selector(dismiss), key: link == nil ? "\r" : "\u{1b}"))
        let row = NSStackView(views: buttons)
        row.spacing = 20

        let stack = NSStackView(views: [heading, name, countdown, row])
        stack.orientation = .vertical
        stack.spacing = 28
        stack.setCustomSpacing(48, after: countdown)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -80),
        ])
        return container
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = .white
        field.alignment = .center
        return field
    }

    private func button(_ title: String, _ action: Selector, key: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .large
        button.font = .systemFont(ofSize: 22, weight: .semibold)
        button.keyEquivalent = key
        return button
    }

    @objc private func join() {
        if let link { NSWorkspace.shared.open(link) }
        close(snoozed: false)
    }

    @objc private func snooze() { close(snoozed: true) }

    @objc private func dismiss() { close(snoozed: false) }

    private func close(snoozed: Bool) {
        timer?.invalidate()
        speech.stopSpeaking()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onClose(snoozed)
    }
}
