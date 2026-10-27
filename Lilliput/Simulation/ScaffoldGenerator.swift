import Foundation
import CoreGraphics

// All scaffold geometry is expressed in *art pixels* relative to the window's
// bottom-left corner (y up). The rendering layer multiplies by the pixel scale, so
// every pole, plank and worker lands on the same pixel grid.

struct PxRect: Equatable {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int

    static let unbounded = PxRect(minX: -100_000, maxX: 100_000, minY: -100_000, maxY: 100_000)
}

enum TowerSide: Int, Hashable {
    case left = 1
    case right = 2
}

/// Shape of a scaffold that is kept stable while a window is being live-resized.
struct ScaffoldTopology: Equatable {
    var bays: Int
    var leftLevels: Int
    var rightLevels: Int
    var crane: Bool
    var pulley: Bool
}

struct ScaffoldParams: Equatable {
    var width: Int
    var height: Int
    var density: ConstructionDensity
    var bounds: PxRect = .unbounded
    var locked: ScaffoldTopology?
}

struct TowerLayout: Equatable {
    let side: TowerSide
    /// x of the outer-left pole.
    let x0: Int
    let levels: Int
    let ladderX: Int

    var x1: Int { x0 + ScaffoldGenerator.towerWidth - 1 }
    var centerX: Int { x0 + ScaffoldGenerator.towerWidth / 2 }
    var topY: Int { levels * ScaffoldGenerator.levelHeight }

    func surfaceID(level: Int) -> Int {
        level == 0 ? Surface.deckID : side.rawValue * 100 + level
    }
}

struct CraneLayout: Equatable {
    let side: TowerSide
    let mastX: Int
    let baseY: Int
    let mastHeight: Int
    /// -1 means the jib points left, +1 right.
    let jibDir: Int
    let jibLength: Int
    let counterLength: Int

    var jibY: Int { baseY + mastHeight }
    var hookX: Int { mastX + jibDir * (jibLength - 1) }
}

struct PulleyLayout: Equatable {
    let side: TowerSide
    /// x the rope hangs at.
    let x: Int
    let baseY: Int
    let armTopY: Int
}

struct BayLayout: Equatable {
    let x0: Int
    let x1: Int
    var center: Int { (x0 + x1) / 2 }
    var width: Int { x1 - x0 }
}

enum ElementKind: Int, Hashable {
    case bay
    case endPost
    case tower
    case ladder
    case crane
    case pulley
}

struct ElementKey: Hashable, CustomStringConvertible {
    let kind: ElementKind
    let side: Int
    let index: Int

    var description: String { "\(kind)-\(side)-\(index)" }
}

struct NavPoint: Equatable {
    var surface: Int
    var x: CGFloat
}

struct ElementSpec: Equatable {
    let key: ElementKey
    let order: Int
    let work: NavPoint
    let requires: [ElementKey]
}

struct Surface: Equatable {
    static let deckID = 0

    let id: Int
    let y: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let side: TowerSide?
    let level: Int

    func clamp(_ x: CGFloat) -> CGFloat { min(max(x, minX), maxX) }
}

struct ScaffoldLayout: Equatable {
    let width: Int
    let height: Int
    let deckL: Int
    let deckR: Int
    let trussDepth: Int
    let bays: [BayLayout]
    let hasRail: Bool
    let left: TowerLayout?
    let right: TowerLayout?
    let crane: CraneLayout?
    let pulley: PulleyLayout?
    let signX: Int
    let stackX: Int
    let toolboxX: Int
    let coneXs: [Int]
    let elements: [ElementSpec]
    let surfaces: [Surface]

    var topology: ScaffoldTopology {
        ScaffoldTopology(bays: bays.count,
                         leftLevels: left?.levels ?? 0,
                         rightLevels: right?.levels ?? 0,
                         crane: crane != nil,
                         pulley: pulley != nil)
    }

    var towers: [TowerLayout] { [left, right].compactMap { $0 } }

    func tower(_ side: TowerSide) -> TowerLayout? { side == .left ? left : right }

    func surface(_ id: Int) -> Surface? { surfaces.first { $0.id == id } }

    var deck: Surface { surfaces[0] }

    func spec(_ key: ElementKey) -> ElementSpec? { elements.first { $0.key == key } }

    func bayIndex(containing x: Int) -> Int? {
        bays.firstIndex { x >= $0.x0 && x < $0.x1 } ?? (bays.isEmpty ? nil : (x < bays[0].x0 ? 0 : bays.count - 1))
    }

    /// Surfaces a worker can stand on that are higher than the deck.
    var raisedSurfaces: [Surface] { surfaces.filter { $0.id != Surface.deckID } }
}

enum ScaffoldGenerator {
    static let levelHeight = 16
    static let towerWidth = 10
    static let railHeight = 7
    static let towerGap = 2
    static let maxTrussDepth = 7
    static let minBayWidth = 8
    static let preferredBayWidth = 18
    static let maxBays = 20

