import Foundation

/// A deterministic neighborhood of agents on a lossy Bluetooth mesh, used as an
/// evaluation harness: every household runs its own `PersonalAgent` on its own copy
/// of the state, phones gossip only with whoever is in range this minute, and every
/// item is signed and verified exactly as on a real phone.
public struct NeighborhoodSimulation {
    public struct Configuration: Sendable {
        public var households = 40
        public var minutes = 90
        /// Probability that a link between two phones in range works in a given minute.
        public var linkReliability = 0.6
        /// Fraction of households within Bluetooth range of each other.
        public var density = 0.18
        public var seed: UInt64 = 2026
        /// Add an attacker that forges "accept" messages and fake check-ins.
        public var includeAttacker = true
        /// Minutes a person takes to look at a question from their agent.
        public var humanResponseMinutes = 3
        /// Share of questions the person approves (the rest are dismissed).
        public var humanApprovalRate = 0.85

        public init() {}
    }

    public struct Report: Sendable, CustomStringConvertible {
        public var households: Int
        public var minutes: Int
        public var neededUnits = 0
        /// Units that could be covered at best, given what neighbors had to share.
        public var achievableUnits = 0
        public var coveredUnits = 0
        public var urgentNeeds = 0
        public var urgentCovered = 0
        public var vulnerableNeeds = 0
        public var vulnerableCovered = 0
        public var agreements = 0
        public var openNegotiations = 0
        public var declinedNegotiations = 0
        public var needsNeverProposed = 0
        public var isolatedHouseholds = 0
        public var medianMinutesToAgreement: Double = 0
        public var overCommitments = 0
        public var forgedItemsAccepted = 0
        public var forgedItemsRejected = 0
        public var familiesReached = 0
        public var familiesTotal = 0
        public var converged = false
        public var pendingHumanDecisions = 0
        public var humanDecisions = 0

        public var coverage: Double { neededUnits == 0 ? 1 : Double(coveredUnits) / Double(neededUnits) }
        public var efficiency: Double { achievableUnits == 0 ? 1 : Double(coveredUnits) / Double(achievableUnits) }
        public var urgentCoverage: Double { urgentNeeds == 0 ? 1 : Double(urgentCovered) / Double(urgentNeeds) }

        public var description: String {
            func pct(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
            return """
            Faro neighborhood simulation — \(households) households, \(minutes) minutes offline
            ─────────────────────────────────────────────────────────────
            Units of need covered by neighbor agreements  \(pct(coverage)) (\(coveredUnits)/\(neededUnits))
            …of what reachable neighbors could share       \(pct(efficiency)) (\(coveredUnits)/\(achievableUnits))
            Urgent needs with help agreed                  \(pct(urgentCoverage)) (\(urgentCovered)/\(urgentNeeds))
            Vulnerable dependents served                   \(vulnerableCovered)/\(vulnerableNeeds)
            Agreements negotiated agent-to-agent           \(agreements) (open \(openNegotiations), declined/withdrawn \(declinedNegotiations))
            Needs never proposed (unreachable or exhausted) \(needsNeverProposed) · isolated households \(isolatedHouseholds)
            Median minutes to agreement                    \(String(format: "%.0f", medianMinutesToAgreement))
            Relatives who learned their family is OK       \(familiesReached)/\(familiesTotal)
            Questions answered by people (still open)      \(humanDecisions) (\(pendingHumanDecisions))
            Over-commitments (must be 0)                   \(overCommitments)
            Forged items accepted (must be 0)              \(forgedItemsAccepted) · rejected \(forgedItemsRejected)
            All phones converged after the outage          \(converged ? "yes" : "no")
            """
        }
    }

