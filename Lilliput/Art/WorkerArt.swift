import Foundation

/// Appearance of one crew member. All crew share the same body plan so they read as
/// one coherent cast, but differ in hat, clothing, skin tone, hair and build.
struct WorkerStyle: Hashable {
    var hat: RGBA
    var hatShade: RGBA
    var hatLight: RGBA
    var skin: RGBA
    var skinShade: RGBA
    var hair: RGBA
    var shirt: RGBA
    var shirtShade: RGBA
    var vest: RGBA?
    var stripe: RGBA
    var pants: RGBA
    var pantsShade: RGBA
    var boots: RGBA
    var bulky = false
    var mustache = false
    var ponytail = false

    static let yellowHat = (RGBA(0xF2C23A), RGBA(0xC08E22), RGBA(0xFBE08A))
    static let orangeHat = (RGBA(0xEE8A2E), RGBA(0xB65E1E), RGBA(0xF8B672))

    static let crew: [WorkerStyle] = [
        // 0: classic hi-vis vest over blue shirt, denim.
        WorkerStyle(hat: yellowHat.0, hatShade: yellowHat.1, hatLight: yellowHat.2,
                    skin: RGBA(0xF0C29A), skinShade: RGBA(0xCF9B74), hair: RGBA(0x5A3A24),
                    shirt: RGBA(0x4F79B7), shirtShade: RGBA(0x395A8C), vest: RGBA(0xEE7D2B), stripe: RGBA(0xF6EFD8),
                    pants: RGBA(0x3D5579), pantsShade: RGBA(0x2C3E5A), boots: RGBA(0x5A3B26)),
        // 1: stocky, orange hat, green work shirt, brown trousers, mustache.
        WorkerStyle(hat: orangeHat.0, hatShade: orangeHat.1, hatLight: orangeHat.2,
                    skin: RGBA(0xB97A52), skinShade: RGBA(0x93593A), hair: RGBA(0x2E211B),
                    shirt: RGBA(0x5E8B4E), shirtShade: RGBA(0x466A3A), vest: nil, stripe: RGBA(0xE9E2C8),
                    pants: RGBA(0x7A5638), pantsShade: RGBA(0x5B3F29), boots: RGBA(0x3A2A20),
                    bulky: true, mustache: true),
        // 2: red flannel, grey pants, ponytail.
        WorkerStyle(hat: yellowHat.0, hatShade: yellowHat.1, hatLight: yellowHat.2,
                    skin: RGBA(0xF4CDA8), skinShade: RGBA(0xD5A47E), hair: RGBA(0xA3532C),
                    shirt: RGBA(0xC4473C), shirtShade: RGBA(0x93322B), vest: nil, stripe: RGBA(0xEFE4CF),
                    pants: RGBA(0x6C717C), pantsShade: RGBA(0x50545E), boots: RGBA(0x4A3527),
                    ponytail: true),
        // 3: teal shirt with yellow vest, denim.
        WorkerStyle(hat: orangeHat.0, hatShade: orangeHat.1, hatLight: orangeHat.2,
                    skin: RGBA(0x8C5A3C), skinShade: RGBA(0x6C432B), hair: RGBA(0x1F1814),
                    shirt: RGBA(0x3E8C8A), shirtShade: RGBA(0x2D6A68), vest: RGBA(0xE3CE45), stripe: RGBA(0xF4F2E6),
                    pants: RGBA(0x40577D), pantsShade: RGBA(0x2E405E), boots: RGBA(0x4B3424)),
        // 4: navy coveralls, yellow hat.
        WorkerStyle(hat: yellowHat.0, hatShade: yellowHat.1, hatLight: yellowHat.2,
                    skin: RGBA(0xE2AE84), skinShade: RGBA(0xBE8862), hair: RGBA(0x3B2A1E),
                    shirt: RGBA(0x34466B), shirtShade: RGBA(0x26334F), vest: nil, stripe: RGBA(0xE9D86A),
                    pants: RGBA(0x34466B), pantsShade: RGBA(0x26334F), boots: RGBA(0x2E2520),
                    bulky: true),
        // 5: mustard shirt with orange vest, khaki.
        WorkerStyle(hat: orangeHat.0, hatShade: orangeHat.1, hatLight: orangeHat.2,
                    skin: RGBA(0xD49A6A), skinShade: RGBA(0xAE774C), hair: RGBA(0x6B4A2B),
                    shirt: RGBA(0xC9A048), shirtShade: RGBA(0x9C7A34), vest: RGBA(0xE86F2A), stripe: RGBA(0xF3EEDC),
                    pants: RGBA(0x8D7F5E), pantsShade: RGBA(0x6E6347), boots: RGBA(0x4B3627),
                    mustache: true),
    ]

