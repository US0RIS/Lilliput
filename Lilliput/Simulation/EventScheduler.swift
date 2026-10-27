import Foundation
import SpriteKit

/// The small, infrequent moments that reward casual observation.
enum SiteEvent {
    case plankDuo(Worker, Worker, SKSpriteNode)
    case dropTool(Worker)
    case craneLift(Worker)
    case nap(sleeper: Worker, waker: Worker)
    case knockStack(Worker)
    case supervisor(Worker)
    case argue(Worker, Worker)
    case celebrate([Worker])
    case flag(Worker)

    var participants: [Worker] {
        switch self {
        case .plankDuo(let a, let b, _): return [a, b]
        case .dropTool(let w), .craneLift(let w), .knockStack(let w), .supervisor(let w), .flag(let w): return [w]
        case .nap(let a, let b): return [a, b]
        case .argue(let a, let b): return [a, b]
        case .celebrate(let ws): return ws
        }
    }
}

enum SpecialEventKind: CaseIterable {
    case plankDuo, dropTool, craneLift, nap, knockStack, supervisor, argue
}

extension ConstructionSite {
    func updateEvents(dt: TimeInterval) {
        if let e = activeEvent {
            let stillBusy = e.participants.contains { w in
                workers.contains { $0 === w } && !w.isIdle
            }
            if !stillBusy { endEvent() }
            return
        }
        guard settings.specialEvents, !isMoving, !isResizing, visibleToUser, phase == .active else { return }
        eventTimer -= dt * settings.intensity.liveliness
        if eventTimer <= 0 {
            eventTimer = rng.range(22, 48)
            _ = triggerRandomEvent()
        }
    }

    private var freeCrew: [Worker] {
        workers.filter { !$0.isSupervisor && !$0.isLeaving && !$0.inEvent && $0.reaction == nil && $0.node.alpha > 0.9 }
    }

    @discardableResult
    func triggerRandomEvent(forced: Bool = false) -> Bool {
        guard phase == .active, activeEvent == nil, layout != nil else { return false }
        let free = freeCrew
        let reach = reachableSurfaces()
        let hasRaised = reach.count > 1
        let craneReady = layout?.crane != nil && crane.stage == .idle && isFullyBuilt
        let supervisorOK = scene?.supervisorAvailable ?? false

        var options: [(SpecialEventKind, Double)] = [
            (.plankDuo, free.count >= 2 && stack.present ? 3 : 0),
            (.dropTool, hasRaised && !free.isEmpty ? 2 : 0),
            (.craneLift, craneReady && !free.isEmpty ? 2 : 0),
            (.nap, free.count >= 2 ? 2 : 0),
            (.knockStack, stack.present && !free.isEmpty ? 1.5 : 0),
            (.supervisor, supervisorOK ? 1.2 : 0),
            (.argue, free.count >= 2 ? 2 : 0),
        ]
        if !forced {
            options = options.map { ($0.0, $0.1) }
        }
        guard let idx = rng.weightedIndex(options.map(\.1)) else { return false }
        switch options[idx].0 {
        case .plankDuo: return startPlankDuo(free)
        case .dropTool: return startDropTool(free)
        case .craneLift: return startCraneEvent(free)
        case .nap: return startNap(free)
        case .knockStack: return startKnockStack(free)
        case .supervisor: return startSupervisor()
        case .argue: return startArgue(free)
        }
    }

    func endEvent() {
        for w in workers {
            w.inEvent = false
            w.speedOverride = nil
            if w.carrying == .longPlank { w.setCarrying(nil) }
        }
        longPlankNode?.removeFromParent()
        longPlankNode = nil
        for p in looseProps { p.node.removeFromParent() }
        looseProps.removeAll()
        stack.tilt = 0
        activeEvent = nil
    }

    private func claim(_ ws: [Worker]) {
        for w in ws {
            w.clearSteps()
            w.cancelReaction()
            w.inEvent = true
            w.setCarrying(nil)
        }
    }

