import SwiftUI

/// One relative: who they are, their medical card and where they usually are.
struct MemberEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var member: HouseholdMember
    let isNew: Bool
    @State private var showingCard = false
    @State private var newCondition = ""
    @State private var newAllergy = ""

    var body: some View {
        Form {
            Section {
                TextField(t("Nombre", "Name"), text: $member.name)
                TextField(t("Parentesco (mamá, hijo…)", "Relation (mom, son…)"), text: $member.relation)
                Toggle(t("Vive conmigo", "Lives with me"), isOn: $member.livesWithUser)
                TextField(t("Teléfono", "Phone"), text: $member.phone)
                    .keyboardType(.phonePad)
            }

            Section(t("Ficha médica", "Medical card")) {
                Picker(t("Año de nacimiento", "Birth year"), selection: birthYear) {
                    Text("—").tag(0)
                    ForEach((1925...2026).reversed(), id: \.self) { Text(String($0)).tag($0) }
                }
                Picker(t("Tipo de sangre", "Blood type"), selection: $member.medical.bloodType) {
                    Text("—").tag("")
                    ForEach(["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"], id: \.self) { Text($0).tag($0) }
                }
                Picker(t("Movilidad", "Mobility"), selection: $member.medical.mobility) {
                    ForEach(MedicalCard.Mobility.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle(t("Usa un equipo eléctrico (oxígeno, CPAP…)", "Uses a powered device (oxygen, CPAP…)"), isOn: $member.medical.usesPoweredDevice)
                tagList(t("Condiciones", "Conditions"), items: $member.medical.conditions, draft: $newCondition)
                tagList(t("Alergias", "Allergies"), items: $member.medical.allergies, draft: $newAllergy)
            }

            Section {
                ForEach($member.medical.medications) { $medication in
                    MedicationRow(medication: $medication)
                }
                .onDelete { member.medical.medications.remove(atOffsets: $0) }
                Button(t("Agregar medicamento", "Add medication")) {
                    member.medical.medications.append(Medication(name: "", times: [8 * 60]))
                }
            } header: {
                Text(t("Medicamentos", "Medications"))
            } footer: {
                Text(t("Si necesita frío y se va la luz, Faro pide energía primero.", "If it needs cooling and power goes out, Faro asks for power first."))
            }

            Section {
                ForEach($member.routine) { $block in
                    RoutineRow(block: $block)
                }
                .onDelete { member.routine.remove(atOffsets: $0) }
                Button(t("Agregar lugar habitual", "Add a usual place")) {
                    member.routine.append(RoutineBlock(place: "", weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60, endMinute: 14 * 60))
                }
            } header: {
                Text(t("Dónde suele estar", "Where they usually are"))
            } footer: {
                Text(t("Si tiembla, Faro te dice dónde debería estar y su punto de encuentro.", "If the ground shakes, Faro tells you where they should be and their meeting point."))
            }

            Section(t("Médico", "Doctor")) {
                TextField(t("Nombre", "Name"), text: $member.medical.doctor)
                TextField(t("Teléfono", "Phone"), text: $member.medical.doctorPhone)
                    .keyboardType(.phonePad)
                TextField(t("Notas para rescatistas", "Notes for responders"), text: $member.medical.notes, axis: .vertical)
            }

            if !isNew {
                Section {
                    Button(t("Eliminar familiar", "Remove relative"), role: .destructive) {
                        model.profile.household.removeAll { $0.id == member.id }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(member.name.isEmpty ? t("Familiar", "Relative") : member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCard = true
                } label: {
                    Label(t("Ficha", "Card"), systemImage: "cross.case.fill")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Guardar", "Save")) { save() }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showingCard) {
            MedicalCardView(member: member)
        }
    }

    private var birthYear: Binding<Int> {
        Binding(get: { member.medical.birthYear ?? 0 }, set: { member.medical.birthYear = $0 == 0 ? nil : $0 })
    }

    private func save() {
        if let index = model.profile.household.firstIndex(where: { $0.id == member.id }) {
            model.profile.household[index] = member
        } else {
            model.profile.household.append(member)
        }
        dismiss()
    }

    private func tagList(_ title: String, items: Binding<[String]>, draft: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if !items.wrappedValue.isEmpty {
                Text(items.wrappedValue.joined(separator: " · "))
                    .font(.subheadline)
            }
            HStack {
                TextField(t("Agregar…", "Add…"), text: draft)
                    .onSubmit { add(draft, to: items) }
                if !items.wrappedValue.isEmpty {
                    Button { items.wrappedValue.removeLast() } label: { Image(systemName: "delete.left") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func add(_ draft: Binding<String>, to items: Binding<[String]>) {
        let value = draft.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        items.wrappedValue.append(value)
        draft.wrappedValue = ""
    }
}

private struct MedicationRow: View {
    @Binding var medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(t("Medicamento", "Medication"), text: $medication.name)
                TextField(t("Dosis", "Dose"), text: $medication.dose)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
            HStack {
                ForEach(medication.times.indices, id: \.self) { index in
                    DatePicker("", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Button { medication.times.append(20 * 60) } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
            }
            Toggle(t("Necesita refrigeración", "Needs refrigeration"), isOn: $medication.needsRefrigeration)
                .font(.subheadline)
            Stepper(t("Quedan \(medication.supplyDays ?? 0) días", "\(medication.supplyDays ?? 0) days left"),
                    value: Binding(get: { medication.supplyDays ?? 0 }, set: { medication.supplyDays = $0 }), in: 0...180)
                .font(.subheadline)
        }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: medication.times[index] / 60, minute: medication.times[index] % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                medication.times[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

private struct RoutineRow: View {
    @Binding var block: RoutineBlock

    private let days: [(Int, String)] = [(2, "L"), (3, "M"), (4, "X"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]
    private let daysEnglish: [(Int, String)] = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(t("Lugar (colegio, trabajo…)", "Place (school, work…)"), text: $block.place)
                .font(.subheadline.weight(.semibold))
            TextField(t("Zona", "Area"), text: $block.area)
            TextField(t("Punto de encuentro del lugar", "The place's meeting point"), text: $block.meetingPoint)
            HStack(spacing: 6) {
                ForEach(Lang.isSpanish ? days : daysEnglish, id: \.0) { day, letter in
                    let on = block.weekdays.contains(day)
                    Button(letter) {
                        if on { block.weekdays.remove(day) } else { block.weekdays.insert(day) }
                    }
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                    .foregroundStyle(on ? .white : .primary)
                    .buttonStyle(.plain)
                }
            }
            HStack {
                DatePicker(t("Desde", "From"), selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker(t("Hasta", "To"), selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<RoutineBlock, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: block[keyPath: keyPath] / 60, minute: block[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                block[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// Large, high-contrast card to hand to a paramedic. Works offline.
struct MedicalCardView: View {
    @Environment(\.dismiss) private var dismiss
    let member: HouseholdMember

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "cross.case.fill").font(.largeTitle).foregroundStyle(FaroTheme.ember)
                        VStack(alignment: .leading) {
                            Text(member.name).font(.largeTitle.weight(.heavy))
                            Text([member.relation, member.medical.age.map { t("\($0) años", "\($0) years old") }].compactMap { $0 }.joined(separator: " · "))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !member.medical.bloodType.isEmpty {
                        field(t("Tipo de sangre", "Blood type"), member.medical.bloodType, big: true)
                    }
                    if !member.medical.allergies.isEmpty {
                        field(t("Alergias", "Allergies"), member.medical.allergies.joined(separator: ", "), alert: true)
                    }
                    if !member.medical.conditions.isEmpty {
                        field(t("Condiciones", "Conditions"), member.medical.conditions.joined(separator: ", "))
                    }
                    if !member.medical.medications.isEmpty {
                        field(t("Medicamentos", "Medications"), member.medical.medications.map { medication in
                            var line = medication.name
                            if !medication.dose.isEmpty { line += " \(medication.dose)" }
                            if !medication.times.isEmpty {
                                line += " · " + medication.times.map { String(format: "%d:%02d", $0 / 60, $0 % 60) }.joined(separator: ", ")
                            }
                            if medication.needsRefrigeration { line += t(" · refrigerar", " · keep cold") }
                            return line
                        }.joined(separator: "\n"))
                    }
                    if member.medical.mobility != .independent || member.medical.usesPoweredDevice {
                        field(t("Movilidad", "Mobility"), [member.medical.mobility.displayName, member.medical.usesPoweredDevice ? t("usa equipo eléctrico", "uses a powered device") : nil].compactMap { $0 }.joined(separator: " · "))
                    }
                    if !member.medical.doctor.isEmpty {
                        field(t("Médico", "Doctor"), member.medical.doctorPhone.isEmpty ? member.medical.doctor : "\(member.medical.doctor) · +\(member.medical.doctorPhone)")
                    }
                    if !member.medical.notes.isEmpty {
                        field(t("Notas", "Notes"), member.medical.notes)
                    }
                    if member.medical.isEmpty {
                        Text(t("Aún no hay datos médicos.", "No medical details yet."))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(t("Cerrar", "Close")) { dismiss() } }
            }
        }
    }

    private func field(_ title: String, _ value: String, big: Bool = false, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(alert ? FaroTheme.ember : .secondary)
            Text(value).font(big ? .system(size: 44, weight: .heavy) : .title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background((alert ? FaroTheme.ember : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}
