import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore.shared
    let permissions = PermissionManager()
    private(set) var coordinator: SimulationCoordinator?
    private var statusMenu: StatusMenuController?
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var demoWindow: DemoWindowController?

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        let coordinator = SimulationCoordinator(settings: settings, permissions: permissions)
        self.coordinator = coordinator
        statusMenu = StatusMenuController(app: self)

        permissions.onChange = { [weak self] trusted in
            guard let self else { return }
            self.coordinator?.permissionChanged(trusted: trusted)
            if trusted { self.onboardingWindow?.close() }
        }

        coordinator.setEnabled(settings.isEnabled)

        if !permissions.isTrusted {
            showOnboarding()
        }
        settings.hasSeenOnboarding = true

        if ProcessInfo.processInfo.arguments.contains("--demo") {
            showDemo()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permissions.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
        demoWindow?.shutdown()
        statusMenu?.remove()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: Windows

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, permissions: permissions) { [weak self] in
                self?.showDemo()
            }
        }
        settingsWindow?.present()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let controller = OnboardingWindowController(permissions: permissions) { [weak self] in
                self?.showDemo()
            }
            controller.onClose = { [weak self] in
                self?.permissions.stopPolling()
                self?.onboardingWindow = nil
            }
            onboardingWindow = controller
        }
        onboardingWindow?.present()
    }

    func showDemo() {
        if demoWindow == nil {
            let controller = DemoWindowController(settings: settings)
            controller.onClose = { [weak self] in self?.demoWindow = nil }
            demoWindow = controller
        }
        demoWindow?.present()
    }
}
