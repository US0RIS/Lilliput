import Foundation
import SpriteKit

enum CarryItem: Equatable {
    case plank
    case toolbox
    case bucket
    case bricks
    case sign
    case cone
    case flag
    case hammer
    case longPlank

    var prop: PropKind {
        switch self {
        case .plank: return .plank
        case .toolbox: return .toolbox
        case .bucket: return .bucket
        case .bricks: return .bricks
        case .sign: return .sign
        case .cone: return .cone
        case .flag: return .flag
        case .hammer: return .hammer
        case .longPlank: return .plank
        }
    }

    /// Carried above the head (true) or at the side (false).
    var overhead: Bool {
        switch self {
        case .plank, .bricks, .longPlank, .bucket: return true
        default: return false
        }
    }
}

enum Activity: Hashable, CaseIterable {
    case hammer, inspect, carry, climb, rest, repair, signal, wander, look
}

struct Personality {
    var speed: CGFloat
    var diligence: Double
    var laziness: Double
    var curiosity: Double

    init(rng: inout SplitMix64) {
        speed = rng.cg(0.85, 1.18)
        diligence = rng.range(0.2, 1)
        laziness = rng.range(0, 0.8)
        curiosity = rng.range(0.1, 1)
    }
}

enum WorkerStep {
    case walk(CGFloat, run: Bool)
    case climb(x: CGFloat, to: Int)
    case anim(Anim, TimeInterval)
    case face(Int)
    case emote(Emote, TimeInterval)
    case call(() -> Void)
    case wait(TimeInterval)
    case waitUntil(() -> Bool, timeout: TimeInterval)
    case hop(to: Int, x: CGFloat)
    case fade(to: CGFloat, TimeInterval)
    case carry(CarryItem?)
}

@MainActor
protocol WorkerContext: AnyObject {
    func surfaceY(_ id: Int) -> CGFloat?
    func hammerImpact(by worker: Worker)
}

/// One member of the crew: an animated sprite plus a queue of steps to carry out.
/// Higher-level decisions (what to do next) come from the ConstructionDirector.
@MainActor
final class Worker {
    let id: Int
    let styleIndex: Int
    let isSupervisor: Bool
    let node: SKSpriteNode
    let emoteNode: SKSpriteNode
    private let carryNode: SKSpriteNode
    var personality: Personality

    var surface: Int = Surface.deckID
    var pos: CGPoint = .zero
    var facing: Int = 1
    private(set) var carrying: CarryItem?

    private(set) var steps: [WorkerStep] = []
    private var stepElapsed: TimeInterval = 0
    private var stepStarted = false
    private var hopFrom: CGPoint = .zero
    private var hopTo: CGPoint = .zero
    private var fadeFrom: CGFloat = 1
    private var lookBaseFacing = 1

    private(set) var anim: Anim = .stand
    private var animClock: TimeInterval = 0
    private var walkPhase: CGFloat = 0
    private var climbPhase: CGFloat = 0
    private var yOffset: CGFloat = 0
    private var blinkTimer: TimeInterval
    private var blinkRemaining: TimeInterval = 0
    private var emoteRemaining: TimeInterval = 0
    private var lastPose: Pose?

    // Reaction overrides (brace, hang, stumble) pause the step queue.
    private(set) var reaction: Anim?
    private var reactionRemaining: TimeInterval = 0
    private var reactionHold = false

    // AI bookkeeping owned by the director.
    var nextDecisionIn: TimeInterval = 0
    var cooldowns: [Activity: TimeInterval] = [:]
    var lastActivity: Activity?
    var assignment: ElementKey?
    var inEvent = false
    var isLeaving = false
    var restingSince: TimeInterval?

    var speedOverride: CGFloat?

    var walkSpeed: CGFloat { speedOverride ?? 14 * personality.speed }
    var runSpeed: CGFloat { 30 * personality.speed }
    var climbSpeed: CGFloat { 11 * personality.speed }

    var isIdle: Bool { steps.isEmpty && reaction == nil }
    var isClimbing: Bool { anim == .climb }
    var isOnTower: Bool { surface != Surface.deckID }

    init(id: Int, styleIndex: Int, isSupervisor: Bool, personality: Personality, parent: SKNode, rng: inout SplitMix64) {
        self.id = id
        self.styleIndex = styleIndex
        self.isSupervisor = isSupervisor
        self.personality = personality
        blinkTimer = rng.range(1.5, 5)

        let cache = TextureCache.shared
        node = SKSpriteNode(texture: cache.worker(style: styleIndex, pose: .stand(blink: false)))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.zPosition = 20 + CGFloat(id % 5) * 0.1
        parent.addChild(node)

        carryNode = SKSpriteNode(texture: nil, color: .clear, size: .zero)
        carryNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        carryNode.zPosition = 0.5
        carryNode.isHidden = true
        node.addChild(carryNode)

        emoteNode = SKSpriteNode(texture: cache.emote(.dots))
        emoteNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        emoteNode.zPosition = 45
        emoteNode.isHidden = true
        parent.addChild(emoteNode)
    }

