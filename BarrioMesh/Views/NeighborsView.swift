import SwiftUI

/// The shared neighborhood board and the agent negotiations happening on it.
struct NeighborsView: View {
    @EnvironmentObject private var model: AppModel

    private enum Section: String, CaseIterable, Identifiable {
        case board = "Pedidos y ofertas"
        case matches = "Coordinación"
        var id: String { rawValue }
    }

    @State private var section: Section = .board

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sección", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch section {
                case .board: BoardView()
                case .matches: MatchesView()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Vecinos")
        }
    }
}
