import Foundation
import CoreGraphics

typealias WindowID = UInt32

/// Minimal metadata Lilliput keeps about another app's window. No titles, no contents.
struct WindowSnapshot: Equatable {
    let id: WindowID
    var pid: pid_t
    /// Global AppKit coordinates (origin bottom-left of the primary display, y up).
    var frame: CGRect
    var bundleID: String?
}

enum WindowEvent: Equatable {
    /// A window appeared and its geometry has settled.
    case opened(WindowSnapshot, animated: Bool)
    /// Position or size changed.
    case changed(WindowSnapshot)
    /// The window still exists but is no longer on screen (minimized, app hidden, other Space).
    case hidden(WindowID, animated: Bool)
    /// A hidden window came back.
    case restored(WindowSnapshot, animated: Bool)
    /// The window no longer exists.
    case closed(WindowID)
}

enum ScreenGeometry {
    /// Converts a Core Graphics global rect (top-left origin, y down) to AppKit global
    /// coordinates (bottom-left origin, y up) given the primary display height.
    static func appKitRect(fromCG r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func cgRect(fromAppKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Converts a global AppKit rect into the local coordinate space of a display-sized
    /// SpriteKit scene whose origin is the display's bottom-left corner.
    static func sceneRect(fromAppKit r: CGRect, displayFrame: CGRect) -> CGRect {
        r.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    /// The display a window "belongs" to: the one containing the middle of its bottom
    /// edge (where most of the scaffolding lives), else the one it overlaps most.
    static func bestDisplayIndex(for frame: CGRect, displays: [CGRect]) -> Int? {
        let anchor = CGPoint(x: frame.midX, y: frame.minY + min(10, frame.height / 2))
        if let i = displays.firstIndex(where: { $0.contains(anchor) }) { return i }
        var best: (Int, CGFloat)?
        for (i, d) in displays.enumerated() {
            let inter = d.intersection(frame)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > (best?.1 ?? 0) { best = (i, area) }
        }
        return best?.0
    }
}

extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