    // 1. Two workers carry one long plank together.
    private func startPlankDuo(_ free: [Worker]) -> Bool {
        guard let L = layout, free.count >= 2 else { return false }
        let deck = L.deck
        guard deck.maxX - deck.minX > 60 else { return false }
        let a = free[0], b = free[1]
        claim([a, b])
        let mid = (deck.minX + deck.maxX) / 2
        let dir: CGFloat = CGFloat(L.stackX) < mid ? 1 : -1
        let pick = deck.clamp(CGFloat(L.stackX) + dir * 8)
        let leadStart = deck.clamp(pick + dir * 9)
        let followStart = deck.clamp(leadStart - dir * 18)
        let dest = dir > 0 ? deck.maxX - 6 : deck.minX + 6
        let leadDest = deck.clamp(dest)
        let followDest = deck.clamp(leadDest - dir * 18)
        var ready = 0
        let speed = min(a.walkSpeed, b.walkSpeed) * 0.85
        a.speedOverride = speed
        b.speedOverride = speed

        var sa = travel(from: here(a), to: NavPoint(surface: Surface.deckID, x: leadStart))
        sa += [.face(Int(dir)), .anim(.crouch, 0.3), .call { ready += 1 }, .waitUntil({ ready >= 2 }, timeout: 8),
               .carry(.longPlank), .wait(0.35), .walk(leadDest, run: false), .wait(0.25), .anim(.crouch, 0.35), .carry(nil),
               .call { [weak self] in
                   guard let self else { return }
                   self.particles.emit(.dust, at: CGPoint(x: (leadDest + followDest) / 2, y: 0), count: 3, rng: &self.rng)
                   if self.visibleToUser { SoundEngine.shared.play(.clunk) }
               },
               .emote(.sparkle, 0.9), .face(Int(-dir)), .anim(.hammer, 1.0)]
        var sb = travel(from: here(b), to: NavPoint(surface: Surface.deckID, x: followStart))
        sb += [.face(Int(dir)), .anim(.crouch, 0.3), .call { ready += 1 }, .waitUntil({ ready >= 2 }, timeout: 8),
               .carry(.longPlank), .wait(0.35), .walk(followDest, run: false), .wait(0.25), .anim(.crouch, 0.35), .carry(nil),
               .anim(.scratch, 0.6)]
        a.setSteps(sa)
        b.setSteps(sb)

        let plank = SKSpriteNode(texture: TextureCache.shared.prop(.longPlank))
        plank.anchorPoint = CGPoint(x: 0.5, y: 0)
        plank.zPosition = 21
        plank.isHidden = true
        root.addChild(plank)
        longPlankNode = plank
        activeEvent = .plankDuo(a, b, plank)
        return true
    }

    // 2. A worker drops a tool, climbs down to fetch it and returns.
    private func startDropTool(_ free: [Worker]) -> Bool {
        guard let L = layout else { return false }
        let raised = reachableSurfaces().filter { $0.id != Surface.deckID }
        guard let w = free.first(where: { $0.surface != Surface.deckID }) ?? free.first, let s = rng.pick(raised) else { return false }
        claim([w])
        let spot = randomSpot(on: s)
        let faceDir = rng.sign()
        let dropX = L.deck.clamp(spot.x + CGFloat(faceDir) * 6)
        var steps = travel(from: here(w), to: spot)
        steps += [.face(faceDir), .anim(.hammer, 1.0)]
        steps.append(.call { [weak self, weak w] in
            guard let self, let w else { return }
            let tool = SiteProp(kind: .hammer, base: CGPoint(x: dropX, y: w.pos.y + 4), wobble: 0.1, parent: self.root)
            tool.falling = true
            tool.fallVelocity = 18
            tool.floorY = 0
            tool.appear(animated: false)
            self.looseProps.append(tool)
        })
        steps += [.emote(.exclaim, 1.0), .anim(.scratch, 0.7)]
        let ground = NavPoint(surface: Surface.deckID, x: dropX)
        steps += travel(from: spot, to: ground)
        steps += [.anim(.crouch, 0.35), .call { [weak self] in
            guard let self else { return }
            for p in self.looseProps where p.kind == .hammer { p.node.removeFromParent() }
            self.looseProps.removeAll { $0.kind == .hammer }
        }, .carry(.hammer), .emote(.sweat, 0.8)]
        steps += travel(from: ground, to: spot)
        steps += [.carry(nil), .face(faceDir), .anim(.hammer, 1.2), .emote(.sparkle, 0.8)]
        w.setSteps(steps)
        activeEvent = .dropTool(w)
        return true
    }

    // 3. The crane slowly raises a load while a worker signals.
    private func startCraneEvent(_ free: [Worker]) -> Bool {
        guard let L = layout, let c = L.crane, let w = free.first else { return false }
        guard startCraneLift() else { return false }
        claim([w])
        let x = L.deck.clamp(CGFloat(c.hookX - c.jibDir * 6))
        var steps = travel(from: here(w), to: NavPoint(surface: Surface.deckID, x: x), run: true)
        steps += [.face(CGFloat(c.hookX) >= x ? 1 : -1), .anim(.signal, 3.0), .anim(.point, 1.2),
                  .waitUntil({ [weak self] in self?.crane.stage == .idle }, timeout: 6), .emote(.thumbs, 1.0), .anim(.thumbsUp, 1.0)]
        w.setSteps(steps)
        activeEvent = .craneLift(w)
        return true
    }

