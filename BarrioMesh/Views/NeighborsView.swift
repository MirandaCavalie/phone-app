import SwiftUI

/// The shared neighborhood board and the agent negotiations happening on it.
struct NeighborsView: View {
    @EnvironmentObject private var model: AppModel

    private enum Section: String, CaseIterable, Identifiable {
        case board
        case matches
        var id: String { rawValue }
        var title: String {
            switch self {
            case .board: t("Pedidos y ofertas", "Needs & offers")
            case .matches: t("Coordinación", "Handoffs")
            }
        }
    }

    @State private var section: Section = .board

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(t("Sección", "Section"), selection: $section) {
                    ForEach(Section.allCases) { Text($0.title).tag($0) }
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
            .navigationTitle(t("Vecinos", "Neighbors"))
        }
    }
}
