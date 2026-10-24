import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = LaunchOptions.tab

    var body: some View {
        Group {
            if model.profile.isConfigured {
                tabs
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(isPresented: quakeIsPresented) {
            if let alert = model.quakeAlert {
                QuakeAlertView(alert: alert)
            }
        }
        .alert("Aviso de la red", isPresented: alertIsPresented) {
            Button("Entendido", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Faro", systemImage: "light.beacon.max.fill") }
                .badge(model.memory.pending.count)
                .tag(0)

            FamilyView()
                .tabItem { Label("Familia", systemImage: "person.2.fill") }
                .badge(model.memory.unsentOutbox.count)
                .tag(1)

            NeighborsView()
                .tabItem { Label("Vecinos", systemImage: "house.and.flag.fill") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }

    private var quakeIsPresented: Binding<Bool> {
        Binding(
            get: { model.quakeAlert != nil },
            set: { if !$0, model.quakeAlert != nil { model.cancelQuakeAlert() } }
        )
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }
}

/// Launch arguments for rehearsals and screenshots, e.g. `-faro-tab 2` or `-faro-sheet paperwork`.
enum LaunchOptions {
    static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var tab: Int { value(after: "-faro-tab").flatMap(Int.init) ?? 0 }
    static var sheet: String? { value(after: "-faro-sheet") }
}