    /// The supervisor wears a white hat and a crisp shirt.
    static let supervisor = WorkerStyle(hat: RGBA(0xF4F2EC), hatShade: RGBA(0xC9C6BC), hatLight: RGBA(0xFFFFFF),
                                        skin: RGBA(0xEDBE95), skinShade: RGBA(0xC99770), hair: RGBA(0x8A8780),
                                        shirt: RGBA(0xE7E3D6), shirtShade: RGBA(0xBDB8AA), vest: RGBA(0xE6D24A), stripe: RGBA(0xF7F5EC),
                                        pants: RGBA(0x4A4F5C), pantsShade: RGBA(0x363A44), boots: RGBA(0x2B2522),
                                        mustache: true)
}

enum Pose: Hashable {
    case stand(blink: Bool)
    case walk(Int)
    case carry(Int)
    case carryStand
    case carryBox(Int)
    case hammer(up: Bool)
    case climb(Int)
    case sit
    case stretch
    case sleep
    case brace
    case hang
    case cheer(Int)
    case thumbsUp
    case blueprint(look: Bool)
    case wrench(Int)
    case signal(Int)
    case clipboard(Int)
    case crouch
    case stumble
    case point
    case scratchHead
}

enum WorkerArt {
    static let canvasSize = 16

    private enum Arm {
        case down, swingF, swingB, forward, forwardDown, up, high, carryHigh
        case hammerUp, hammerDown, thumb, point, scratch, out, outBack, climbUp, climbDown, hold
    }

    private enum Legs {
        case stand, walk(Int), sit, wide, climb(Int), dangle
    }

    private enum Tool {
        case none, hammerUp, hammerDown, wrench(Int), blueprint, clipboard
    }

    private enum Eyes {
        case open, closed, up, wide
    }

    private static func armPixels(_ arm: Arm) -> (sleeves: [(Int, Int)], hand: (Int, Int)?) {
        switch arm {
        case .down: return ([(0, 0), (0, 1)], (0, 2))
        case .swingF: return ([(0, 0), (0, 1)], (1, 2))
        case .swingB: return ([(0, 0), (0, 1)], (-1, 2))
        case .forward: return ([(0, 0), (1, 0)], (2, 0))
        case .forwardDown: return ([(0, 0), (1, 1)], (2, 1))
        case .hold: return ([(0, 0), (1, 0)], (2, 0))
        case .up: return ([(0, 0), (0, -1), (0, -2)], (0, -3))
        case .high: return ([(0, 0), (0, -1), (0, -2), (0, -3), (0, -4)], (0, -5))
        case .carryHigh: return ([(0, 0), (0, -1), (0, -2), (0, -3), (0, -4), (0, -5)], (0, -6))
        case .hammerUp: return ([(0, 0), (0, -1), (0, -2)], (0, -3))
        case .hammerDown: return ([(0, 0), (1, 0)], (2, 1))
        case .thumb: return ([(0, 0), (1, 0)], (2, 0))
        case .point: return ([(0, 0), (1, -1)], (2, -2))
        case .scratch: return ([(0, 0), (0, -1)], (-1, -2))
        case .out: return ([(0, 0), (1, 0)], (2, -1))
        case .outBack: return ([(0, 0), (-1, 0)], (-2, -1))
        case .climbUp: return ([(0, 0), (0, -1), (0, -2)], (0, -3))
        case .climbDown: return ([(0, 0), (0, 1)], (0, 2))
        }
    }

