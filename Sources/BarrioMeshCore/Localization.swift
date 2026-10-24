import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    public var id: String { rawValue }
    public var shortName: String { rawValue.uppercased() }
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// The language the agent speaks. Strings are written bilingually at the call site with `t(es, en)`,
/// so a translation can never drift away from the sentence it translates.
public enum Lang {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: AppLanguage = .spanish

    public static var current: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    public static var isSpanish: Bool { current == .spanish }
}

/// Spanish first, English second.
public func t(_ spanish: String, _ english: String) -> String {
    Lang.isSpanish ? spanish : english
}
