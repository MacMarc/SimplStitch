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

    /// `initialFormat`: das in den Einstellungen gewählte bevorzugte Format, vorausgewählt.
    init(objects: [DesignObject], canvasSize: CGSize, exportService: FileExportServicing, initialFormat: EmbroideryFileFormat) {
        self.objects = objects
        self.canvasSize = canvasSize
        self.exportService = exportService
        _format = State(initialValue: initialFormat)
    }

    @State private var format: EmbroideryFileFormat
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
                HStack(alignment: .top, spacing: 8) {
                    BobbiView(mood: .oops)
                        .frame(width: 30, height: 36)
                    Text(previewError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                // Issue #27: Bobbi dreht Faden, solange die Stiche gerechnet werden.
                HStack(spacing: 8) {
                    BobbiView(mood: .working, isSpinning: true)
                        .frame(width: 30, height: 36)
                    Text("bobbi.export.working")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
