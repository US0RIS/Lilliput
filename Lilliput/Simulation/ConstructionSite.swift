import Foundation
import SpriteKit

/// Owns everything around one window: scaffold geometry, crew, props, rigs, particles
/// and the site's lifecycle. Coordinates inside `root` are art pixels relative to the
/// window's bottom-left corner; `root` itself is positioned in scene points and scaled.
@MainActor
final class ConstructionSite: WorkerContext {
    enum Phase: Equatable {
        case constructing
        case active
        case packing
        case packed
        case rebuilding
        case tearingDown
        case finished
    }

    struct LiftState {
        enum Stage { case idle, lowering, hooking, raising, delivering }
        var stage: Stage = .idle
        var ropeLength: CGFloat = 5
        var loaded = false
        var timer: TimeInterval = 0
        var pendulum = Pendulum()
    }

    let windowID: WindowID
    let root = SKNode()
    let isDemo: Bool
    weak var scene: ConstructionScene?

    private(set) var frame: CGRect
    private(set) var scale: CGFloat
    var settings: SimSettings
    var available: CGRect
    private(set) var occlusion: OcclusionInfo = .clear
    var rng: SplitMix64

    var layout: ScaffoldLayout?
    var elementNodes: [ElementKey: ScaffoldElementNode] = [:]
    var built: Set<ElementKey> = []
    var assigned: Set<ElementKey> = []
    var workers: [Worker] = []
    var particles: ParticleSystem!
    var phase: Phase = .constructing
    var phaseTime: TimeInterval = 0
    var siteTime: TimeInterval = 0
    var backingScale: CGFloat = 2

    // Props.
    var sign: SiteProp!
    var stack: SiteProp!
    var toolbox: SiteProp!
    var cones: [SiteProp] = []
    var flag: SiteProp?
    var looseProps: [SiteProp] = []

    // Motion.
    var motion = MotionTracker()
    var isMoving = false
    var moveQuiet: TimeInterval = 0
    var peakSpeed: CGFloat = 0
    var lastFastReaction: TimeInterval = -10
    var isResizing = false
    var resizeQuiet: TimeInterval = 0
    private var lastResizeSize: CGSize = .zero

    // Rigs.
    var crane = LiftState()
    var pulley = LiftState()
    var pulleyTimer: TimeInterval = 8

    // Director / events state.
    var constructionTarget: TimeInterval = 4.8
    var teardownSchedule: [(ElementKey, TimeInterval)] = []
    var teardownExitAt: TimeInterval = 2.2
    var packSchedule: [(ElementKey, TimeInterval)] = []
    var rebuildSchedule: [(ElementKey, TimeInterval)] = []
    var completedOnce = false
    /// One-shot markers within the current phase (props packed, exit issued, …).
    var stageMarks: Set<Int> = []
    var crewCheckTimer: TimeInterval = 2
    var eventTimer: TimeInterval = 30
    var activeEvent: SiteEvent?
    var longPlankNode: SKSpriteNode?
    var nextWorkerID = 0
    var styleCursor = 0
    var suspended = false
    var structureVisible = true
    private var visibilityFrame = 0
    private var occlusionApplied = false

    init(windowID: WindowID, frame: CGRect, settings: SimSettings, available: CGRect, isDemo: Bool, scene: ConstructionScene) {
        self.windowID = windowID
        self.frame = frame
        self.settings = settings
        self.scale = settings.pixelScale
        self.available = available
        self.isDemo = isDemo
        self.scene = scene
        rng = SplitMix64(seed: UInt64(windowID) &* 0x9E37_79B1 &+ 0x5EED)
        styleCursor = rng.int(0...(WorkerStyle.crew.count - 1))
        eventTimer = rng.range(18, 36)
        root.zPosition = 10
        root.setScale(scale)
        particles = ParticleSystem(parent: root)
        particles.amplitude = settings.intensity.amplitude
        sign = SiteProp(kind: .sign, base: .zero, wobble: 0.05, parent: root)
        stack = SiteProp(kind: .plankPile, base: .zero, wobble: 0.02, parent: root)
        toolbox = SiteProp(kind: .toolbox, base: .zero, wobble: 0.04, parent: root)
        positionRoot()
        layout = computeLayout(locked: nil)
        syncElements(animateRemovals: false)
        placeProps()
    }

