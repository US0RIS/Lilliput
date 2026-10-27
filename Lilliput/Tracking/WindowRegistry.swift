import Foundation
import CoreGraphics

/// Turns a stream of raw on-screen window lists into lifecycle events.
///
/// Pure logic with no system calls so it can be unit tested. Identity is the Core
/// Graphics window number, which is stable for the lifetime of a window.
final class WindowRegistry {
    struct Input: Equatable {
        let id: WindowID
        let pid: pid_t
        let frame: CGRect
        let bundleID: String?
    }

    struct Output {
        var events: [WindowEvent] = []
        /// Active (tracked, on-screen) windows, front to back.
        var stacking: [WindowSnapshot] = []
        var stackingChanged = false
    }

    enum State: Equatable {
        case pending(firstSeen: TimeInterval, lastChange: TimeInterval, snapshot: WindowSnapshot)
        case active(WindowSnapshot)
        case hidden(WindowSnapshot)
    }

    /// How long a new window's frame must stay unchanged before construction starts.
    var stabilizeDelay: TimeInterval = 0.25
    /// Minimum age of a new window before construction starts.
    var minimumAge: TimeInterval = 0.2

    private(set) var states: [WindowID: State] = [:]
    private var lastStackIDs: [WindowID] = []

    var activeIDs: [WindowID] {
        states.compactMap { if case .active = $0.value { return $0.key } else { return nil } }
    }

    func reset() {
        states.removeAll()
        lastStackIDs.removeAll()
    }

    /// - Parameters:
    ///   - inputs: eligible on-screen windows, front to back.
    ///   - exists: whether a window that left the screen still exists (minimized / hidden).
    ///   - checkHidden: whether to re-check hidden windows for closure this pass.
    func reconcile(_ inputs: [Input],
                   now: TimeInterval,
                   animated: Bool,
                   checkHidden: Bool,
                   exists: (WindowID) -> Bool) -> Output {
        var out = Output()
        var seen = Set<WindowID>()
        seen.reserveCapacity(inputs.count)

        for input in inputs {
            seen.insert(input.id)
            let snap = WindowSnapshot(id: input.id, pid: input.pid, frame: input.frame, bundleID: input.bundleID)
            switch states[input.id] {
            case .none:
                states[input.id] = .pending(firstSeen: now, lastChange: now, snapshot: snap)
            case .pending(let first, let lastChange, let old)?:
                var change = lastChange
                if !old.frame.approximatelyEquals(snap.frame) { change = now }
                if now - change >= stabilizeDelay, now - first >= minimumAge {
                    states[input.id] = .active(snap)
                    out.events.append(.opened(snap, animated: animated))
                } else {
                    states[input.id] = .pending(firstSeen: first, lastChange: change, snapshot: snap)
                }
            case .active(let old)?:
                if !old.frame.approximatelyEquals(snap.frame) {
                    states[input.id] = .active(snap)
                    out.events.append(.changed(snap))
                }
            case .hidden?:
                states[input.id] = .active(snap)
                out.events.append(.restored(snap, animated: animated))
            }
        }

        for (id, state) in states where !seen.contains(id) {
            switch state {
            case .pending:
                states[id] = nil
            case .active(let snap):
                if exists(id) {
                    states[id] = .hidden(snap)
                    out.events.append(.hidden(id, animated: animated))
                } else {
                    states[id] = nil
                    out.events.append(.closed(id))
                }
            case .hidden:
                if checkHidden, !exists(id) {
                    states[id] = nil
                    out.events.append(.closed(id))
                }
            }
        }

        var stack: [WindowSnapshot] = []
        for input in inputs {
            if case .active(let s)? = states[input.id] { stack.append(s) }
        }
        let ids = stack.map(\.id)
        out.stackingChanged = ids != lastStackIDs
        lastStackIDs = ids
        out.stacking = stack
        return out
    }
}
