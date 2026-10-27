import Foundation

enum PropKind: String, CaseIterable, Hashable {
    case sign
    case barrier
    case cone
    case toolbox
    case bricks
    case plankPile
    case plank
    case longPlank
    case bucket
    case hook
    case flag
    case cab
    case counterweight
    case wheel
    case hammer
    case blueprintRoll
    case trafficLight
}

enum Emote: String, CaseIterable, Hashable {
    case exclaim
    case question
    case sleep
    case note
    case sparkle
    case sweat
    case dots
    case thumbs
}

enum PropArt {
    private static let p: [Character: RGBA] = [
        "k": Pal.ink, "K": Pal.inkSoft,
        "Y": Pal.yellow, "y": Pal.yellowDark, "L": Pal.yellowLight,
        "O": Pal.orange, "o": Pal.orangeDark,
        "W": Pal.white, "w": Pal.offWhite,
        "R": Pal.red, "r": Pal.redDark, "q": Pal.redLight,
        "S": Pal.steel, "s": Pal.steelDark, "l": Pal.steelLight, "c": Pal.coupler,
        "D": Pal.wood, "d": Pal.woodDark, "e": Pal.woodLight, "g": Pal.woodGrain,
        "B": Pal.brick, "b": Pal.brickDark, "m": Pal.offWhite,
        "C": Pal.concrete, "x": Pal.concreteDark,
        "F": Pal.flagRed, "U": Pal.blueprint, "u": Pal.blueprintLight,
        "h": Pal.hook, "v": Pal.sweat,
    ]

    static func canvas(_ kind: PropKind) -> PixelCanvas {
        switch kind {
        case .sign:
            return make([
                "...k...",
                "..kYk..",
                ".kYkYk.",
                "kYYkYYk",
                ".kYYYk.",
                "..kkk..",
                "...k...",
                "...d...",
                "...d...",
                "..ddd..",
            ])
        case .barrier:
            return make([
                "OOWWOOWWO",
                "oWWooWWoo",
                ".w.....w.",
                ".w.....w.",
                "w.......w",
                "k.......k",
            ])
        case .cone:
            return make([
                "..O..",
                "..W..",
                ".OOO.",
                ".WWW.",
                "OOOOO",
                "kkkkk",
            ])
        case .toolbox:
            return make([
                "..sss..",
                "..s.s..",
                "qqqqqqq",
                "RRRYRRR",
                "rrrrrrr",
            ])
        case .bricks:
            return make([
                "..BBbBB.",
                ".BbBBBbB",
                "BBBbBBBb",
                "bbbbbbbb",
            ])
        case .plankPile:
            return make([
                "...eeeeeeegeed",
                "..dDDDgDDDDDDd",
                "eeeeegeeeeeed.",
                "DDDDDDDgDDDDd.",
                "kKKKKKKKKKKK..",
            ])
        case .plank:
            return make([
                "eeeegeeeeeed",
                "dDDDDDDgDDDd",
            ])
        case .longPlank:
            return make([
                "eeeeegeeeeeeeegeeeeeeeed",
                "dDDDDDDDgDDDDDDDDDgDDDDd",
            ])
        case .bucket:
            return make([
                ".s..s.",
                "..ss..",
                "sllls.",
                "sSSSs.",
                ".sss..",
            ])
        case .hook:
            return make([
                ".s.",
                "sls",
                ".h.",
                ".h.",
                "h.h",
                ".hh",
            ])
        case .flag:
            return make([
                "dFFFFF",
                "dFWWFF",
                "dFFFF.",
                "d.....",
                "d.....",
                "d.....",
                "d.....",
            ])
        case .cab:
            return make([
                "YYYY",
                "YuuY",
                "YuuY",
                "yyyy",
            ])
        case .counterweight:
            return make([
                "CCCC",
                "CxCx",
                "xxxx",
            ])
        case .wheel:
            return make([
                ".s.",
                "sls",
                ".s.",
            ])
        case .hammer:
            return make([
                "sss",
                ".d.",
                ".d.",
            ])
        case .blueprintRoll:
            return make([
                "uUUUu",
                "UUUUU",
            ])
        case .trafficLight:
            return make([
                ".RR.",
                "RqRR",
                "RRRR",
                ".RR.",
            ])
        }
    }

