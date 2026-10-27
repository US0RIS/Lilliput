import Foundation
import CoreGraphics

enum ConstructionDensity: String, CaseIterable, Identifiable, Codable {
    case sparse, normal, busy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sparse: return "Sparse"
        case .normal: return "Normal"
        case .busy: return "Busy"
        }
    }
    /// Crew size before the per-site limit is applied.
    var crewSize: Int {
        switch self {
        case .sparse: return 2
        case .normal: return 3
        case .busy: return 5
        }
    }
}

enum WorkerSize: String, CaseIterable, Identifiable, Codable {
    case small, normal, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        }
    }
    /// Points per art pixel. Worker art is 12 px tall, so this gives 18 / 21 / 24 pt.
    var pixelScale: CGFloat {
        switch self {
        case .small: return 1.5
        case .normal: return 1.75
        case .large: return 2.0
        }
    }
}

enum AnimationIntensity: String, CaseIterable, Identifiable, Codable {
    case subtle, balanced, playful
    var id: String { rawValue }
    var label: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .playful: return "Playful"
        }
    }
    /// Multiplier on how often special moments and lively reactions happen.
    var liveliness: Double {
        switch self {
        case .subtle: return 0.45
        case .balanced: return 1.0
        case .playful: return 1.7
        }
    }
    /// Multiplier on particle counts and reaction amplitudes.
    var amplitude: CGFloat {
        switch self {
        case .subtle: return 0.6
        case .balanced: return 1.0
        case .playful: return 1.35
        }
    }
    /// Frame rate used while nothing structural is happening.
    var idleFramesPerSecond: Int {
        switch self {
        case .subtle: return 20
        case .balanced: return 30
        case .playful: return 30
        }
    }
}

/// Immutable snapshot of the settings the simulation cares about.
struct SimSettings: Equatable {
    var density: ConstructionDensity = .normal
    var pixelScale: CGFloat = WorkerSize.normal.pixelScale
    var intensity: AnimationIntensity = .balanced
    var specialEvents = true
    var sound = false
    var maxWorkersPerSite = 4
    var paused = false

    var crewSize: Int { max(1, min(density.crewSize, maxWorkersPerSite)) }
}
