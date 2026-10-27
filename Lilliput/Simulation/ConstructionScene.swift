import Foundation
import SpriteKit

enum SceneActivity: Equatable {
    case empty
    case idle
    case busy
}

enum SiteOpenMode: Equatable {
    /// Full arrival-and-construction sequence (a new window).
    case construct
    /// Fast rebuild (a window that came back or got promoted).
    case quick
    /// Already built, no animation (startup after a display change, Space switch).
    case instant
}

/// Renders the miniature world for one display (or for the Demo window) and owns the
/// construction sites on it. Pure presentation + simulation; it never talks to the
/// window server — callers feed it window frames in scene coordinates.
@MainActor
final class ConstructionScene: SKScene {
    let isDemo: Bool
    private(set) var sites: [WindowID: ConstructionSite] = [:]
    private var pending: [(id: WindowID, frame: CGRect, mode: SiteOpenMode, at: TimeInterval)] = []
    private var pendingOcclusion: [WindowID: OcclusionInfo] = [:]
    private(set) var simSettings = SimSettings()
    var availableRect: CGRect = .zero {
        didSet { for s in sites.values { s.available = availableRect } }
    }
    var backingScale: CGFloat = 2 {
        didSet { for s in sites.values { s.backingScale = backingScale; s.positionRoot() } }
    }

    var supervisorActive = false {
        didSet { if !supervisorActive && oldValue { lastSupervisorEnded = clock } }
    }
    private var lastSupervisorEnded: TimeInterval = -60
    var supervisorAvailable: Bool { !supervisorActive && clock - lastSupervisorEnded > 75 }

    /// Called every frame before sites update (used by the Demo to animate fake windows).
    var onFrame: ((TimeInterval) -> Void)?
    var onActivityChange: ((SceneActivity) -> Void)?
    private(set) var activity: SceneActivity = .empty

    private var lastUpdate: TimeInterval?
    private(set) var clock: TimeInterval = 0
    private var lastScheduledOpen: TimeInterval = -10

    init(size: CGSize, isDemo: Bool) {
        self.isDemo = isDemo
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if isDemo { availableRect = CGRect(origin: .zero, size: size) }
    }

    // MARK: Site API (scene coordinates)

    func hasSite(_ id: WindowID) -> Bool { sites[id] != nil || pending.contains { $0.id == id } }

    func site(_ id: WindowID) -> ConstructionSite? { sites[id] }

    func openSite(_ id: WindowID, frame: CGRect, mode: SiteOpenMode) {
        if let existing = sites[id] {
            existing.windowChanged(to: frame)
            if existing.phase == .packed { existing.beginRebuild(animated: mode != .instant) }
            return
        }
        if pending.contains(where: { $0.id == id }) { return }
        var at = clock
        if mode == .construct {
            at = max(clock, lastScheduledOpen + 0.45)
            lastScheduledOpen = at
        }
        pending.append((id, frame, mode, at))
        refreshActivity()
    }

    private func createSite(_ id: WindowID, frame: CGRect, mode: SiteOpenMode) {
        let site = ConstructionSite(windowID: id, frame: frame, settings: simSettings, available: availableRect, isDemo: isDemo, scene: self)
        site.backingScale = backingScale
        site.positionRoot()
        addChild(site.root)
        sites[id] = site
        switch mode {
        case .construct: site.beginConstruction(animated: true)
        case .quick: site.beginRebuild(animated: true)
        case .instant: site.beginConstruction(animated: false)
        }
        if let occ = pendingOcclusion.removeValue(forKey: id) { site.setOcclusion(occ) }
    }

    func updateSite(_ id: WindowID, frame: CGRect) {
        if let s = sites[id] {
            s.windowChanged(to: frame)
        } else if let i = pending.firstIndex(where: { $0.id == id }) {
            pending[i].frame = frame
        }
    }

