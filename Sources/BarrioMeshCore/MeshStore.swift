import Foundation

public final class MeshStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL?
    private var storedState: MeshState

    public init(fileURL: URL? = nil, initialState: MeshState = MeshState()) {
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode(MeshState.self, from: data) {
            self.storedState = decoded
        } else {
            self.storedState = initialState
        }
    }

    public var state: MeshState {
        lock.withLock { storedState }
    }

    @discardableResult
    public func add(_ post: MeshPost) -> Bool {
        lock.withLock {
            guard !storedState.posts.contains(where: { $0.id == post.id }) else { return false }
            storedState.posts.append(post)
            persistLocked()
            return true
        }
    }

    @discardableResult
    public func upsert(_ proposal: MatchProposal) -> Bool {
        lock.withLock {
            if let index = storedState.proposals.firstIndex(where: { $0.id == proposal.id }) {
                let merged = storedState.proposals[index].merged(with: proposal)
                guard merged != storedState.proposals[index] else { return false }
                storedState.proposals[index] = merged
            } else {
                storedState.proposals.append(proposal)
            }
            persistLocked()
            return true
        }
    }

    @discardableResult
    public func closePost(id: UUID, at date: Date = Date()) -> Bool {
        lock.withLock {
            guard let index = storedState.posts.firstIndex(where: { $0.id == id }),
                  storedState.posts[index].closedAt == nil else { return false }
            storedState.posts[index].closedAt = date
            persistLocked()
            return true
        }
    }

    @discardableResult
    public func merge(_ incoming: MeshState, now: Date = Date()) -> Bool {
        lock.withLock {
            var changed = false
            var postIndex = Dictionary(uniqueKeysWithValues: storedState.posts.enumerated().map { ($1.id, $0) })

            let cutoff = now.addingTimeInterval(-Self.defaultRetention)
            for post in incoming.posts {
                if let index = postIndex[post.id] {
                    if storedState.posts[index].closedAt == nil, let incomingClosedAt = post.closedAt {
                        storedState.posts[index].closedAt = incomingClosedAt
                        changed = true
                    }
                } else if !Self.isStale(post, cutoff: cutoff) {
                    // A peer that has not compacted yet must not resurrect forgotten history.
                    storedState.posts.append(post)
                    postIndex[post.id] = storedState.posts.count - 1
                    changed = true
                }
            }

            var proposalIndex = Dictionary(uniqueKeysWithValues: storedState.proposals.enumerated().map { ($1.id, $0) })
            for proposal in incoming.proposals {
                if let index = proposalIndex[proposal.id] {
                    let merged = storedState.proposals[index].merged(with: proposal)
                    if merged != storedState.proposals[index] {
                        storedState.proposals[index] = merged
                        changed = true
                    }
                } else {
                    storedState.proposals.append(proposal)
                    proposalIndex[proposal.id] = storedState.proposals.count - 1
                    changed = true
                }
            }

            changed = Self.union(&storedState.messages, with: incoming.messages) || changed
            changed = Self.union(&storedState.checkIns, with: incoming.checkIns) || changed

            if changed { persistLocked() }
            return changed
        }
    }

    @discardableResult
    public func add(_ message: AgentMessage) -> Bool {
        lock.withLock {
            guard Self.union(&storedState.messages, with: [message]) else { return false }
            persistLocked()
            return true
        }
    }

    @discardableResult
    public func add(_ checkIn: SafetyCheckIn) -> Bool {
        lock.withLock {
            guard Self.union(&storedState.checkIns, with: [checkIn]) else { return false }
            persistLocked()
            return true
        }
    }

    /// Applies everything an agent step decided, persisting once.
    @discardableResult
    public func apply(posts: [MeshPost], proposals: [MatchProposal], messages: [AgentMessage], checkIns: [SafetyCheckIn]) -> Bool {
        lock.withLock {
            var changed = false
            for post in posts where !storedState.posts.contains(where: { $0.id == post.id }) {
                storedState.posts.append(post)
                changed = true
            }
            for proposal in proposals {
                if let index = storedState.proposals.firstIndex(where: { $0.id == proposal.id }) {
                    let merged = storedState.proposals[index].merged(with: proposal)
                    if merged != storedState.proposals[index] {
                        storedState.proposals[index] = merged
                        changed = true
                    }
                } else {
                    storedState.proposals.append(proposal)
                    changed = true
                }
            }
            changed = Self.union(&storedState.messages, with: messages) || changed
            changed = Self.union(&storedState.checkIns, with: checkIns) || changed
            if changed { persistLocked() }
            return changed
        }
    }

    /// Forgets history nobody can act on anymore, so gossip payloads stay small:
    /// posts that expired or closed more than `retention` ago, the proposals and
    /// negotiation messages about them, and check-ins superseded or older than two days.
    @discardableResult
    public func compact(now: Date = Date(), retention: TimeInterval = MeshStore.defaultRetention) -> Bool {
        lock.withLock {
            let before = (storedState.posts.count, storedState.proposals.count, storedState.messages.count, storedState.checkIns.count)
            storedState = Self.compacted(storedState, now: now, retention: retention)
            let after = (storedState.posts.count, storedState.proposals.count, storedState.messages.count, storedState.checkIns.count)
            guard before != after else { return false }
            persistLocked()
            return true
        }
    }

    public static let defaultRetention: TimeInterval = 12 * 3_600

    static func compacted(_ state: MeshState, now: Date, retention: TimeInterval) -> MeshState {
        let cutoff = now.addingTimeInterval(-retention)
        let posts = state.posts.filter { !isStale($0, cutoff: cutoff) }
        let livePostIDs = Set(posts.map(\.id))
        let proposals = state.proposals.filter { livePostIDs.contains($0.needID) && livePostIDs.contains($0.offerID) }
        let liveProposalIDs = Set(proposals.map(\.id))
        let messages = state.messages.filter { liveProposalIDs.contains($0.proposalID) }

        let checkInCutoff = now.addingTimeInterval(-48 * 3_600)
        var newest: [String: SafetyCheckIn] = [:]
        for checkIn in state.checkIns where checkIn.createdAt >= checkInCutoff {
            let key = "\(checkIn.circleID)|\(checkIn.authorID)"
            if let current = newest[key], current.createdAt >= checkIn.createdAt { continue }
            newest[key] = checkIn
        }
        let checkIns = state.checkIns.filter { newest["\($0.circleID)|\($0.authorID)"]?.id == $0.id }

        return MeshState(posts: posts, proposals: proposals, messages: messages, checkIns: checkIns)
    }

    static func isStale(_ post: MeshPost, cutoff: Date) -> Bool {
        post.expiresAt < cutoff || (post.closedAt.map { $0 < cutoff } ?? false)
    }

    public func reset() {
        lock.withLock {
            storedState = MeshState()
            persistLocked()
        }
    }

    private static func union<Item: Identifiable>(_ items: inout [Item], with incoming: [Item]) -> Bool where Item.ID == UUID {
        var known = Set(items.map(\.id))
        var changed = false
        for item in incoming where known.insert(item.id).inserted {
            items.append(item)
            changed = true
        }
        return changed
    }

    private func persistLocked() {
        guard let fileURL else { return }
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(storedState)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The in-memory state remains usable. The app surfaces persistence errors separately.
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
