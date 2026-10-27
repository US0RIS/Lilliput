import Foundation
import SpriteKit

/// Sequencing and crew decision-making for a site: the arrival/construction choreography,
/// teardown, the quick pack/unpack used for minimize, idle behaviour and reactions to
/// window motion and resizing.
extension ConstructionSite {
    private enum Mark: Int {
        case conesShown = 1
        case propsPacked
        case exitIssued
        case forcedBuild
    }

    // MARK: Travel helpers

    func travel(from: NavPoint, to: NavPoint, run: Bool = false) -> [WorkerStep] {
        guard let L = layout else { return [] }
        return L.path(from: from, to: to).map { step -> WorkerStep in
            switch step {
            case .walk(_, let x): return .walk(x, run: run)
            case .climb(let x, _, let to): return .climb(x: x, to: to)
            }
        }
    }

    func here(_ w: Worker) -> NavPoint { NavPoint(surface: w.surface, x: w.pos.x) }

    /// Surfaces a worker can actually reach given what has been built.
    func reachableSurfaces() -> [Surface] {
        guard let L = layout else { return [] }
        var result = [L.deck]
        for t in L.towers {
            for level in 1...t.levels {
                let s = t.side.rawValue
                if built.contains(ElementKey(kind: .tower, side: s, index: level)),
                   built.contains(ElementKey(kind: .ladder, side: s, index: level)),
                   let surf = L.surface(t.surfaceID(level: level)) {
                    result.append(surf)
                } else {
                    break
                }
            }
        }
        return result
    }

    func randomSpot(on s: Surface) -> NavPoint {
        NavPoint(surface: s.id, x: rng.cg(s.minX, s.maxX).rounded())
    }

    func stagingPoint() -> (x: CGFloat, side: CGFloat) {
        guard let L = layout else { return (0, -1) }
        let b = pxBounds
        let leftGap = CGFloat(L.deckL - b.minX)
        let rightGap = CGFloat(b.maxX - L.deckR)
        if leftGap <= rightGap {
            return (CGFloat(L.deckL) - min(26, max(0, leftGap - 6)), -1)
        }
        return (CGFloat(L.deckR) + min(26, max(0, rightGap - 6)), 1)
    }

    func desiredCrewSize() -> Int {
        guard let L = layout else { return 0 }
        var n = settings.crewSize
        if L.deckR - L.deckL < 90 { n = min(n, 2) }
        if L.deckR - L.deckL < 50 { n = min(n, 1) }
        return n
    }

    var crew: [Worker] { workers.filter { !$0.isSupervisor && !$0.isLeaving } }

    // MARK: Construction

    func beginConstruction(animated: Bool) {
        stageMarks.removeAll()
        let target = desiredCrewSize()
        while crew.count < target { _ = spawnWorker() }
        guard let L = layout else {
            phase = .active
            return
        }
        if !animated {
            buildAllInstantly()
            for p in [sign, stack, toolbox] { p?.appear(animated: false) }
            for c in cones { c.appear(animated: false) }
            let spots = reachableSurfaces()
            for w in workers {
                let s = rng.pick(spots) ?? L.deck
                let p = randomSpot(on: s)
                w.place(surface: s.id, x: p.x, y: s.y)
                w.node.alpha = 1
                w.nextDecisionIn = rng.range(0.2, 2.5)
            }
            phase = .active
            phaseTime = 0
            completedOnce = true
            return
        }

        phase = .constructing
        phaseTime = 0
        constructionTarget = rng.range(4.0, 5.2)
        let staging = stagingPoint()
        for (i, w) in workers.enumerated() {
            let startX = staging.x + staging.side * CGFloat(i) * 3
            w.place(surface: Surface.deckID, x: startX, y: 0)
            w.facing = staging.side > 0 ? -1 : 1
            w.node.alpha = 0
            let start = NavPoint(surface: Surface.deckID, x: startX)
            let item: CarryItem
            let dest: CGFloat
            var deliver: (() -> Void)?
            switch i {
            case 0:
                item = .sign
                dest = CGFloat(L.signX) + 4
                deliver = { [weak self] in
                    guard let self else { return }
                    self.sign.appear(animated: true)
                    self.particles.emit(.dust, at: self.sign.base, count: 3, rng: &self.rng)
                }
            case 1:
                item = .plank
                dest = CGFloat(L.stackX) + 7
                deliver = { [weak self] in
                    guard let self else { return }
                    self.stack.appear(animated: true)
                    self.particles.emit(.dust, at: self.stack.base, count: 3, rng: &self.rng)
                }
            case 2:
                item = .toolbox
                dest = CGFloat(L.toolboxX) - 4
                deliver = { [weak self] in
                    guard let self else { return }
                    self.toolbox.appear(animated: true)
                }
            default:
                item = rng.chance(0.5) ? .plank : .bricks
                dest = rng.cg(L.deck.minX, L.deck.maxX)
            }
            var steps: [WorkerStep] = [.wait(Double(i) * 0.22 + rng.range(0, 0.08)), .carry(item), .fade(to: 1, 0.2)]
            steps += travel(from: start, to: NavPoint(surface: Surface.deckID, x: dest), run: true)
            steps += [.anim(.crouch, 0.3), .carry(nil)]
            if let deliver { steps.append(.call(deliver)) }
            if i >= 3, !stack.present {
                steps.append(.call { [weak self] in self?.stack.appear(animated: true) })
            }
            w.setSteps(steps)
        }
    }