    static func emote(_ e: Emote) -> PixelCanvas {
        if e == .sweat {
            return make([
                ".v.",
                "vvv",
                "vWv",
                ".v.",
            ])
        }
        var c = PixelCanvas(width: 7, height: 7)
        let bubble = Pal.white
        let edge = Pal.offWhite
        c.fill(1, 0, 5, 6, bubble)
        c.fill(0, 1, 7, 4, bubble)
        c.set(0, 1, edge); c.set(6, 1, edge); c.set(0, 4, edge); c.set(6, 4, edge)
        c.set(2, 6, bubble)
        let ink = Pal.ink
        switch e {
        case .exclaim:
            c.vline(3, 1, 2, Pal.red); c.set(3, 4, Pal.red)
        case .question:
            c.hline(2, 4, 1, ink); c.set(4, 2, ink); c.set(3, 3, ink); c.set(3, 4, Pal.inkSoft)
            c.set(2, 1, Pal.inkSoft)
        case .sleep:
            c.hline(1, 3, 1, Pal.blueprint); c.set(2, 2, Pal.blueprint); c.hline(1, 3, 3, Pal.blueprint)
            c.hline(4, 5, 3, Pal.blueprintLight); c.set(4, 4, Pal.blueprintLight); c.hline(4, 5, 4, Pal.blueprintLight)
        case .note:
            c.vline(4, 1, 3, ink); c.set(5, 1, ink); c.fill(2, 3, 2, 2, ink)
        case .sparkle:
            c.vline(3, 1, 4, Pal.yellowDark); c.hline(1, 5, 2, Pal.yellowDark); c.set(3, 2, Pal.yellow)
        case .dots:
            c.set(1, 3, ink); c.set(3, 3, ink); c.set(5, 3, ink)
        case .thumbs:
            c.vline(3, 1, 2, Pal.orangeDark); c.fill(2, 3, 3, 2, Pal.orange); c.set(1, 3, Pal.orangeDark)
        case .sweat:
            break
        }
        return c
    }

    /// 128 px long plank strip; shorter planks are sub-textures of this.
    static func plankStrip(length: Int = 128) -> PixelCanvas {
        var c = PixelCanvas(width: length, height: 2)
        for x in 0..<length {
            let knot = (x * 7 + 3) % 11 == 0
            let grain = (x * 5) % 9 == 0
            c.set(x, 0, knot ? Pal.woodGrain : (grain ? Pal.wood : Pal.woodLight))
            c.set(x, 1, grain ? Pal.woodGrain : Pal.wood)
        }
        return c
    }

    /// 4 px wide ladder strip, 128 px tall (rails with a rung every 3 px).
    static func ladderStrip(length: Int = 128) -> PixelCanvas {
        var c = PixelCanvas(width: 4, height: length)
        for y in 0..<length {
            c.set(0, y, Pal.woodDark)
            c.set(3, y, Pal.woodDark)
            if y % 3 == 1 {
                c.set(1, y, Pal.wood)
                c.set(2, y, Pal.woodLight)
            }
        }
        return c
    }

    /// Lattice crane mast, 3 px wide.
    static func mastStrip(length: Int = 64) -> PixelCanvas {
        var c = PixelCanvas(width: 3, height: length)
        for y in 0..<length {
            c.set(0, y, Pal.yellow)
            c.set(2, y, Pal.yellowDark)
            if y % 2 == 0 { c.set(1, y, Pal.yellowDark) }
        }
        return c
    }

    /// Lattice jib, 3 px tall.
    static func jibStrip(length: Int = 64) -> PixelCanvas {
        var c = PixelCanvas(width: length, height: 3)
        for x in 0..<length {
            c.set(x, 0, Pal.yellow)
            c.set(x, 2, Pal.yellowDark)
            if x % 2 == 0 { c.set(x, 1, Pal.yellowDark) }
        }
        return c
    }

    /// Template image for the menu bar: a hard hat over a tiny scaffold, 18x18.
    static func menuBarIcon() -> PixelCanvas {
        let k = Pal.ink
        return make([
            "..................",
            "..................",
            ".......kkkk.......",
            ".....kkkkkkkk.....",
            "....kkk.kkkkkk....",
            "...kkk.kkkkkkkk...",
            "...kkkkkkkkkkkk...",
            "..kkkkkkkkkkkkkk..",
            ".kkkkkkkkkkkkkkkk.",
            ".kkkkkkkkkkkkkkkk.",
            "..................",
            "..k...k....k...k..",
            "..kkkkkkkkkkkkkk..",
            "..k.k.k....k.k.k..",
            "..k..kk....kk..k..",
            "..kkkkkkkkkkkkkk..",
            "..k............k..",
            "..................",
        ], palette: ["k": k])
    }

    private static func make(_ rows: [String], palette: [Character: RGBA]? = nil) -> PixelCanvas {
        let w = rows.map(\.count).max() ?? 0
        var c = PixelCanvas(width: w, height: rows.count)
        c.stamp(rows, palette: palette ?? p)
        return c
    }
}
