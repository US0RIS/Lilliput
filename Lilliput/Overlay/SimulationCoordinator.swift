import Foundation
import AppKit

/// Glue between window observation and rendering: turns tracker events into site
/// operations on the right display's scene, enforces the site limit, and computes
/// occlusion from the real stacking order.
@MainActor
final class SimulationCoordinator: NSObject, WindowTrackerDelegate {
    let settings: SettingsStore
    let permissions: PermissionManager
    let tracker = WindowTracker()
    let overlays = OverlayManager()

    private(set) var isEnabled = false
    private var windows: [WindowID: WindowSnapshot] = [:]
    private var stacking: [WindowID] = []
    private var occluders: [(id: WindowID, frame: CGRect)] = []
    private var siteDisplay: [WindowID: CGDirectDisplayID] = [:]
    private var live: Set<WindowID> = []
    private var pendingMode: [WindowID: SiteOpenMode] = [:]
    private var lastSim = SimSettings()
    private var lastMaxSites = 0
    private var lastExcluded: [String] = []
    private var lastFullScreen = false

    init(settings: SettingsStore, permissions: PermissionManager) {
        self.settings = settings
        self.permissions = permissions
        super.init()
        tracker.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    // MARK: Enable / disable

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on {
            lastSim = settings.simSettings
            SoundEngine.shared.enabled = settings.soundEnabled
            overlays.setShowOverFullScreen(settings.showOverFullScreen)
            overlays.apply(settings: lastSim)
            overlays.rebuild()
            applyTrackerSettings()
            if permissions.isTrusted { tracker.start() }
        } else {
            tracker.stop()
            overlays.tearDown()
            resetState()
        }
    }

    func permissionChanged(trusted: Bool) {
        guard isEnabled else { return }
        if trusted {
            tracker.start()
        } else {
            tracker.stop()
            for d in overlays.displays { d.scene.removeAllSites() }
            resetState()
        }
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        tracker.stop()
        overlays.tearDown()
        resetState()
    }

    func triggerSpecialEvent() -> Bool {
        for d in overlays.displays where d.scene.triggerSpecialEvent() { return true }
        return false
    }

    var trackedWindowCount: Int { live.count }

    private func resetState() {
        windows.removeAll()
        stacking.removeAll()
        occluders.removeAll()
        siteDisplay.removeAll()
        live.removeAll()
        pendingMode.removeAll()
    }

    private func applyTrackerSettings() {
        tracker.excludedBundleIDs = Set(settings.excludedBundleIDs)
        tracker.allowFullScreenWindows = settings.showOverFullScreen
        lastExcluded = settings.excludedBundleIDs
        lastFullScreen = settings.showOverFullScreen
        lastMaxSites = settings.maxActiveSites
    }

    // MARK: Notifications

    @objc private func settingsChanged() {
        if settings.isEnabled != isEnabled { setEnabled(settings.isEnabled) }
        SoundEngine.shared.enabled = settings.soundEnabled
        guard isEnabled else { return }
        let sim = settings.simSettings
        if sim != lastSim {
            lastSim = sim
            overlays.apply(settings: sim)
        }
        if settings.showOverFullScreen != lastFullScreen {
            overlays.setShowOverFullScreen(settings.showOverFullScreen)
        }
        if settings.excludedBundleIDs != lastExcluded || settings.showOverFullScreen != lastFullScreen {
            applyTrackerSettings()
        }
        if settings.maxActiveSites != lastMaxSites {
            lastMaxSites = settings.maxActiveSites
            reconcileSites()
            updateOcclusion()
        }
    }

    @objc private func screensChanged() {
        guard isEnabled else { return }
        overlays.rebuild()
        overlays.apply(settings: lastSim)
        live.removeAll()
        siteDisplay.removeAll()
        for id in windows.keys { pendingMode[id] = .instant }
        reconcileSites()
        updateOcclusion()
    }

    @objc private func willSleep() {
        guard isEnabled else { return }
        tracker.stop()
    }