    private func constructionUpdate() {
        guard let L = layout else { phase = .active; return }
        if phaseTime > 1.4, !stageMarks.contains(Mark.conesShown.rawValue) {
            stageMarks.insert(Mark.conesShown.rawValue)
            for c in cones where !c.present { c.appear(animated: true) }
            if !sign.present { sign.appear(animated: true) }
            if !stack.present { stack.appear(animated: true) }
        }
        for w in workers where w.isIdle && !w.inEvent && !w.isLeaving && !w.isSupervisor {
            assignConstructionWork(w, layout: L)
        }
        // Safety net: never let construction drag on.
        if phaseTime > constructionTarget + 2.0 {
            let pending = L.elements.filter { !built.contains($0.key) }.sorted { $0.order < $1.order }
            if let next = pending.first {
                build(next.key)
            }
        }
        if isFullyBuilt { finishConstruction() }
    }

    private func assignConstructionWork(_ w: Worker, layout L: ScaffoldLayout) {
        let candidates = L.elements.filter { spec in
            !built.contains(spec.key) && !assigned.contains(spec.key) && spec.requires.allSatisfy { built.contains($0) }
        }
        guard !candidates.isEmpty else {
            w.setSteps([.wait(rng.range(0.15, 0.35))])
            return
        }
        let me = here(w)
        func cost(_ p: NavPoint) -> CGFloat {
            let la = L.surface(me.surface)?.level ?? 0
            let lb = L.surface(p.surface)?.level ?? 0
            return abs(p.x - me.x) + CGFloat(abs(la - lb)) * 24
        }
        let pool = Array(candidates.sorted { $0.order < $1.order }.prefix(3))
        guard let spec = pool.min(by: { cost($0.work) < cost($1.work) }) else { return }

        var keys = [spec]
        if spec.key.kind == .bay {
            let groupSize = max(1, min(4, Int((Double(L.bays.count) / Double(max(1, crew.count) * 2)).rounded(.up))))
            let dir = spec.work.x >= me.x ? 1 : -1
            var idx = spec.key.index
            while keys.count < groupSize {
                idx += dir
                let key = ElementKey(kind: .bay, side: 0, index: idx)
                guard idx >= 0, idx < L.bays.count, !built.contains(key), !assigned.contains(key), let s = L.spec(key) else { break }
                keys.append(s)
            }
        }

        let remaining = max(1, L.elements.count - built.count)
        let timeLeft = max(1.0, constructionTarget - phaseTime)
        let perWorker = (Double(remaining) / Double(max(1, crew.count))).rounded(.up)
        let hammerTime = min(0.65, max(0.18, timeLeft / max(1, perWorker) * 0.5))

        var steps: [WorkerStep] = []
        var cur = me
        for s in keys {
            assigned.insert(s.key)
            let jitter = s.key.kind == .bay ? rng.cg(-2, 2) : 0
            let target = NavPoint(surface: s.work.surface, x: s.work.x + jitter)
            steps += travel(from: cur, to: target)
            cur = target
            let center = elementNodes[s.key]?.center.x ?? target.x
            steps.append(.face(center >= target.x ? 1 : -1))
            steps.append(.anim(.hammer, hammerTime * (s.key.kind == .bay && keys.count > 1 ? 0.7 : 1)))
            let key = s.key
            steps.append(.call { [weak self] in self?.build(key) })
        }
        w.assignment = spec.key
        w.setSteps(steps)
    }

