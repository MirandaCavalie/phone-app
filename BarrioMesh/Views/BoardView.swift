import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var composerKind: PostKind?

    var body: some View {
        ScrollView {
                VStack(spacing: 16) {
                    ConnectionBanner()

                    actionButtons

                    if model.activePosts.isEmpty {
                        emptyState
                    } else {
                        postSection(title: t("Necesidades", "Needs"), posts: model.activeNeeds)
                        postSection(title: t("Ofertas", "Offers"), posts: model.activeOffers)
                    }
                }
                .padding()
            }
            .sheet(item: $composerKind) { kind in
                PostComposerView(kind: kind)
            }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                composerKind = .need
            } label: {
                Label(t("Necesito ayuda", "I need help"), systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                composerKind = .offer
            } label: {
                Label(t("Puedo ayudar", "I can help"), systemImage: "hands.sparkles.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(t("La red está lista", "The network is ready"), systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("Publica una necesidad u oferta, o deja que Faro lo haga desde tu perfil. Se comparte cuando aparece otro teléfono.")
        }
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func postSection(title: String, posts: [MeshPost]) -> some View {
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(posts) { post in
                    PostCard(post: post)
                }
            }
        }
    }
}

private struct PostCard: View {
    @EnvironmentObject private var model: AppModel
    let post: MeshPost

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: post.resource.systemImage)
                .font(.title2)
                .foregroundStyle(post.kind == .need ? .orange : .green)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(post.resource.displayName)
                        .font(.headline)
                    Spacer()
                    if post.urgency == .urgent {
                        Text("URGENTE")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }

                Text("\(post.resource.count(post.quantity)) · \(post.area)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                coverage

                if !post.note.isEmpty {
                    Text(post.note)
                        .font(.subheadline)
                        .lineLimit(3)
                }

                HStack {
                    Label(post.authorName, systemImage: "person.fill")
                    Spacer()
                    Text(post.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if post.authorID == model.deviceID {
                    Button(t("Cerrar publicación", "Close post"), role: .destructive) {
                        model.close(post)
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverage: some View {
        let agreed = model.agreedQuantity(for: post)
        if agreed > 0 {
            let covered = agreed >= post.quantity
            HStack(spacing: 8) {
                ProgressView(value: Double(min(agreed, post.quantity)), total: Double(post.quantity))
                    .tint(post.kind == .need ? FaroTheme.safe : .orange)
                    .frame(maxWidth: 90)
                Text(post.kind == .need
                     ? (covered ? t("Cubierto por acuerdo", "Covered") : t("\(agreed) de \(post.quantity) asegurados", "\(agreed) of \(post.quantity) secured"))
                     : (covered ? t("Todo comprometido", "All promised") : t("Quedan \(post.quantity - agreed)", "\(post.quantity - agreed) left")))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(post.kind == .need ? FaroTheme.safe : .orange)
            }
        }
    }
}

struct ConnectionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.peerSession.connectedPeerNames.isEmpty ? Color.orange : Color.green)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.peerSession.statusText)
                    .font(.subheadline.weight(.semibold))
                Text(model.peerSession.connectedPeerNames.isEmpty
                     ? t("Todo queda guardado hasta encontrar otro dispositivo.", "Saved until another phone shows up.")
                     : t("Sincronizando directamente, sin internet.", "Syncing directly, no internet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(FaroTheme.beam.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