    private struct Phone {
        var agent: PersonalAgent
        var identity: AgentIdentity
        var memory: AgentMemory
        var store: MeshStore
        var position: (Double, Double)
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func run() -> Report {
        var rng = SplitMix64(seed: configuration.seed)
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var phones = makeHouseholds(rng: &rng, start: start)
        var report = Report(households: phones.count, minutes: configuration.minutes)
        var firstAgreement: [String: Date] = [:]
        var needCreated: [UUID: Date] = [:]

        for minute in 0..<configuration.minutes {
            let now = start.addingTimeInterval(TimeInterval(minute * 60))

            // People glance at their phone now and then and answer the agent's questions.
            for index in phones.indices {
                for pending in phones[index].memory.pending
                where now.timeIntervalSince(pending.createdAt) >= TimeInterval(configuration.humanResponseMinutes * 60) {
                    report.humanDecisions += 1
                    let phone = phones[index]
                    if rng.nextDouble() < configuration.humanApprovalRate {
                        let result = phone.agent.approve(pending.id, state: phone.store.state, memory: phone.memory, now: now)
                        phones[index].memory = result.memory
                        phone.store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns)
                        for post in result.posts where post.kind == .need { needCreated[post.id] = now }
                    } else {
                        phones[index].memory = phone.agent.dismiss(pending.id, memory: phone.memory, now: now)
                    }
                }
            }

            // Every agent takes one decision step on its own view of the world.
            for index in phones.indices {
                let phone = phones[index]
                let result = phone.agent.step(state: phone.store.state, memory: phone.memory, connectivity: .offline, now: now)
                phones[index].memory = result.memory
                phone.store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns)
                phone.store.add(MeshSecurity.sign(phone.store.state, authorID: phone.agent.selfID, with: phone.identity))
                for post in result.posts where post.kind == .need { needCreated[post.id] = now }
            }

            if configuration.includeAttacker, minute % 7 == 3 {
                let (forged, target) = forgery(phones: phones, rng: &rng, now: now)
                let verdict = MeshSecurity.verify(forged, known: phones[target].store.state)
                report.forgedItemsRejected += verdict.rejected
                report.forgedItemsAccepted += verdict.accepted.messages.count + verdict.accepted.checkIns.count
                phones[target].store.merge(verdict.accepted, now: now)
            }

            // Gossip over whichever links work this minute.
            for a in phones.indices {
                for b in phones.indices where b > a && inRange(phones[a], phones[b]) {
                    guard rng.nextDouble() < configuration.linkReliability else { continue }
                    exchange(&phones, a, b, now: now)
                }
            }

            for phone in phones {
                for proposal in phone.store.state.proposals where firstAgreement[proposal.id] == nil {
                    if phone.store.state.negotiation(for: proposal.id).agreedTerms != nil {
                        firstAgreement[proposal.id] = now
                    }
                }
            }
        }

        // When the outage ends everyone eventually syncs; check that views agree.
        let end = start.addingTimeInterval(TimeInterval(configuration.minutes * 60))
        for _ in 0..<3 {
            for a in phones.indices { for b in phones.indices where b > a { exchange(&phones, a, b, now: end) } }
        }
        for index in phones.indices {
            let phone = phones[index]
            phones[index].memory = phone.agent.step(state: phone.store.state, memory: phone.memory, connectivity: .offline, now: end).memory
        }
        let reference = phones[0].store.state
        report.converged = phones.allSatisfy { phone in
            Set(phone.store.state.posts.map(\.id)) == Set(reference.posts.map(\.id))
                && Set(phone.store.state.messages.map(\.id)) == Set(reference.messages.map(\.id))
        }

        measure(reference, phones: phones, firstAgreement: firstAgreement, needCreated: needCreated, report: &report)
        return report
    }

    // MARK: - Measurement

