import AppKit
import EventKit
import ServiceManagement

@main
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let store = EKEventStore()
    private let leadTime: TimeInterval = 120
    private var statusItem: NSStatusItem!
    private var hasAccess = false
    private var alerted = Set<String>()
    private var snoozed: [String: Date] = [:]
    private var alert: MeetingAlert?
    private var lastSourceRefresh = Date.distantPast
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "alarm", accessibilityDescription: "StopMissingMeetings")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(tick), name: .EKEventStoreChanged, object: store)
        Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(tick), userInfo: nil, repeats: true)

        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.hasAccess = granted
                self.tick()
            }
        }
    }

    // MARK: - Watching

    private func events(within interval: TimeInterval) -> [EKEvent] {
        guard hasAccess else { return [] }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: now.addingTimeInterval(interval), calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !isDeclined($0) && $0.startDate > now.addingTimeInterval(-300) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private func key(_ event: EKEvent) -> String {
        "\(event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)"
    }

    private var hasGoogleCalendar: Bool {
        store.sources.contains { $0.sourceType == .calDAV && !$0.title.localizedCaseInsensitiveContains("icloud") }
    }

    @objc private func tick() {
        if Date().timeIntervalSince(lastSourceRefresh) > 120 {
            store.refreshSourcesIfNecessary()
            lastSourceRefresh = Date()
        }
        let now = Date()
        let upcoming = events(within: 12 * 3600)
        updateStatusTitle(next: upcoming.first { $0.startDate > now })

        guard alert == nil else { return }
        let due = upcoming.first { event in
            let k = key(event)
            if let until = snoozed[k] { return now >= until }
            return !alerted.contains(k) && event.startDate.timeIntervalSince(now) <= leadTime
        }
        if let due { show(due) }
    }

    private func updateStatusTitle(next: EKEvent?) {
        guard let button = statusItem.button else { return }
        guard hasAccess else { button.title = " !"; return }
        guard let next, next.startDate.timeIntervalSinceNow < 3600 else { button.title = ""; return }
        button.title = " \(Int(ceil(next.startDate.timeIntervalSinceNow / 60)))m"
    }

    private func show(_ event: EKEvent) {
        let k = key(event)
        alerted.insert(k)
        snoozed[k] = nil
        alert = MeetingAlert(title: event.title ?? "Meeting", start: event.startDate, link: meetingLink(event)) { [weak self] snooze in
            if snooze { self?.snoozed[k] = Date().addingTimeInterval(60) }
            self?.alert = nil
        }
        alert?.show()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !hasAccess {
            menu.addItem(item("Allow calendar access…", #selector(openPrivacy)))
        } else {
            if !hasGoogleCalendar {
                menu.addItem(item("⚠️ No Google calendar found. Add your Google account…", #selector(openInternetAccounts)))
                menu.addItem(.separator())
            }
            let next = events(within: 24 * 3600).filter { $0.startDate > Date() }.prefix(6)
            if next.isEmpty {
                let empty = NSMenuItem(title: "No meetings in the next 24 hours", action: nil, keyEquivalent: "")
                menu.addItem(empty)
            }
            for event in next {
                let link = meetingLink(event)
                let entry = NSMenuItem(title: "\(timeFormatter.string(from: event.startDate))   \(event.title ?? "Untitled")",
                                       action: link == nil ? nil : #selector(join(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = link
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Test alert", #selector(testAlert)))
        let login = item("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Add Google account…", #selector(openInternetAccounts)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func join(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func testAlert() {
        guard alert == nil else { return }
        alert = MeetingAlert(title: "Test meeting", start: Date().addingTimeInterval(leadTime), link: nil) { [weak self] _ in
            self?.alert = nil
        }
        alert?.show()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}

func meetingLink(_ event: EKEvent) -> URL? {
    let text = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " ")
    let pattern = #"https://(meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com|[\w.-]*webex\.com)/[^\s<>"')]+"#
    guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
    return URL(string: String(text[range]))
}