    // 4. A worker dozes off on a break and gets woken by a colleague.
    private func startNap(_ free: [Worker]) -> Bool {
        guard let L = layout, free.count >= 2 else { return false }
        let sleeper = free.max { $0.personality.laziness < $1.personality.laziness } ?? free[0]
        guard let waker = free.first(where: { $0 !== sleeper }) else { return false }
        claim([sleeper, waker])
        let raised = reachableSurfaces().filter { $0.id != Surface.deckID }
        let s = (rng.chance(0.6) ? rng.pick(raised) : nil) ?? L.deck
        let spot = randomSpot(on: s)
        let side: CGFloat = spot.x > (s.minX + s.maxX) / 2 ? -1 : 1
        let wakeSpot = NavPoint(surface: s.id, x: s.clamp(spot.x + side * 6))

        var ss = travel(from: here(sleeper), to: spot)
        ss += [.face(Int(side)), .anim(.sit, 1.6), .emote(.sleep, 25), .anim(.sleep, 25)]
        sleeper.setSteps(ss)

        var sw: [WorkerStep] = [.wait(3.5), .waitUntil({ [weak sleeper] in sleeper?.anim == .sleep }, timeout: 12)]
        sw += travel(from: here(waker), to: wakeSpot)
        sw += [.face(Int(-side)), .anim(.point, 0.5), .emote(.exclaim, 0.8),
               .call { [weak sleeper] in
                   guard let sleeper else { return }
                   sleeper.emoteNode.isHidden = true
                   sleeper.clearSteps()
                   sleeper.setSteps([.emote(.exclaim, 0.9), .hop(to: sleeper.surface, x: sleeper.pos.x),
                                     .anim(.scratch, 0.8), .emote(.dots, 0.9), .wait(0.4)])
               },
               .anim(.thumbsUp, 0.9), .wait(0.3)]
        waker.setSteps(sw)
        activeEvent = .nap(sleeper: sleeper, waker: waker)
        return true
    }

    // 5. A worker bumps the material stack over, then tidies it.
    private func startKnockStack(_ free: [Worker]) -> Bool {
        guard let L = layout, let w = free.first else { return false }
        claim([w])
        let fromLeft = w.pos.x < CGFloat(L.stackX)
        let approach = L.deck.clamp(CGFloat(L.stackX) + (fromLeft ? -9 : 9))
        let bump = L.deck.clamp(CGFloat(L.stackX) + (fromLeft ? -4 : 4))
        let dir: CGFloat = fromLeft ? 1 : -1
        var steps = travel(from: here(w), to: NavPoint(surface: Surface.deckID, x: approach))
        steps += [.carry(.plank), .walk(bump, run: false),
                  .call { [weak self] in
                      guard let self else { return }
                      self.stack.tilt = -0.35 * dir
                      self.stack.spring.velocity.dx += 30 * dir
                      self.particles.emit(.dust, at: self.stack.base, count: 4, rng: &self.rng)
                      self.particles.emit(.chip, at: CGPoint(x: self.stack.base.x, y: 3), count: 2, rng: &self.rng)
                      if self.visibleToUser { SoundEngine.shared.play(.clunk) }
                  },
                  .carry(nil), .emote(.exclaim, 0.9), .anim(.stumble, 0.4), .anim(.scratch, 0.8),
                  .anim(.crouch, 1.3),
                  .call { [weak self] in
                      guard let self else { return }
                      self.stack.tilt = 0
                      self.particles.emit(.dust, at: self.stack.base, count: 2, rng: &self.rng)
                  },
                  .emote(.sparkle, 0.8), .anim(.lookAround, 0.9)]
        w.setSteps(steps)
        activeEvent = .knockStack(w)
        return true
    }

