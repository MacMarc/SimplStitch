//
//  ImageTraceSheet.swift
//  SimplStitch
//
//  Issue #3: Optionen fürs Nachzeichnen eines Bilds (Anzahl Garnfarben, Hintergrund weglassen)
//  und Fortschritt, solange `ImageTraceService` rechnet. Das Ergebnis geht über `onTraced` als
//  fertige DesignObjects zurück an ContentView → `CanvasStore.importObjects`.
//

import SwiftData
import SwiftUI

struct ImageTraceSheet: View {
    let imageURL: URL
    let canvasSizeMillimeters: CGSize
    let traceService: ImageTracing
    /// Standard-Garnliste des Dokuments — nachgezeichnete Flächen bekommen das nächstliegende Garn daraus.
    var threadPaletteID: UUID?
    let onTraced: ([DesignObject]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var appSettingsList: [AppSettings]
    @Query private var palettes: [ThreadPalette]

    private var threadCandidates: [ThreadCandidate] {
        guard let threadPaletteID, let palette = palettes.first(where: { $0.id == threadPaletteID }) else { return [] }
        return palette.colors.map {
            ThreadCandidate(name: $0.name, red: $0.red, green: $0.green, blue: $0.blue, catalogNumber: $0.catalogNumber)
        }
    }
    @State private var colorCount = ImageTraceOptions.defaultColorCount
    @State private var removesBackground = true
    @State private var isTracing = false
    @State private var isAdvising = false
    /// Einmal beim Erscheinen abgefragt — die Verfügbarkeit ändert sich nicht, während das Sheet offen ist.
    @State private var appleIntelligenceStatus = AppleIntelligenceStatus.current

    private var usesAppleIntelligence: Bool {
        appSettingsList.isAppleIntelligenceEnabled && appleIntelligenceStatus == .available
    }
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

            // Transparent machen, wer die Sticharten wählt — Apple Intelligence ist abschaltbar.
            Label(
                usesAppleIntelligence ? LocalizedStringKey("imageTrace.sheet.advisor.ai") : LocalizedStringKey("imageTrace.sheet.advisor.rules"),
                systemImage: usesAppleIntelligence ? "apple.intelligence" : "list.bullet.clipboard"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isTracing {
                    ProgressView()
                        .controlSize(.small)
                    Text(isAdvising ? LocalizedStringKey("imageTrace.sheet.advising") : LocalizedStringKey("imageTrace.sheet.working"))
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
                isAdvising = false
            }
            do {
                let regions = try await traceService.traceImage(at: url, options: options)
                isAdvising = true
                let advisor: any StitchAdvising = usesAppleIntelligence
                    ? AppleIntelligenceStitchAdvisor()
                    : RuleBasedStitchAdvisor()
                let advice = await advisor.advice(for: regions)
                onTraced(ImageTraceService.designObjects(from: regions, advice: advice, threads: threadCandidates))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
