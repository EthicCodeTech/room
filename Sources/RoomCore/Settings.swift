import Foundation

public enum AdvisorMode: String, Codable, Sendable, CaseIterable {
    case off, onDevice, claude
    public var title: String {
        switch self { case .off: "Off"; case .onDevice: "On-device (private)"; case .claude: "Claude (your API key)" }
    }
}

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark
    public var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
}

/// How much the trackpad answers you.
/// Cinnabar says haptics answer actions and never fire on hover or scroll, so hover detents are opt-in (Full).
public enum HapticLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case off, standard, full
    public var title: String { switch self { case .off: "Off"; case .standard: "Standard"; case .full: "Full" } }
    public var blurb: String {
        switch self {
        case .off: "No trackpad feedback."
        case .standard: "Feedback for things you do: taps, choices, confirmations and warnings."
        case .full: "Everything in Standard, plus gentle detents as you move across the map and when the water hits the glass."
        }
    }
    private var rank: Int { switch self { case .off: 0; case .standard: 1; case .full: 2 } }
    public static func < (l: HapticLevel, r: HapticLevel) -> Bool { l.rank < r.rank }
    /// Whether a pattern that needs `required` should play at this level.
    public func permits(_ required: HapticLevel) -> Bool { self != .off && self >= required }
}

public struct AppSettings: Codable, Sendable, Equatable {
    /// Follows the Mac's light or dark setting unless the user picks one.
    public var appearance: Appearance = .system
    /// Share anonymized decisions to help improve Room. Off until the user turns it on.
    public var learningOptIn = false
    public var learningConsentDate: Date?
    public var advisorMode: AdvisorMode = .onDevice
    public var staleProjectDays = 60
    public var lowSpaceAlertGB = 15
    public var hapticLevel: HapticLevel = .standard
    /// Tilt the liquid with the Mac's accelerometer (undocumented sensor; Macs without it just keep a still tank).
    public var tiltEnabled = true
    public var tilt = TiltCalibration.none
    /// Also keep node_modules and other rebuildable folders in the undo vault for 7 days (caches are always removed directly).
    public var vaultRebuildable = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case appearance, learningOptIn, learningConsentDate, advisorMode, staleProjectDays, lowSpaceAlertGB
        case hapticLevel, haptics, tiltEnabled, tilt, vaultRebuildable
    }

    /// Every field is optional on disk. A settings file written by an older version must never fail to load,
    /// because a failed load silently resets everything, including the tilt calibration.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        learningOptIn = try c.decodeIfPresent(Bool.self, forKey: .learningOptIn) ?? false
        learningConsentDate = try c.decodeIfPresent(Date.self, forKey: .learningConsentDate)
        advisorMode = try c.decodeIfPresent(AdvisorMode.self, forKey: .advisorMode) ?? .onDevice
        staleProjectDays = try c.decodeIfPresent(Int.self, forKey: .staleProjectDays) ?? 60
        lowSpaceAlertGB = try c.decodeIfPresent(Int.self, forKey: .lowSpaceAlertGB) ?? 15
        tiltEnabled = try c.decodeIfPresent(Bool.self, forKey: .tiltEnabled) ?? true
        tilt = try c.decodeIfPresent(TiltCalibration.self, forKey: .tilt) ?? .none
        vaultRebuildable = try c.decodeIfPresent(Bool.self, forKey: .vaultRebuildable) ?? false
        // Older builds had a single on/off switch.
        let legacyOn = try c.decodeIfPresent(Bool.self, forKey: .haptics)
        hapticLevel = try c.decodeIfPresent(HapticLevel.self, forKey: .hapticLevel) ?? (legacyOn == false ? .off : .standard)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(appearance, forKey: .appearance); try c.encode(learningOptIn, forKey: .learningOptIn)
        try c.encodeIfPresent(learningConsentDate, forKey: .learningConsentDate)
        try c.encode(advisorMode, forKey: .advisorMode); try c.encode(staleProjectDays, forKey: .staleProjectDays)
        try c.encode(lowSpaceAlertGB, forKey: .lowSpaceAlertGB); try c.encode(hapticLevel, forKey: .hapticLevel)
        try c.encode(tiltEnabled, forKey: .tiltEnabled); try c.encode(tilt, forKey: .tilt)
        try c.encode(vaultRebuildable, forKey: .vaultRebuildable)
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let paths: AppPaths
    private let lock = NSLock()
    public init(paths: AppPaths) { self.paths = paths }

    public func load() -> AppSettings {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: paths.settings) else { return AppSettings() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    public func save(_ settings: AppSettings) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) { try? data.write(to: paths.settings, options: .atomic) }
    }
}
