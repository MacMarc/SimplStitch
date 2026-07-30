//
//  ExportDialogView.swift
//  SimplStitch
//
//  Provisorischer Export-Dialog (Phase 7) — Formatwahl + Vorschau Stichzahl/
//  Farbanzahl, dann NSSavePanel fürs Zielverzeichnis. Bewusst provisorisch wie
//  der Werkzeug-Picker/Ebenen-Toggle (ContentView), bis Phase 8 die echte
//  Menü-/Toolbar-Verdrahtung bringt.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportDialogView: View {
    let objects: [DesignObject]
    let canvasSize: CGSize
    let exportService: FileExportServicing

    @Environment(\.dismiss) private var dismiss

    @State private var format: EmbroideryFileFormat = .vp3
    @State private var preview: ExportSummary?
    @State private var previewError: String?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("export.dialog.title")

            Picker("export.dialog.formatPicker.label", selection: $format) {
                ForEach(EmbroideryFileFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)

            if let preview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: String(localized: "export.dialog.preview.stitchCount"), preview.stitchCount))
                    Text(String(format: String(localized: "export.dialog.preview.colorCount"), preview.colorCount))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let previewError {
                Text(previewError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("export.dialog.cancel") { dismiss() }
                Button("export.dialog.export") { runExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
        .task(id: format) {
            await refreshPreview()
        }
    }

    private func refreshPreview() async {
        preview = nil
        previewError = nil
        do {
            preview = try await exportService.previewSummary(objects: objects, canvasSize: canvasSize, format: format)
        } catch {
            previewError = error.localizedDescription
        }
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = "Design.\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        exportError = nil
        Task {
            do {
                _ = try await exportService.export(objects: objects, canvasSize: canvasSize, to: url, format: format)
                isExporting = false
                dismiss()
            } catch {
                exportError = error.localizedDescription
                isExporting = false
            }
        }
    }
}
