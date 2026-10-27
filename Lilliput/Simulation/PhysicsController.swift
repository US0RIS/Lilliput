import Foundation
import CoreGraphics

/// Damped spring used for loose props that lag behind a moving window and settle.
struct Spring2D {
    var offset: CGVector = .zero
    var velocity: CGVector = .zero

    mutating func step(dt: CGFloat, drive: CGVector, stiffness: CGFloat = 170, damping: CGFloat = 11, limit: CGFloat = 3) {
        guard dt > 0 else { return }
        let ax = -stiffness * offset.dx - damping * velocity.dx + drive.dx
        let ay = -stiffness * offset.dy - damping * velocity.dy + drive.dy
        velocity.dx += ax * dt
        velocity.dy += ay * dt
        offset.dx += velocity.dx * dt
        offset.dy += velocity.dy * dt
        if abs(offset.dx) > limit { offset.dx = limit * (offset.dx < 0 ? -1 : 1); velocity.dx *= -0.3 }
        if abs(offset.dy) > limit { offset.dy = limit * (offset.dy < 0 ? -1 : 1); velocity.dy *= -0.3 }
    }

    var isSettled: Bool {
        abs(offset.dx) < 0.05 && abs(offset.dy) < 0.05 && abs(velocity.dx) < 0.1 && abs(velocity.dy) < 0.1
    }
}

/// Simple pendulum for crane hooks and pulley buckets, driven by the horizontal
/// acceleration of the window it hangs from.
struct Pendulum {
    var angle: CGFloat = 0
    var angularVelocity: CGFloat = 0

    mutating func step(dt: CGFloat, length: CGFloat, accelX: CGFloat, gravity: CGFloat = 380, damping: CGFloat = 1.6) {
        guard dt > 0, length > 1 else { return }
        let alpha = -(gravity / length) * sin(angle) - (accelX / length) * cos(angle) - damping * angularVelocity
        angularVelocity += alpha * dt
        angle += angularVelocity * dt
        angle = max(-0.9, min(0.9, angle))
    }
}

/// Estimates velocity and acceleration of a window from successive positions.
struct MotionTracker {
    private(set) var velocity: CGVector = .zero
    private(set) var acceleration: CGVector = .zero
    private var lastPosition: CGPoint?
    private var lastVelocity: CGVector = .zero

    var speed: CGFloat { hypot(velocity.dx, velocity.dy) }

    mutating func update(position: CGPoint, dt: CGFloat) {
        guard dt > 0 else { return }
        guard let last = lastPosition else {
            lastPosition = position
            return
        }
        let raw = CGVector(dx: (position.x - last.x) / dt, dy: (position.y - last.y) / dt)
        // Light smoothing: window positions arrive at the tracker's cadence, not ours.
        let k: CGFloat = 0.45
        velocity = CGVector(dx: velocity.dx + (raw.dx - velocity.dx) * k,
                            dy: velocity.dy + (raw.dy - velocity.dy) * k)
        let rawAcc = CGVector(dx: (velocity.dx - lastVelocity.dx) / dt, dy: (velocity.dy - lastVelocity.dy) / dt)
        acceleration = CGVector(dx: acceleration.dx + (rawAcc.dx - acceleration.dx) * 0.5,
                                dy: acceleration.dy + (rawAcc.dy - acceleration.dy) * 0.5)
        lastVelocity = velocity
        lastPosition = position
    }

    mutating func reset(at position: CGPoint? = nil) {
        velocity = .zero
        acceleration = .zero
        lastVelocity = .zero
        lastPosition = position
    }
}
