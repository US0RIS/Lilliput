import Foundation
import SpriteKit

enum ParticleKind {
    case dust
    case spark
    case chip
    case puff
}

/// A fixed pool of single-pixel sprites per site. Nothing is allocated while running.
@MainActor
final class ParticleSystem {
    private struct Particle {
        var position: CGPoint = .zero
        var velocity: CGVector = .zero
        var life: CGFloat = 0
        var maxLife: CGFloat = 1
        var gravity: CGFloat = 0
        var drag: CGFloat = 0
        var active = false
    }

    private var particles: [Particle]
    private var nodes: [SKSpriteNode]
    private var cursor = 0
    private(set) var activeCount = 0
    var amplitude: CGFloat = 1

    init(parent: SKNode, capacity: Int = 36) {
        particles = Array(repeating: Particle(), count: capacity)
        nodes = []
        nodes.reserveCapacity(capacity)
        for _ in 0..<capacity {
            let n = SKSpriteNode(color: Pal.dust.nsColor, size: CGSize(width: 1, height: 1))
            n.anchorPoint = .zero
            n.isHidden = true
            n.zPosition = 40
            parent.addChild(n)
            nodes.append(n)
        }
    }

    func emit(_ kind: ParticleKind, at p: CGPoint, count: Int, rng: inout SplitMix64) {
        let n = max(0, Int((CGFloat(count) * amplitude).rounded()))
        guard n > 0 else { return }
        for _ in 0..<n {
            let i = cursor
            cursor = (cursor + 1) % particles.count
            var part = Particle()
            part.active = true
            part.position = p
            switch kind {
            case .dust:
                part.velocity = CGVector(dx: rng.cg(-10, 10), dy: rng.cg(2, 12))
                part.gravity = -14
                part.drag = 2.2
                part.maxLife = rng.cg(0.5, 0.9)
                nodes[i].color = rng.chance(0.5) ? Pal.dust.nsColor : Pal.dustDark.nsColor
            case .puff:
                part.velocity = CGVector(dx: rng.cg(-16, 16), dy: rng.cg(4, 18))
                part.gravity = -6
                part.drag = 3.0
                part.maxLife = rng.cg(0.4, 0.75)
                nodes[i].color = rng.chance(0.6) ? Pal.offWhite.nsColor : Pal.dust.nsColor
            case .spark:
                part.velocity = CGVector(dx: rng.cg(-22, 22), dy: rng.cg(10, 30))
                part.gravity = -90
                part.drag = 0.5
                part.maxLife = rng.cg(0.18, 0.32)
                nodes[i].color = rng.chance(0.5) ? Pal.spark.nsColor : Pal.sparkHot.nsColor
            case .chip:
                part.velocity = CGVector(dx: rng.cg(-14, 14), dy: rng.cg(8, 22))
                part.gravity = -110
                part.drag = 0.4
                part.maxLife = rng.cg(0.35, 0.6)
                nodes[i].color = Pal.chip.nsColor
            }
            part.life = part.maxLife
            if !particles[i].active { activeCount += 1 }
            particles[i] = part
            nodes[i].isHidden = false
            nodes[i].alpha = 1
            nodes[i].position = CGPoint(x: p.x.rounded(), y: p.y.rounded())
        }
    }

    func update(dt: CGFloat) {
        guard activeCount > 0, dt > 0 else { return }
        for i in particles.indices where particles[i].active {
            var part = particles[i]
            part.life -= dt
            if part.life <= 0 {
                part.active = false
                particles[i] = part
                nodes[i].isHidden = true
                activeCount -= 1
                continue
            }
            part.velocity.dy += part.gravity * dt
            let d = max(0, 1 - part.drag * dt)
            part.velocity.dx *= d
            part.velocity.dy *= d
            part.position.x += part.velocity.dx * dt
            part.position.y += part.velocity.dy * dt
            particles[i] = part
            nodes[i].position = CGPoint(x: part.position.x.rounded(), y: part.position.y.rounded())
            nodes[i].alpha = min(1, part.life / (part.maxLife * 0.5))
        }
    }

    func clear() {
        for i in particles.indices {
            particles[i].active = false
            nodes[i].isHidden = true
        }
        activeCount = 0
    }
}