    private func finishConstruction() {
        phase = .active
        phaseTime = 0
        for c in cones where !c.present { c.appear(animated: true) }
        for p in [sign, stack, toolbox] where !(p?.present ?? true) { p?.appear(animated: true) }
        for w in workers { w.nextDecisionIn = rng.range(0.2, 1.4) }
        if !completedOnce {
            completedOnce = true
            if settings.specialEvents {
                let roll = rng.unit()
                let live = settings.intensity.liveliness
                if roll < 0.45 * live {
                    startCelebration()
                } else if roll < 0.8 * live, layout?.towers.isEmpty == false {
                    _ = startFlagEvent()
                }
            }
        }
    }

    // MARK: Active phase

    private func activeUpdate(dt: TimeInterval) {
        guard let L = layout else { return }
        crewCheckTimer -= dt
        if crewCheckTimer <= 0 {
            crewCheckTimer = 1.5
            if crew.count != desiredCrewSize() { adjustCrew() }
        }
        // Elements added by a resize or density change get built by the crew.
        let pending = L.elements.filter { spec in
            !built.contains(spec.key) && !assigned.contains(spec.key) && spec.requires.allSatisfy { built.contains($0) }
        }
        for w in workers where w.isIdle && !w.inEvent && !w.isLeaving && !w.isSupervisor {
            if let spec = pending.first(where: { !assigned.contains($0.key) }) {
                assignRepairBuild(w, spec: spec, layout: L)
                continue
            }
            w.nextDecisionIn -= dt
            if w.nextDecisionIn <= 0 {
                planIdle(w, layout: L)
            }
        }
        // Elements whose prerequisites can't be met (e.g. rebuilt partially) — build them.
        if pending.isEmpty, !isFullyBuilt, phaseTime > 8 {
            if let stuck = L.elements.first(where: { !built.contains($0.key) && !assigned.contains($0.key) }) {
                build(stuck.key)
            }
        }
    }

    private func assignRepairBuild(_ w: Worker, spec: ElementSpec, layout L: ScaffoldLayout) {
        assigned.insert(spec.key)
        let stackPoint = NavPoint(surface: Surface.deckID, x: L.deck.clamp(CGFloat(L.stackX) + 6))
        var steps = travel(from: here(w), to: stackPoint)
        steps += [.face(-1), .anim(.crouch, 0.3), .carry(.plank)]
        steps += travel(from: stackPoint, to: spec.work)
        steps += [.carry(nil)]
        let center = elementNodes[spec.key]?.center.x ?? spec.work.x
        steps.append(.face(center >= spec.work.x ? 1 : -1))
        steps.append(.anim(.hammer, rng.range(0.6, 1.0)))
        let key = spec.key
        steps.append(.call { [weak self] in self?.build(key) })
        w.assignment = key
        w.setSteps(steps)
    }

