import Foundation
import CoreGraphics

enum NavStep: Equatable {
    case walk(surface: Int, x: CGFloat)
    case climb(x: CGFloat, from: Int, to: Int)
}

/// Path planning over the scaffold: the deck plus a vertical chain of platforms in
/// each tower, connected by ladders.
extension ScaffoldLayout {
    /// The ladder that goes from `level - 1` up to `level` on the given tower.
    func ladderX(side: TowerSide, level: Int) -> CGFloat? {
        guard let t = tower(side), level >= 1, level <= t.levels else { return nil }
        return CGFloat(t.ladderX)
    }

    func path(from: NavPoint, to: NavPoint) -> [NavStep] {
        guard let fromSurface = surface(from.surface) ?? surface(Surface.deckID),
              let toSurface = surface(to.surface) ?? surface(Surface.deckID) else { return [] }

        var steps: [NavStep] = []
        var curSurface = fromSurface
        var curX = from.x

        func walk(to x: CGFloat) {
            let tx = curSurface.clamp(x)
            if abs(tx - curX) > 0.5 {
                steps.append(.walk(surface: curSurface.id, x: tx))
                curX = tx
            }
        }

        func moveVertically(side: TowerSide, from a: Int, to b: Int) {
            guard let t = tower(side), a != b else { return }
            if a < b {
                for level in (a + 1)...b {
                    let lx = CGFloat(t.ladderX)
                    walk(to: lx)
                    let next = t.surfaceID(level: level)
                    steps.append(.climb(x: lx, from: curSurface.id, to: next))
                    if let s = surface(next) { curSurface = s }
                    curX = lx
                }
            } else {
                for level in stride(from: a, to: b, by: -1) {
                    let lx = CGFloat(t.ladderX)
                    walk(to: lx)
                    let next = t.surfaceID(level: level - 1)
                    steps.append(.climb(x: lx, from: curSurface.id, to: next))
                    if let s = surface(next) { curSurface = s }
                    curX = lx
                }
            }
        }

        let fromSide = fromSurface.side
        let toSide = toSurface.side

        if fromSide != nil, fromSide == toSide, let side = fromSide {
            moveVertically(side: side, from: fromSurface.level, to: toSurface.level)
        } else {
            if let side = fromSide {
                moveVertically(side: side, from: fromSurface.level, to: 0)
            }
            if let side = toSide {
                moveVertically(side: side, from: 0, to: toSurface.level)
            }
        }
        walk(to: to.x)
        return steps
    }

    /// The surface directly below a removed one (used when a platform disappears
    /// under a worker's feet).
    func fallbackSurface(for id: Int) -> Surface {
        if let s = surface(id) { return s }
        guard id >= 100, let side = TowerSide(rawValue: id / 100), let t = tower(side) else { return deck }
        let level = min(id % 100, t.levels)
        return surface(t.surfaceID(level: level)) ?? deck
    }
}
