import Foundation

/// The permissions the person grants their agent ahead of time, while calm.
/// During an outage the agent acts alone inside these limits and asks for everything else.
public struct AgentPolicy: Codable, Equatable, Sendable {
    /// Turn on emergency mode automatically when the phone loses internet.
    public var activateOnOutage: Bool
    /// Start a cancellable countdown when the phone feels an earthquake; activate at once if nearby phones felt it too.
    public var activateOnShaking: Bool
    /// Activate emergency mode when an official source reports a dangerous quake or tsunami nearby.
    public var activateOnOfficialAlert: Bool
    /// Broadcast "estoy bien" to the family circle as soon as emergency mode starts.
    public var autoCheckIn: Bool
    /// Publish the household's standing needs without asking.
    public var autoPublishNeeds: Bool
    /// Publish shareable supplies (above the reserve) without asking.
    public var autoPublishOffers: Bool
    /// Accept a match where this household receives help.
    public var autoAcceptIncomingHelp: Bool
    /// Commit to give up to this many units per match without asking. 0 means always ask.
    public var autoGiveLimit: Int

    public init(
        activateOnOutage: Bool = true,
        activateOnShaking: Bool = true,
        activateOnOfficialAlert: Bool = true,
        autoCheckIn: Bool = true,
        autoPublishNeeds: Bool = true,
        autoPublishOffers: Bool = true,
        autoAcceptIncomingHelp: Bool = true,
        autoGiveLimit: Int = 3
    ) {
        self.activateOnOutage = activateOnOutage
        self.activateOnShaking = activateOnShaking
        self.activateOnOfficialAlert = activateOnOfficialAlert
        self.autoCheckIn = autoCheckIn
        self.autoPublishNeeds = autoPublishNeeds
        self.autoPublishOffers = autoPublishOffers
        self.autoAcceptIncomingHelp = autoAcceptIncomingHelp
        self.autoGiveLimit = max(0, autoGiveLimit)
    }

    /// Resources that always need a human, whatever the policy says.
    public init(from decoder: Decoder) throws {
        // Policies saved before a permission existed get that permission's default.
        let defaults = AgentPolicy()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activateOnOutage = try container.decodeIfPresent(Bool.self, forKey: .activateOnOutage) ?? defaults.activateOnOutage
        activateOnShaking = try container.decodeIfPresent(Bool.self, forKey: .activateOnShaking) ?? defaults.activateOnShaking
        activateOnOfficialAlert = try container.decodeIfPresent(Bool.self, forKey: .activateOnOfficialAlert) ?? defaults.activateOnOfficialAlert
        autoCheckIn = try container.decodeIfPresent(Bool.self, forKey: .autoCheckIn) ?? defaults.autoCheckIn
        autoPublishNeeds = try container.decodeIfPresent(Bool.self, forKey: .autoPublishNeeds) ?? defaults.autoPublishNeeds
        autoPublishOffers = try container.decodeIfPresent(Bool.self, forKey: .autoPublishOffers) ?? defaults.autoPublishOffers
        autoAcceptIncomingHelp = try container.decodeIfPresent(Bool.self, forKey: .autoAcceptIncomingHelp) ?? defaults.autoAcceptIncomingHelp
        autoGiveLimit = try container.decodeIfPresent(Int.self, forKey: .autoGiveLimit) ?? defaults.autoGiveLimit
    }

    public static let alwaysAskResources: Set<ResourceKind> = [.medicine, .firstAid]

    public func allowsPublishing(_ kind: PostKind, resource: ResourceKind) -> Bool {
        guard !Self.alwaysAskResources.contains(resource) else { return false }
        return kind == .need ? autoPublishNeeds : autoPublishOffers
    }

    public func allowsAccepting(role: PostKind, resource: ResourceKind, quantity: Int) -> Bool {
        guard !Self.alwaysAskResources.contains(resource) else { return false }
        switch role {
        case .need: return autoAcceptIncomingHelp
        case .offer: return autoGiveLimit > 0 && quantity <= autoGiveLimit
        }
    }
}