    func planIdle(_ w: Worker, layout L: ScaffoldLayout) {
        let p = w.personality
        let reach = reachableSurfaces()
        let raised = reach.filter { $0.id != Surface.deckID }
        let craneReady = L.crane != nil && crane.stage == .idle &&
            built.contains(ElementKey(kind: .crane, side: L.crane!.side.rawValue, index: 0))
        let subtle = settings.intensity == .subtle

        var options: [(Activity, Double)] = [
            (.hammer, 3.0 * (0.6 + p.diligence)),
            (.inspect, 1.1 * (0.5 + p.curiosity)),
            (.carry, stack.present ? 1.4 : 0),
            (.climb, raised.isEmpty ? 0 : 1.3),
            (.rest, (subtle ? 1.6 : 1.0) * (0.4 + p.laziness)),
            (.repair, 1.2 * (0.5 + p.diligence)),
            (.signal, craneReady ? 0.7 : 0),
            (.wander, 0.8),
            (.look, subtle ? 1.4 : 0.8),
        ]
        for i in options.indices {
            if let until = w.cooldowns[options[i].0], siteTime < until { options[i].1 *= 0.15 }
            if options[i].0 == w.lastActivity { options[i].1 *= 0.3 }
        }
        guard let idx = rng.weightedIndex(options.map(\.1)) else { return }
        let activity = options[idx].0
        w.lastActivity = activity
        w.cooldowns[activity] = siteTime + rng.range(8, 16)

        let me = here(w)
        var steps: [WorkerStep] = []
        switch activity {
        case .hammer:
            let s = (rng.chance(0.45) ? rng.pick(raised) : nil) ?? L.deck
            let target = randomSpot(on: s)
            steps = travel(from: me, to: target)
            steps += [.face(rng.sign()), .anim(.hammer, rng.range(1.2, 3.2))]
            if rng.chance(0.3) { steps.append(.wait(rng.range(0.3, 0.8))) }

        case .inspect:
            let s = (rng.chance(0.35) ? rng.pick(raised) : nil) ?? L.deck
            let edge = rng.chance(0.5)
            let x = edge ? (rng.chance(0.5) ? s.minX + 1 : s.maxX - 1) : rng.cg(s.minX, s.maxX)
            let target = NavPoint(surface: s.id, x: x.rounded())
            steps = travel(from: me, to: target)
            let outward = x < (s.minX + s.maxX) / 2 ? -1 : 1
            steps += [.face(outward), .anim(.inspect, rng.range(1.6, 3.2))]
            if rng.chance(0.35) { steps.append(.emote(rng.chance(0.5) ? .question : .sparkle, 1.0)) }
            steps.append(.anim(.lookAround, rng.range(0.8, 1.6)))

        case .carry:
            let pickup = NavPoint(surface: Surface.deckID, x: L.deck.clamp(CGFloat(L.stackX) + (rng.chance(0.5) ? 7 : -7)))
            let drop = NavPoint(surface: Surface.deckID, x: rng.cg(L.deck.minX, L.deck.maxX).rounded())
            steps = travel(from: me, to: pickup)
            steps += [.face(CGFloat(L.stackX) >= pickup.x ? 1 : -1), .anim(.crouch, 0.35), .carry(rng.chance(0.75) ? .plank : .bricks)]
            steps += travel(from: pickup, to: drop)
            steps += [.anim(.crouch, 0.3), .carry(nil)]
            if rng.chance(0.5) { steps += [.face(rng.sign()), .anim(.hammer, rng.range(0.6, 1.4))] }

        case .climb:
            if let s = rng.pick(raised) {
                steps = travel(from: me, to: randomSpot(on: s))
                steps.append(.anim(.lookAround, rng.range(1.0, 2.2)))
                if rng.chance(0.3) { steps.append(.anim(.point, 0.6)) }
            }

        case .rest:
            let s = (rng.chance(0.65) ? rng.pick(raised) : nil) ?? L.deck
            let target = randomSpot(on: s)
            steps = travel(from: me, to: target)
            steps += [.face(rng.sign()), .anim(.sit, rng.range(3, 7))]
            if rng.chance(0.4) { steps.append(.anim(.stretch, 1.0)) }

        case .repair:
            var target = randomSpot(on: L.deck)
            var faceDir = 1
            if let t = L.towers.randomElement(using: &rng), let s = rng.pick(raised.filter { $0.side == t.side }) ?? (rng.chance(0.5) ? L.deck : nil) {
                let leftPole = rng.chance(0.5)
                let x = leftPole ? CGFloat(t.x0 + 1) : CGFloat(t.x1 - 1)
                target = NavPoint(surface: s.id, x: s.clamp(x))
                faceDir = leftPole ? -1 : 1
            } else if let bay = L.bays.randomElement(using: &rng) {
                target = NavPoint(surface: Surface.deckID, x: L.deck.clamp(CGFloat(bay.x0 + 2)))
                faceDir = -1
            }
            steps = travel(from: me, to: target)
            steps += [.face(faceDir), .anim(.wrench, rng.range(1.4, 2.6)), .call { [weak self] in
                if self?.visibleToUser == true { SoundEngine.shared.play(.ratchet) }
            }]

        case .signal:
            if let c = L.crane {
                let x = L.deck.clamp(CGFloat(c.hookX - c.jibDir * 6))
                let target = NavPoint(surface: Surface.deckID, x: x)
                steps = travel(from: me, to: target)
                steps += [.face(CGFloat(c.hookX) >= x ? 1 : -1),
                          .call { [weak self] in _ = self?.startCraneLift() },
                          .anim(.signal, 2.6),
                          .anim(.point, 0.6)]
            }

        case .wander:
            let s = L.surface(w.surface) ?? L.deck
            steps = travel(from: me, to: randomSpot(on: s))
            steps.append(.wait(rng.range(0.5, 1.5)))

        case .look:
            steps = [.anim(.lookAround, rng.range(1.2, 2.2))]
        }

        if steps.isEmpty { steps = [.wait(rng.range(0.5, 1.2))] }
        w.setSteps(steps)
        let pace: Double = settings.intensity == .subtle ? 1.6 : (settings.intensity == .playful ? 0.7 : 1.0)
        w.nextDecisionIn = rng.range(0.3, 2.0) * pace
    }