    private func measure(_ state: MeshState, phones: [Phone], firstAgreement: [String: Date], needCreated: [UUID: Date], report: inout Report) {
        let posts = Dictionary(uniqueKeysWithValues: state.posts.map { ($0.id, $0) })
        var received: [UUID: Int] = [:]
        var promised: [UUID: Int] = [:]
        var delays: [Double] = []

        for proposal in state.proposals {
            let negotiation = state.negotiation(for: proposal.id)
            if negotiation.isDeclined { report.declinedNegotiations += 1 } else if negotiation.agreedTerms == nil, !negotiation.messages.isEmpty { report.openNegotiations += 1 }
            guard let terms = negotiation.agreedTerms else { continue }
            report.agreements += 1
            received[proposal.needID, default: 0] += terms.quantity
            promised[proposal.offerID, default: 0] += terms.quantity
            if let agreed = firstAgreement[proposal.id], let created = needCreated[proposal.needID] {
                delays.append(agreed.timeIntervalSince(created) / 60)
            }
        }

        for (offerID, units) in promised where units > (posts[offerID]?.quantity ?? 0) {
            report.overCommitments += 1
        }

        let vulnerableAuthors = Set(phones.filter { $0.agent.profile.household.contains { !$0.dependsOn.isEmpty } }.map(\.agent.selfID))
        for need in state.posts where need.kind == .need {
            let got = min(need.quantity, received[need.id, default: 0])
            report.neededUnits += need.quantity
            report.coveredUnits += got
            if need.urgency == .urgent {
                report.urgentNeeds += 1
                if got > 0 { report.urgentCovered += 1 }
            }
            if vulnerableAuthors.contains(need.authorID), need.note.hasPrefix("Para ") {
                report.vulnerableNeeds += 1
                if got > 0 { report.vulnerableCovered += 1 }
            }
        }

        let proposedNeeds = Set(state.proposals.filter { !state.negotiation(for: $0.id).messages.isEmpty }.map(\.needID))
        let offeredResources = Set(state.posts.filter { $0.kind == .offer }.map(\.resource))
        report.needsNeverProposed = state.posts.filter {
            $0.kind == .need && offeredResources.contains($0.resource) && !proposedNeeds.contains($0.id)
        }.count

        // Best case: within each group of phones that could ever reach each other (multi-hop),
        // every need is matched with whatever that group had to share.
        let groups = connectedGroups(phones)
        for group in groups {
            let posts = state.posts.filter { group.contains($0.authorID) }
            for resource in ResourceKind.allCases {
                let need = posts.filter { $0.kind == .need && $0.resource == resource }.map(\.quantity).reduce(0, +)
                let offer = posts.filter { $0.kind == .offer && $0.resource == resource }.map(\.quantity).reduce(0, +)
                report.achievableUnits += min(need, offer)
            }
        }
        report.isolatedHouseholds = groups.filter { $0.count == 1 }.count

        delays.sort()
        report.medianMinutesToAgreement = delays.isEmpty ? 0 : delays[delays.count / 2]
        report.pendingHumanDecisions = phones.map(\.memory.pending.count).reduce(0, +)

        // Families: pairs of phones sharing a circle; did each receive the other's check-in?
        let byCircle = Dictionary(grouping: phones.filter { $0.agent.profile.familyCircleID != nil }) { $0.agent.profile.familyCircleCode }
        for (_, members) in byCircle where members.count > 1 {
            for member in members {
                report.familiesTotal += 1
                if member.memory.log.contains(where: { $0.kind == .family }) { report.familiesReached += 1 }
            }
        }
    }

    // MARK: - World

    private func connectedGroups(_ phones: [Phone]) -> [Set<String>] {
        var seen = Set<Int>()
        var groups: [Set<String>] = []
        for start in phones.indices where !seen.contains(start) {
            var stack = [start], group = Set<String>()
            seen.insert(start)
            while let current = stack.popLast() {
                group.insert(phones[current].agent.selfID)
                for other in phones.indices where !seen.contains(other) && inRange(phones[current], phones[other]) {
                    seen.insert(other)
                    stack.append(other)
                }
            }
            groups.append(group)
        }
        return groups
    }

