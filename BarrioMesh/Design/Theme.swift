import SwiftUI

/// Faro's visual language: a night-blue sky with a warm lighthouse beam.
/// Calm by default; the beam turns to a signal red only in emergency mode.
enum FaroTheme {
    static let night = Color(red: 0.05, green: 0.09, blue: 0.17)
    static let dusk = Color(red: 0.11, green: 0.18, blue: 0.31)
    static let beam = Color(red: 1.0, green: 0.71, blue: 0.16)
    static let ember = Color(red: 0.93, green: 0.32, blue: 0.22)
    static let safe = Color(red: 0.18, green: 0.70, blue: 0.45)
    static let cardRadius: CGFloat = 20

    static func heroGradient(emergency: Bool) -> LinearGradient {
        LinearGradient(
            colors: emergency
                ? [Color(red: 0.32, green: 0.07, blue: 0.08), Color(red: 0.55, green: 0.13, blue: 0.10)]
                : [night, dusk],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct FaroCard: ViewModifier {
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FaroTheme.cardRadius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.10) } ?? Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func faroCard(tint: Color? = nil) -> some View {
        modifier(FaroCard(tint: tint))
    }
}

/// The brand mark: a beacon with its beam.
struct FaroMark: View {
    var size: CGFloat = 44
    var emergency = false

    var body: some View {
        ZStack {
            Circle()
                .fill(emergency ? FaroTheme.ember.opacity(0.85) : FaroTheme.beam.opacity(0.18))
            Circle()
                .strokeBorder((emergency ? FaroTheme.ember : FaroTheme.beam).opacity(0.45), lineWidth: 1)
            Image(systemName: "light.beacon.max.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(emergency ? Color.white : FaroTheme.beam)
                .symbolEffect(.pulse, isActive: emergency)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusChip: View {
    let text: String
    let systemImage: String
    var color: Color = .white

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

extension ActivityEntry.Kind {
    var systemImage: String {
        switch self {
        case .mode: "light.beacon.max.fill"
        case .published: "megaphone.fill"
        case .negotiation: "arrow.left.arrow.right"
        case .agreement: "hand.thumbsup.fill"
        case .checkIn: "heart.fill"
        case .family: "person.2.fill"
        case .followUp: "clock.badge.checkmark.fill"
        case .approval: "checkmark.shield.fill"
        case .outbox: "envelope.fill"
        case .alert: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .mode: FaroTheme.ember
        case .published: .blue
        case .negotiation: .purple
        case .agreement, .checkIn, .family: FaroTheme.safe
        case .followUp: .orange
        case .approval: .teal
        case .outbox: .indigo
        case .alert: FaroTheme.ember
        }
    }
}
