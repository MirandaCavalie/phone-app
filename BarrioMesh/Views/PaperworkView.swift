import SwiftUI

/// The calls and forms the agent prepared, ready for a person to use.
struct PaperworkView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pdfURL: URL?

    var body: some View {
        let script = model.callScript
        let report = model.incidentReport

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Guion para llamar al \(script.number)", systemImage: "phone.fill")
                            .font(.headline)
                        Text("Si logras comunicarte, lee esto. Ya incluye quién es vulnerable en tu hogar y qué falta.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(script.text)
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Button {
                                if let url = URL(string: "tel://\(script.number)") { openURL(url) }
                            } label: {
                                Label("Llamar al \(script.number)", systemImage: "phone.arrow.up.right.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(FaroTheme.ember)

                            Button {
                                model.narrator.speak(script.text, country: model.profile.country)
                            } label: {
                                Label("Escuchar", systemImage: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .faroCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reporte de afectación prellenado", systemImage: "doc.text.fill")
                            .font(.headline)
                        Text("Para el registro de damnificados, tu aseguradora o una organización de ayuda. Revísalo y compártelo cuando vuelva la señal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ReportDocument(report: report)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        HStack {
                            if let pdfURL {
                                ShareLink(item: pdfURL) {
                                    Label("Compartir PDF", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            ShareLink(item: report.plainText) {
                                Label("Texto", systemImage: "text.alignleft")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .faroCard()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trámites listos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .task { pdfURL = ReportDocument.renderPDF(report) }
        }
    }
}

/// The report laid out like a form; also rendered to PDF.
struct ReportDocument: View {
    let report: Paperwork.Report

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                FaroMark(size: 30)
                VStack(alignment: .leading) {
                    Text(report.title).font(.headline)
                    Text(report.generatedAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(report.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(section.rows, id: \.self) { row in
                        Text(row).font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    static func renderPDF(_ report: Paperwork.Report) -> URL? {
        let renderer = ImageRenderer(content:
            ReportDocument(report: report)
                .frame(width: 595)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Reporte-Faro.pdf")
        var rendered = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 595, height: max(842, size.height)))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: box.height - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            rendered = true
        }
        return rendered ? url : nil
    }
}