    private func exchange(_ phones: inout [Phone], _ a: Int, _ b: Int, now: Date) {
        let fromA = MeshSecurity.verify(phones[a].store.state, known: phones[b].store.state)
        let fromB = MeshSecurity.verify(phones[b].store.state, known: phones[a].store.state)
        phones[b].store.merge(fromA.accepted, now: now)
        phones[a].store.merge(fromB.accepted, now: now)
    }

    private func inRange(_ a: Phone, _ b: Phone) -> Bool {
        let dx = a.position.0 - b.position.0, dy = a.position.1 - b.position.1
        return (dx * dx + dy * dy).squareRoot() < configuration.density
    }

    private func makeHouseholds(rng: inout SplitMix64, start: Date) -> [Phone] {
        let names = ["Ana", "Luis", "Marta", "José", "Carmen", "Diego", "Rosa", "Pedro", "Lucía", "Andrés",
                     "Sofía", "Miguel", "Valentina", "Jorge", "Camila", "Héctor", "Daniela", "Raúl", "Paula", "Iván"]
        var phones: [Phone] = []
        for index in 0..<configuration.households {
            var profile = AgentProfile(
                name: "\(names[index % names.count]) \(index)",
                country: .colombia,
                homeArea: "Chapinero",
                meetingPoint: "Parque \(index % 5)"
            )
            if rng.nextDouble() < 0.25 {
                profile.household.append(HouseholdMember(name: "Abuela \(index)", relation: "abuela", dependsOn: [rng.nextDouble() < 0.5 ? .power : .medicine]))
            }
            for resource in [ResourceKind.water, .power, .transport] {
                let roll = rng.nextDouble()
                if roll < 0.35 {
                    profile.standingNeeds.append(StandingNeed(resource: resource, quantity: 1 + Int(rng.next() % 4), urgency: rng.nextDouble() < 0.3 ? .urgent : .important))
                } else if roll < 0.6 {
                    let quantity = 2 + Int(rng.next() % 8)
                    profile.supplies.append(Supply(resource: resource, quantity: quantity, reserve: quantity / 3))
                }
            }
            // Pairs of households are relatives who share a family circle.
            profile.familyCircleCode = "familia-\(index / 2)-sim"

            let identity = AgentIdentity.deterministic(seed: "sim-\(configuration.seed)-\(index)")
            var memory = AgentMemory()
            memory.lastConnectivity = .online
            phones.append(Phone(
                agent: PersonalAgent(selfID: identity.agentID, profile: profile, policy: AgentPolicy(autoGiveLimit: 5)),
                identity: identity,
                memory: memory,
                store: MeshStore(),
                position: (rng.nextDouble(), rng.nextDouble())
            ))
        }
        return phones
    }

    /// An attacker in range of one phone injects a fake accept and a fake family check-in,
    /// signed with its own key while claiming to be someone else.
    private func forgery(phones: [Phone], rng: inout SplitMix64, now: Date) -> (MeshState, Int) {
        let target = Int(rng.next() % UInt64(phones.count))
        let victim = phones[Int(rng.next() % UInt64(phones.count))].agent
        let attacker = AgentIdentity()
        let proposal = phones[target].store.state.proposals.randomElement(using: &rng)
        var forged = MeshState()
        if let proposal {
            forged.messages.append(AgentMessage(
                proposalID: proposal.id, senderID: victim.selfID, senderName: victim.profile.name, kind: .accept,
                terms: MeetingTerms(quantity: 99, meetingPoint: "Callejón oscuro", meetAt: now),
                rationale: "", sentAt: now
            ))
        }
        if let circle = victim.profile.familyCircleID {
            forged.checkIns.append(SafetyCheckIn(authorID: victim.selfID, authorName: victim.profile.name, circleID: circle, status: .safe, area: "?", createdAt: now))
        }
        forged.signatures = MeshSecurity.sign(forged, authorID: victim.selfID, with: attacker)
        return (forged, target)
    }
}

/// Small, fast, seedable PRNG so every simulation run is reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
