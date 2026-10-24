import Foundation
import Security

/// The API key lives in the Keychain, typed by the person in Profile. Never in code or logs.
enum CloudKeyStore {
    private static let service = "com.faro.anthropic"
    private static let account = "api-key"

    static var key: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        clear()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(key.utf8)
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as CFDictionary)
    }
}

/// Something the online agent wants to do. Shown in the chat; runs only when the person confirms.
struct ProposedAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case publish(PostKind, ResourceKind, Int, String)
        case note(agentID: String, name: String, text: String)
        case calendar(title: String, start: Date, minutes: Int)
        case order
        case emergency(Bool)
        case checkIn(SafetyStatus)
        case whatsapp(name: String, phone: String, text: String)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}

/// With internet, Faro's brain is Claude with tools over the agent's own state, web
/// search for live context, and actions that always wait for the person's OK.
/// Without internet the app falls back to the on-device model and the local engine.
@MainActor
final class OnlineBrain {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Reply {
        let text: String
        let actions: [ProposedAction]
        let searched: Bool
    }

    enum BrainError: Error, LocalizedError {
        case noKey, http(Int, String), refused, badResponse

        var errorDescription: String? {
            switch self {
            case .noKey: t("Falta la API key.", "Missing API key.")
            case let .http(code, message): "HTTP \(code): \(message)"
            case .refused: t("El modelo no pudo ayudar con eso.", "The model declined that request.")
            case .badResponse: t("Respuesta inesperada.", "Unexpected response.")
            }
        }
    }

    /// The running conversation, kept exactly as the API returned it (thinking blocks included).
    private(set) var messages: [[String: Any]] = []

    func reset() { messages = [] }