    func hideSite(_ id: WindowID, animated: Bool) {
        pending.removeAll { $0.id == id }
        guard let s = sites[id] else { return }
        switch s.phase {
        case .packed, .packing, .tearingDown, .finished: return
        default: s.beginPack(animated: animated)
        }
        refreshActivity()
    }

    /// Returns false if there was no hidden site to restore.
    @discardableResult
    func restoreSite(_ id: WindowID, frame: CGRect, animated: Bool) -> Bool {
        guard let s = sites[id] else { return false }
        s.windowChanged(to: frame)
        if s.phase == .packed || s.phase == .packing {
            s.beginRebuild(animated: animated)
        }
        refreshActivity()
        return true
    }

    func closeSite(_ id: WindowID) {
        pending.removeAll { $0.id == id }
        pendingOcclusion[id] = nil
        guard let s = sites[id] else { return }
        if s.phase == .packed || s.phase == .packing || s.layout == nil || s.suspended {
            s.removeEverything()
            sites[id] = nil
        } else if s.phase != .tearingDown {
            s.beginTeardown()
        }
        refreshActivity()
    }

    func detachSite(_ id: WindowID) -> ConstructionSite? {
        guard let s = sites.removeValue(forKey: id) else { return nil }
        s.root.removeFromParent()
        refreshActivity()
        return s
    }

    func attachSite(_ site: ConstructionSite, frame: CGRect) {
        site.scene = self
        site.available = availableRect
        site.backingScale = backingScale
        addChild(site.root)
        sites[site.windowID] = site
        site.windowChanged(to: frame)
        site.motion.reset(at: frame.origin)
        refreshActivity()
    }

    func setOcclusion(_ id: WindowID, _ info: OcclusionInfo) {
        if let s = sites[id] {
            if s.occlusion != info { s.setOcclusion(info) }
        } else {
            pendingOcclusion[id] = info
        }
    }

    func removeAllSites() {
        for s in sites.values { s.removeEverything() }
        sites.removeAll()
        pending.removeAll()
        pendingOcclusion.removeAll()
        supervisorActive = false
        refreshActivity()
    }

    func apply(settings: SimSettings) {
        guard settings != simSettings else { return }
        simSettings = settings
        for s in sites.values { s.apply(settings: settings) }
    }

    @discardableResult
    func triggerSpecialEvent(preferring id: WindowID? = nil) -> Bool {
        var candidates = Array(sites.values).filter { $0.phase == .active && !$0.suspended }
        if let id, let s = sites[id], candidates.contains(where: { $0 === s }) {
            candidates = [s] + candidates.filter { $0 !== s }
        } else {
            candidates.shuffle()
        }
        for s in candidates {
            if s.triggerRandomEvent(forced: true) { return true }
        }
        return false
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(max(currentTime - $0, 0), 0.05) } ?? 0
        lastUpdate = currentTime
        clock += dt

        if !pending.isEmpty {
            let due = pending.filter { $0.at <= clock }
            if !due.isEmpty {
                pending.removeAll { $0.at <= clock }
                for p in due { createSite(p.id, frame: p.frame, mode: p.mode) }
            }
        }

        onFrame?(dt)

        var finished: [WindowID] = []
        for (id, site) in sites {
            site.update(dt: dt)
            if site.phase == .finished { finished.append(id) }
        }
        for id in finished {
            sites[id]?.removeEverything()
            sites[id] = nil
        }
        refreshActivity()
    }

    private func refreshActivity() {
        let new: SceneActivity
        if sites.isEmpty && pending.isEmpty {
            new = .empty
        } else if !pending.isEmpty || sites.values.contains(where: { s in
            switch s.phase {
            case .constructing, .packing, .rebuilding, .tearingDown: return true
            default: return s.isMoving || s.isResizing || s.particles.activeCount > 0
            }
        }) {
            new = .busy
        } else {
            new = .idle
        }
        if new != activity {
            activity = new
            onActivityChange?(new)
        }
    }
}
