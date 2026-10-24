import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    struct MatchSummary: Identifiable {
        let candidate: MatchCandidate
        let proposal: MatchProposal?
        let negotiation: Negotiation
        let status: ProposalStatus

        var id: String { candidate.id }
        var requiredPeers: Set<String> { [candidate.need.authorID, candidate.offer.authorID] }
        var isAgentNegotiated: Bool { !negotiation.messages.isEmpty }
    }

    @Published private(set) var meshState: MeshState
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var memory: AgentMemory
    @Published private(set) var hasInternet = true
    @Published var alertMessage: String?
    @Published var profile: AgentProfile {
        didSet { save(profile, to: Self.profileURL); runAgent() }
    }
    @Published var policy: AgentPolicy {
        didSet { save(policy, to: Self.policyURL); runAgent() }
    }
    /// Demo switch: behave as if internet were gone, even on Wi-Fi.
    @Published var simulateOutage = false {
        didSet { runAgent() }
    }

    let deviceID: String
    let peerSession: PeerSession
    let connectivity = ConnectivityMonitor()
    let seismometer = Seismometer()
    let hazardMonitor = HazardMonitor()
    let assistant = DailyAssistant()
    let identity: AgentIdentity
    let narrator = Narrator()
    /// English by default; the whole app, the agent's log and its voice follow this.
    @Published var language: AppLanguage {
        didSet {
            Lang.current = language
            UserDefaults.standard.set(language.rawValue, forKey: "faro.language")
        }
    }
    @Published var speaksUpdates: Bool = UserDefaults.standard.object(forKey: "faro.speaks") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(speaksUpdates, forKey: "faro.speaks")
            narrator.isEnabled = speaksUpdates
            if !speaksUpdates { narrator.stop() }
        }
    }
    /// Items from peers dropped because their signature did not check out.
    @Published private(set) var rejectedItems = 0

    /// A quake felt only by this phone, waiting out its cancel window.
    struct QuakeAlert: Equatable {
        let event: SeismicEvent
        let deadline: Date
    }
    @Published private(set) var quakeAlert: QuakeAlert?
    private var quakeCountdown: Task<Void, Never>?

    private let store: MeshStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var heartbeat: Task<Void, Never>?
    private var peerUpdates: AnyCancellable?
    private var assistantUpdates: AnyCancellable?
    private var demoNeighbors: [(agent: PersonalAgent, memory: AgentMemory)] = []
    private var demoIdentities: [String: AgentIdentity] = [:]

    init() {
        // The agent id is derived from the signing key, so nobody else can speak for this phone.
        let savedLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "faro.language") ?? "") ?? .english
        language = savedLanguage
        Lang.current = savedLanguage

        let identity = IdentityStore.loadOrCreate()
        self.identity = identity
        deviceID = identity.agentID

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        store = MeshStore(fileURL: Self.applicationSupportURL.appendingPathComponent("mesh-state.json"))
        store.compact()
        meshState = store.state
        let loadedProfile = Self.load(AgentProfile.self, from: Self.profileURL, decoder: decoder) ?? AgentProfile()
        profile = loadedProfile
        policy = Self.load(AgentPolicy.self, from: Self.policyURL, decoder: decoder) ?? AgentPolicy()
        memory = Self.load(AgentMemory.self, from: Self.memoryURL, decoder: decoder) ?? AgentMemory()

        let deviceName = UIDevice.current.name.replacingOccurrences(of: "’s iPhone", with: "")
        let visibleName = loadedProfile.name.isEmpty ? deviceName : loadedProfile.name
        peerSession = PeerSession(displayName: "\(visibleName)-\(deviceID.prefix(4))")
        peerSession.onData = { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        peerSession.onPeerConnected = { [weak self] in
            Task { @MainActor in self?.broadcastState() }
        }
        peerSession.start()
        // Views observe the model; forward peer-list changes so connection badges stay live.
        peerUpdates = peerSession.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }

        connectivity.onChange = { [weak self] online in
            self?.hasInternet = online
            self?.runAgent()
        }
        connectivity.start()

        seismometer.onShaking = { [weak self] event in self?.feltShaking(event) }
        seismometer.start()

        hazardMonitor.isOnline = { [weak self] in self?.effectiveConnectivity == .online }
        hazardMonitor.home = { [weak self] in self?.profile.approximateLocation.point ?? GeoPoint(latitude: 4.711, longitude: -74.072) }
        hazardMonitor.onAlerts = { [weak self] alerts in self?.receiveOfficial(alerts) }
        hazardMonitor.start(relayedBy: deviceID)
        assistantUpdates = assistant.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        if profile.isConfigured { Task { await assistant.refreshCalendar() } }
        if profile.isConfigured { HazardMonitor.requestNotificationPermission() }

        // Follow-ups are time-based, so the agent also wakes up on its own.
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if self?.store.compact() == true { self?.meshState = self?.store.state ?? MeshState() }
                self?.runAgent()
            }
        }
        runAgent()

        // Rehearsal shortcut: launch with `-faro-demo` to start the simulated neighbors.
        if ProcessInfo.processInfo.arguments.contains("-faro-demo"), profile.isConfigured {
            startSimulatedNeighbors()
        }
        // Rehearsal shortcut: `-faro-alert` plays an official USGS alert near home.
        if ProcessInfo.processInfo.arguments.contains("-faro-alert"), profile.isConfigured {
            simulateOfficialAlert()
        }
        // Rehearsal shortcut: `-faro-quake` plays the earthquake alert as if the phone felt shaking.
        if ProcessInfo.processInfo.arguments.contains("-faro-quake"), profile.isConfigured {
            simulateQuake()
        }
    }

    // MARK: - Agent

    var agent: PersonalAgent {
        PersonalAgent(selfID: deviceID, profile: profile, policy: policy)
    }

    var effectiveConnectivity: Connectivity {
        hasInternet && !simulateOutage ? .online : .offline
    }

    var snapshot: AgentSnapshot {
        AgentSnapshot(
            profile: profile,
            policy: policy,
            memory: memory,
            state: meshState,
            selfID: deviceID,
            connectedPeers: peerSession.connectedPeerNames.count,
            hasInternet: effectiveConnectivity == .online
        )
    }

    func runAgent() {
        guard profile.isConfigured else { return }
        let now = Date()
        let result = agent.step(state: store.state, memory: memory, connectivity: effectiveConnectivity, now: now)
        commit(result)
        stepDemoNeighbors(now: now)
        if memory.emergencyActive, quakeAlert != nil {
            // Nearby phones confirmed the quake while this one was still counting down.
            quakeCountdown?.cancel()
            quakeAlert = nil
        }
    }

    // MARK: - Official alerts

    /// Relevant official alerts this phone knows about, newest first, with their assessment.
    var officialAlerts: [(alert: HazardAlert, assessment: HazardAssessment)] {
        let home = profile.approximateLocation.point
        return meshState.hazardAlerts
            .map { ($0, HazardAssessment.assess($0, home: home)) }
            .filter { $0.1.level > .ignore && Date().timeIntervalSince($0.0.occurredAt) < 6 * 3_600 }
            .sorted { $0.0.occurredAt > $1.0.occurredAt }
    }

    /// Keeps only alerts that matter around here, then relays them to phones without internet.
    private func receiveOfficial(_ alerts: [HazardAlert]) {
        let home = profile.approximateLocation.point
        let relevant = alerts.filter { HazardAssessment.assess($0, home: home).level > .ignore }
        guard !relevant.isEmpty, store.add(relevant) else { return }
        for alert in relevant where !memory.seenHazards.contains(alert.eventID) {
            let assessment = HazardAssessment.assess(alert, home: home)
            if assessment.level >= .warning { HazardMonitor.notify(assessment, alert: alert) }
        }
        publishChange()
        runAgent()
    }

    /// Rehearsal: a strong quake near home, exactly as if USGS had reported it.
    func simulateOfficialAlert() {
        let home = profile.approximateLocation.point
        let alert = HazardAlert(
            eventID: "sim-\(UUID().uuidString.prefix(8))",
            source: "USGS",
            kind: .earthquake,
            magnitude: 7.2,
            place: t("35 km al sureste de \(profile.approximateLocation.label) (simulado)", "35 km SE of \(profile.approximateLocation.label) (simulated)"),
            epicenter: GeoPoint(latitude: home.latitude - 0.22, longitude: home.longitude + 0.22),
            depthKm: 15,
            occurredAt: Date(),
            pagerLevel: "orange",
            tsunamiFlag: false,
            url: "https://earthquake.usgs.gov/earthquakes/map/",
            relayedBy: deviceID,
            isSimulated: true
        )
        receiveOfficial([alert])
    }

    // MARK: - Earthquakes

    func feltShaking(_ event: SeismicEvent) {
        guard profile.isConfigured else { return }
        let now = Date()
        let report = SeismicReport(deviceID: deviceID, area: profile.homeArea, peakAcceleration: event.peakAcceleration, detectedAt: now)
        if store.add(report) { publishChange() }

        switch agent.assessShaking(event, reports: store.state.seismicReports, memory: memory, now: now) {
        case .ignore:
            break
        case let .activateNow(phones):
            activateForQuake(event, phones: phones)
        case let .countdown(seconds):
            quakeAlert = QuakeAlert(event: event, deadline: now.addingTimeInterval(TimeInterval(seconds)))
            quakeCountdown?.cancel()
            quakeCountdown = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self, let alert = self.quakeAlert else { return }
                self.activateForQuake(alert.event, phones: 1)
            }
        }
    }

    func cancelQuakeAlert() {
        quakeCountdown?.cancel()
        quakeAlert = nil
        memory.record(ActivityEntry(date: Date(), kind: .mode, title: t("Cancelaste la alerta de sismo", "You cancelled the quake alert")))
        save(memory, to: Self.memoryURL)
    }

    func confirmQuakeNow() {
        guard let alert = quakeAlert else { return }
        activateForQuake(alert.event, phones: 1)
    }

    /// Rehearsal: the same path a real accelerometer event takes.
    func simulateQuake() {
        feltShaking(SeismicEvent(peakAcceleration: 0.21, duration: 3))
    }

    private func activateForQuake(_ event: SeismicEvent?, phones: Int) {
        quakeCountdown?.cancel()
        quakeAlert = nil
        memory = agent.activateForEarthquake(event, phones: phones, memory: memory, now: Date())
        save(memory, to: Self.memoryURL)
        runAgent()
    }

    func setEmergency(_ active: Bool) {
        let now = Date()
        memory = active
            ? agent.activateEmergency(memory: memory, reason: t("Lo activaste tú.", "You turned it on."), now: now)
            : agent.deactivateEmergency(memory: memory, now: now)
        save(memory, to: Self.memoryURL)
        runAgent()
    }

    func approve(_ pending: PendingApproval) {
        commit(agent.approve(pending.id, state: store.state, memory: memory, now: Date()))
        runAgent()
    }

    func dismiss(_ pending: PendingApproval) {
        memory = agent.dismiss(pending.id, memory: memory, now: Date())
        save(memory, to: Self.memoryURL)
    }

    func checkIn(_ status: SafetyStatus) {
        commit(agent.manualCheckIn(status, memory: memory, now: Date()))
    }

    func markSent(_ item: OutboxItem) {
        guard let index = memory.outbox.firstIndex(where: { $0.id == item.id }) else { return }
        memory.outbox[index].sentAt = Date()
        save(memory, to: Self.memoryURL)
    }

    private func commit(_ result: AgentStepResult) {
        if result.changesMesh,
           store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns) {
            publishChange()
        }
        if result.memory != memory {
            memory = result.memory
            save(memory, to: Self.memoryURL)
        }
        narrator.isEnabled = speaksUpdates && memory.emergencyActive
        narrator.narrate(memory.log, country: profile.country)
    }

    // MARK: - Network picture

    var simulatedNeighborCount: Int { demoNeighbors.count }

    /// Everyone the agent can currently see, directly or through other phones.
    var meshNodes: [MeshRadarView.Node] {
        var nodes: [String: MeshRadarView.Node] = [:]
        for post in meshState.posts where post.authorID != deviceID && post.isActive() {
            nodes[post.authorID] = .init(id: post.authorID, name: post.authorName, kind: .relayed)
        }
        let connected = Set(peerSession.connectedPeerNames)
        for name in connected {
            let key = "peer:\(name)"
            nodes[key] = .init(id: key, name: String(name.split(separator: "-").first ?? Substring(name)), kind: .peer)
        }
        for demo in demoNeighbors {
            nodes[demo.agent.selfID] = .init(id: demo.agent.selfID, name: demo.agent.profile.name, kind: .peer)
        }
        for checkIn in familyCheckIns {
            nodes[checkIn.authorID] = .init(id: checkIn.authorID, name: checkIn.authorName, kind: .family)
        }
        for summary in matchSummaries where summary.status == .accepted && summary.requiredPeers.contains(deviceID) {
            let other = summary.candidate.need.authorID == deviceID ? summary.candidate.offer : summary.candidate.need
            nodes[other.authorID] = .init(id: other.authorID, name: other.authorName, kind: .agreement)
        }
        return nodes.values.sorted { $0.id < $1.id }
    }

    // MARK: - Proactive help

    var briefing: ProactiveAgent.Briefing {
        ProactiveAgent.briefing(profile: profile, alerts: officialAlerts, calendar: assistant.todayEvents, now: Date())
    }

    var suggestions: [Suggestion] {
        ProactiveAgent.suggestions(
            profile: profile, memory: memory, alerts: officialAlerts, calendar: assistant.todayEvents,
            remindersScheduled: assistant.remindersScheduled, now: Date()
        )
    }

    /// Performs an offer the person accepted, logs it, and hides it.
    func perform(_ suggestion: Suggestion, openURL: @escaping (URL) -> Void) {
        Task {
            var done = true
            var detail = ""
            switch suggestion.action {
            case let .addToCalendar(title, start, minutes, notes):
                done = await assistant.addEvent(title: title, start: start, durationMinutes: minutes, notes: notes)
                detail = done
                    ? "\(title) · \(start.formatted(date: .abbreviated, time: .shortened))"
                    : t("Permite el acceso al calendario en Ajustes.", "Allow calendar access in Settings.")
            case .remindDoses:
                await assistant.scheduleReminders(for: profile)
                done = assistant.remindersScheduled
            case let .call(number, label):
                if let url = URL(string: "tel://\(number)") { openURL(url) }
                detail = label
            case let .message(item):
                memory.outbox.append(item)
                if let url = URL(string: "https://wa.me/\(item.phone)?text=\(item.body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") { openURL(url) }
                detail = item.recipientName
            }
            if done { memory.dismissedKeys.insert(suggestion.id) }
            memory.record(ActivityEntry(
                date: Date(),
                kind: .followUp,
                title: done ? t("Hecho: \(suggestion.title)", "Done: \(suggestion.title)") : t("No pude: \(suggestion.title)", "Couldn't: \(suggestion.title)"),
                detail: detail
            ))
            save(memory, to: Self.memoryURL)
        }
    }

    func dismiss(_ suggestion: Suggestion) {
        memory.dismissedKeys.insert(suggestion.id)
        save(memory, to: Self.memoryURL)
    }

    // MARK: - Paperwork

    var callScript: Paperwork.CallScript {
        Paperwork.callScript(profile: profile, state: meshState, selfID: deviceID, now: Date())
    }

    var incidentReport: Paperwork.Report {
        Paperwork.report(profile: profile, memory: memory, state: meshState, selfID: deviceID, now: Date())
    }

    // MARK: - Family

    var familyCheckIns: [SafetyCheckIn] {
        meshState.latestCheckIns(circleCode: profile.familyCircleCode).filter { $0.authorID != deviceID }
    }

    var myLatestCheckIn: SafetyCheckIn? {
        meshState.checkIns
            .filter { $0.authorID == deviceID }
            .max(by: { $0.createdAt < $1.createdAt })?
            .opened(withCircleCode: profile.familyCircleCode)
    }

    // MARK: - Mesh

    /// Units already agreed between agents for a need (received) or an offer (promised).
    func agreedQuantity(for post: MeshPost) -> Int {
        meshState.proposals
            .filter { post.kind == .need ? $0.needID == post.id : $0.offerID == post.id }
            .compactMap { meshState.negotiation(for: $0.id).agreedTerms?.quantity }
            .reduce(0, +)
    }

    var activeNeeds: [MeshPost] { activePosts.filter { $0.kind == .need } }
    var activeOffers: [MeshPost] { activePosts.filter { $0.kind == .offer } }

    var activePosts: [MeshPost] {
        meshState.posts
            .filter { $0.isActive() }
            .sorted {
                if $0.urgency == $1.urgency { return $0.createdAt > $1.createdAt }
                return $0.urgency.rawValue > $1.urgency.rawValue
            }
    }

    var matchSummaries: [MatchSummary] {
        MatchEngine.candidates(in: meshState.posts).map { candidate in
            let proposal = meshState.proposals.first(where: { $0.id == candidate.id })
            let negotiation = meshState.negotiation(for: candidate.id)
            let required: Set<String> = [candidate.need.authorID, candidate.offer.authorID]
            let status = proposal?.status(requiredPeers: required, negotiation: negotiation) ?? .suggested
            return MatchSummary(candidate: candidate, proposal: proposal, negotiation: negotiation, status: status)
        }
        .filter { $0.status != .declined }
    }

    func addPost(
        kind: PostKind,
        resource: ResourceKind,
        quantity: Int,
        unit: String,
        urgency: Urgency,
        area: String,
        note: String,
        expiresIn: TimeInterval
    ) {
        let post = MeshPost(
            authorID: deviceID,
            authorName: sanitizedDisplayName,
            kind: kind,
            resource: resource,
            quantity: quantity,
            unit: unit.isEmpty ? resource.defaultUnit : unit,
            urgency: urgency,
            area: area,
            note: note,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        guard store.add(post) else { return }
        publishChange()
        runAgent()
    }

    func close(_ post: MeshPost) {
        guard post.authorID == deviceID, store.closePost(id: post.id) else { return }
        publishChange()
    }

    func approve(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID) else { return }
        var proposal = summary.proposal ?? MatchProposal(needID: summary.candidate.need.id, offerID: summary.candidate.offer.id)
        proposal.approvals.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func decline(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID) else { return }
        var proposal = summary.proposal ?? MatchProposal(needID: summary.candidate.need.id, offerID: summary.candidate.offer.id)
        proposal.declines.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func complete(_ summary: MatchSummary) {
        guard summary.requiredPeers.contains(deviceID), var proposal = summary.proposal else { return }
        proposal.completions.insert(deviceID)
        guard store.upsert(proposal) else { return }
        publishChange()
    }

    func hasApproved(_ summary: MatchSummary) -> Bool {
        summary.proposal?.approvals.contains(deviceID) == true
    }

    func hasCompleted(_ summary: MatchSummary) -> Bool {
        summary.proposal?.completions.contains(deviceID) == true
    }

    func resetLocalData() {
        store.reset()
        meshState = store.state
        memory = AgentMemory()
        demoNeighbors = []
        demoIdentities = [:]
        save(memory, to: Self.memoryURL)
        broadcastState()
    }

    func resetEverything() {
        resetLocalData()
        profile = AgentProfile()
        policy = AgentPolicy()
    }

    // MARK: - Demo fallback

    /// Runs two simulated neighbors on this phone so the full agent flow can be shown with one device.
    /// They are labeled "(simulado)" everywhere and never pretend a real peer is connected.
    func startSimulatedNeighbors() {
        guard demoNeighbors.isEmpty else { return }
        let luisIdentity = AgentIdentity.deterministic(seed: "luis")
        let familyIdentity = AgentIdentity.deterministic(seed: "family")
        let luis = PersonalAgent(
            selfID: luisIdentity.agentID,
            profile: AgentProfile(
                name: t("Luis (simulado)", "Luis (simulated)"),
                country: profile.country,
                homeArea: profile.homeArea.isEmpty ? "Chapinero" : profile.homeArea,
                meetingPoint: t("Tienda de la esquina", "Corner store"),
                supplies: [
                    Supply(id: Self.demoID(1), resource: .water, quantity: 12, reserve: 8),
                    Supply(id: Self.demoID(2), resource: .power, quantity: 3, reserve: 1),
                    Supply(id: Self.demoID(3), resource: .transport, quantity: 3)
                ]
            ),
            policy: AgentPolicy(autoGiveLimit: 10)
        )
        var family = AgentProfile(
            name: "\(profile.household.first?.name ?? t("Mamá", "Mom")) \(t("(simulado)", "(simulated)"))",
            country: profile.country,
            homeArea: "Usaquén",
            familyCircleCode: profile.familyCircleCode
        )
        family.standingNeeds = []
        let relative = PersonalAgent(selfID: familyIdentity.agentID, profile: family, policy: AgentPolicy())

        let now = Date()
        demoIdentities = [luis.selfID: luisIdentity, relative.selfID: familyIdentity]
        demoNeighbors = [luis, relative].map { agent in
            var memory = agent.activateEmergency(memory: AgentMemory(), reason: "Simulación", now: now)
            // Simulated agents are not persisted; remember what they already published in an earlier run.
            for supply in agent.profile.supplies {
                if let post = store.state.posts.first(where: { $0.authorID == agent.selfID && $0.kind == .offer && $0.resource == supply.resource }) {
                    memory.publishedFromProfile["offer:\(supply.id.uuidString)"] = post.id
                }
            }
            if store.state.checkIns.contains(where: { $0.authorID == agent.selfID }) { memory.checkedInAt = now }
            return (agent, memory)
        }
        if !memory.emergencyActive { setEmergency(true) } else { runAgent() }
    }

    private func stepDemoNeighbors(now: Date) {
        guard !demoNeighbors.isEmpty else { return }
        // Take turns like nearby phones would, until nobody has anything new to say.
        for _ in 0..<6 {
            var changed = false
            for index in demoNeighbors.indices {
                let neighbor = demoNeighbors[index]
                let result = neighbor.agent.step(state: store.state, memory: neighbor.memory, connectivity: .offline, now: now)
                demoNeighbors[index].memory = result.memory
                if result.changesMesh,
                   store.apply(posts: result.posts, proposals: result.proposals, messages: result.messages, checkIns: result.checkIns) {
                    changed = true
                }
            }
            let reaction = agent.step(state: store.state, memory: memory, connectivity: effectiveConnectivity, now: now)
            if reaction.changesMesh { changed = true }
            commit(reaction)
            guard changed else { break }
            publishChange()
        }
    }

    // MARK: - Transport

    private func receive(_ data: Data) {
        do {
            let message = try decoder.decode(MeshWireMessage.self, from: data)
            guard message.protocolVersion == MeshWireMessage.currentProtocolVersion else {
                alertMessage = t("Un teléfono cercano usa otra versión de Faro.", "A nearby phone runs a different Faro version.")
                return
            }
            // Only correctly signed items, from the key first seen for each author, get in.
            let verdict = MeshSecurity.verify(message.state, known: store.state)
            rejectedItems += verdict.rejected
            if store.merge(verdict.accepted) {
                meshState = store.state
                lastSyncAt = Date()
                // Gossip only converges when newly learned state is relayed onward.
                broadcastState()
                runAgent()
            }
        } catch {
            alertMessage = t("No pude leer un mensaje de la red local.", "Could not read a message from the local network.")
        }
    }

    private func publishChange() {
        signLocalItems()
        meshState = store.state
        broadcastState()
    }

    /// Signs whatever this phone (or a simulated neighbor on it) authored and has not signed yet.
    private func signLocalItems() {
        var signatures = MeshSecurity.sign(store.state, authorID: deviceID, with: identity)
        for (author, demoIdentity) in demoIdentities {
            signatures += MeshSecurity.sign(store.state, authorID: author, with: demoIdentity)
        }
        if !signatures.isEmpty { store.add(signatures) }
    }

    private func broadcastState() {
        do {
            let message = MeshWireMessage(senderID: deviceID, state: store.state)
            try peerSession.send(encoder.encode(message))
        } catch PeerSession.SendError.noConnectedPeers {
            // Offline-first: state stays queued locally until a peer connects.
        } catch {
            alertMessage = t("Guardado, pero aún no se pudo enviar.", "Saved, but not sent yet.")
        }
    }

    private var sanitizedDisplayName: String {
        let cleaned = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? t("Vecino", "Neighbor") : cleaned
    }

    // MARK: - Persistence

    private func save<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            // In-memory state stays usable; the next save retries.
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from url: URL, decoder: JSONDecoder) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func demoID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "FA20DE30-0000-4000-8000-%012d", n))!
    }


    private static var applicationSupportURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("BarrioMesh", isDirectory: true)
    }

    private static var profileURL: URL { applicationSupportURL.appendingPathComponent("agent-profile.json") }
    private static var policyURL: URL { applicationSupportURL.appendingPathComponent("agent-policy.json") }
    private static var memoryURL: URL { applicationSupportURL.appendingPathComponent("agent-memory.json") }
}