    func adjustCrew() {
        guard let L = layout else { return }
        let target = desiredCrewSize()
        let current = crew
        if current.count < target {
            let staging = stagingPoint()
            for _ in 0..<(target - current.count) {
                let w = spawnWorker()
                w.place(surface: Surface.deckID, x: staging.x, y: 0)
                w.node.alpha = 0
                let dest = NavPoint(surface: Surface.deckID, x: rng.cg(L.deck.minX, L.deck.maxX).rounded())
                var steps: [WorkerStep] = [.carry(.toolbox), .fade(to: 1, 0.2)]
                steps += travel(from: NavPoint(surface: Surface.deckID, x: staging.x), to: dest)
                steps += [.anim(.crouch, 0.3), .carry(nil)]
                w.setSteps(steps)
            }
        } else if current.count > target {
            for w in current.suffix(current.count - target) {
                sendHome(w)
            }
        }
    }

    func sendHome(_ w: Worker) {
        guard layout != nil else { removeWorker(w); return }
        w.isLeaving = true
        w.inEvent = false
        w.cancelReaction()
        let staging = stagingPoint()
        var steps = travel(from: here(w), to: NavPoint(surface: Surface.deckID, x: staging.x), run: true)
        steps.append(.walk(staging.x + staging.side * 4, run: true))
        steps += [.fade(to: 0, 0.25), .call { [weak self, weak w] in
            guard let self, let w else { return }
            self.removeWorker(w)
        }]
        w.setSteps(steps)
    }

    // MARK: Teardown (window closed)

    func beginTeardown() {
        endEvent()
        stageMarks.removeAll()
        phase = .tearingDown
        phaseTime = 0
        let keys = built.sorted { (layout?.spec($0)?.order ?? 0) > (layout?.spec($1)?.order ?? 0) }
        let span = 1.45
        let interval = keys.isEmpty ? 0 : span / Double(keys.count)
        teardownSchedule = keys.enumerated().map { ($0.element, 0.35 + Double($0.offset) * interval) }
        teardownExitAt = 0.35 + span + 0.15
        guard let L = layout else { return }
        for w in workers {
            w.clearSteps()
            w.cancelReaction()
            w.inEvent = false
            w.speedOverride = nil
            w.setCarrying(nil)
            var steps: [WorkerStep] = []
            if rng.chance(0.5) { steps.append(.emote(.exclaim, 0.6)) }
            if w.node.alpha < 0.5 { steps.append(.fade(to: 1, 0.1)) }
            if w.surface != Surface.deckID {
                let x = L.deck.clamp(w.pos.x)
                steps += travel(from: here(w), to: NavPoint(surface: Surface.deckID, x: x), run: true)
            }
            steps.append(.anim(rng.chance(0.5) ? .wrench : .hammer, rng.range(0.4, 0.9)))
            steps.append(.waitUntil({ [weak self] in (self?.phaseTime ?? 99) >= (self?.teardownExitAt ?? 0) }, timeout: 3))
            w.setSteps(steps)
        }
    }

