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
            var occluders: [CGRect] = []
            for front in frontToBack[..<index] where front.frame.intersects(area) {
                occluders.append(front.frame)
            }
            let fraction = occluders.isEmpty ? 1 : visibleFraction(of: entry.frame, occluders: occluders)
            result[entry.id] = OcclusionInfo(occluders: occluders, visibleFraction: fraction)
        }
        return result
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
