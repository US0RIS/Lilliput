import Foundation
import SpriteKit
import SwiftUI

/// A pretend window drawn inside the Demo scene. The construction crew around it is the
/// real simulation: the Demo feeds these frames through exactly the same site API the
/// window tracker uses.
@MainActor
final class FakeWindow {
    let id: WindowID
    var frame: CGRect
    let node = SKNode()
    private let body = SKShapeNode()
    private let titleBar = SKShapeNode()
    private let lights: [SKShapeNode]
    private let title = SKLabelNode(fontNamed: "Helvetica Neue")
    private var lines: [SKSpriteNode] = []
    private let tint: NSColor
    var minimized = false
    var closing = false
    var tween: ((CGFloat) -> CGRect)?
    var tweenDuration: TimeInterval = 0
    var tweenElapsed: TimeInterval = 0

    init(id: WindowID, frame: CGRect, name: String, tint: NSColor) {
        self.id = id
        self.frame = frame
        self.tint = tint
        lights = [NSColor(srgbRed: 0.99, green: 0.37, blue: 0.34, alpha: 1),
                  NSColor(srgbRed: 0.99, green: 0.74, blue: 0.18, alpha: 1),
                  NSColor(srgbRed: 0.16, green: 0.79, blue: 0.27, alpha: 1)].map { c in
            let n = SKShapeNode(circleOfRadius: 6)
            n.fillColor = c
            n.strokeColor = c.blended(withFraction: 0.25, of: .black) ?? c
            n.lineWidth = 0.5
            return n
        }
        body.fillColor = NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)
        body.strokeColor = NSColor(white: 0, alpha: 0.18)
        body.lineWidth = 1
        titleBar.fillColor = NSColor(srgbRed: 0.91, green: 0.90, blue: 0.88, alpha: 1)
        titleBar.strokeColor = .clear
        title.text = name
        title.fontSize = 12
        title.fontColor = NSColor(white: 0.25, alpha: 1)
        title.verticalAlignmentMode = .center
        node.addChild(body)
        node.addChild(titleBar)
        for l in lights { node.addChild(l) }
        node.addChild(title)
        for i in 0..<6 {
            let line = SKSpriteNode(color: i == 0 ? tint : NSColor(white: 0.82, alpha: 1), size: CGSize(width: 10, height: 8))
            line.anchorPoint = .zero
            node.addChild(line)
            lines.append(line)
        }
        layout()
    }

    func layout() {
        node.position = frame.origin
        let w = frame.width, h = frame.height
        body.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: 10, cornerHeight: 10, transform: nil)
        let tb = CGMutablePath()
        tb.addRoundedRect(in: CGRect(x: 0, y: h - 28, width: w, height: 28), cornerWidth: 10, cornerHeight: 10)
        tb.addRect(CGRect(x: 0, y: h - 28, width: w, height: 12))
        titleBar.path = tb
        for (i, l) in lights.enumerated() { l.position = CGPoint(x: 16 + CGFloat(i) * 20, y: h - 14) }
        title.position = CGPoint(x: w / 2, y: h - 14)
        let contentTop = h - 46
        for (i, line) in lines.enumerated() {
            if i == 0 {
                line.size = CGSize(width: min(w - 40, 140), height: 14)
                line.position = CGPoint(x: 20, y: contentTop - 10)
            } else {
                let lw = max(20, (w - 40) * [0.9, 0.75, 0.85, 0.6, 0.7][(i - 1) % 5])
                line.size = CGSize(width: lw, height: 7)
                line.position = CGPoint(x: 20, y: contentTop - 30 - CGFloat(i) * 16)
            }
            line.isHidden = line.position.y < 12
        }
    }
}

