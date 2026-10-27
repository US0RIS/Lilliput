import Foundation
import CoreGraphics

struct OcclusionInfo: Equatable {
    /// Rects of windows in front of this one that overlap its construction area.
    var occluders: [CGRect]
    /// 0…1 estimate of how much of the construction area is visible.
    var visibleFraction: CGFloat

    static let clear = OcclusionInfo(occluders: [], visibleFraction: 1)
}

enum Occlusion {
    /// Margin around a window that scaffolding may occupy (towers, deck truss, crane).
    static let siteMargin: CGFloat = 70

    /// - Parameter frontToBack: every on-screen window (tracked or not), front first.
    /// - Returns: occlusion info for each window in `targets`.
    static func compute(frontToBack: [(id: WindowID, frame: CGRect)], targets: Set<WindowID>) -> [WindowID: OcclusionInfo] {
        var result: [WindowID: OcclusionInfo] = [:]
        for (index, entry) in frontToBack.enumerated() where targets.contains(entry.id) {
            let area = entry.frame.insetBy(dx: -siteMargin, dy: -siteMargin)
            var raw: [CGRect] = []
            var occluders: [CGRect] = []
            for front in frontToBack[..<index] {
                // A front window also "owns" the strip below and beside it where its own
                // crew works; anything of ours there would just pile up behind its deck.
                let claimed = claimedArea(of: front.frame)
                guard claimed.intersects(area) else { continue }
                raw.append(front.frame)
                occluders.append(targets.contains(front.id) ? claimed : front.frame)
            }
            let fraction = raw.isEmpty ? 1 : visibleFraction(of: entry.frame, occluders: raw)
            result[entry.id] = OcclusionInfo(occluders: occluders, visibleFraction: fraction)
        }
        return result
    }

    /// The window plus the margin its own scaffolding occupies (deck truss below, towers beside).
    static func claimedArea(of frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - 26, y: frame.minY - 20, width: frame.width + 52, height: frame.height + 20)
    }

    /// Samples points along the bottom edge and lower sides — where the crew works.
    static func visibleFraction(of frame: CGRect, occluders: [CGRect]) -> CGFloat {
        var samples = 0
        var visible = 0
        func test(_ p: CGPoint) {
            samples += 1
            if !occluders.contains(where: { $0.contains(p) }) { visible += 1 }
        }
        let bottomY = frame.minY + 8
        for i in 0..<12 {
            let t = (CGFloat(i) + 0.5) / 12
            test(CGPoint(x: frame.minX + frame.width * t, y: bottomY))
        }
        let sideHeight = min(frame.height, 90)
        for i in 0..<4 {
            let y = frame.minY + sideHeight * (CGFloat(i) + 0.5) / 4
            test(CGPoint(x: frame.minX - 10, y: y))
            test(CGPoint(x: frame.maxX + 10, y: y))
        }
        return samples == 0 ? 1 : CGFloat(visible) / CGFloat(samples)
    }
}
