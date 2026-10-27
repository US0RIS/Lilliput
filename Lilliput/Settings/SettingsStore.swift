import Foundation
import ServiceManagement

/// Persisted user preferences. Every change is written to UserDefaults immediately and
/// broadcast via `SettingsStore.didChange` so the live simulation updates in place.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let didChange = Notification.Name("LilliputSettingsDidChange")

    private enum Key {
        static let enabled = "enabled"
        static let paused = "paused"
        static let density = "density"
        static let workerSize = "workerSize"
        static let intensity = "intensity"
        static let specialEvents = "specialEvents"
        static let sound = "sound"
        static let maxSites = "maxSites"
        static let maxWorkers = "maxWorkers"
        static let excluded = "excludedBundleIDs"
        static let fullScreen = "showOverFullScreen"
        static let onboarded = "hasSeenOnboarding"
    }

    private let defaults: UserDefaults
    private var loading = true

    @Published var isEnabled: Bool { didSet { persist() } }
    @Published var isPaused: Bool { didSet { persist() } }
    @Published var density: ConstructionDensity { didSet { persist() } }
    @Published var workerSize: WorkerSize { didSet { persist() } }
    @Published var intensity: AnimationIntensity { didSet { persist() } }
    @Published var specialEvents: Bool { didSet { persist() } }
    @Published var soundEnabled: Bool { didSet { persist() } }
    @Published var maxActiveSites: Int { didSet { persist() } }
    @Published var maxWorkersPerSite: Int { didSet { persist() } }
    @Published var excludedBundleIDs: [String] { didSet { persist() } }
    @Published var showOverFullScreen: Bool { didSet { persist() } }
    @Published var hasSeenOnboarding: Bool { didSet { persist() } }

    static let siteLimitRange = 1...12
    static let workerLimitRange = 1...6

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.paused: false,
            Key.density: ConstructionDensity.normal.rawValue,
            Key.workerSize: WorkerSize.normal.rawValue,
            Key.intensity: AnimationIntensity.balanced.rawValue,
            Key.specialEvents: true,
            Key.sound: false,
            Key.maxSites: 6,
            Key.maxWorkers: 4,
            Key.excluded: [String](),
            Key.fullScreen: false,
            Key.onboarded: false,
        ])
        isEnabled = defaults.bool(forKey: Key.enabled)
        isPaused = defaults.bool(forKey: Key.paused)
        density = ConstructionDensity(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .normal
        workerSize = WorkerSize(rawValue: defaults.string(forKey: Key.workerSize) ?? "") ?? .normal
        intensity = AnimationIntensity(rawValue: defaults.string(forKey: Key.intensity) ?? "") ?? .balanced
        specialEvents = defaults.bool(forKey: Key.specialEvents)
        soundEnabled = defaults.bool(forKey: Key.sound)
        maxActiveSites = Self.clamp(defaults.integer(forKey: Key.maxSites), Self.siteLimitRange)
        maxWorkersPerSite = Self.clamp(defaults.integer(forKey: Key.maxWorkers), Self.workerLimitRange)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excluded) ?? []
        showOverFullScreen = defaults.bool(forKey: Key.fullScreen)
        hasSeenOnboarding = defaults.bool(forKey: Key.onboarded)
        loading = false
    }

    private static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(max(v, r.lowerBound), r.upperBound) }

    private func persist() {
        guard !loading else { return }
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(isPaused, forKey: Key.paused)
        defaults.set(density.rawValue, forKey: Key.density)
        defaults.set(workerSize.rawValue, forKey: Key.workerSize)
        defaults.set(intensity.rawValue, forKey: Key.intensity)
        defaults.set(specialEvents, forKey: Key.specialEvents)
        defaults.set(soundEnabled, forKey: Key.sound)
        defaults.set(Self.clamp(maxActiveSites, Self.siteLimitRange), forKey: Key.maxSites)
        defaults.set(Self.clamp(maxWorkersPerSite, Self.workerLimitRange), forKey: Key.maxWorkers)
        defaults.set(excludedBundleIDs, forKey: Key.excluded)
        defaults.set(showOverFullScreen, forKey: Key.fullScreen)
        defaults.set(hasSeenOnboarding, forKey: Key.onboarded)
        // Post after the @Published value has actually changed.
        let name = Self.didChange
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    var simSettings: SimSettings {
        SimSettings(density: density,
                    pixelScale: workerSize.pixelScale,
                    intensity: intensity,
                    specialEvents: specialEvents,
                    sound: soundEnabled,
                    maxWorkersPerSite: Self.clamp(maxWorkersPerSite, Self.workerLimitRange),
                    paused: isPaused)
    }

    // MARK: Launch at login (ServiceManagement)

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message if the change could not be applied.
    func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