    private func teardownUpdate() {
        guard let L = layout else {
            if phaseTime > 0.6 { phase = .finished }
            return
        }
        while let first = teardownSchedule.first, phaseTime >= first.1 {
            teardownSchedule.removeFirst()
            removeElementDuringTeardown(first.0, layout: L)
        }
        if phaseTime >= teardownExitAt - 0.35, !stageMarks.contains(Mark.propsPacked.rawValue) {
            stageMarks.insert(Mark.propsPacked.rawValue)
            for p in allProps where p.present {
                particles.emit(.dust, at: p.base, count: 2, rng: &rng)
                p.disappear(animated: true)
            }
            longPlankNode?.isHidden = true
        }
        if phaseTime >= teardownExitAt, !stageMarks.contains(Mark.exitIssued.rawValue) {
            stageMarks.insert(Mark.exitIssued.rawValue)
            let staging = stagingPoint()
            for (i, w) in workers.enumerated() {
                w.clearSteps()
                w.cancelReaction()
                let item: CarryItem? = i == 0 ? .toolbox : (i == 1 ? .sign : (rng.chance(0.6) ? .plank : nil))
                var steps: [WorkerStep] = [.carry(item), .wait(Double(i) * 0.08)]
                if w.surface != Surface.deckID {
                    w.place(surface: Surface.deckID, x: L.deck.clamp(w.pos.x), y: 0)
                }
                steps.append(.walk(staging.x + staging.side * CGFloat(i * 3 + 4), run: true))
                steps.append(.fade(to: 0, 0.25))
                w.setSteps(steps)
            }
        }
        let allGone = stageMarks.contains(Mark.exitIssued.rawValue) && workers.allSatisfy { $0.node.alpha <= 0.01 || $0.isIdle && $0.node.alpha < 0.05 }
        if (allGone && phaseTime > teardownExitAt + 0.3) || phaseTime > teardownExitAt + 1.8 {
            phase = .finished
        }
    }

    private func removeElementDuringTeardown(_ key: ElementKey, layout L: ScaffoldLayout) {
        guard let node = elementNodes[key], node.buildState == .built else { return }
        built.remove(key)
        let kind: ParticleKind = rng.chance(0.5) ? .chip : .dust
        particles.emit(kind, at: node.center, count: 2, rng: &rng)
        node.animateRemoval(duration: 0.18)
        if visibleToUser, rng.chance(0.4) { SoundEngine.shared.play(.clunk) }
        // Anyone standing on a platform that just vanished hops down a level.
        if key.kind == .tower, let side = TowerSide(rawValue: key.side), let t = L.tower(side) {
            for w in workers where w.surface != Surface.deckID && w.surface / 100 == side.rawValue && (w.surface % 100) >= key.index {
                let target = L.surface(t.surfaceID(level: key.index - 1)) ?? L.deck
                w.clearSteps()
                w.setSteps([.hop(to: target.id, x: target.clamp(w.pos.x)),
                            .waitUntil({ [weak self] in (self?.phaseTime ?? 99) >= (self?.teardownExitAt ?? 0) }, timeout: 3)])
            }
        }
    }

    // MARK: Pack / rebuild (minimize, hide, Space switch)

    func beginPack(animated: Bool) {
        endEvent()
        stageMarks.removeAll()
        if !animated || layout == nil {
            finishPack()
            return
        }
        phase = .packing
        phaseTime = 0
        let keys = built.sorted { (layout?.spec($0)?.order ?? 0) > (layout?.spec($1)?.order ?? 0) }
        let interval = keys.isEmpty ? 0 : 0.42 / Double(keys.count)
        packSchedule = keys.enumerated().map { ($0.element, 0.05 + Double($0.offset) * interval) }
        for (i, w) in workers.enumerated() {
            w.clearSteps()
            w.cancelReaction()
            w.inEvent = false
            w.setSteps([.anim(.crouch, 0.25 + Double(i) * 0.06),
                        .call { [weak self, weak w] in
                            guard let self, let w else { return }
                            self.particles.emit(.puff, at: CGPoint(x: w.pos.x, y: w.pos.y + 4), count: 4, rng: &self.rng)
                        },
                        .fade(to: 0, 0.12)])
        }
    }

