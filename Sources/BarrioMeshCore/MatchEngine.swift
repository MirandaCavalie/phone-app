import Foundation

public struct MatchCandidate: Identifiable, Equatable, Sendable {
    public let need: MeshPost
    public let offer: MeshPost
    public let score: Int
    public let reason: String

    public var id: String {
        MatchProposal.makeID(needID: need.id, offerID: offer.id)
    }
}

public enum MatchEngine {
    public static func candidates(
        in posts: [MeshPost],
        at date: Date = Date()
    ) -> [MatchCandidate] {
        let needs = posts.filter { $0.kind == .need && $0.isActive(at: date) }
        let offers = posts.filter { $0.kind == .offer && $0.isActive(at: date) }

        return needs.flatMap { need in
            offers.compactMap { offer in
                guard need.authorID != offer.authorID,
                      need.resource == offer.resource else {
                    return nil
                }

                let enoughQuantity = offer.quantity >= need.quantity
                let sameArea = normalized(need.area) == normalized(offer.area) && !need.area.isEmpty
                let quantityScore = enoughQuantity ? 30 : 10
                let areaScore = sameArea ? 25 : 0
                let urgencyScore = need.urgency.rawValue * 15
                let ageScore = min(15, max(0, Int(date.timeIntervalSince(need.createdAt) / 300)))
                let score = quantityScore + areaScore + urgencyScore + ageScore

                var reasons = [need.resource.displayName]
                if enoughQuantity { reasons.append(t("cantidad suficiente", "enough quantity")) }
                if sameArea { reasons.append(t("misma zona", "same area")) }

                return MatchCandidate(
                    need: need,
                    offer: offer,
                    score: score,
                    reason: reasons.joined(separator: " · ")
                )
            }
        }
        .sorted {
            if $0.score == $1.score {
                return $0.need.createdAt < $1.need.createdAt
            }
            return $0.score > $1.score
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
