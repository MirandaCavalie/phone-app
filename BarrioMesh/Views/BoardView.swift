import SwiftUI

struct BoardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var composerKind: PostKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ConnectionBanner()

                    actionButtons

                    if model.activePosts.isEmpty {
                        emptyState
                    } else {
                        postSection(title: "Necesidades", posts: model.activeNeeds)
                        postSection(title: "Ofertas", posts: model.activeOffers)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Barrio Mesh")
            .sheet(item: $composerKind) { kind in
                PostComposerView(kind: kind)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                composerKind = .need
            } label: {
                Label("Necesito ayuda", systemImage: "hand.raised.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                composerKind = .offer
            } label: {
                Label("Puedo ayudar", systemImage: "hands.sparkles.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("La red está lista", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("Publicá una necesidad u oferta. Quedará guardada y se compartirá cuando aparezca otro teléfono.")
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

                Text("\(post.quantity) \(post.unit) · \(post.area)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                    Button("Cerrar publicación", role: .destructive) {
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
                     ? "Todo queda guardado hasta encontrar otro dispositivo."
                     : "Sincronizando directamente, sin internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }
}