    private func packUpdate() {
        while let first = packSchedule.first, phaseTime >= first.1 {
            packSchedule.removeFirst()
            if let node = elementNodes[first.0], node.buildState == .built {
                built.remove(first.0)
                node.animateRemoval(duration: 0.12)
                particles.emit(.puff, at: node.center, count: 1, rng: &rng)
            }
        }
        if phaseTime > 0.3, !stageMarks.contains(Mark.propsPacked.rawValue) {
            stageMarks.insert(Mark.propsPacked.rawValue)
            for p in allProps where p.present { p.disappear(animated: true) }
        }
        if phaseTime > 0.95 { finishPack() }
    }

    private func finishPack() {
        phase = .packed
        phaseTime = 0
        packSchedule.removeAll()
        for (_, node) in elementNodes { node.setUnbuilt() }
        built.removeAll()
        assigned.removeAll()
        for p in allProps { p.disappear(animated: false) }
        for w in workers {
            w.clearSteps()
            w.cancelReaction()
            w.node.alpha = 0
        }
        particles.clear()
        root.isHidden = true
        crane = LiftState()
        pulley = LiftState()
    }

    func beginRebuild(animated: Bool) {
        stageMarks.removeAll()
        layout = computeLayout(locked: nil)
        root.isHidden = layout == nil
        syncElements(animateRemovals: false)
        placeProps()
        guard let L = layout else { phase = .active; return }
        let target = desiredCrewSize()
        while crew.count < target { _ = spawnWorker() }
        while crew.count > target, let extra = crew.last { removeWorker(extra) }

        let spots = [L.deck]
        if !animated {
            buildAllInstantly()
            for p in [sign, stack, toolbox] { p?.appear(animated: false) }
            for c in cones { c.appear(animated: false) }
            for w in workers {
                let p = randomSpot(on: L.deck)
                w.place(surface: Surface.deckID, x: p.x, y: 0)
                w.node.alpha = 1
                w.nextDecisionIn = rng.range(0.3, 2)
            }
            phase = .active
            phaseTime = 0
            return
        }
        phase = .rebuilding
        phaseTime = 0
        let keys = L.elements.sorted { $0.order < $1.order }.map(\.key)
        let interval = keys.isEmpty ? 0 : 1.0 / Double(keys.count)
        rebuildSchedule = keys.enumerated().map { ($0.element, 0.2 + Double($0.offset) * interval) }
        for (i, w) in workers.enumerated() {
            let s = rng.pick(spots) ?? L.deck
            let p = randomSpot(on: s)
            w.place(surface: s.id, x: p.x, y: s.y)
            w.node.alpha = 0
            w.setSteps([.wait(Double(i) * 0.07),
                        .call { [weak self, weak w] in
                            guard let self, let w else { return }
                            self.particles.emit(.puff, at: CGPoint(x: w.pos.x, y: w.pos.y + 4), count: 3, rng: &self.rng)
                        },
                        .fade(to: 1, 0.15),
                        .face(rng.sign()),
                        .anim(.hammer, rng.range(0.6, 1.0))])
        }
    }

    private func rebuildUpdate() {
        while let first = rebuildSchedule.first, phaseTime >= first.1 {
            rebuildSchedule.removeFirst()
            build(first.0)
        }
        if phaseTime > 0.25, !stageMarks.contains(Mark.propsPacked.rawValue) {
            stageMarks.insert(Mark.propsPacked.rawValue)
            for p in [sign, stack, toolbox] { p?.appear(animated: true) }
            for c in cones { c.appear(animated: true) }
        }
        if rebuildSchedule.isEmpty, phaseTime > 1.3 {
            phase = .active
            phaseTime = 0
            for w in workers { w.nextDecisionIn = rng.range(0.2, 1.5) }
        }
    }

    // MARK: Per-frame dispatch

    func directorUpdate(dt: TimeInterval) {
        switch phase {
        case .constructing: constructionUpdate()
        case .active: activeUpdate(dt: dt)
        case .tearingDown: teardownUpdate()
        case .packing: packUpdate()
        case .rebuilding: rebuildUpdate()
        case .packed, .finished: break
        }
    }

