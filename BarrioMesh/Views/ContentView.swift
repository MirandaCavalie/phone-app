import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            BoardView()
                .tabItem { Label("Barrio", systemImage: "square.grid.2x2.fill") }

            MatchesView()
                .tabItem { Label("Matches", systemImage: "arrow.left.arrow.right.circle.fill") }
                .badge(pendingMatches)

            NetworkView()
                .tabItem { Label("Red", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .tint(.indigo)
        .alert("Aviso de la red", isPresented: alertIsPresented) {
            Button("Entendido", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var pendingMatches: Int {
        model.matchSummaries.filter { $0.status == .suggested || $0.status == .waiting }.count
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }
}
