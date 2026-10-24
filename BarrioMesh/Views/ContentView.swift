import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

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
        TabView {
            HomeView()
                .tabItem { Label("Faro", systemImage: "light.beacon.max.fill") }
                .badge(model.memory.pending.count)

            FamilyView()
                .tabItem { Label("Familia", systemImage: "person.2.fill") }
                .badge(model.memory.unsentOutbox.count)

            NeighborsView()
                .tabItem { Label("Vecinos", systemImage: "house.and.flag.fill") }

            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
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