    // 6. The supervisor walks the site, checks the work and gives a thumbs-up.
    private func startSupervisor() -> Bool {
        guard let L = layout, let scene, scene.supervisorAvailable else { return false }
        scene.supervisorActive = true
        let s = spawnWorker(supervisor: true)
        s.inEvent = true
        let staging = stagingPoint()
        s.place(surface: Surface.deckID, x: staging.x, y: 0)
        s.node.alpha = 0
        let deck = L.deck
        let stops = [0.2, 0.5, 0.8].map { deck.minX + (deck.maxX - deck.minX) * CGFloat($0) }
        let ordered = staging.side < 0 ? stops : stops.reversed()
        var steps: [WorkerStep] = [.fade(to: 1, 0.25)]
        var cur = NavPoint(surface: Surface.deckID, x: staging.x)
        for (i, x) in ordered.enumerated() {
            let p = NavPoint(surface: Surface.deckID, x: x.rounded())
            steps += travel(from: cur, to: p)
            cur = p
            steps += [.face(rng.sign()), .anim(.clipboard, 1.4)]
            if i == 1 { steps.append(.anim(.lookAround, 0.9)) }
        }
        steps.append(.call { [weak self] in
            guard let self else { return }
            for w in self.crew where !w.inEvent && self.rng.chance(0.5) {
                w.showEmote(.sparkle, duration: 0.9)
            }
        })
        steps += [.face(Int(-staging.side)), .anim(.thumbsUp, 1.2), .emote(.thumbs, 1.0)]
        steps += travel(from: cur, to: NavPoint(surface: Surface.deckID, x: staging.x))
        steps += [.walk(staging.x + staging.side * 4, run: false), .fade(to: 0, 0.25),
                  .call { [weak self, weak s] in
                      guard let self, let s else { return }
                      self.removeWorker(s)
                  }]
        s.setSteps(steps)
        activeEvent = .supervisor(s)
        return true
    }

    // 7. Two workers briefly disagree over the blueprint, then get back to it.
    private func startArgue(_ free: [Worker]) -> Bool {
        guard let L = layout, free.count >= 2 else { return false }
        let a = free[0], b = free[1]
        claim([a, b])
        let deck = L.deck
        let mx = rng.cg(deck.minX + 8, max(deck.minX + 9, deck.maxX - 8)).rounded()
        let pa = NavPoint(surface: Surface.deckID, x: deck.clamp(mx - 4))
        let pb = NavPoint(surface: Surface.deckID, x: deck.clamp(mx + 4))
        var ready = 0
        var sa = travel(from: here(a), to: pa)
        sa += [.face(1), .call { ready += 1 }, .waitUntil({ ready >= 2 }, timeout: 8),
               .anim(.inspect, 1.2), .emote(.question, 0.9), .anim(.argue, 1.8), .emote(.dots, 0.9), .anim(.scratch, 0.6)]
        var sb = travel(from: here(b), to: pb)
        sb += [.face(-1), .call { ready += 1 }, .waitUntil({ ready >= 2 }, timeout: 8),
               .anim(.point, 1.2), .emote(.exclaim, 0.9), .anim(.argue, 1.8), .anim(.scratch, 0.6), .emote(.note, 0.8)]
        a.setSteps(sa)
        b.setSteps(sb)
        activeEvent = .argue(a, b)
        return true
    }

    // 9. Celebration when a structure is first completed.
    func startCelebration() {
        let ws = freeCrewIncludingBusy()
        guard !ws.isEmpty else { return }
        claim(ws)
        for (i, w) in ws.enumerated() {
            w.setSteps([.wait(Double(i) * 0.14), .anim(.cheer, 1.2), .emote(rng.chance(0.5) ? .note : .sparkle, 0.9)])
        }
        activeEvent = .celebrate(ws)
    }

    // 10. A worker plants a small flag on top of the finished tower.
    @discardableResult
    func startFlagEvent() -> Bool {
        guard let L = layout, let t = L.towers.last, let w = freeCrewIncludingBusy().first else { return false }
        guard let top = L.surface(t.surfaceID(level: t.levels)) else { return false }
        claim([w])
        let x = top.clamp(CGFloat(t.side == .left ? t.x0 + 2 : t.x1 - 2))
        var steps: [WorkerStep] = [.carry(.flag)]
        steps += travel(from: here(w), to: NavPoint(surface: top.id, x: x))
        steps += [.face(t.side == .left ? -1 : 1), .anim(.crouch, 0.4), .carry(nil),
                  .call { [weak self] in
                      guard let self else { return }
                      if self.flag == nil {
                          self.flag = SiteProp(kind: .flag, base: .zero, wobble: 0.06, parent: self.root)
                      }
                      self.placeProps()
                      self.flag?.appear(animated: true)
                      if let f = self.flag { self.particles.emit(.spark, at: f.base, count: 2, rng: &self.rng) }
                  },
                  .anim(.cheer, 0.9), .emote(.sparkle, 0.9)]
        w.setSteps(steps)
        activeEvent = .flag(w)
        return true
    }

    private func freeCrewIncludingBusy() -> [Worker] {
        workers.filter { !$0.isSupervisor && !$0.isLeaving && !$0.inEvent && $0.node.alpha > 0.5 }
    }
}