    static func layout(_ p: ScaffoldParams) -> ScaffoldLayout? {
        let W = p.width
        let H = p.height
        let b = p.bounds
        guard W >= 30, H >= 16 else { return nil }

        // How many levels can towers have without poking past the window top or the screen?
        let heightLimit = min(H - 8, b.maxY - 12)
        let maxByHeight = max(0, heightLimit / levelHeight)

        var desiredLevels: Int
        switch p.density {
        case .sparse: desiredLevels = 1
        case .normal: desiredLevels = 2
        case .busy: desiredLevels = H >= 260 ? 4 : 3
        }
        if H < 60 { desiredLevels = min(desiredLevels, 1) }

        var wantLeft: Bool
        var wantRight: Bool
        switch p.density {
        case .sparse: wantLeft = false; wantRight = true
        case .normal: wantLeft = W >= 110; wantRight = true
        case .busy: wantLeft = W >= 70; wantRight = true
        }

        var leftTarget = desiredLevels
        var rightTarget = desiredLevels
        if let t = p.locked {
            wantLeft = t.leftLevels > 0
            wantRight = t.rightLevels > 0
            leftTarget = t.leftLevels
            rightTarget = t.rightLevels
        }

        let leftX0 = -towerGap - towerWidth
        let rightX0 = W + towerGap
        let leftFits = leftX0 - 1 >= b.minX
        let rightFits = rightX0 + towerWidth <= b.maxX

        var leftLevels = (wantLeft && leftFits) ? min(leftTarget, maxByHeight) : 0
        var rightLevels = (wantRight && rightFits) ? min(rightTarget, maxByHeight) : 0

        // A single wanted tower that does not fit on its side moves to the other side.
        if p.locked == nil, wantRight, !wantLeft, rightLevels == 0, leftFits {
            leftLevels = min(rightTarget, maxByHeight)
        }
        if p.locked == nil, leftLevels == 0, rightLevels == 0, wantLeft, !rightFits, leftFits {
            leftLevels = min(leftTarget, maxByHeight)
        }
        leftLevels = max(0, leftLevels)
        rightLevels = max(0, rightLevels)

        let left = leftLevels > 0 ? TowerLayout(side: .left, x0: leftX0, levels: leftLevels, ladderX: leftX0 + 2) : nil
        let right = rightLevels > 0 ? TowerLayout(side: .right, x0: rightX0, levels: rightLevels, ladderX: rightX0 + towerWidth - 3) : nil

        var deckL = left?.x0 ?? 0
        var deckR = right.map { $0.x0 + towerWidth } ?? W
        deckL = max(deckL, b.minX)
        deckR = min(deckR, b.maxX)
        guard deckR - deckL >= 20 else { return nil }
        let len = deckR - deckL

        var n = p.locked?.bays ?? Int((Double(len) / Double(preferredBayWidth)).rounded())
        n = min(max(n, 1), maxBays)
        n = min(n, max(1, len / minBayWidth))

        var bays: [BayLayout] = []
        bays.reserveCapacity(n)
        let base = len / n
        let remainder = len % n
        var x = deckL
        for i in 0..<n {
            let w = base + (i < remainder ? 1 : 0)
            bays.append(BayLayout(x0: x, x1: x + w))
            x += w
        }

        let trussDepth = max(0, min(maxTrussDepth, -2 - b.minY))
        let hasRail = p.density != .sparse

        // Crane on the right tower (or left) top.
        var crane: CraneLayout?
        let craneWanted = p.locked?.crane ?? ((p.density == .busy && H >= 50) || (p.density == .normal && W >= 280 && H >= 70))
        if craneWanted, let host = right ?? left {
            let mastHeight = 14
            let baseY = host.topY
            let jibLength = min(20, max(10, W / 10))
            if baseY + mastHeight + 4 <= b.maxY {
                let dir = host.side == .right ? -1 : 1
                crane = CraneLayout(side: host.side,
                                    mastX: host.centerX,
                                    baseY: baseY,
                                    mastHeight: mastHeight,
                                    jibDir: dir,
                                    jibLength: jibLength,
                                    counterLength: 6)
            }
        }

        var pulley: PulleyLayout?
        let pulleyWanted = p.locked?.pulley ?? (p.density != .sparse)
        if pulleyWanted {
            let candidates = [left, right].compactMap { $0 }.filter { $0.side != crane?.side }
            if let host = candidates.first, host.topY + 10 <= b.maxY {
                let ropeX = host.side == .left ? host.x0 - 2 : host.x1 + 2
                if ropeX - 1 >= b.minX, ropeX + 1 <= b.maxX {
                    pulley = PulleyLayout(side: host.side, x: ropeX, baseY: host.topY, armTopY: host.topY + 7)
                }
            }
        }

        let signX = deckL + (left != nil ? towerWidth + 3 : 3)
        let stackX = min(deckR - 10, max(deckL + 16, deckL + len / 4))
        let toolboxX = min(deckR - 6, deckL + (len * 3) / 5)
        var cones: [Int] = []
        if p.density != .sparse, len > 60 { cones.append(deckR - (right != nil ? towerWidth + 4 : 4)) }
        if p.density == .busy, len > 120 { cones.append(deckL + len / 2 + 7) }

        // Surfaces.
        var surfaces: [Surface] = []
        surfaces.append(Surface(id: Surface.deckID, y: 0, minX: CGFloat(deckL + 2), maxX: CGFloat(deckR - 3), side: nil, level: 0))
        for t in [left, right].compactMap({ $0 }) {
            for level in 1...t.levels {
                surfaces.append(Surface(id: t.surfaceID(level: level),
                                        y: CGFloat(level * levelHeight),
                                        minX: CGFloat(t.x0 + 1),
                                        maxX: CGFloat(t.x1 - 1),
                                        side: t.side,
                                        level: level))
            }
        }

        // Elements and construction order.
        var elements: [ElementSpec] = []
        var order = 0
        for (i, bay) in bays.enumerated() {
            elements.append(ElementSpec(key: ElementKey(kind: .bay, side: 0, index: i),
                                        order: order,
                                        work: NavPoint(surface: Surface.deckID, x: CGFloat(bay.center)),
                                        requires: []))
            order += 1
        }
        elements.append(ElementSpec(key: ElementKey(kind: .endPost, side: 0, index: 0),
                                    order: order,
                                    work: NavPoint(surface: Surface.deckID, x: CGFloat(deckR - 4)),
                                    requires: [ElementKey(kind: .bay, side: 0, index: bays.count - 1)]))
        order += 1

        func bayKey(for x: Int) -> ElementKey {
            let idx = bays.firstIndex { x >= $0.x0 && x < $0.x1 } ?? (x < deckL ? 0 : bays.count - 1)
            return ElementKey(kind: .bay, side: 0, index: idx)
        }

        let maxLevels = max(left?.levels ?? 0, right?.levels ?? 0)
        if maxLevels > 0 {
            for level in 1...maxLevels {
                for t in [left, right].compactMap({ $0 }) where level <= t.levels {
                    let side = t.side.rawValue
                    let below = t.surfaceID(level: level - 1)
                    let towerReq: [ElementKey] = level == 1
                        ? [bayKey(for: t.centerX)]
                        : [ElementKey(kind: .ladder, side: side, index: level - 1)]
                    elements.append(ElementSpec(key: ElementKey(kind: .tower, side: side, index: level),
                                                order: order,
                                                work: NavPoint(surface: below, x: CGFloat(t.centerX)),
                                                requires: towerReq))
                    order += 1
                    elements.append(ElementSpec(key: ElementKey(kind: .ladder, side: side, index: level),
                                                order: order,
                                                work: NavPoint(surface: below, x: CGFloat(t.ladderX + (t.side == .left ? 2 : -2))),
                                                requires: [ElementKey(kind: .tower, side: side, index: level)]))
                    order += 1
                }
            }
        }

        if let c = crane, let t = side(c.side, left, right) {
            elements.append(ElementSpec(key: ElementKey(kind: .crane, side: c.side.rawValue, index: 0),
                                        order: order,
                                        work: NavPoint(surface: t.surfaceID(level: t.levels), x: CGFloat(t.centerX)),
                                        requires: [ElementKey(kind: .tower, side: c.side.rawValue, index: t.levels),
                                                   ElementKey(kind: .ladder, side: c.side.rawValue, index: t.levels)]))
            order += 1
        }
        if let pl = pulley, let t = side(pl.side, left, right) {
            elements.append(ElementSpec(key: ElementKey(kind: .pulley, side: pl.side.rawValue, index: 0),
                                        order: order,
                                        work: NavPoint(surface: t.surfaceID(level: t.levels), x: CGFloat(t.centerX)),
                                        requires: [ElementKey(kind: .tower, side: pl.side.rawValue, index: t.levels),
                                                   ElementKey(kind: .ladder, side: pl.side.rawValue, index: t.levels)]))
            order += 1
        }

        return ScaffoldLayout(width: W,
                              height: H,
                              deckL: deckL,
                              deckR: deckR,
                              trussDepth: trussDepth,
                              bays: bays,
                              hasRail: hasRail,
                              left: left,
                              right: right,
                              crane: crane,
                              pulley: pulley,
                              signX: signX,
                              stackX: stackX,
                              toolboxX: toolboxX,
                              coneXs: cones,
                              elements: elements,
                              surfaces: surfaces)
    }

    private static func side(_ s: TowerSide, _ l: TowerLayout?, _ r: TowerLayout?) -> TowerLayout? {
        s == .left ? l : r
    }
}
