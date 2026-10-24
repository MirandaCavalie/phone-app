import SwiftUI

/// A live picture of the offline network: you in the center, the phones your agent
/// can reach around you, beams for the handoffs it agreed and hearts for family.
struct MeshRadarView: View {
    struct Node: Identifiable, Equatable {
        enum Kind { case peer, relayed, agreement, family }
        let id: String
        let name: String
        let kind: Kind
    }

    let nodes: [Node]
    var emergency = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rx = size.width / 2 - 36
                let ry = size.height / 2 - 24
                let radius = max(rx, ry)
                let beam = emergency ? FaroTheme.beam : FaroTheme.safe

                // Static rings.
                for fraction in [0.45, 0.8] {
                    canvas.stroke(Path(ellipseIn: CGRect(x: center.x - rx * fraction, y: center.y - ry * fraction, width: rx * fraction * 2, height: ry * fraction * 2)),
                                  with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
                // Expanding pulses: the phone advertising itself over Bluetooth.
                for offset in [0.0, 0.5] {
                    let phase = (t / 2.4 + offset).truncatingRemainder(dividingBy: 1)
                    canvas.stroke(Path(ellipseIn: CGRect(x: center.x - rx * phase, y: center.y - ry * phase, width: rx * phase * 2, height: ry * phase * 2)),
                                  with: .color(beam.opacity(0.5 * (1 - phase))), lineWidth: 2)
                }
                // Sweeping beam, like a lighthouse.
                let angle = Angle.radians(t * 0.9)
                var sweep = Path()
                sweep.move(to: center)
                sweep.addArc(center: center, radius: radius, startAngle: angle - .degrees(22), endAngle: angle, clockwise: false)
                sweep.closeSubpath()
                canvas.fill(sweep, with: .linearGradient(
                    Gradient(colors: [beam.opacity(0), beam.opacity(0.28)]),
                    startPoint: center,
                    endPoint: CGPoint(x: center.x + cos(angle.radians) * radius, y: center.y + sin(angle.radians) * radius)
                ))

                for (index, node) in nodes.enumerated() {
                    let point = position(for: node, index: index, center: center, rx: rx, ry: ry)
                    if node.kind != .relayed {
                        var link = Path()
                        link.move(to: center)
                        link.addLine(to: point)
                        let color: Color = node.kind == .agreement ? FaroTheme.safe : node.kind == .family ? .pink : .white
                        canvas.stroke(link, with: .color(color.opacity(node.kind == .peer ? 0.25 : 0.7)),
                                      style: StrokeStyle(lineWidth: node.kind == .peer ? 1 : 2, dash: node.kind == .peer ? [] : [4, 4], dashPhase: -t * 12))
                    }
                    let dot: CGFloat = node.kind == .relayed ? 7 : 11
                    canvas.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)),
                                with: .color(color(for: node)))
                    canvas.draw(
                        Text(label(for: node)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.9)),
                        at: CGPoint(x: point.x, y: point.y + 14)
                    )
                }

                // You.
                canvas.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)), with: .color(beam))
                canvas.draw(Text(t("Tú", "You")).font(.caption.weight(.bold)).foregroundStyle(.white), at: CGPoint(x: center.x, y: center.y + 20))
            }
        }
        .frame(height: 230)
        .accessibilityElement()
        .accessibilityLabel(t("Red cercana: \(nodes.count) teléfonos", "Nearby network: \(nodes.count) phones"))
    }

    private func label(for node: Node) -> String {
        let name = node.name.replacingOccurrences(of: " (simulado)", with: "*").replacingOccurrences(of: " (simulated)", with: "*")
        switch node.kind {
        case .family: return "♥ \(name)"
        default: return name
        }
    }

    private func color(for node: Node) -> Color {
        switch node.kind {
        case .peer: .white
        case .relayed: .white.opacity(0.5)
        case .agreement: FaroTheme.safe
        case .family: .pink
        }
    }

    /// Stable placement: each phone keeps its spot as the radar redraws.
    private func position(for node: Node, index: Int, center: CGPoint, rx: CGFloat, ry: CGFloat) -> CGPoint {
        let hash = node.id.unicodeScalars.reduce(UInt32(2166136261)) { ($0 ^ $1.value) &* 16777619 }
        // Spread nodes around the circle; the hash only nudges each one so the layout feels organic.
        let angle = (Double(index) / Double(max(1, nodes.count)) + Double(hash % 40) / 400) * 2 * .pi - .pi / 2
        let ring = node.kind == .relayed ? 0.95 : 0.72 + Double(hash % 16) / 100
        return CGPoint(x: center.x + cos(angle) * rx * ring, y: center.y + sin(angle) * ry * ring)
    }
}
