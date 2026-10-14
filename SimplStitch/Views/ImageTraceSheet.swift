//
//  ImageTraceSheet.swift
//  SimplStitch
//
//  Issue #3: Optionen fürs Nachzeichnen eines Bilds (Anzahl Garnfarben, Hintergrund weglassen)
//  und Fortschritt, solange `ImageTraceService` rechnet. Das Ergebnis geht über `onTraced` als
//  fertige DesignObjects zurück an ContentView → `CanvasStore.importObjects`.
//

import SwiftUI

struct ImageTraceSheet: View {
    let imageURL: URL
    let canvasSizeMillimeters: CGSize
    let traceService: ImageTracing
    let onTraced: ([DesignObject]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var colorCount = ImageTraceOptions().colorCount
    @State private var removesBackground = true
    @State private var isTracing = false
    @State private var errorMessage: String?

    /// Etwas Rand zur Rahmenkante, damit die Formen nicht direkt am Rand kleben.
    static let canvasFillFraction = 0.9

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("imageTrace.sheet.title")
                .font(.headline)
            Text("imageTrace.sheet.message")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                LabeledContent("imageTrace.sheet.file") {
                    Text(imageURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Stepper(value: $colorCount, in: ImageTraceOptions.colorCountRange) {
                    Text(String(format: String(localized: "imageTrace.sheet.colorCount"), colorCount))
                }
                Toggle("imageTrace.sheet.removeBackground", isOn: $removesBackground)
            }
            .disabled(isTracing)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isTracing {
                    ProgressView()
                        .controlSize(.small)
                    Text("imageTrace.sheet.working")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("imageTrace.sheet.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("imageTrace.sheet.trace") { trace() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTracing)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func trace() {
        isTracing = true
        errorMessage = nil
        let options = ImageTraceOptions(
            colorCount: colorCount,
            removesBackground: removesBackground,
            targetSizeMillimeters: CGSize(
                width: canvasSizeMillimeters.width * Self.canvasFillFraction,
                height: canvasSizeMillimeters.height * Self.canvasFillFraction
            )
        )
        let url = imageURL
        Task {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
                isTracing = false
            }
            do {
                let regions = try await traceService.traceImage(at: url, options: options)
                onTraced(ImageTraceService.designObjects(from: regions))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
