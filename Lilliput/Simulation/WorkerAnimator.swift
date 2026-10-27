import Foundation
import CoreGraphics

enum Anim: Equatable {
    case stand
    case walk
    case run
    case carryWalk
    case carryBoxWalk
    case carryStand
    case hammer
    case climb
    case sit
    case stretch
    case sleep
    case brace
    case hang
    case cheer
    case thumbsUp
    case inspect
    case wrench
    case signal
    case clipboard
    case crouch
    case stumble
    case point
    case scratch
    case lookAround
    case argue
}

/// Maps an animation state and its clocks to a concrete sprite pose.
/// Walking and climbing advance by distance travelled, so feet never slide.
enum WorkerAnimator {
    static let hammerPeriod: Double = 0.36
    static let hammerDownAt: Double = 0.22

    static func hammerIsDown(_ t: Double) -> Bool {
        t.truncatingRemainder(dividingBy: hammerPeriod) >= hammerDownAt
    }

    /// Number of hammer impacts that have happened by time t.
    static func hammerImpacts(by t: Double) -> Int {
        guard t >= hammerDownAt else { return 0 }
        return Int((t - hammerDownAt) / hammerPeriod) + 1
    }

    static func pose(_ anim: Anim, t: Double, walkPhase: CGFloat, climbPhase: CGFloat, blink: Bool) -> Pose {
        switch anim {
        case .stand, .lookAround:
            return .stand(blink: blink)
        case .walk:
            return .walk(Int(walkPhase / 2.5) % 4)
        case .run:
            return .walk(Int(walkPhase / 3.2) % 4)
        case .carryWalk:
            return .carry(Int(walkPhase / 2.5) % 4)
        case .carryBoxWalk:
            return .carryBox(Int(walkPhase / 2.5) % 4)
        case .carryStand:
            return .carryStand
        case .hammer:
            return .hammer(up: !hammerIsDown(t))
        case .climb:
            return .climb(Int(climbPhase / 2.5) % 2)
        case .sit:
            return .sit
        case .stretch:
            return .stretch
        case .sleep:
            return .sleep
        case .brace:
            return .brace
        case .hang:
            return .hang
        case .cheer:
            return .cheer(Int(t / 0.22) % 2)
        case .thumbsUp:
            return .thumbsUp
        case .inspect:
            return .blueprint(look: t.truncatingRemainder(dividingBy: 1.8) > 0.9)
        case .wrench:
            return .wrench(Int(t / 0.28) % 2)
        case .signal:
            return .signal(Int(t / 0.35) % 2)
        case .clipboard:
            return .clipboard(Int(t / 0.5) % 2)
        case .crouch:
            return .crouch
        case .stumble:
            return .stumble
        case .point:
            return .point
        case .scratch:
            return .scratchHead
        case .argue:
            return t.truncatingRemainder(dividingBy: 1.0) < 0.5 ? .point : .scratchHead
        }
    }

    /// Vertical offset (art px) layered on top of the pose for bouncy animations.
    static func yOffset(_ anim: Anim, t: Double) -> CGFloat {
        switch anim {
        case .cheer:
            return Int(t / 0.22) % 2 == 1 ? 2 : 0
        case .stumble:
            return CGFloat(Int(t / 0.12) % 2)
        default:
            return 0
        }
    }
}
