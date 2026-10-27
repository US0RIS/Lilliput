import AppKit

/// The menu-bar item: a tiny hard-hat-over-scaffold template icon and the app menu.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private unowned let app: AppDelegate
    private var settings: SettingsStore { app.settings }

    init(app: AppDelegate) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = Self.makeIcon()
            button.toolTip = "Lilliput"
            button.setAccessibilityLabel("Lilliput")
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    static func makeIcon() -> NSImage {
        let canvas = PropArt.menuBarIcon().scaled(by: 2)
        let size = NSSize(width: 18, height: 18)
        guard let cg = canvas.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: cg, size: size)
        image.isTemplate = true
        image.accessibilityDescription = "Lilliput"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Lilliput", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !app.permissions.isTrusted {
            let warn = item("Grant Accessibility Access…", #selector(showOnboarding))
            menu.addItem(warn)
        } else if settings.isEnabled {
            let count = app.coordinator?.trackedWindowCount ?? 0
            let status = NSMenuItem(title: count == 1 ? "1 site under construction" : "\(count) sites under construction", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        menu.addItem(.separator())

        menu.addItem(toggle(settings.isEnabled ? "Disable Lilliput" : "Enable Lilliput", on: false, #selector(toggleEnabled)))
        menu.addItem(toggle("Pause Workers", on: settings.isPaused, #selector(togglePaused)))
        menu.addItem(.separator())

        menu.addItem(submenu("Construction Density", ConstructionDensity.allCases.map { ($0.label, $0.rawValue, $0 == settings.density) }, #selector(pickDensity(_:))))
        menu.addItem(submenu("Worker Size", WorkerSize.allCases.map { ($0.label, $0.rawValue, $0 == settings.workerSize) }, #selector(pickSize(_:))))
        menu.addItem(submenu("Animation Intensity", AnimationIntensity.allCases.map { ($0.label, $0.rawValue, $0 == settings.intensity) }, #selector(pickIntensity(_:))))
        menu.addItem(toggle("Special Events", on: settings.specialEvents, #selector(toggleEvents)))
        menu.addItem(toggle("Sound Effects", on: settings.soundEnabled, #selector(toggleSound)))
        let surprise = item("Start a Special Event Now", #selector(triggerEvent))
        surprise.isEnabled = settings.isEnabled && app.permissions.isTrusted
        menu.addItem(surprise)
        menu.addItem(.separator())

        menu.addItem(item("Demo Construction…", #selector(openDemo)))
        let prefs = item("Settings…", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = item("Quit Lilliput", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.isEnabled = true
        return i
    }

    private func toggle(_ title: String, on: Bool, _ action: Selector) -> NSMenuItem {
        let i = item(title, action)
        i.state = on ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ options: [(String, String, Bool)], _ action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        sub.autoenablesItems = false
        for (label, value, selected) in options {
            let i = item(label, action)
            i.representedObject = value
            i.state = selected ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    @objc private func toggleEnabled() { settings.isEnabled.toggle() }
    @objc private func togglePaused() { settings.isPaused.toggle() }
    @objc private func toggleEvents() { settings.specialEvents.toggle() }
    @objc private func toggleSound() { settings.soundEnabled.toggle() }

    @objc private func pickDensity(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let d = ConstructionDensity(rawValue: v) { settings.density = d }
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let s = WorkerSize(rawValue: v) { settings.workerSize = s }
    }

    @objc private func pickIntensity(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? String, let i = AnimationIntensity(rawValue: v) { settings.intensity = i }
    }

    @objc private func triggerEvent() { _ = app.coordinator?.triggerSpecialEvent() }
    @objc private func openDemo() { app.showDemo() }
    @objc private func openSettings() { app.showSettings() }
    @objc private func showOnboarding() { app.showOnboarding() }
    @objc private func quit() { NSApp.terminate(nil) }
}
