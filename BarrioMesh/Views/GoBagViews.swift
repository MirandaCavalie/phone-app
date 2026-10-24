import SwiftUI

/// The household's go-bag checklist, with what the agent thinks is missing.
struct GoBagView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ordering: SupplyOrder?

    var body: some View {
        let now = Date()
        let gaps = GoBag.audit(model.profile.goBag, for: model.profile, now: now)
        let readiness = GoBag.readiness(model.profile.goBag, for: model.profile, now: now)

        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                        Circle().trim(from: 0, to: CGFloat(readiness) / 100)
                            .stroke(readiness == 100 ? FaroTheme.safe : FaroTheme.beam, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(readiness)%").font(.caption.weight(.bold))
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gaps.isEmpty ? t("Mochila lista", "Go-bag ready") : t("Faltan \(gaps.count) cosas", "\(gaps.count) items to sort out"))
                            .font(.headline)
                        Text(t("Para \(model.profile.housemates.count + 1) personas, 72 horas", "For \(model.profile.housemates.count + 1) people, 72 hours"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !SupplyOrder(gaps: gaps).lines.isEmpty {
                    Button {
                        ordering = SupplyOrder(gaps: gaps)
                    } label: {
                        Label(t("Pedir lo que falta", "Order what's missing"), systemImage: "cart.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section(t("Contenido", "Contents")) {
                ForEach(GoBag.recommended(for: model.profile), id: \.label) { requirement in
                    GoBagRow(requirement: requirement, gap: gaps.first { $0.requirement == requirement })
                }
            }
        }
        .navigationTitle(t("Mochila de emergencia", "Emergency go-bag"))
        .sheet(item: Binding(get: { ordering.map(IdentifiedOrder.init) }, set: { ordering = $0?.order })) { wrapper in
            SupplyOrderView(order: wrapper.order)
        }
    }
}

struct IdentifiedOrder: Identifiable {
    let order: SupplyOrder
    var id: String { order.lines.map(\.id).joined() }
}

private struct GoBagRow: View {
    @EnvironmentObject private var model: AppModel
    let requirement: GoBag.Requirement
    let gap: GoBag.Gap?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: requirement.kind.systemImage)
                    .foregroundStyle(gap == nil ? FaroTheme.safe : FaroTheme.beam)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(requirement.label).font(.subheadline.weight(.semibold))
                    Text(gap?.status ?? t("Listo", "Ready"))
                        .font(.caption)
                        .foregroundStyle(gap == nil ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
                Spacer()
                Stepper("\(quantity)/\(requirement.quantity)", value: quantityBinding, in: 0...200)
                    .labelsHidden()
                Text("\(quantity)/\(requirement.quantity)")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 40, alignment: .trailing)
            }
            if requirement.kind.shelfLifeMonths != nil, quantity > 0 {
                DatePicker(t("Vence", "Expires"), selection: expiryBinding, displayedComponents: .date)
                    .font(.caption)
            }
        }
    }

    private var index: Int? {
        model.profile.goBag.firstIndex { $0.kind == requirement.kind && (requirement.kind != .medication || $0.label == requirement.label) }
    }

    private var quantity: Int { index.map { model.profile.goBag[$0].quantity } ?? 0 }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { quantity },
            set: { value in
                if let index {
                    model.profile.goBag[index].quantity = value
                } else {
                    let months = requirement.kind.shelfLifeMonths
                    let expiry = months.flatMap { Calendar.current.date(byAdding: .month, value: $0, to: Date()) }
                    model.profile.goBag.append(GoBagItem(kind: requirement.kind, label: requirement.kind == .medication ? requirement.label : "", quantity: value, expiresAt: expiry))
                }
            }
        )
    }

    private var expiryBinding: Binding<Date> {
        Binding(
            get: { index.flatMap { model.profile.goBag[$0].expiresAt } ?? Date() },
            set: { date in if let index { model.profile.goBag[index].expiresAt = date } }
        )
    }
}

/// Review screen: the agent prepared the order, the person decides how to send it.
struct SupplyOrderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let order: SupplyOrder
    @State private var excluded: Set<String> = []
    @State private var storeName = ""
    @State private var storePhone = ""

    private var selected: [SupplyOrder.Line] { order.lines.filter { !excluded.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order.lines) { line in
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(line.id) },
                            set: { on in if on { excluded.remove(line.id) } else { excluded.insert(line.id) } }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(line.name) ×\(line.quantity)").font(.subheadline)
                                if line.isMedication {
                                    Text(t("Con receta, en farmacia", "Prescription, at a pharmacy")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(t("Lo que preparé", "What I prepared"))
                }

                Section {
                    if let store = model.profile.trustedStore {
                        Button {
                            send(to: store)
                        } label: {
                            Label(t("Enviar por WhatsApp a \(store.name)", "Send on WhatsApp to \(store.name)"), systemImage: "paperplane.fill")
                        }
                        .disabled(selected.isEmpty)
                    } else {
                        TextField(t("Tienda o farmacia del barrio", "Neighborhood store or pharmacy"), text: $storeName)
                        TextField(t("WhatsApp con código de país", "WhatsApp with country code"), text: $storePhone)
                            .keyboardType(.phonePad)
                        Button(t("Guardar y enviar", "Save and send")) {
                            let store = FamilyContact(name: storeName, phone: storePhone)
                            model.profile.trustedStore = store
                            send(to: store)
                        }
                        .disabled(storeName.isEmpty || storePhone.filter(\.isNumber).count < 7 || selected.isEmpty)
                    }
                } header: {
                    Text(t("Tienda de confianza", "Trusted store"))
                } footer: {
                    Text(t("Abro WhatsApp con el mensaje listo. Tú confirmas precio, entrega y pago.", "I open WhatsApp with the message ready. You confirm price, delivery and payment."))
                }

                Section(t("O búscalo en línea", "Or find it online")) {
                    ForEach(selected.filter { !$0.isMedication }) { line in
                        if let url = SupplyOrder.marketplaceURL(for: line, country: model.profile.country) {
                            Link(destination: url) {
                                Label(line.name, systemImage: "magnifyingglass")
                            }
                        }
                    }
                }
            }
            .navigationTitle(t("Pedido de la mochila", "Go-bag order"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Cerrar", "Close")) { dismiss() } }
            }
        }
    }

    private func send(to store: FamilyContact) {
        let text = order.whatsAppMessage(customer: model.profile.name, area: model.profile.homeArea, lines: selected)
        guard let url = URL(string: "https://wa.me/\(store.phone)?text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") else { return }
        model.logOrder(to: store.name, lines: selected)
        openURL(url)
        dismiss()
    }
}