    // MARK: Geometry

    var pxWidth: Int { Int((frame.width / scale).rounded(.down)) }
    var pxHeight: Int { Int((frame.height / scale).rounded(.down)) }

    var pxBounds: PxRect {
        PxRect(minX: Int(((available.minX - frame.minX) / scale).rounded(.up)),
               maxX: Int(((available.maxX - frame.minX) / scale).rounded(.down)),
               minY: Int(((available.minY - frame.minY) / scale).rounded(.up)),
               maxY: Int(((available.maxY - frame.minY) / scale).rounded(.down)))
    }

    func computeLayout(locked: ScaffoldTopology?) -> ScaffoldLayout? {
        ScaffoldGenerator.layout(ScaffoldParams(width: pxWidth, height: pxHeight, density: settings.density, bounds: pxBounds, locked: locked))
    }

    func positionRoot() {
        let s = max(1, backingScale)
        root.position = CGPoint(x: (frame.minX * s).rounded() / s, y: (frame.minY * s).rounded() / s)
    }

    /// Converts a site-pixel point to scene points.
    func scenePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: root.position.x + p.x * scale, y: root.position.y + p.y * scale)
    }

    func surfaceY(_ id: Int) -> CGFloat? {
        layout?.surface(id)?.y ?? (id == Surface.deckID ? 0 : nil)
    }

    // MARK: Element synchronisation

    /// Creates / reconfigures / removes element nodes so they match `layout`.
    func syncElements(animateRemovals: Bool) {
        guard let L = layout else {
            for (key, node) in elementNodes {
                if animateRemovals, node.buildState == .built {
                    node.animateRemoval { node.removeFromParent() }
                } else {
                    node.removeFromParent()
                }
                built.remove(key)
            }
            elementNodes.removeAll()
            return
        }
        var keep = Set<ElementKey>()
        for spec in L.elements {
            keep.insert(spec.key)
            let node: ScaffoldElementNode
            if let existing = elementNodes[spec.key] {
                node = existing
            } else {
                node = ScaffoldElementNode(key: spec.key)
                root.addChild(node)
                elementNodes[spec.key] = node
            }
            node.configure(layout: L)
        }
        for (key, node) in elementNodes where !keep.contains(key) {
            elementNodes[key] = nil
            built.remove(key)
            assigned.remove(key)
            if animateRemovals, node.buildState == .built {
                let c = node.center
                particles.emit(.dust, at: c, count: 3, rng: &rng)
                node.animateRemoval { node.removeFromParent() }
            } else {
                node.removeFromParent()
            }
        }
    }

    func placeProps() {
        guard let L = layout else { return }
        sign.base = CGPoint(x: L.signX, y: 0)
        stack.base = CGPoint(x: L.stackX, y: 0)
        toolbox.base = CGPoint(x: L.toolboxX, y: 0)
        // Cones: reuse nodes, add or remove to match.
        while cones.count < L.coneXs.count {
            let c = SiteProp(kind: .cone, base: .zero, wobble: 0.08, parent: root)
            if phase == .active { c.appear(animated: true) }
            cones.append(c)
        }
        while cones.count > L.coneXs.count {
            let c = cones.removeLast()
            c.disappear(animated: true)
            let n = c.node
            n.run(SKAction.sequence([SKAction.wait(forDuration: 0.2), SKAction.removeFromParent()]))
        }
        for (i, x) in L.coneXs.enumerated() { cones[i].base = CGPoint(x: x, y: 0) }
        if let f = flag, let t = L.towers.last {
            f.base = CGPoint(x: t.side == .left ? t.x0 : t.x1, y: t.topY + ScaffoldGenerator.railHeight)
        }
    }

    var allProps: [SiteProp] {
        var p: [SiteProp] = [sign, stack, toolbox]
        p.append(contentsOf: cones)
        if let flag { p.append(flag) }
        p.append(contentsOf: looseProps)
        return p
    }

    func build(_ key: ElementKey, animated: Bool = true) {
        guard let node = elementNodes[key], node.buildState != .built else { return }
        built.insert(key)
        assigned.remove(key)
        if animated {
            node.animateBuild()
            particles.emit(.dust, at: node.center, count: 2, rng: &rng)
            if visibleToUser { SoundEngine.shared.play(.pop) }
        } else {
            node.setBuiltInstantly()
        }
    }

    func buildAllInstantly() {
        guard let L = layout else { return }
        for spec in L.elements { build(spec.key, animated: false) }
    }

    var isFullyBuilt: Bool {
        guard let L = layout else { return true }
        return L.elements.allSatisfy { built.contains($0.key) }
    }

    var visibleToUser: Bool {
        !suspended && phase != .packed && structureVisible
    }

    // MARK: Window events

    func windowChanged(to newFrame: CGRect) {
        let sizeChanged = abs(newFrame.width - frame.width) > 0.5 || abs(newFrame.height - frame.height) > 0.5
        frame = newFrame
        positionRoot()
        guard sizeChanged else { return }
        guard phase != .tearingDown, phase != .finished, phase != .packed else { return }
        if !isResizing {
            isResizing = true
            resizeDidBegin()
        }
        resizeQuiet = 0
        let oldLayout = layout
        let locked = layout?.topology
        layout = computeLayout(locked: locked)
        root.isHidden = layout == nil
        syncElements(animateRemovals: true)
        placeProps()
        remapWorkers(from: oldLayout, animate: false)
    }

    func resizeDidSettle() {
        guard phase == .active || phase == .constructing || phase == .rebuilding else { return }
        let oldLayout = layout
        layout = computeLayout(locked: nil)
        root.isHidden = layout == nil
        syncElements(animateRemovals: true)
        placeProps()
        remapWorkers(from: oldLayout, animate: true)
        resizeSettledReaction(oldLayout: oldLayout)
    }

    /// Keeps workers on sensible surfaces after the layout moved underneath them.
    func remapWorkers(from old: ScaffoldLayout?, animate: Bool) {
        guard let new = layout else { return }
        for w in workers where !w.isLeaving {
            let oldDeck = old?.deck
            if w.surface == Surface.deckID || w.isClimbing {
                if let od = oldDeck, od.maxX > od.minX, !w.isClimbing {
                    let t = (w.pos.x - od.minX) / (od.maxX - od.minX)
                    w.pos.x = new.deck.minX + t * (new.deck.maxX - new.deck.minX)
                } else if !w.isClimbing {
                    w.pos.x = new.deck.clamp(w.pos.x)
                }
            }
            if w.isClimbing || w.surface != Surface.deckID {
                let side = TowerSide(rawValue: w.surface / 100) ?? (w.pos.x < CGFloat(new.width) / 2 ? .left : .right)
                let oldX0 = old?.tower(side)?.x0
                if let t = new.tower(side) {
                    if let ox = oldX0 { w.pos.x += CGFloat(t.x0 - ox) }
                    if let s = new.surface(w.surface) {
                        w.pos.x = s.clamp(w.pos.x)
                        if !w.isClimbing { w.pos.y = s.y }
                    } else {
                        let fb = new.fallbackSurface(for: w.surface)
                        dropWorker(w, to: fb, animate: animate)
                    }
                } else {
                    dropWorker(w, to: new.deck, animate: animate)
                }
            }
            if !w.inEvent && phase != .tearingDown && phase != .packing {
                if w.isClimbing || !w.steps.isEmpty {
                    // Steps refer to old coordinates; re-plan from a valid spot.
                    if w.isClimbing, let s = new.surface(w.surface) {
                        w.pos.y = s.y
                    }
                    w.clearSteps()
                    w.nextDecisionIn = rng.range(0.2, 0.8)
                }
            }
        }
    }

    func dropWorker(_ w: Worker, to s: Surface, animate: Bool) {
        let x = s.clamp(w.pos.x)
        if animate {
            w.clearSteps()
            w.cancelReaction()
            w.setSteps([.hop(to: s.id, x: x), .emote(.exclaim, 0.8), .anim(.scratch, 0.6)])
        } else {
            w.place(surface: s.id, x: x, y: s.y)
        }
    }

    func setOcclusion(_ info: OcclusionInfo) {
        occlusion = info
        let shouldSuspend = info.visibleFraction < 0.3
        if shouldSuspend != suspended {
            suspended = shouldSuspend
            root.removeAction(forKey: "suspend")
            root.run(SKAction.fadeAlpha(to: suspended ? 0 : 1, duration: 0.3), withKey: "suspend")
        }
        updateVisibility(force: true)
    }

    func apply(settings new: SimSettings) {
        let old = settings
        settings = new
        particles.amplitude = new.intensity.amplitude
        if abs(new.pixelScale - old.pixelScale) > 0.001 {
            rescale(to: new.pixelScale)
            return
        }
        if new.density != old.density, phase == .active || phase == .constructing {
            let oldLayout = layout
            layout = computeLayout(locked: nil)
            syncElements(animateRemovals: true)
            placeProps()
            remapWorkers(from: oldLayout, animate: true)
        }
        if new.crewSize != old.crewSize, phase == .active {
            adjustCrew()
        }
    }

    private func rescale(to s: CGFloat) {
        scale = s
        root.setScale(s)
        positionRoot()
        layout = computeLayout(locked: nil)
        root.isHidden = layout == nil
        for (_, node) in elementNodes { node.removeFromParent() }
        elementNodes.removeAll()
        built.removeAll()
        assigned.removeAll()
        syncElements(animateRemovals: false)
        placeProps()
        if phase == .active || phase == .constructing || phase == .rebuilding {
            buildAllInstantly()
            for p in [sign, stack, toolbox] { p?.appear(animated: false) }
            for c in cones { c.appear(animated: false) }
            phase = .active
        }
        guard let L = layout else { return }
        for w in workers {
            w.clearSteps()
            w.cancelReaction()
            w.place(surface: Surface.deckID, x: L.deck.clamp(w.pos.x), y: 0)
            w.nextDecisionIn = rng.range(0.2, 1.5)
        }
        endEvent()
    }

    // MARK: Per-frame update

    func update(dt: TimeInterval) {
        siteTime += dt
        phaseTime += dt
        let fdt = CGFloat(dt)

        motion.update(position: frame.origin, dt: fdt)
        updateMotionReactions(dt: dt)

        if isResizing {
            resizeQuiet += dt
            if resizeQuiet > 0.35 {
                isResizing = false
                resizeDidSettle()
            }
        }

        if phase == .packed || phase == .finished { return }
        let aiDT = settings.paused ? 0 : dt

        if !suspended || phase != .active {
            directorUpdate(dt: aiDT)
            for w in workers { w.update(dt: aiDT, ctx: self) }
            if phase == .active { updateEvents(dt: aiDT) }
        }

        // Props and rigs react to motion even when paused, so the world stays physical.
        let accPx = CGVector(dx: motion.acceleration.dx / scale, dy: motion.acceleration.dy / scale)
        let amp = settings.intensity.amplitude
        let drive = CGVector(dx: -accPx.dx * 0.3 * amp, dy: -accPx.dy * 0.3 * amp)
        for p in allProps where p.present {
            if p.falling {
                p.fallVelocity -= 220 * fdt
                p.base.y += p.fallVelocity * fdt
                if p.base.y <= p.floorY {
                    p.base.y = p.floorY
                    if abs(p.fallVelocity) > 25 {
                        p.fallVelocity = -p.fallVelocity * 0.3
                        particles.emit(.dust, at: p.base, count: 2, rng: &rng)
                        if visibleToUser { SoundEngine.shared.play(.clunk) }
                    } else {
                        p.falling = false
                        p.fallVelocity = 0
                    }
                }
            } else {
                p.spring.step(dt: fdt, drive: drive)
            }
            p.render()
        }
        updateRigs(dt: aiDT, accelX: accPx.dx)
        particles.update(dt: fdt)
        if let plank = longPlankNode, case .plankDuo(let a, let b, _)? = activeEvent {
            plank.isHidden = !(a.carrying == .longPlank && b.carrying == .longPlank)
            plank.position = CGPoint(x: ((a.pos.x + b.pos.x) / 2).rounded(), y: (min(a.pos.y, b.pos.y) + 12).rounded())
        }

        visibilityFrame += 1
        if visibilityFrame % 2 == 0 { updateVisibility(force: false) }
    }

    // MARK: Rigs

    private func updateRigs(dt: TimeInterval, accelX: CGFloat) {
        let fdt = CGFloat(dt)
        if let L = layout, let c = L.crane, let node = elementNodes[ElementKey(kind: .crane, side: c.side.rawValue, index: 0)], node.buildState == .built {
            let maxLen = CGFloat(c.jibY - 4)
            switch crane.stage {
            case .idle:
                crane.ropeLength += (5 - crane.ropeLength) * min(1, fdt * 2)
            case .lowering:
                crane.ropeLength += 16 * fdt
                if crane.ropeLength >= maxLen { crane.ropeLength = maxLen; crane.stage = .hooking; crane.timer = 0.7 }
            case .hooking:
                crane.timer -= dt
                if crane.timer <= 0 { crane.loaded = true; crane.stage = .raising; if visibleToUser { SoundEngine.shared.play(.clunk) } }
            case .raising:
                crane.ropeLength -= 10 * fdt
                if crane.ropeLength <= 7 { crane.ropeLength = 7; crane.stage = .delivering; crane.timer = 0.8 }
            case .delivering:
                crane.timer -= dt
                if crane.timer <= 0 {
                    crane.loaded = false
                    crane.stage = .idle
                    let drop = CGPoint(x: CGFloat(c.hookX), y: CGFloat(c.jibY) - crane.ropeLength - 4)
                    particles.emit(.dust, at: drop, count: 2, rng: &rng)
                }
            }
            crane.pendulum.step(dt: CGFloat(max(dt, 1.0 / 120)), length: max(4, crane.ropeLength), accelX: accelX)
            node.updateRig(length: crane.ropeLength, angle: crane.pendulum.angle, loaded: crane.loaded)
        }
        if let L = layout, let pl = L.pulley, let node = elementNodes[ElementKey(kind: .pulley, side: pl.side.rawValue, index: 0)], node.buildState == .built {
            let maxLen = CGFloat(pl.armTopY - 3)
            pulleyTimer -= dt
            switch pulley.stage {
            case .idle:
                if pulleyTimer <= 0 { pulley.stage = .lowering; pulleyTimer = rng.range(14, 30) }
                pulley.ropeLength += (5 - pulley.ropeLength) * min(1, fdt * 2)
            case .lowering:
                pulley.ropeLength += 9 * fdt
                if pulley.ropeLength >= maxLen { pulley.ropeLength = maxLen; pulley.stage = .hooking; pulley.timer = 1.2 }
            case .hooking:
                pulley.timer -= dt
                if pulley.timer <= 0 { pulley.stage = .raising }
            case .raising:
                pulley.ropeLength -= 7 * fdt
                if pulley.ropeLength <= 5 { pulley.ropeLength = 5; pulley.stage = .idle }
            case .delivering:
                pulley.stage = .idle
            }
            pulley.pendulum.step(dt: CGFloat(max(dt, 1.0 / 120)), length: max(4, pulley.ropeLength), accelX: accelX)
            node.updateRig(length: pulley.ropeLength, angle: pulley.pendulum.angle, loaded: false)
        }
    }

    func startCraneLift() -> Bool {
        guard layout?.crane != nil, crane.stage == .idle else { return false }
        crane.stage = .lowering
        return true
    }

    // MARK: Visibility (occlusion by windows in front)

    func updateVisibility(force: Bool) {
        let occluders = occlusion.occluders
        if occluders.isEmpty {
            guard force || occlusionApplied else { return }
            for (_, n) in elementNodes { n.isHidden = false }
            for w in workers { w.node.isHidden = false }
            for p in allProps { p.node.isHidden = false }
            structureVisible = true
            occlusionApplied = false
            return
        }
        occlusionApplied = true
        func hidden(_ p: CGPoint) -> Bool {
            let sp = scenePoint(p)
            return occluders.contains { $0.contains(sp) }
        }
        var anyVisible = false
        for (_, n) in elementNodes {
            let h = hidden(n.center)
            n.isHidden = h
            if !h { anyVisible = true }
        }
        // Things that hang off a tower disappear with the tower section that holds them,
        // so nothing floats in mid-air next to a window in front.
        func towerHidden(side: Int, level: Int) -> Bool {
            elementNodes[ElementKey(kind: .tower, side: side, index: level)]?.isHidden ?? false
        }
        for (key, n) in elementNodes where !n.isHidden {
            switch key.kind {
            case .ladder:
                if towerHidden(side: key.side, level: key.index) { n.isHidden = true }
            case .crane, .pulley:
                if let side = TowerSide(rawValue: key.side), let t = layout?.tower(side), towerHidden(side: key.side, level: t.levels) {
                    n.isHidden = true
                }
            default:
                break
            }
        }
        for w in workers {
            var h = hidden(CGPoint(x: w.pos.x, y: w.pos.y + 6))
            if !h, w.surface != Surface.deckID {
                h = towerHidden(side: w.surface / 100, level: w.surface % 100)
            }
            if !h, w.surface == Surface.deckID, w.node.alpha > 0.5, let L = layout,
               let bay = L.bayIndex(containing: Int(w.pos.x)),
               let n = elementNodes[ElementKey(kind: .bay, side: 0, index: bay)], n.buildState == .built {
                h = n.isHidden
            }
            w.node.isHidden = h
            if h { w.emoteNode.isHidden = true }
        }
        for p in allProps { p.node.isHidden = hidden(CGPoint(x: p.base.x, y: p.base.y + 2)) }
        structureVisible = anyVisible
    }

    // MARK: Hammer feedback

    func hammerImpact(by worker: Worker) {
        guard visibleToUser, !worker.node.isHidden else { return }
        let tip = worker.toolTip
        if rng.chance(0.55) {
            let kind: ParticleKind = rng.chance(0.35) ? .spark : .chip
            let count = rng.int(1...2)
            particles.emit(kind, at: tip, count: count, rng: &rng)
        }
        SoundEngine.shared.play(.tap)
    }

    // MARK: Teardown helpers

    func removeEverything() {
        if workers.contains(where: { $0.isSupervisor }) { scene?.supervisorActive = false }
        for w in workers { w.removeFromScene() }
        workers.removeAll()
        longPlankNode?.removeFromParent()
        longPlankNode = nil
        root.removeAllActions()
        root.removeFromParent()
    }

    // MARK: Workers

    func spawnWorker(supervisor: Bool = false) -> Worker {
        let style: Int
        if supervisor {
            style = TextureCache.supervisorStyleIndex
        } else {
            style = styleCursor % WorkerStyle.crew.count
            styleCursor += 1
        }
        let personality = Personality(rng: &rng)
        let w = Worker(id: nextWorkerID, styleIndex: style, isSupervisor: supervisor, personality: personality, parent: root, rng: &rng)
        nextWorkerID += 1
        workers.append(w)
        return w
    }

    func removeWorker(_ w: Worker) {
        if w.isSupervisor { scene?.supervisorActive = false }
        w.removeFromScene()
        workers.removeAll { $0 === w }
    }

    func resizeDidBegin() {
        guard phase == .active else { return }
        resizeBeganReaction()
    }
}
