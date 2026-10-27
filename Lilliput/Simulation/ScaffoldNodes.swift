import Foundation
import SpriteKit

/// Renders one scaffold element (a deck bay, a tower section, a ladder, the crane…)
/// out of crisp 1-px colour sprites and pixel textures. Child sprites are created once
/// and re-positioned when the layout changes, so live resizing allocates nothing.
@MainActor
final class ScaffoldElementNode: SKNode {
    enum BuildState {
        case unbuilt
        case built
        case removing
    }

    let key: ElementKey
    private(set) var buildState: BuildState = .unbuilt
    private var parts: [SKSpriteNode] = []
    /// Approximate centre in site pixels, used for occlusion tests.
    private(set) var center: CGPoint = .zero
    private var pivot: CGPoint = .zero

    // Rig parts (crane / pulley) the site animates every frame.
    private var rigRope: SKSpriteNode?
    private var rigHook: SKSpriteNode?
    private var rigLoad: SKSpriteNode?
    private var rigAnchor: CGPoint = .zero

    init(key: ElementKey) {
        self.key = key
        super.init()
        alpha = 0
        switch key.kind {
        case .bay, .endPost: zPosition = 2
        case .tower: zPosition = 3
        case .ladder: zPosition = 4
        case .pulley: zPosition = 5
        case .crane: zPosition = 6
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Build state

    func setBuiltInstantly() {
        removeAllActions()
        buildState = .built
        alpha = 1
        yScale = 1
        xScale = 1
    }

    func animateBuild() {
        removeAllActions()
        buildState = .built
        alpha = 0
        yScale = 0.25
        let grow = SKAction.sequence([
            SKAction.scaleY(to: 1.12, duration: 0.12),
            SKAction.scaleY(to: 1.0, duration: 0.08),
        ])
        grow.timingMode = .easeOut
        run(SKAction.group([SKAction.fadeIn(withDuration: 0.1), grow]))
    }

    func animateRemoval(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        removeAllActions()
        buildState = .removing
        let shrink = SKAction.group([
            SKAction.fadeOut(withDuration: duration),
            SKAction.scaleY(to: 0.2, duration: duration),
        ])
        if let completion {
            run(SKAction.sequence([shrink, SKAction.run(completion)]))
        } else {
            run(shrink)
        }
    }

    func setUnbuilt() {
        removeAllActions()
        buildState = .unbuilt
        alpha = 0
        yScale = 1
    }

    // MARK: Geometry

    private func part(_ i: Int) -> SKSpriteNode {
        while parts.count <= i {
            let p = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            p.anchorPoint = .zero
            addChild(p)
            parts.append(p)
        }
        let p = parts[i]
        p.isHidden = false
        return p
    }

    private func rect(_ i: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: RGBA) {
        let p = part(i)
        guard w > 0, h > 0 else { p.isHidden = true; return }
        p.texture = nil
        p.color = color.nsColor
        p.colorBlendFactor = 1
        p.anchorPoint = .zero
        p.zRotation = 0
        p.size = CGSize(width: w, height: h)
        p.position = CGPoint(x: CGFloat(x) - pivot.x, y: CGFloat(y) - pivot.y)
    }

    private func line(_ i: Int, _ from: CGPoint, _ to: CGPoint, _ color: RGBA) {
        let p = part(i)
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len >= 1 else { p.isHidden = true; return }
        p.texture = nil
        p.color = color.nsColor
        p.colorBlendFactor = 1
        p.anchorPoint = CGPoint(x: 0, y: 0.5)
        p.size = CGSize(width: len, height: 1)
        p.zRotation = atan2(dy, dx)
        p.position = CGPoint(x: from.x - pivot.x, y: from.y - pivot.y)
    }

    private func textured(_ i: Int, _ tex: SKTexture, _ x: Int, _ y: Int, z: CGFloat = 0) {
        let p = part(i)
        p.texture = tex
        p.colorBlendFactor = 0
        p.color = .white
        p.anchorPoint = .zero
        p.zRotation = 0
        p.size = tex.size()
        p.zPosition = z
        p.position = CGPoint(x: CGFloat(x) - pivot.x, y: CGFloat(y) - pivot.y)
    }

    private func hide(from i: Int) {
        if i < parts.count {
            for j in i..<parts.count { parts[j].isHidden = true }
        }
    }

    func configure(layout L: ScaffoldLayout) {
        let cache = TextureCache.shared
        let td = L.trussDepth
        let railH = ScaffoldGenerator.railHeight

        switch key.kind {
        case .bay:
            guard key.index < L.bays.count else { return }
            let b = L.bays[key.index]
            pivot = CGPoint(x: b.x0, y: -2)
            position = pivot
            textured(0, cache.plank(width: b.width), b.x0, -2, z: 1)
            rect(1, b.x0, -2 - td, 1, td, Pal.steel)
            rect(2, b.x0, -2 - td, b.width, td >= 2 ? 1 : 0, Pal.steelDark)
            if td >= 3 {
                line(3, CGPoint(x: b.x0, y: -2 - td), CGPoint(x: b.x1, y: -2), Pal.steel)
                if b.width >= 20 {
                    line(4, CGPoint(x: b.x0, y: -2), CGPoint(x: b.x1, y: -2 - td), Pal.steelDark)
                } else {
                    part(4).isHidden = true
                }
            } else {
                part(3).isHidden = true
                part(4).isHidden = true
            }
            if L.hasRail {
                rect(5, b.x0, 0, 1, railH, Pal.steelDark)
                rect(6, b.x0, railH, b.width, 1, Pal.steel)
            } else {
                part(5).isHidden = true
                part(6).isHidden = true
            }
            rect(7, b.x0, -2 - td, td > 0 ? 1 : 0, td > 0 ? 1 : 0, Pal.coupler)
            hide(from: 8)
            center = CGPoint(x: CGFloat(b.center), y: -2)

        case .endPost:
            let x = L.deckR - 1
            pivot = CGPoint(x: x, y: -2)
            position = pivot
            rect(0, x, -2 - td, 1, td, Pal.steel)
            rect(1, x, 0, L.hasRail ? 1 : 0, railH + 1, Pal.steelDark)
            hide(from: 2)
            center = CGPoint(x: CGFloat(x), y: 0)

        case .tower:
            guard let side = TowerSide(rawValue: key.side), let t = L.tower(side), key.index <= t.levels else { return }
            let level = key.index
            let lh = ScaffoldGenerator.levelHeight
            let y0 = level == 1 ? -2 - td : lh * (level - 1)
            let y1 = lh * level
            let isTop = level == t.levels
            pivot = CGPoint(x: t.x0, y: y0)
            position = pivot
            let poleTop = y1 + (isTop ? railH : 0)
            rect(0, t.x0, y0, 1, poleTop - y0, Pal.steel)
            rect(1, t.x1, y0, 1, poleTop - y0, Pal.steelDark)
            textured(2, cache.plank(width: ScaffoldGenerator.towerWidth + 2), t.x0 - 1, y1 - 2, z: 1)
            let by0 = max(y0, lh * (level - 1)) + (level == 1 ? 0 : 0)
            let by1 = y1 - 2
            line(3, CGPoint(x: t.x0, y: by0), CGPoint(x: t.x1, y: by1), Pal.steel)
            line(4, CGPoint(x: t.x0, y: by1), CGPoint(x: t.x1, y: by0), Pal.steelDark)
            if isTop {
                rect(5, t.x0, y1 + railH - 1, ScaffoldGenerator.towerWidth, 1, Pal.steel)
                rect(6, t.x0, y1 + 3, ScaffoldGenerator.towerWidth, 1, Pal.steelDark)
            } else {
                part(5).isHidden = true
                part(6).isHidden = true
            }
            if level == 1 {
                rect(7, t.x0 - 1, y0 - 1, 3, 1, Pal.coupler)
                rect(8, t.x1 - 1, y0 - 1, 3, 1, Pal.coupler)
            } else {
                part(7).isHidden = true
                part(8).isHidden = true
            }
            rect(9, t.x0, y1 - 2, 1, 1, Pal.coupler)
            rect(10, t.x1, y1 - 2, 1, 1, Pal.coupler)
            hide(from: 11)
            center = CGPoint(x: CGFloat(t.centerX), y: CGFloat(y0 + y1) / 2)

        case .ladder:
            guard let side = TowerSide(rawValue: key.side), let t = L.tower(side), key.index <= t.levels else { return }
            let lh = ScaffoldGenerator.levelHeight
            let y0 = lh * (key.index - 1)
            pivot = CGPoint(x: t.ladderX - 2, y: y0)
            position = pivot
            textured(0, cache.ladder(height: lh + 3), t.ladderX - 2, y0)
            hide(from: 1)
            center = CGPoint(x: CGFloat(t.ladderX), y: CGFloat(y0 + lh / 2))

        case .crane:
            guard let c = L.crane else { return }
            pivot = CGPoint(x: c.mastX - 1, y: c.baseY)
            position = pivot
            textured(0, cache.mast(height: c.mastHeight), c.mastX - 1, c.baseY)
            let jibX = c.jibDir < 0 ? c.mastX - c.jibLength + 1 : c.mastX
            textured(1, cache.jib(width: c.jibLength), jibX, c.jibY)
            let counterX = c.jibDir < 0 ? c.mastX + 1 : c.mastX - c.counterLength
            textured(2, cache.jib(width: c.counterLength), counterX, c.jibY)
            let cwX = c.jibDir < 0 ? c.mastX + c.counterLength - 2 : c.mastX - c.counterLength - 1
            textured(3, cache.prop(.counterweight), cwX, c.jibY - 3, z: 1)
            textured(4, cache.prop(.cab), c.mastX - 2, c.jibY - 4, z: 1)
            rect(5, c.mastX, c.jibY + 3, 1, 4, Pal.yellowDark)
            line(6, CGPoint(x: c.mastX, y: c.jibY + 6), CGPoint(x: c.hookX, y: c.jibY + 3), Pal.rope)
            let counterEnd = c.jibDir < 0 ? c.mastX + c.counterLength : c.mastX - c.counterLength
            line(7, CGPoint(x: c.mastX, y: c.jibY + 6), CGPoint(x: counterEnd, y: c.jibY + 3), Pal.rope)
            hide(from: 8)
            ensureRig(load: .plank)
            rigAnchor = CGPoint(x: CGFloat(c.hookX) + 0.5, y: CGFloat(c.jibY))
            center = CGPoint(x: CGFloat(c.mastX), y: CGFloat(c.jibY))

        case .pulley:
            guard let pl = L.pulley, let t = L.tower(pl.side) else { return }
            let poleX = pl.side == .left ? t.x0 : t.x1
            pivot = CGPoint(x: poleX, y: pl.baseY)
            position = pivot
            rect(0, poleX, pl.baseY, 1, pl.armTopY - pl.baseY + 1, Pal.steelDark)
            rect(1, min(poleX, pl.x), pl.armTopY, abs(pl.x - poleX) + 1, 1, Pal.steelDark)
            textured(2, cache.prop(.wheel), pl.x - 1, pl.armTopY - 1, z: 1)
            hide(from: 3)
            ensureRig(load: .bucket)
            rigAnchor = CGPoint(x: CGFloat(pl.x) + 0.5, y: CGFloat(pl.armTopY - 1))
            center = CGPoint(x: CGFloat(pl.x), y: CGFloat(pl.armTopY))
        }
    }

    private func ensureRig(load: PropKind) {
        guard rigRope == nil else { return }
        let rope = SKSpriteNode(color: Pal.rope.nsColor, size: CGSize(width: 1, height: 4))
        rope.anchorPoint = CGPoint(x: 0.5, y: 1)
        rope.zPosition = 2
        addChild(rope)
        rigRope = rope
        let cache = TextureCache.shared
        if load == .plank {
            let hook = SKSpriteNode(texture: cache.prop(.hook))
            hook.anchorPoint = CGPoint(x: 0.5, y: 1)
            hook.zPosition = 3
            addChild(hook)
            rigHook = hook
            let plank = SKSpriteNode(texture: cache.prop(.plank))
            plank.anchorPoint = CGPoint(x: 0.5, y: 1)
            plank.zPosition = 3
            plank.isHidden = true
            addChild(plank)
            rigLoad = plank
        } else {
            let bucket = SKSpriteNode(texture: cache.prop(.bucket))
            bucket.anchorPoint = CGPoint(x: 0.5, y: 1)
            bucket.zPosition = 3
            addChild(bucket)
            rigHook = bucket
        }
    }

    /// Positions the hanging rope, hook/bucket and optional load.
    func updateRig(length: CGFloat, angle: CGFloat, loaded: Bool) {
        guard let rope = rigRope else { return }
        let len = max(1, length.rounded())
        let a = CGPoint(x: rigAnchor.x - pivot.x, y: rigAnchor.y - pivot.y)
        rope.position = a
        rope.size = CGSize(width: 1, height: len)
        rope.zRotation = angle
        let end = CGPoint(x: a.x + sin(angle) * len, y: a.y - cos(angle) * len)
        let snapped = CGPoint(x: end.x.rounded(), y: end.y.rounded())
        rigHook?.position = snapped
        rigHook?.zRotation = angle * 0.5
        if let load = rigLoad {
            load.isHidden = !loaded
            load.position = CGPoint(x: snapped.x, y: snapped.y - 5)
            load.zRotation = angle * 0.4
        }
    }
}

/// A loose object on site: sign, cones, toolbox, material stack, flag, dropped tools.
@MainActor
final class SiteProp {
    let kind: PropKind
    let node: SKSpriteNode
    var base: CGPoint
    var spring = Spring2D()
    var tilt: CGFloat = 0
    var wobble: CGFloat
    var falling = false
    var fallVelocity: CGFloat = 0
    var floorY: CGFloat = 0
    var present = false

    init(kind: PropKind, base: CGPoint, wobble: CGFloat, parent: SKNode) {
        self.kind = kind
        self.base = base
        self.wobble = wobble
        let tex = TextureCache.shared.prop(kind)
        node = SKSpriteNode(texture: tex)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.zPosition = 12
        node.alpha = 0
        parent.addChild(node)
    }

    func appear(animated: Bool) {
        present = true
        node.removeAllActions()
        if animated {
            node.alpha = 0
            node.setScale(0.4)
            node.run(SKAction.group([SKAction.fadeIn(withDuration: 0.12), SKAction.scale(to: 1, duration: 0.16)]))
        } else {
            node.alpha = 1
            node.setScale(1)
        }
    }

    func disappear(animated: Bool) {
        present = false
        node.removeAllActions()
        if animated {
            node.run(SKAction.group([SKAction.fadeOut(withDuration: 0.15), SKAction.scale(to: 0.4, duration: 0.15)]))
        } else {
            node.alpha = 0
        }
    }

    func render() {
        node.position = CGPoint(x: (base.x + spring.offset.dx).rounded(), y: (base.y + spring.offset.dy).rounded())
        node.zRotation = tilt + spring.offset.dx * wobble
    }
}
