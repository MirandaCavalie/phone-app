import Foundation

/// On-device shaking detector using the classic seismology STA/LTA trigger:
/// the short-term average of ground motion suddenly towering over its long-term
/// average. It runs on the phone's accelerometer, needs no network, and only says
/// "posible sismo" — corroboration from nearby phones is what makes it confident.
public struct SeismicDetector: Sendable {
    public struct Configuration: Sendable {
        public var shortWindow: TimeInterval = 0.5
        public var longWindow: TimeInterval = 10
        public var triggerRatio: Double = 4
        /// Ignore anything below this short-term amplitude, in g (a table tap is ~0.01 g).
        public var minimumAmplitude: Double = 0.04
        /// Shaking must persist this long; footsteps and bumps are shorter.
        public var minimumDuration: TimeInterval = 1.2
        public var cooldown: TimeInterval = 60

        public init() {}
    }

    private struct Sample: Sendable {
        let time: TimeInterval
        let magnitude: Double
    }

    public let configuration: Configuration
    private var samples: [Sample] = []
    private var triggeredSince: TimeInterval?
    private var peak: Double = 0
    private var lastEventAt: TimeInterval?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Feed one user-acceleration sample (gravity removed), in g. Returns an event once
    /// shaking has been sustained long enough.
    public mutating func ingest(time: TimeInterval, x: Double, y: Double, z: Double) -> SeismicEvent? {
        let magnitude = (x * x + y * y + z * z).squareRoot()
        samples.append(Sample(time: time, magnitude: magnitude))
        samples.removeAll { time - $0.time > configuration.longWindow }

        guard let first = samples.first, time - first.time >= configuration.longWindow * 0.5 else { return nil }

        let short = samples.filter { time - $0.time <= configuration.shortWindow }
        let sta = short.map(\.magnitude).reduce(0, +) / Double(max(1, short.count))
        // The long-term average excludes the triggering burst, so sustained shaking stays detectable.
        let background = samples.filter { time - $0.time > configuration.shortWindow * 4 }
        let lta = max(0.002, background.map(\.magnitude).reduce(0, +) / Double(max(1, background.count)))

        let shaking = sta >= configuration.minimumAmplitude && sta / lta >= configuration.triggerRatio
        if shaking || (triggeredSince != nil && sta >= configuration.minimumAmplitude) {
            if triggeredSince == nil { triggeredSince = time; peak = 0 }
            peak = max(peak, short.map(\.magnitude).max() ?? 0)
        } else {
            triggeredSince = nil
            return nil
        }

        guard let start = triggeredSince,
              time - start >= configuration.minimumDuration,
              lastEventAt.map({ time - $0 >= configuration.cooldown }) ?? true else { return nil }

        lastEventAt = time
        triggeredSince = nil
        return SeismicEvent(peakAcceleration: peak, duration: time - start)
    }
}

public struct SeismicEvent: Equatable, Sendable {
    public let peakAcceleration: Double
    public let duration: TimeInterval

    public init(peakAcceleration: Double, duration: TimeInterval) {
        self.peakAcceleration = peakAcceleration
        self.duration = duration
    }

    /// Rough perceived intensity from peak acceleration (after Wald et al., 1999).
    public var intensity: SeismicIntensity {
        switch peakAcceleration {
        case ..<0.039: .light
        case ..<0.092: .moderate
        case ..<0.18: .strong
        default: .severe
        }
    }
}

public enum SeismicIntensity: String, Codable, Sendable {
    case light, moderate, strong, severe

    public var displayName: String {
        switch self {
        case .light: "leve"
        case .moderate: "moderado"
        case .strong: "fuerte"
        case .severe: "muy fuerte"
        }
    }
}

/// "My phone felt shaking" — gossiped so nearby phones can corroborate each other.
public struct SeismicReport: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let deviceID: String
    public let area: String
    public let peakAcceleration: Double
    public let detectedAt: Date

    public init(id: UUID = UUID(), deviceID: String, area: String, peakAcceleration: Double, detectedAt: Date) {
        self.id = id
        self.deviceID = deviceID
        self.area = area
        self.peakAcceleration = peakAcceleration
        self.detectedAt = detectedAt
    }
}

public enum SeismicCorroboration {
    public static let window: TimeInterval = 45

    /// Distinct phones (including this one) that felt shaking around `date`.
    public static func devices(near date: Date, in reports: [SeismicReport]) -> Set<String> {
        Set(reports.filter { abs($0.detectedAt.timeIntervalSince(date)) <= window }.map(\.deviceID))
    }

    public static func isConfirmed(near date: Date, in reports: [SeismicReport]) -> Bool {
        devices(near: date, in: reports).count >= 2
    }
}