    func removeFromScene() {
        node.removeAllActions()
        node.removeFromParent()
        emoteNode.removeFromParent()
    }

    // MARK: Step queue

    func setSteps(_ s: [WorkerStep]) {
        steps = s
        stepElapsed = 0
        stepStarted = false
    }

    func append(_ s: [WorkerStep]) {
        steps.append(contentsOf: s)
    }

    func clearSteps() {
        steps.removeAll()
        stepElapsed = 0
        stepStarted = false
        assignment = nil
    }

    func place(surface: Int, x: CGFloat, y: CGFloat) {
        self.surface = surface
        pos = CGPoint(x: x, y: y)
    }

    func setCarrying(_ item: CarryItem?) {
        carrying = item
        if let item {
            let tex = TextureCache.shared.prop(item == .longPlank ? .longPlank : item.prop)
            carryNode.texture = tex
            carryNode.size = tex.size()
            carryNode.isHidden = item == .longPlank // long planks are drawn by the event
            carryNode.zPosition = item.overhead ? 0.5 : 0.6
        } else {
            carryNode.isHidden = true
        }
    }

    func showEmote(_ e: Emote, duration: TimeInterval) {
        emoteNode.texture = TextureCache.shared.emote(e)
        emoteNode.size = emoteNode.texture?.size() ?? .zero
        emoteNode.isHidden = false
        emoteRemaining = duration
    }

    func react(_ a: Anim, duration: TimeInterval, hold: Bool = false) {
        reaction = a
        reactionRemaining = duration
        reactionHold = hold
        animClock = 0
    }

    func releaseReaction() {
        reactionHold = false
        if reactionRemaining > 0.25 { reactionRemaining = 0.25 }
    }

    func cancelReaction() {
        reaction = nil
        reactionHold = false
        reactionRemaining = 0
    }

    // MARK: Update

    func update(dt: TimeInterval, ctx: WorkerContext) {
        animClock += dt
        if emoteRemaining > 0 {
            emoteRemaining -= dt
            if emoteRemaining <= 0 { emoteNode.isHidden = true }
        }
        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkRemaining = 0.13
            blinkTimer = Double.random(in: 2.2...5.5)
        }
        if blinkRemaining > 0 { blinkRemaining -= dt }

        if let r = reaction {
            if !reactionHold { reactionRemaining -= dt }
            if reactionRemaining <= 0 && !reactionHold {
                reaction = nil
            } else {
                render(anim: r, ctx: ctx)
                return
            }
        }

