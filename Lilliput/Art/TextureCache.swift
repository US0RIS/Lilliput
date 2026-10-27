import Foundation
import SpriteKit

/// Lazily turns pixel canvases into nearest-filtered SpriteKit textures. The cache is
/// bounded: worker/prop textures are a fixed small set, and the variable-length
/// sub-textures (planks, ladders, mast, jib) are capped.
@MainActor
final class TextureCache {
    static let shared = TextureCache()

    private struct WorkerKey: Hashable {
        let style: Int
        let pose: Pose
    }

    private var workers: [WorkerKey: SKTexture] = [:]
    private var props: [PropKind: SKTexture] = [:]
    private var emotes: [Emote: SKTexture] = [:]
    private var strips: [String: SKTexture] = [:]
    private var subTextures: [String: SKTexture] = [:]
    private let maxSubTextures = 256

    static let supervisorStyleIndex = 99

    static func style(for index: Int) -> WorkerStyle {
        index == supervisorStyleIndex ? WorkerStyle.supervisor : WorkerStyle.crew[index % WorkerStyle.crew.count]
    }

    func worker(style: Int, pose: Pose) -> SKTexture {
        let key = WorkerKey(style: style, pose: pose)
        if let t = workers[key] { return t }
        let t = Self.texture(from: WorkerArt.draw(Self.style(for: style), pose))
        workers[key] = t
        return t
    }

    func prop(_ kind: PropKind) -> SKTexture {
        if let t = props[kind] { return t }
        let t = Self.texture(from: PropArt.canvas(kind))
        props[kind] = t
        return t
    }

    func emote(_ e: Emote) -> SKTexture {
        if let t = emotes[e] { return t }
        let t = Self.texture(from: PropArt.emote(e))
        emotes[e] = t
        return t
    }

    func plank(width: Int) -> SKTexture {
        subTexture(strip: "plank", length: max(1, min(128, width)), horizontal: true) { PropArt.plankStrip() }
    }

    func ladder(height: Int) -> SKTexture {
        subTexture(strip: "ladder", length: max(1, min(128, height)), horizontal: false) { PropArt.ladderStrip() }
    }

    func mast(height: Int) -> SKTexture {
        subTexture(strip: "mast", length: max(1, min(64, height)), horizontal: false) { PropArt.mastStrip() }
    }

    func jib(width: Int) -> SKTexture {
        subTexture(strip: "jib", length: max(1, min(64, width)), horizontal: true) { PropArt.jibStrip() }
    }

    private func subTexture(strip name: String, length: Int, horizontal: Bool, make: () -> PixelCanvas) -> SKTexture {
        let key = "\(name):\(length)"
        if let t = subTextures[key] { return t }
        let base: SKTexture
        if let b = strips[name] {
            base = b
        } else {
            base = Self.texture(from: make())
            strips[name] = base
        }
        let full = horizontal ? base.size().width : base.size().height
        let fraction = CGFloat(length) / max(1, full)
        let rect = horizontal
            ? CGRect(x: 0, y: 0, width: fraction, height: 1)
            : CGRect(x: 0, y: 1 - fraction, width: 1, height: fraction)
        let t = SKTexture(rect: rect, in: base)
        t.filteringMode = .nearest
        if subTextures.count >= maxSubTextures { subTextures.removeAll(keepingCapacity: true) }
        subTextures[key] = t
        return t
    }

    static func texture(from canvas: PixelCanvas) -> SKTexture {
        let t: SKTexture
        if let image = canvas.makeImage() {
            t = SKTexture(cgImage: image)
        } else {
            t = SKTexture()
        }
        t.filteringMode = .nearest
        return t
    }
}