@MainActor
final class DemoController: ObservableObject {
    let scene: ConstructionScene
    private(set) var windows: [FakeWindow] = []   // back to front
    @Published var autoplay = false
    @Published private(set) var windowCount = 0
    @Published private(set) var minimizedCount = 0
    private var nextID: WindowID = 1
    private var autoplayTimer: TimeInterval = 0
    private var rng = SplitMix64(seed: UInt64(Date().timeIntervalSince1970))
    private let background = SKSpriteNode(color: NSColor(srgbRed: 0.33, green: 0.47, blue: 0.56, alpha: 1), size: .zero)
    private let backgroundGlow = SKSpriteNode(color: NSColor(srgbRed: 0.45, green: 0.60, blue: 0.66, alpha: 1), size: .zero)
    private var occlusionDirty = true
    private var started = false
    private var scheduled: [(TimeInterval, () -> Void)] = []
    private var clock: TimeInterval = 0

    private static let names = ["Notes", "Safari", "Finder", "Mail", "Photos", "Terminal", "Calendar", "Music"]
    private static let tints: [NSColor] = [
        NSColor(srgbRed: 0.95, green: 0.78, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.30, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.70, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.40, green: 0.62, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.50, blue: 0.40, alpha: 1),
        NSColor(srgbRed: 0.25, green: 0.25, blue: 0.28, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.35, blue: 0.35, alpha: 1),
        NSColor(srgbRed: 0.95, green: 0.35, blue: 0.55, alpha: 1),
    ]

    init(size: CGSize, settings: SimSettings) {
        scene = ConstructionScene(size: size, isDemo: true)
        scene.backgroundColor = NSColor(srgbRed: 0.33, green: 0.47, blue: 0.56, alpha: 1)
        scene.availableRect = CGRect(origin: .zero, size: size)
        scene.apply(settings: settings)
        background.anchorPoint = .zero
        background.zPosition = -1000
        backgroundGlow.anchorPoint = .zero
        backgroundGlow.zPosition = -999
        backgroundGlow.alpha = 0.35
        scene.addChild(background)
        scene.addChild(backgroundGlow)
        scene.onFrame = { [weak self] dt in self?.frame(dt: dt) }
    }

    func start() {
        guard !started else { return }
        started = true
        after(0.3) { [weak self] in self?.openWindow() }
        after(2.4) { [weak self] in self?.openWindow() }
        after(4.6) { [weak self] in self?.openWindow() }
    }

    func shutdown() {
        scene.onFrame = nil
        scene.removeAllSites()
        scheduled.removeAll()
    }

    private func after(_ delay: TimeInterval, _ f: @escaping () -> Void) {
        scheduled.append((clock + delay, f))
    }

    private var bounds: CGRect { CGRect(origin: .zero, size: scene.size) }

    private var front: FakeWindow? { windows.last { !$0.minimized && !$0.closing } }

    // MARK: Actions

    func openWindow() {
        guard windows.filter({ !$0.closing }).count < 6 else { return }
        let b = bounds.insetBy(dx: 48, dy: 40)
        guard b.width > 300, b.height > 240 else { return }
        let w = rng.cg(260, min(440, b.width * 0.5)).rounded()
        let h = rng.cg(180, min(320, b.height * 0.6)).rounded()
        let x = rng.cg(b.minX + 30, max(b.minX + 31, b.maxX - w - 30)).rounded()
        let y = rng.cg(b.minY + 30, max(b.minY + 31, b.maxY - h - 10)).rounded()
        let id = nextID
        nextID += 1
        let idx = Int(id - 1) % Self.names.count
        let fw = FakeWindow(id: id, frame: CGRect(x: x, y: y, width: w, height: h), name: Self.names[idx], tint: Self.tints[idx])
        windows.append(fw)
        scene.addChild(fw.node)
        restack()
        fw.node.alpha = 0
        fw.node.setScale(0.94)
        fw.node.run(SKAction.group([SKAction.fadeIn(withDuration: 0.18), SKAction.scale(to: 1, duration: 0.18)]))
        // Like the real tracker, wait for the "window" to settle before construction.
        after(0.35) { [weak self, weak fw] in
            guard let self, let fw, !fw.closing else { return }
            self.scene.openSite(fw.id, frame: fw.frame, mode: .construct)
            self.occlusionDirty = true
        }
        publishCounts()
    }