    @objc private func didWake() {
        guard isEnabled, permissions.isTrusted, !tracker.isRunning else { return }
        // Rebuild cleanly: drop all sites and re-discover windows without animation.
        for d in overlays.displays { d.scene.removeAllSites() }
        resetState()
        tracker.start()
    }

    // MARK: Tracker events

    func tracker(_ tracker: WindowTracker, didEmit events: [WindowEvent], stacking: [WindowSnapshot], occluders: [(id: WindowID, frame: CGRect)]) {
        for e in events {
            switch e {
            case .opened(let s, let animated):
                windows[s.id] = s
                pendingMode[s.id] = animated ? .construct : .instant
            case .changed(let s):
                windows[s.id] = s
                route(s)
            case .hidden(let id, let animated):
                windows[id] = nil
                pendingMode[id] = nil
                if let d = siteDisplay[id].flatMap({ overlays.display(id: $0) }) {
                    d.scene.hideSite(id, animated: animated)
                }
                live.remove(id)
            case .restored(let s, let animated):
                windows[s.id] = s
                pendingMode[s.id] = animated ? .quick : .instant
            case .closed(let id):
                windows[id] = nil
                pendingMode[id] = nil
                if let d = siteDisplay[id].flatMap({ overlays.display(id: $0) }) {
                    d.scene.closeSite(id)
                }
                siteDisplay[id] = nil
                live.remove(id)
            }
        }
        self.stacking = stacking.map(\.id)
        self.occluders = occluders
        reconcileSites()
        updateOcclusion()
    }

    private func sceneFrame(_ global: CGRect, in d: OverlayManager.Display) -> CGRect {
        ScreenGeometry.sceneRect(fromAppKit: global, displayFrame: d.frame)
    }

    /// Moves a site to the display its window now belongs to, or just updates its frame.
    private func route(_ s: WindowSnapshot) {
        guard let current = siteDisplay[s.id], let target = overlays.display(for: s.frame) else { return }
        if target.id == current {
            target.scene.updateSite(s.id, frame: sceneFrame(s.frame, in: target))
        } else if let from = overlays.display(id: current), let site = from.scene.detachSite(s.id) {
            target.scene.attachSite(site, frame: sceneFrame(s.frame, in: target))
            siteDisplay[s.id] = target.id
        } else {
            siteDisplay[s.id] = nil
            live.remove(s.id)
        }
    }

    /// Ensures the frontmost N tracked windows have live sites; others are packed away.
    private func reconcileSites() {
        let ordered = stacking.filter { windows[$0] != nil }
        let desired = Set(ordered.prefix(settings.maxActiveSites))
        for id in ordered where desired.contains(id) && !live.contains(id) {
            guard let s = windows[id], let d = overlays.display(for: s.frame) else { continue }
            let frame = sceneFrame(s.frame, in: d)
            let mode = pendingMode.removeValue(forKey: id) ?? .quick
            if let currentID = siteDisplay[id], let current = overlays.display(id: currentID), current.scene.site(id) != nil {
                if currentID != d.id, let site = current.scene.detachSite(id) {
                    d.scene.attachSite(site, frame: frame)
                }
                d.scene.restoreSite(id, frame: frame, animated: mode != .instant)
            } else {
                d.scene.openSite(id, frame: frame, mode: mode)
            }
            siteDisplay[id] = d.id
            live.insert(id)
        }
        for id in live where !desired.contains(id) {
            if windows[id] != nil, let d = siteDisplay[id].flatMap({ overlays.display(id: $0) }) {
                d.scene.hideSite(id, animated: true)
            }
            live.remove(id)
        }
    }

    private func updateOcclusion() {
        guard !live.isEmpty else { return }
        let info = Occlusion.compute(frontToBack: occluders, targets: live)
        for id in live {
            guard let d = siteDisplay[id].flatMap({ overlays.display(id: $0) }) else { continue }
            let i = info[id] ?? .clear
            let converted = OcclusionInfo(occluders: i.occluders.map { sceneFrame($0, in: d) }, visibleFraction: i.visibleFraction)
            d.scene.setOcclusion(id, converted)
        }
    }
}