    static func draw(_ s: WorkerStyle, _ pose: Pose) -> PixelCanvas {
        var c = PixelCanvas(width: canvasSize, height: canvasSize)

        var bob = 0
        var legs: Legs = .stand
        var back: Arm = .down
        var front: Arm = .down
        var tool: Tool = .none
        var eyes: Eyes = .open
        var backView = false
        var headDrop = 0

        switch pose {
        case .stand(let blink):
            eyes = blink ? .closed : .open
        case .walk(let i):
            legs = .walk(i); bob = i % 2
            switch i % 4 {
            case 0: front = .swingF; back = .swingB
            case 2: front = .swingB; back = .swingF
            default: break
            }
        case .carry(let i):
            legs = .walk(i); bob = i % 2; front = .carryHigh; back = .carryHigh
        case .carryStand:
            front = .carryHigh; back = .carryHigh
        case .carryBox(let i):
            legs = .walk(i); bob = i % 2; front = .down
            back = (i % 4 == 0) ? .swingB : ((i % 4 == 2) ? .swingF : .down)
        case .hammer(let up):
            front = up ? .hammerUp : .hammerDown
            tool = up ? .hammerUp : .hammerDown
            bob = up ? 0 : 1
            legs = up ? .stand : .wide
        case .climb(let i):
            backView = true
            legs = .climb(i)
            front = i % 2 == 0 ? .climbUp : .climbDown
            back = i % 2 == 0 ? .climbDown : .climbUp
        case .sit:
            legs = .sit; bob = 2; front = .forwardDown
        case .stretch:
            legs = .sit; bob = 2; front = .high; back = .high; eyes = .closed
        case .sleep:
            legs = .sit; bob = 2; headDrop = 1; eyes = .closed
        case .brace:
            legs = .wide; bob = 1; front = .out; back = .outBack; eyes = .wide
        case .hang:
            legs = .dangle; front = .high; back = .high; eyes = .wide
        case .cheer(let i):
            legs = i % 2 == 0 ? .stand : .wide
            front = i % 2 == 0 ? .high : .up
            back = i % 2 == 0 ? .high : .up
            eyes = .closed
        case .thumbsUp:
            front = .thumb
        case .blueprint(let look):
            front = .hold; back = .forward; tool = .blueprint
            eyes = look ? .up : .open
        case .wrench(let i):
            front = .forward; tool = .wrench(i)
        case .signal(let i):
            front = i % 2 == 0 ? .up : .point
        case .clipboard(let i):
            front = .hold; tool = .clipboard
            back = i % 2 == 0 ? .down : .forward
        case .crouch:
            legs = .wide; bob = 2; front = .forwardDown
        case .stumble:
            legs = .walk(2); front = .up; back = .outBack; eyes = .wide
        case .point:
            front = .point
        case .scratchHead:
            front = .scratch
        }

        let top = 4 + bob
        let bodyL = s.bulky ? 4 : 5
        let bodyR = s.bulky ? 11 : 10
        let shoulderY = top + 6
        let backShoulder = bodyL - 1
        let frontShoulder = bodyR + 1

        func drawArm(_ arm: Arm, shoulderX: Int, isFront: Bool) {
            let px = armPixels(arm)
            let sleeve = isFront ? s.shirt : s.shirtShade
            for (dx, dy) in px.sleeves { c.set(shoulderX + dx, shoulderY + dy, sleeve) }
            if let h = px.hand { c.set(shoulderX + h.0, shoulderY + h.1, isFront ? s.skin : s.skinShade) }
            if isFront, case .thumb = arm, let h = px.hand {
                c.set(shoulderX + h.0, shoulderY + h.1 - 1, s.skin)
            }
        }

        // 1. Back arm (behind torso).
        if !backView { drawArm(back, shoulderX: backShoulder, isFront: false) }

        // 2. Legs and boots.
        let hipY = 13
        func leg(_ x: Int, _ color: RGBA, toe: Bool = true) {
            c.fill(x, 14, 2, 1, color)
            c.fill(x, 15, toe ? 3 : 2, 1, s.boots)
        }
        switch legs {
        case .stand:
            c.hline(bodyL, bodyR, hipY, s.pants)
            leg(5, s.pantsShade, toe: false)
            leg(8, s.pants)
        case .walk(let i):
            c.hline(bodyL, bodyR, hipY, s.pants)
            let pairs: [(Int, Int)] = [(9, 4), (7, 6), (4, 9), (6, 7)]
            let (a, b) = pairs[((i % 4) + 4) % 4]
            leg(b, s.pantsShade)
            leg(a, s.pants)
        case .sit:
            c.hline(bodyL, bodyR, 15, s.pants)
            c.hline(bodyR + 1, bodyR + 2, 15, s.pants)
            c.set(bodyR + 3, 14, s.boots)
            c.set(bodyR + 3, 15, s.boots)
        case .wide:
            c.hline(bodyL, bodyR, hipY, s.pants)
            c.fill(3, 14, 2, 1, s.pantsShade)
            c.fill(10, 14, 2, 1, s.pants)
            c.fill(2, 15, 3, 1, s.boots)
            c.fill(10, 15, 3, 1, s.boots)
        case .climb(let i):
            c.hline(bodyL, bodyR, hipY, s.pants)
            if i % 2 == 0 {
                c.fill(5, 14, 2, 1, s.pantsShade); c.fill(5, 15, 2, 1, s.boots)
                c.fill(8, 13, 2, 1, s.pants); c.fill(8, 14, 2, 1, s.boots)
            } else {
                c.fill(5, 13, 2, 1, s.pantsShade); c.fill(5, 14, 2, 1, s.boots)
                c.fill(8, 14, 2, 1, s.pants); c.fill(8, 15, 2, 1, s.boots)
            }
        case .dangle:
            c.hline(bodyL, bodyR, hipY, s.pants)
            c.fill(6, 14, 4, 1, s.pants)
            c.fill(6, 15, 4, 1, s.boots)
        }

        // 3. Torso.
        let torsoTop = top + 6
        c.fill(bodyL, torsoTop, bodyR - bodyL + 1, 3, s.shirt)
        c.vline(bodyL, torsoTop, torsoTop + 2, s.shirtShade)
        if let vest = s.vest {
            c.fill(bodyL + 1, torsoTop, bodyR - bodyL - 1, 3, vest)
            c.hline(bodyL + 1, bodyR - 1, torsoTop + 1, s.stripe)
            if backView {
                c.vline((bodyL + bodyR) / 2, torsoTop, torsoTop + 2, s.stripe)
            }
        } else if !backView {
            c.set(bodyR - 2, torsoTop + 1, s.shirtShade)
            c.set(bodyL + 2, torsoTop + 2, s.shirtShade)
        }
        // Belt.
        if case .sit = legs {} else if case .dangle = legs {} else {
            c.hline(bodyL, bodyR, hipY, s.pantsShade)
            c.set((bodyL + bodyR) / 2 + 1, hipY, Pal.yellowDark)
        }

        // 4. Head and hat.
        let ht = top + headDrop
        let faceTop = ht + 3
        if backView {
            c.fill(5, faceTop, 6, 2, s.hair)
            c.fill(6, faceTop + 2, 4, 1, s.skinShade)
            c.set(5, faceTop + 1, s.skin)
            c.set(10, faceTop + 1, s.skin)
        } else {
            c.fill(5, faceTop, 6, 3, s.skin)
            c.vline(5, faceTop, faceTop + 1, s.hair)
            if s.ponytail {
                c.vline(4, faceTop, faceTop + 2, s.hair)
                c.set(3, faceTop + 2, s.hair)
            }
            switch eyes {
            case .open:
                c.set(7, faceTop + 1, Pal.ink); c.set(9, faceTop + 1, Pal.ink)
            case .closed:
                c.set(7, faceTop + 1, s.skinShade); c.set(9, faceTop + 1, s.skinShade)
            case .up:
                c.set(7, faceTop, Pal.ink); c.set(9, faceTop, Pal.ink)
            case .wide:
                c.set(7, faceTop + 1, Pal.ink); c.set(9, faceTop + 1, Pal.ink)
                c.set(8, faceTop + 2, Pal.inkSoft)
            }
            if s.mustache {
                c.hline(7, 9, faceTop + 2, s.hair)
            } else if case .wide = eyes {
            } else {
                c.set(8, faceTop + 2, s.skinShade)
            }
            c.set(10, faceTop + 2, s.skinShade)
        }
        // Hat: crown, highlight, brim.
        c.hline(6, 9, ht, s.hat)
        c.hline(5, 10, ht + 1, s.hat)
        c.set(7, ht, s.hatLight)
        c.set(6, ht + 1, s.hatLight)
        c.set(10, ht + 1, s.hatShade)
        if backView {
            c.hline(4, 11, ht + 2, s.hatShade)
        } else {
            c.hline(4, 11, ht + 2, s.hatShade)
            c.set(11, ht + 2, s.hat)
        }

        // 5. Front arm and tool.
        drawArm(front, shoulderX: backView ? frontShoulder : frontShoulder, isFront: true)
        if backView {
            drawArm(back, shoulderX: backShoulder, isFront: true)
        }

        let hand = armPixels(front).hand.map { (frontShoulder + $0.0, shoulderY + $0.1) }
        if let h = hand {
            let hx = h.0
            let hy = h.1
            switch tool {
            case .none:
                break
            case .hammerUp:
                c.set(hx, hy - 1, Pal.woodDark)
                c.set(hx, hy - 2, Pal.woodDark)
                c.hline(hx - 1, hx + 1, hy - 3, Pal.steelDark)
                c.set(hx + 1, hy - 3, Pal.steel)
            case .hammerDown:
                c.set(hx + 1, hy, Pal.woodDark)
                c.set(hx + 2, hy, Pal.woodDark)
                c.vline(hx + 3, hy - 1, hy + 1, Pal.steelDark)
                c.set(hx + 3, hy - 1, Pal.steel)
            case .wrench(let i):
                if i % 2 == 0 {
                    c.set(hx + 1, hy, Pal.steel)
                    c.set(hx + 2, hy, Pal.steel)
                    c.set(hx + 3, hy - 1, Pal.steelLight)
                    c.set(hx + 3, hy + 1, Pal.steelLight)
                } else {
                    c.set(hx + 1, hy - 1, Pal.steel)
                    c.set(hx + 2, hy - 2, Pal.steel)
                    c.set(hx + 2, hy - 3, Pal.steelLight)
                    c.set(hx + 3, hy - 2, Pal.steelLight)
                }
            case .blueprint:
                c.fill(hx - 2, hy - 2, 5, 3, Pal.blueprint)
                c.hline(hx - 1, hx + 1, hy - 1, Pal.blueprintLight)
                c.set(hx - 2, hy - 2, Pal.blueprintLight)
            case .clipboard:
                c.fill(hx, hy - 3, 3, 4, Pal.woodDark)
                c.fill(hx, hy - 2, 3, 3, Pal.white)
                c.set(hx + 1, hy - 3, Pal.steel)
                c.set(hx + 1, hy - 1, Pal.inkSoft)
            }
        }

        return c
    }
}
