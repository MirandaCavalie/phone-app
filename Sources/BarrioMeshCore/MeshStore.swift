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
    public func merge(_ incoming: MeshState) -> Bool {
        lock.withLock {
            var changed = false
            var postIndex = Dictionary(uniqueKeysWithValues: storedState.posts.enumerated().map { ($1.id, $0) })

            for post in incoming.posts {
                if let index = postIndex[post.id] {
                    if storedState.posts[index].closedAt == nil, let incomingClosedAt = post.closedAt {
                        storedState.posts[index].closedAt = incomingClosedAt
                        changed = true
                    }
                } else {
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
