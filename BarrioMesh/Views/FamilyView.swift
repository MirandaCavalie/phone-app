import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var newContactName = ""
    @State private var newContactPhone = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusButtons
                } footer: {
                    if let latest = model.myLatestCheckIn {
                        Text(t("Último aviso: \(latest.status.displayName.lowercased()), \(latest.createdAt.formatted(date: .omitted, time: .shortened))",
                               "Last update: \(latest.status.displayName), \(latest.createdAt.formatted(date: .omitted, time: .shortened))"))
                    } else if model.profile.familyCircleID == nil {
                        Text(t("Primero crea el código de familia.", "Create a family code first."))
                    }
                }

                Section {
                    ForEach(model.profile.household) { member in
                        NavigationLink {
                            MemberEditorView(member: member, isNew: false)
                        } label: {
                            MemberRow(member: member)
                        }
                    }
                    NavigationLink {
                        MemberEditorView(member: HouseholdMember(name: "", relation: ""), isNew: true)
                    } label: {
                        Label(t("Agregar familiar", "Add relative"), systemImage: "person.badge.plus")
                    }
                } header: {
                    Text(t("Personas", "People"))
                }

                if model.profile.familyCircleID != nil {
                    Section(t("Avisos recibidos", "Check-ins received")) {
                        if model.familyCheckIns.isEmpty {
                            Text(t("Aún sin noticias. Sigo escuchando.", "No word yet. Still listening."))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.familyCheckIns) { checkIn in
                            HStack(spacing: 10) {
                                Image(systemName: checkIn.status == .safe ? "heart.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(checkIn.status == .safe ? FaroTheme.safe : FaroTheme.ember)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(checkIn.authorName): \(checkIn.status.displayName.lowercased())")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(checkIn.area) · \(checkIn.createdAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !model.memory.unsentOutbox.isEmpty {
                    Section {
                        ForEach(model.memory.unsentOutbox) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.recipientName).font(.subheadline.weight(.semibold))
                                Text(item.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                HStack {
                                    Button("SMS") { open(item, channel: .sms) }
                                        .buttonStyle(.borderedProminent)
                                    Button("WhatsApp") { open(item, channel: .whatsapp) }
                                        .buttonStyle(.bordered)
                                        .tint(.green)
                                    Spacer()
                                    Button(t("Enviado", "Sent")) { model.markSent(item) }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                }
                                .controlSize(.small)
                            }
                        }
                    } header: {
                        Text(t("Listos para enviar", "Ready to send"))
                    } footer: {
                        Text(model.effectiveConnectivity == .online
                             ? t("Hay señal: ábrelo y envíalo tú.", "Signal is back: open it and send.")
                             : t("Sin señal. Se envían cuando vuelva.", "No signal. Send them when it returns."))
                    }
                }

                Section {
                    HStack {
                        TextField(t("Código", "Code"), text: $model.profile.familyCircleCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(t("Generar", "Generate")) { model.profile.familyCircleCode = FamilyCircle.suggestCode() }
                            .buttonStyle(.borderless)
                        if !model.profile.familyCircleCode.isEmpty {
                            ShareLink(item: t("Mi código de familia en Faro: \(model.profile.familyCircleCode)", "My Faro family code: \(model.profile.familyCircleCode)")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text(t("Código de familia", "Family code"))
                } footer: {
                    Text(!model.profile.familyCircleCode.isEmpty && model.profile.familyCircleID == nil
                         ? t("Usa al menos 4 letras o números.", "Use at least 4 letters or numbers.")
                         : t("El mismo código en cada teléfono. Los avisos viajan cifrados.", "Same code on every phone. Check-ins travel encrypted."))
                }

                Section(t("Contactos", "Contacts")) {
                    ForEach(model.profile.familyContacts) { contact in
                        LabeledContent(contact.name, value: "+\(contact.phone)")
                    }
                    .onDelete { model.profile.familyContacts.remove(atOffsets: $0) }
                    HStack {
                        TextField(t("Nombre", "Name"), text: $newContactName)
                        TextField(t("Teléfono", "Phone"), text: $newContactPhone)
                            .keyboardType(.phonePad)
                        Button {
                            model.profile.familyContacts.append(FamilyContact(name: newContactName, phone: newContactPhone))
                            newContactName = ""
                            newContactPhone = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newContactName.isEmpty || newContactPhone.filter(\.isNumber).count < 7)
                    }
                }
            }
            .navigationTitle(t("Familia", "Family"))
        }
    }

    private struct MemberRow: View {
        @EnvironmentObject private var model: AppModel
        let member: HouseholdMember

        var body: some View {
            let location = FamilyLocator.likelyLocation(of: member, at: Date(), homeArea: model.profile.homeArea)
            HStack(spacing: 12) {
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(member.isVulnerable ? FaroTheme.ember : Color.accentColor, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.name).font(.subheadline.weight(.semibold))
                    Text([member.relation, location.description].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !member.medical.medications.isEmpty {
                    Image(systemName: "pills.fill").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusButtons: some View {
        HStack(spacing: 10) {
            Button { model.checkIn(.safe) } label: {
                Label(t("Estoy bien", "I'm OK"), systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FaroTheme.safe)

            Button { model.checkIn(.needsHelp) } label: {
                Label(t("Ayuda", "Help"), systemImage: "exclamationmark.triangle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FaroTheme.ember)
        }
        .controlSize(.large)
        .disabled(model.profile.familyCircleID == nil)
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .listRowBackground(Color.clear)
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