    func moveFront(fast: Bool = false) {
        guard let fw = front, fw.tween == nil else { return }
        let start = fw.frame
        let b = bounds.insetBy(dx: 30, dy: 30)
        func clampOrigin(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, b.minX), b.maxX - start.width), y: min(max(p.y, b.minY), b.maxY - start.height))
        }
        let dx: CGFloat = (start.midX < bounds.midX ? 1 : -1) * (fast ? 380 : 200)
        let dy: CGFloat = rng.cg(-60, 60)
        let mid = clampOrigin(CGPoint(x: start.minX + dx, y: start.minY + dy))
        let back = clampOrigin(CGPoint(x: start.minX + dx * 0.25, y: start.minY - dy * 0.3))
        let total: TimeInterval = fast ? 1.25 : 1.9
        fw.tweenDuration = total
        fw.tween = { t in
            let tt = Double(t) * total
            let p: CGPoint
            if fast {
                if tt < 0.28 {
                    p = Self.lerp(start.origin, mid, Self.easeInOut(CGFloat(tt / 0.28)))
                } else if tt < 0.75 {
                    p = mid
                } else {
                    p = Self.lerp(mid, back, Self.easeInOut(CGFloat(min(1, (tt - 0.75) / 0.3))))
                }
            } else {
                if tt < 0.9 {
                    p = Self.lerp(start.origin, mid, Self.easeInOut(CGFloat(tt / 0.9)))
                } else if tt < 1.2 {
                    p = mid
                } else {
                    p = Self.lerp(mid, back, Self.easeInOut(CGFloat(min(1, (tt - 1.2) / 0.7))))
                }
            }
            return CGRect(origin: p, size: start.size)
        }
        fw.tweenElapsed = 0
    }

    func resizeFront() {
        guard let fw = front, fw.tween == nil else { return }
        let start = fw.frame
        let b = bounds.insetBy(dx: 40, dy: 30)
        let grownW = min(start.width * 1.45, b.maxX - start.minX - 20)
        let grownH = min(start.height * 1.3, b.maxY - start.minY)
        let shrunkW = max(200, start.width * 0.7)
        let shrunkH = max(150, start.height * 0.8)
        let total: TimeInterval = 4.2
        fw.tweenDuration = total
        fw.tween = { t in
            let tt = Double(t) * total
            let size: CGSize
            func mix(_ a: CGSize, _ b: CGSize, _ k: CGFloat) -> CGSize {
                CGSize(width: a.width + (b.width - a.width) * k, height: a.height + (b.height - a.height) * k)
            }
            let grown = CGSize(width: grownW, height: grownH)
            let shrunk = CGSize(width: shrunkW, height: shrunkH)
            if tt < 0.9 {
                size = mix(start.size, grown, Self.easeInOut(CGFloat(tt / 0.9)))
            } else if tt < 1.9 {
                size = grown
            } else if tt < 2.9 {
                size = mix(grown, shrunk, Self.easeInOut(CGFloat((tt - 1.9) / 1.0)))
            } else if tt < 3.5 {
                size = shrunk
            } else {
                size = mix(shrunk, start.size, Self.easeInOut(CGFloat(min(1, (tt - 3.5) / 0.7))))
            }
            return CGRect(origin: start.origin, size: CGSize(width: size.width.rounded(), height: size.height.rounded()))
        }
        fw.tweenElapsed = 0
    }

    func minimizeFront() {
        guard let fw = front else { return }
        fw.minimized = true
        fw.tween = nil
        fw.node.run(SKAction.group([SKAction.fadeOut(withDuration: 0.3),
                                    SKAction.scale(to: 0.2, duration: 0.3),
                                    SKAction.move(to: CGPoint(x: fw.frame.midX, y: 0), duration: 0.3)]))
        scene.hideSite(fw.id, animated: true)
        occlusionDirty = true
        publishCounts()
    }

    func restoreOne() {
        guard let fw = windows.last(where: { $0.minimized && !$0.closing }) else { return }
        fw.minimized = false
        windows.removeAll { $0 === fw }
        windows.append(fw)
        restack()
        fw.node.removeAllActions()
        fw.node.run(SKAction.group([SKAction.fadeIn(withDuration: 0.3),
                                    SKAction.scale(to: 1, duration: 0.3),
                                    SKAction.move(to: fw.frame.origin, duration: 0.3)]))
        after(0.32) { [weak self, weak fw] in
            guard let self, let fw, !fw.minimized, !fw.closing else { return }
            self.scene.restoreSite(fw.id, frame: fw.frame, animated: true)
            self.occlusionDirty = true
        }
        publishCounts()
    }

    func closeFront() {
        guard let fw = front else { return }
        fw.closing = true
        fw.tween = nil
        fw.node.run(SKAction.sequence([
            SKAction.group([SKAction.fadeOut(withDuration: 0.18), SKAction.scale(to: 0.96, duration: 0.18)]),
            SKAction.removeFromParent(),
        ]))
        scene.closeSite(fw.id)
        windows.removeAll { $0 === fw }
        restack()
        publishCounts()
    }

    func focusNext() {
        let visible = windows.filter { !$0.minimized && !$0.closing }
        guard visible.count > 1, let back = visible.first else { return }
        windows.removeAll { $0 === back }
        windows.append(back)
        restack()
    }

    func specialEvent() {
        _ = scene.triggerSpecialEvent(preferring: front?.id)
    }

    // MARK: Frame loop

    private func frame(dt: TimeInterval) {
        clock += dt
        if background.size != scene.size {
            background.size = scene.size
            backgroundGlow.size = CGSize(width: scene.size.width, height: scene.size.height * 0.45)
            backgroundGlow.position = CGPoint(x: 0, y: scene.size.height * 0.55)
        }
        if !scheduled.isEmpty {
            let due = scheduled.filter { $0.0 <= clock }
            scheduled.removeAll { $0.0 <= clock }
            for (_, f) in due { f() }
        }
        for fw in windows where fw.tween != nil && !fw.minimized && !fw.closing {
            fw.tweenElapsed += dt
            let t = CGFloat(min(1, fw.tweenElapsed / max(0.01, fw.tweenDuration)))
            if let tw = fw.tween {
                fw.frame = tw(t)
                fw.layout()
                scene.updateSite(fw.id, frame: fw.frame)
                occlusionDirty = true
            }
            if t >= 1 { fw.tween = nil }
        }
        if autoplay {
            autoplayTimer -= dt
            if autoplayTimer <= 0 {
                autoplayTimer = rng.range(5.5, 8.5)
                autoplayStep()
            }
        }
        if occlusionDirty {
            occlusionDirty = false
            let visible = windows.filter { !$0.minimized && !$0.closing }
            let frontToBack = visible.reversed().map { (id: $0.id, frame: $0.frame) }
            let info = Occlusion.compute(frontToBack: frontToBack, targets: Set(visible.map(\.id)))
            for fw in visible { scene.setOcclusion(fw.id, info[fw.id] ?? .clear) }
        }
    }

    private func autoplayStep() {
        let visibleCount = windows.filter { !$0.minimized && !$0.closing }.count
        if visibleCount < 2 { openWindow(); return }
        let roll = rng.unit()
        switch roll {
        case ..<0.18: moveFront()
        case ..<0.30: moveFront(fast: true)
        case ..<0.45: resizeFront()
        case ..<0.55: focusNext()
        case ..<0.65: minimizeFront(); after(2.5) { [weak self] in self?.restoreOne() }
        case ..<0.75: specialEvent()
        case ..<0.85: if visibleCount >= 3 { closeFront() } else { openWindow() }
        default: if visibleCount < 4 { openWindow() } else { focusNext() }
        }
    }

    private func restack() {
        for (i, fw) in windows.enumerated() { fw.node.zPosition = -100 + CGFloat(i) }
        occlusionDirty = true
    }

    private func publishCounts() {
        windowCount = windows.filter { !$0.closing }.count
        minimizedCount = windows.filter { $0.minimized && !$0.closing }.count
    }

    nonisolated private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    nonisolated private static func easeInOut(_ t: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)
    }
}
