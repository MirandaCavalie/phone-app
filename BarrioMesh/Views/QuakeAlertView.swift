import SwiftUI
import UIKit

/// Full-screen alert when only this phone felt shaking: a short window to cancel a false alarm.
struct QuakeAlertView: View {
    @EnvironmentObject private var model: AppModel
    let alert: AppModel.QuakeAlert

    var body: some View {
        ZStack {
            FaroTheme.heroGradient(emergency: true).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 72, weight: .bold))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("¿Está temblando?")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Este teléfono sintió un movimiento \(alert.event.intensity.displayName) durante \(Int(alert.event.duration.rounded())) segundos.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(alert.deadline.timeIntervalSince(context.date).rounded(.up)))
                    VStack(spacing: 6) {
                        Text("\(remaining)")
                            .font(.system(size: 96, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("Faro se activa al llegar a cero")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                Text("Cúbrete, agáchate y sujétate. Aléjate de ventanas.")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: Capsule())

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        model.confirmQuakeNow()
                    } label: {
                        Text("Activar ahora").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(FaroTheme.ember)

                    Button(t("Falsa alarma, cancelar", "False alarm, cancel")) { model.cancelQuakeAlert() }
                        .font(.headline)
                        .tint(.white)
                }
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