    func ask(_ question: String, model app: AppModel) async throws -> Reply {
        guard let key = CloudKeyStore.key, !key.isEmpty else { throw BrainError.noKey }
        messages.append(["role": "user", "content": question])
        var actions: [ProposedAction] = []
        var searched = false

        for _ in 0..<8 {
            let response = try await send(key: key, system: systemPrompt(app))
            guard let content = response["content"] as? [[String: Any]],
                  let stop = response["stop_reason"] as? String else { throw BrainError.badResponse }
            messages.append(["role": "assistant", "content": content])
            if content.contains(where: { ($0["type"] as? String) == "server_tool_use" }) { searched = true }

            switch stop {
            case "tool_use":
                var results: [[String: Any]] = []
                for block in content where (block["type"] as? String) == "tool_use" {
                    guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]
                    let (output, action) = run(tool: name, input: input, app: app)
                    if let action { actions.append(action) }
                    results.append(["type": "tool_result", "tool_use_id": id, "content": output])
                }
                messages.append(["role": "user", "content": results])
            case "pause_turn":
                continue  // The server-side search loop resumes from the trailing assistant turn.
            case "refusal":
                throw BrainError.refused
            default:
                let text = content
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                return Reply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), actions: actions, searched: searched)
            }
        }
        return Reply(text: t("Hice varias acciones; revísalas abajo.", "I took several steps; review them below."), actions: actions, searched: searched)
    }

    // MARK: - Request

    private func send(key: String, system: String) async throws -> [String: Any] {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": "medium"],
            "fallbacks": "default",
            "system": system,
            "tools": Self.tools,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BrainError.badResponse }
        guard code == 200 else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            // Drop the turn that failed so the next question starts clean.
            if messages.last?["role"] as? String == "user" { messages.removeLast() }
            throw BrainError.http(code, message)
        }
        return json
    }

    private func systemPrompt(_ app: AppModel) -> String {
        """
        You are Faro, the personal emergency agent of \(app.profile.name), who lives in \(app.profile.homeArea), \(app.profile.country.displayName). \
        Your job is to keep their household safe and ready: answer, research and act on their behalf through your tools.

        Reply in \(Lang.isSpanish ? "Spanish (use tú)" : "English"), short and warm, the way a capable friend texts. \
        Look things up with the read tools before answering questions about family, alerts, the go-bag, calendar or neighbors; never invent those facts. \
        Use web search for live context (official alerts, news about an earthquake, shelters, pharmacies or stores open nearby) and say where information came from.

        Action tools only propose: the person confirms each one on screen. Propose what genuinely helps and say so briefly; do not claim an action already happened. \
        If the network may fail soon, prefer actions that also work offline: messages to trusted people travel over Bluetooth.

        Never give medical diagnoses or dosages. If someone's life may be at risk, tell them to call \(app.profile.country.emergencyNumber) first. \
        Never share exact home addresses; use approximate areas and public meeting points.
        Current time: \(Date().formatted(date: .complete, time: .shortened)). Mode: \(app.memory.emergencyActive ? "emergency" : "normal").
        """
    }

    // MARK: - Tools

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description, "input_schema": ["type": "object", "properties": properties, "required": required]]
    }

    private static let tools: [[String: Any]] = [
        ["type": "web_search_20260209", "name": "web_search", "max_uses": 3],
        tool("get_situation", "Current mode, connectivity, nearby phones, pending questions and the agent's latest actions."),
        tool("get_family", "Household members with likely location now, medical card summaries, family check-ins, trusted people and their latest updates and messages."),
        tool("get_alerts", "Official quake, tsunami, flood and volcano alerts near home, plus regional activity in the last 24 h."),
        tool("get_go_bag", "Emergency go-bag readiness and missing, short or expiring items."),
        tool("get_calendar", "The person's calendar events today and upcoming medication doses."),
        tool("get_neighborhood", "Needs and offers posted by nearby neighbors, and agreed handoffs."),
        tool("publish_request", "Propose posting a need or an offer to nearby neighbors' agents over the mesh.", [
            "kind": ["type": "string", "enum": ["need", "offer"]],
            "resource": ["type": "string", "enum": ResourceKind.allCases.map(\.rawValue)],
            "quantity": ["type": "integer", "minimum": 1, "maximum": 99],
            "note": ["type": "string"]
        ], required: ["kind", "resource", "quantity"]),
        tool("message_trusted_person", "Propose sending a short encrypted message to a trusted person. Works without internet over Bluetooth.", [
            "name": ["type": "string", "description": "Trusted person's name"],
            "text": ["type": "string"]
        ], required: ["name", "text"]),
        tool("add_calendar_event", "Propose adding an event to the person's calendar.", [
            "title": ["type": "string"],
            "start": ["type": "string", "description": "ISO 8601 date-time with time zone"],
            "duration_minutes": ["type": "integer", "minimum": 5, "maximum": 600]
        ], required: ["title", "start", "duration_minutes"]),
        tool("prepare_supply_order", "Propose preparing the order for missing go-bag items (WhatsApp to the trusted store or online search)."),
        tool("set_emergency_mode", "Propose turning emergency mode on or off.", ["active": ["type": "boolean"]], required: ["active"]),
        tool("send_check_in", "Propose telling the family circle the person is OK or needs help.", [
            "status": ["type": "string", "enum": ["safe", "needsHelp"]]
        ], required: ["status"]),
        tool("draft_whatsapp", "Propose opening WhatsApp with a drafted message to a family contact or relative.", [
            "name": ["type": "string"],
            "text": ["type": "string"]
        ], required: ["name", "text"])
    ]

    private func run(tool name: String, input: [String: Any], app: AppModel) -> (String, ProposedAction?) {
        let proposed = t("Propuesto. Espera la confirmación de la persona en pantalla.", "Proposed. Waiting for the person to confirm on screen.")
        switch name {
        case "get_situation":
            let snapshot = app.snapshot
            var lines = [
                "mode: \(app.memory.emergencyActive ? "emergency" : "normal")",
                "internet: \(app.effectiveConnectivity == .online)",
                "nearby_phones: \(snapshot.connectedPeers + app.simulatedNeighborCount)",
                "unsent_family_messages: \(app.memory.unsentOutbox.count)"
            ]
            lines += app.memory.pending.map { "pending_question: \($0.title)" }
            lines += app.memory.log.prefix(8).map { "recent_action: \($0.title). \($0.detail)" }
            return (lines.joined(separator: "\n"), nil)
        case "get_family":
            var lines = app.snapshot.whereaboutsLines + app.snapshot.familyLines
            for person in app.memory.trusted where person.status == .active {
                var line = "trusted: \(person.name)"
                if let update = app.memory.trustedUpdates[person.agentID] {
                    line += ", latest: \(update.status?.displayName ?? "-") in \(update.area) at \(update.sentAt.formatted(date: .omitted, time: .shortened))"
                }
                lines.append(line)
                lines += app.memory.trustedNotes.filter { $0.agentID == person.agentID }.suffix(3)
                    .map { "  message \($0.fromMe ? "to" : "from") \(person.name): \($0.text)" }
            }
            return (lines.isEmpty ? "No family data yet." : lines.joined(separator: "\n"), nil)
        case "get_alerts":
            var lines = app.officialAlerts.map { "relevant: \($0.assessment.headline) — \($0.alert.place) (\($0.alert.source))" }
            lines += app.hazardMonitor.regional.prefix(10).map {
                "regional: \($0.kind.rawValue) M\(String(format: "%.1f", $0.magnitude)) \($0.place) at \($0.occurredAt.formatted(date: .omitted, time: .shortened)) (\($0.source))"
            }
            return (lines.isEmpty ? "No alerts near \(app.profile.approximateLocation.label) in the last 24 h." : lines.joined(separator: "\n"), nil)
        case "get_go_bag":
            let gaps = GoBag.audit(app.profile.goBag, for: app.profile, now: Date())
            let ready = GoBag.readiness(app.profile.goBag, for: app.profile, now: Date())
            let lines = ["readiness: \(ready)%", "trusted_store: \(app.profile.trustedStore?.name ?? "none")"] + gaps.map(\.summary)
            return (lines.joined(separator: "\n"), nil)
        case "get_calendar":
            var lines = app.assistant.todayEvents.map { "event: \($0.title) at \($0.start.formatted(date: .omitted, time: .shortened)) \($0.location)" }
            lines += ProactiveAgent.upcomingDoses(profile: app.profile, now: Date()).map {
                "dose: \($0.member.name) \($0.medication.name) at \($0.at.formatted(date: .omitted, time: .shortened))"
            }
            return (lines.isEmpty ? "Nothing scheduled today." : lines.joined(separator: "\n"), nil)
        case "get_neighborhood":
            let lines = app.snapshot.neighborhoodLines + app.snapshot.agreementLines.map { "agreed: \($0)" }
            return (lines.isEmpty ? "No neighbor posts yet." : lines.joined(separator: "\n"), nil)
        case "publish_request":
            guard let kind = PostKind(rawValue: input["kind"] as? String ?? ""),
                  let resource = ResourceKind(rawValue: input["resource"] as? String ?? "") else { return ("Invalid input.", nil) }
            let quantity = max(1, input["quantity"] as? Int ?? 1)
            let note = input["note"] as? String ?? ""
            let title = kind == .need ? t("Pedir \(resource.amount(quantity))", "Request \(resource.amount(quantity))") : t("Ofrecer \(resource.amount(quantity))", "Offer \(resource.amount(quantity))")
            return (proposed, ProposedAction(kind: .publish(kind, resource, quantity, note), title: title, detail: t("A los agentes cercanos, en \(app.profile.homeArea)", "To nearby agents, in \(app.profile.homeArea)")))
        case "message_trusted_person":
            let name = input["name"] as? String ?? ""
            let text = input["text"] as? String ?? ""
            guard let person = app.memory.activeTrusted.first(where: { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }) else {
                let names = app.memory.activeTrusted.map(\.name).joined(separator: ", ")
                return ("No trusted person named \(name). Trusted people: \(names.isEmpty ? "none" : names).", nil)
            }
            return (proposed, ProposedAction(kind: .note(agentID: person.agentID, name: person.name, text: text), title: t("Mensaje a \(person.name)", "Message \(person.name)"), detail: text))
        case "add_calendar_event":
            let title = input["title"] as? String ?? ""
            let formatter = ISO8601DateFormatter()
            guard let start = formatter.date(from: input["start"] as? String ?? "") else { return ("Invalid start date; use ISO 8601 with time zone.", nil) }
            let minutes = input["duration_minutes"] as? Int ?? 30
            return (proposed, ProposedAction(kind: .calendar(title: title, start: start, minutes: minutes), title: t("Agendar: \(title)", "Schedule: \(title)"), detail: start.formatted(date: .abbreviated, time: .shortened)))
        case "prepare_supply_order":
            let lines = SupplyOrder(gaps: GoBag.audit(app.profile.goBag, for: app.profile, now: Date())).lines
            guard !lines.isEmpty else { return ("The go-bag is complete; nothing to order.", nil) }
            return (proposed, ProposedAction(kind: .order, title: t("Preparar pedido de la mochila", "Prepare go-bag order"), detail: lines.prefix(3).map { "\($0.name) ×\($0.quantity)" }.joined(separator: ", ")))
        case "set_emergency_mode":
            let active = input["active"] as? Bool ?? true
            return (proposed, ProposedAction(kind: .emergency(active), title: active ? t("Activar modo emergencia", "Start emergency mode") : t("Volver a modo normal", "Back to normal"), detail: ""))
        case "send_check_in":
            let status = SafetyStatus(rawValue: input["status"] as? String ?? "") ?? .safe
            return (proposed, ProposedAction(kind: .checkIn(status), title: t("Avisar a la familia: \(status.inlineName)", "Tell family: \(status.displayName)"), detail: ""))
        case "draft_whatsapp":
            let name = input["name"] as? String ?? ""
            let text = input["text"] as? String ?? ""
            let phone = app.profile.familyContacts.first { $0.name.localizedCaseInsensitiveContains(name) }?.phone
                ?? app.profile.household.first { $0.name.localizedCaseInsensitiveContains(name) && !$0.phone.isEmpty }?.phone
            guard let phone else { return ("No phone number saved for \(name).", nil) }
            return (proposed, ProposedAction(kind: .whatsapp(name: name, phone: phone, text: text), title: t("WhatsApp a \(name)", "WhatsApp \(name)"), detail: text))
        default:
            return ("Unknown tool.", nil)
        }
    }
}
