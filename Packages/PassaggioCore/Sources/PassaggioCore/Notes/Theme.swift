import Foundation

/// The fixed themes lesson feedback is grouped under. Order is display order and
/// also the order routine exercises run in (breath first, repertoire last).
public enum Theme: String, CaseIterable, Codable, Sendable, Identifiable, Comparable {
    case breathSupport = "breath_support"
    case registrationMix = "registration_mix"
    case placementResonance = "placement_resonance"
    case vowels
    case tensionHabits = "tension_habits"
    case range
    case repertoire

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .breathSupport: "Breath support"
        case .registrationMix: "Registration and mix"
        case .placementResonance: "Placement and resonance"
        case .vowels: "Vowels"
        case .tensionHabits: "Tension and bad habits"
        case .range: "Range"
        case .repertoire: "Repertoire"
        }
    }

    public var systemImage: String {
        switch self {
        case .breathSupport: "wind"
        case .registrationMix: "slider.horizontal.3"
        case .placementResonance: "waveform.path"
        case .vowels: "mouth"
        case .tensionHabits: "exclamationmark.triangle"
        case .range: "arrow.up.and.down"
        case .repertoire: "music.note.list"
        }
    }

    /// One-line definition given to the model so classification is consistent.
    var promptDefinition: String {
        switch self {
        case .breathSupport: "breathing, support, airflow, onset, breath management"
        case .registrationMix: "chest/head voice, mixed voice, register breaks and transitions, the passaggio"
        case .placementResonance: "placement, resonance, forward/back sound, brightness, twang, space"
        case .vowels: "vowel shape, modification, diction and articulation"
        case .tensionHabits: "jaw, tongue, neck, larynx or shoulder tension; pushing, straining; any habit the teacher wants removed"
        case .range: "extending or securing high/low notes, working a specific part of the range"
        case .repertoire: "notes about a specific song: phrasing, interpretation, memorisation, style"
        }
    }

    public static func < (lhs: Theme, rhs: Theme) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