        var remaining = dt
        var guardCount = 0
        while remaining > 0, guardCount < 10, !steps.isEmpty {
            guardCount += 1
            let (consumed, done) = perform(steps[0], dt: remaining, ctx: ctx)
            remaining -= consumed
            if done {
                if !steps.isEmpty { steps.removeFirst() }
                stepElapsed = 0
                stepStarted = false
            } else {
                break
            }
        }
        if steps.isEmpty {
            let idleAnim: Anim = carrying.map { $0.overhead ? .carryStand : .stand } ?? .stand
            if anim != idleAnim && !isRestAnim(anim) { setAnim(idleAnim) }
        }
        render(anim: anim, ctx: ctx)
    }

    private func isRestAnim(_ a: Anim) -> Bool {
        a == .sit || a == .sleep
    }

    private func setAnim(_ a: Anim) {
        if anim != a {
            anim = a
            animClock = 0
        }
    }

    /// Returns (time consumed, finished).
    private func perform(_ step: WorkerStep, dt: TimeInterval, ctx: WorkerContext) -> (TimeInterval, Bool) {
        let first = !stepStarted
        stepStarted = true
        switch step {
        case .walk(let x, let run):
            let speed = Double(run ? runSpeed : walkSpeed)
            let dx = x - pos.x
            if abs(dx) < 0.01 { return (0, true) }
            facing = dx > 0 ? 1 : -1
            let move = min(abs(dx), CGFloat(speed * dt))
            pos.x += move * CGFloat(facing)
            walkPhase += move
            if let c = carrying {
                setAnim(c.overhead ? .carryWalk : .carryBoxWalk)
            } else {
                setAnim(run ? .run : .walk)
            }
            let reached = abs(x - pos.x) < 0.01
            if reached { pos.x = x }
            return (Double(move) / speed, reached)

        case .climb(let x, let to):
            if first { pos.x = x }
            guard let ty = ctx.surfaceY(to) else { return (0, true) }
            let dy = ty - pos.y
            setAnim(.climb)
            if abs(dy) < 0.01 {
                surface = to
                return (0, true)
            }
            let speed = Double(climbSpeed)
            let move = min(abs(dy), CGFloat(speed * dt))
            pos.y += move * (dy > 0 ? 1 : -1)
            climbPhase += move
            if abs(ty - pos.y) < 0.01 {
                pos.y = ty
                surface = to
                return (Double(move) / speed, true)
            }
            return (dt, false)

        case .anim(let a, let duration):
            if first {
                anim = a
                animClock = 0
                lookBaseFacing = facing
            }
            let before = stepElapsed
            let use = min(dt, max(0, duration - before))
            stepElapsed += use
            if a == .hammer {
                let impactsBefore = WorkerAnimator.hammerImpacts(by: before)
                let impactsAfter = WorkerAnimator.hammerImpacts(by: stepElapsed)
                if impactsAfter > impactsBefore { ctx.hammerImpact(by: self) }
            }
            if a == .lookAround {
                facing = Int(stepElapsed / 0.9) % 2 == 0 ? lookBaseFacing : -lookBaseFacing
            }
            return (use, stepElapsed >= duration)

        case .face(let d):
            facing = d >= 0 ? 1 : -1
            return (0, true)

        case .emote(let e, let duration):
            showEmote(e, duration: duration)
            return (0, true)

        case .call(let f):
            f()
            return (0, true)

        case .wait(let duration):
            if first { setAnim(carrying.map { $0.overhead ? .carryStand : .stand } ?? .stand) }
            let use = min(dt, max(0, duration - stepElapsed))
            stepElapsed += use
            return (use, stepElapsed >= duration)

        case .waitUntil(let cond, let timeout):
            if first { setAnim(carrying.map { $0.overhead ? .carryStand : .stand } ?? .stand) }
            if cond() { return (0, true) }
            stepElapsed += dt
            return (dt, stepElapsed >= timeout)

        case .hop(let to, let x):
            let duration = 0.42
            if first {
                hopFrom = pos
                hopTo = CGPoint(x: x, y: ctx.surfaceY(to) ?? pos.y)
                setAnim(.stumble)
            }
            let use = min(dt, max(0, duration - stepElapsed))
            stepElapsed += use
            let t = CGFloat(min(1, stepElapsed / duration))
            pos.x = hopFrom.x + (hopTo.x - hopFrom.x) * t
            let baseY = hopFrom.y + (hopTo.y - hopFrom.y) * t * t
            pos.y = baseY + 6 * sin(.pi * t)
            if stepElapsed >= duration {
                pos = hopTo
                surface = to
                setAnim(.stand)
                return (use, true)
            }
            return (use, false)

        case .fade(let target, let duration):
            if first { fadeFrom = node.alpha }
            let use = min(dt, max(0, duration - stepElapsed))
            stepElapsed += use
            let t = CGFloat(duration <= 0 ? 1 : min(1, stepElapsed / duration))
            node.alpha = fadeFrom + (target - fadeFrom) * t
            return (use, stepElapsed >= duration)

        case .carry(let item):
            setCarrying(item)
            return (0, true)
        }
    }

    private func render(anim a: Anim, ctx: WorkerContext) {
        let blink = blinkRemaining > 0
        let pose = WorkerAnimator.pose(a, t: animClock, walkPhase: walkPhase, climbPhase: climbPhase, blink: blink)
        if pose != lastPose {
            node.texture = TextureCache.shared.worker(style: styleIndex, pose: pose)
            lastPose = pose
        }
        yOffset = WorkerAnimator.yOffset(a, t: animClock)
        var drawY = pos.y + yOffset
        if a == .hang { drawY -= 9 }
        node.position = CGPoint(x: pos.x.rounded(), y: drawY.rounded())
        node.xScale = a == .climb ? 1 : CGFloat(facing)

        if let c = carrying, !carryNode.isHidden {
            if c.overhead {
                let bob: CGFloat
                if case .carry(let f) = pose { bob = CGFloat(f % 2) } else { bob = 0 }
                carryNode.position = CGPoint(x: 0, y: 12 - bob)
            } else {
                carryNode.position = CGPoint(x: 4, y: 1)
            }
        }
        if !emoteNode.isHidden {
            emoteNode.position = CGPoint(x: (pos.x + CGFloat(facing) * 2).rounded(), y: (drawY + 15).rounded())
        }
    }

    /// World-space point (site px) at the business end of a hammer.
    var toolTip: CGPoint {
        CGPoint(x: pos.x + CGFloat(facing) * 7, y: pos.y + 3)
    }
}