    // MARK: Motion reactions

    func updateMotionReactions(dt: TimeInterval) {
        let speed = motion.speed
        if speed > 45 {
            if !isMoving {
                isMoving = true
                moveDidBegin()
            }
            moveQuiet = 0
            peakSpeed = max(peakSpeed, speed)
            let fastThreshold: CGFloat = 1250 / CGFloat(settings.intensity.liveliness).squareRoot()
            if speed > fastThreshold, siteTime - lastFastReaction > 2.5, phase == .active, !suspended {
                lastFastReaction = siteTime
                fastMoveReaction()
            }
        } else if isMoving {
            moveQuiet += dt
            if moveQuiet > 0.28 {
                isMoving = false
                moveDidEnd()
            }
        }
    }

    private var reactivePhase: Bool {
        phase == .active || phase == .constructing || phase == .rebuilding
    }

    private func moveDidBegin() {
        guard reactivePhase, !settings.paused else { return }
        for w in workers where !w.isLeaving && w.node.alpha > 0.5 && w.reaction == nil {
            switch w.anim {
            case .climb: w.react(.climb, duration: 0, hold: true)
            case .sit, .sleep: w.react(w.anim, duration: 0, hold: true)
            default: w.react(.brace, duration: 0, hold: true)
            }
        }
    }

    private func moveDidEnd() {
        for w in workers { w.releaseReaction() }
        guard reactivePhase, let L = layout else { peakSpeed = 0; return }
        if peakSpeed > 450, visibleToUser {
            particles.emit(.dust, at: CGPoint(x: L.deck.minX, y: 0), count: 2, rng: &rng)
            particles.emit(.dust, at: CGPoint(x: L.deck.maxX, y: 0), count: 2, rng: &rng)
            for w in workers where !w.isLeaving && rng.chance(0.25 * settings.intensity.liveliness) {
                w.showEmote(rng.chance(0.6) ? .sweat : .exclaim, duration: 0.9)
            }
        }
        peakSpeed = 0
    }

    private func fastMoveReaction() {
        let towerFolks = workers.filter { $0.surface != Surface.deckID && !$0.isClimbing && !$0.isLeaving && !$0.inEvent }
        if let w = rng.pick(towerFolks) {
            w.react(.hang, duration: 0, hold: true)
            w.showEmote(.exclaim, duration: 1.0)
        } else if let w = rng.pick(workers.filter { !$0.isLeaving && !$0.inEvent }) {
            w.react(.stumble, duration: 0.55)
            w.showEmote(.exclaim, duration: 0.8)
        }
    }

    // MARK: Resize reactions

    func resizeBeganReaction() {
        guard !settings.paused else { return }
        let candidates = workers.filter { !$0.isLeaving && !$0.inEvent && $0.node.alpha > 0.5 }
        guard !candidates.isEmpty else { return }
        // One worker nearly loses their balance; the rest steady themselves.
        func wobbleScore(_ w: Worker) -> CGFloat {
            let raisedBonus: CGFloat = w.surface != Surface.deckID ? 1000 : 0
            return raisedBonus + w.pos.x
        }
        let wobbler = candidates.max { wobbleScore($0) < wobbleScore($1) }
        for w in candidates {
            if w === wobbler, settings.specialEvents {
                w.react(.stumble, duration: 0.7)
                w.showEmote(.exclaim, duration: 0.9)
            } else if w.reaction == nil, w.anim != .climb {
                w.react(.brace, duration: 0, hold: true)
            }
        }
    }

    func resizeSettledReaction(oldLayout: ScaffoldLayout?) {
        for w in workers { w.releaseReaction() }
        guard phase == .active, let new = layout else { return }
        let lostElements = (oldLayout?.elements.count ?? 0) > new.elements.count
        if lostElements, let w = rng.pick(crew) {
            w.clearSteps()
            w.setSteps([.anim(.scratch, 0.8), .emote(.question, 0.9), .anim(.lookAround, 1.0)])
        }
        if let w = rng.pick(crew.filter { $0.isIdle }), !lostElements, rng.chance(0.5) {
            w.setSteps([.anim(.inspect, 1.4), .emote(.sparkle, 0.8)])
        }
    }
}
