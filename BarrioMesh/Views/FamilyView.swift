import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var newContactName = ""
    @State private var newContactPhone = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    myStatus
                    circleCard
                    familyList
                    outbox
                    contacts
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Familia")
        }
    }

    private var myStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿Cómo estás?")
                .font(.headline)
            if let latest = model.myLatestCheckIn {
                Label("Último aviso: \(latest.status.displayName.lowercased()), \(latest.createdAt.formatted(date: .omitted, time: .shortened))",
                      systemImage: latest.status == .safe ? "heart.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(latest.status == .safe ? FaroTheme.safe : FaroTheme.ember)
            }
            HStack {
                Button {
                    model.checkIn(.safe)
                } label: {
                    Label("Estoy bien", systemImage: "heart.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FaroTheme.safe)

                Button {
                    model.checkIn(.needsHelp)
                } label: {
                    Label("Necesito ayuda", systemImage: "exclamationmark.triangle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FaroTheme.ember)
            }
            .controlSize(.large)
            .disabled(model.profile.familyCircleID == nil)

            if model.profile.familyCircleID == nil {
                Text("Primero crea el código de familia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .faroCard()
    }

    private var circleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Código de familia", systemImage: "person.badge.key.fill")
                .font(.headline)
            Text("Escribe el mismo código en el teléfono de cada familiar. Sus avisos de “estoy bien” saltan entre teléfonos cercanos hasta llegarles, sin internet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Ej.: casa-rodriguez-2026", text: $model.profile.familyCircleCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.profile.familyCircleCode.isEmpty && model.profile.familyCircleID == nil {
                Text("Usa al menos 4 letras o números.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .faroCard()
    }

    @ViewBuilder
    private var familyList: some View {
        if model.profile.familyCircleID != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Lo que sé de tu familia", systemImage: "person.2.fill")
                    .font(.headline)
                if model.familyCheckIns.isEmpty {
                    Text("Aún no llegó ningún aviso. Faro sigue escuchando.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.familyCheckIns) { checkIn in
                    HStack(alignment: .top) {
                        Image(systemName: checkIn.status == .safe ? "heart.circle.fill" : "exclamationmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(checkIn.status == .safe ? FaroTheme.safe : FaroTheme.ember)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(checkIn.authorName): \(checkIn.status.displayName.lowercased())")
                                .font(.subheadline.weight(.semibold))
                            Text("\(checkIn.area) · \(checkIn.createdAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .faroCard(tint: FaroTheme.safe)
        }
    }

    @ViewBuilder
    private var outbox: some View {
        let unsent = model.memory.unsentOutbox
        if !unsent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Mensajes listos para cuando vuelva la señal", systemImage: "envelope.badge.fill")
                    .font(.headline)
                Text(model.effectiveConnectivity == .online
                     ? "Ya hay señal. Toca para abrir el mensaje y envíalo tú."
                     : "Sin señal por ahora. Faro los guarda; los envías tú cuando vuelva.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(unsent) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.recipientName).font(.subheadline.weight(.semibold))
                        Text(item.body).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("SMS") { open(item, channel: .sms) }
                                .buttonStyle(.borderedProminent)
                            Button("WhatsApp") { open(item, channel: .whatsapp) }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            Spacer()
                            Button("Ya lo envié") { model.markSent(item) }
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .faroCard(tint: .indigo)
        }
    }

    private var contacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Contactos de familia", systemImage: "phone.fill")
                .font(.headline)
            ForEach(model.profile.familyContacts) { contact in
                HStack {
                    Text(contact.name)
                    Spacer()
                    Text("+\(contact.phone)").foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        model.profile.familyContacts.removeAll { $0.id == contact.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline)
            }
            HStack {
                TextField("Nombre", text: $newContactName)
                TextField("Teléfono con país", text: $newContactPhone)
                    .keyboardType(.phonePad)
                Button("Agregar") {
                    model.profile.familyContacts.append(FamilyContact(name: newContactName, phone: newContactPhone))
                    newContactName = ""
                    newContactPhone = ""
                }
                .disabled(newContactName.isEmpty || newContactPhone.filter(\.isNumber).count < 7)
            }
            .textFieldStyle(.roundedBorder)
            .font(.subheadline)
        }
        .faroCard()
    }

    private func open(_ item: OutboxItem, channel: OutboxItem.Channel) {
        var components = URLComponents()
        switch channel {
        case .sms:
            components.scheme = "sms"
            components.path = "+\(item.phone)"
            components.queryItems = [URLQueryItem(name: "body", value: item.body)]
        case .whatsapp:
            components.scheme = "https"
            components.host = "wa.me"
            components.path = "/\(item.phone)"
            components.queryItems = [URLQueryItem(name: "text", value: item.body)]
        }
        if let url = components.url { openURL(url) }
    }
}
