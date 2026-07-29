//
//  ThreadPalettesPanelView.swift
//  SimplStitch
//
//  Phase 8e: Garnlisten-Panel — importierte `.gpl`-Paletten (GPLPaletteImporter,
//  Phase 7) auflisten und Farben per Drag einem Canvas-Objekt zuweisen
//  (DraggedThreadColor + CanvasStore.assignColor, siehe CanvasView-Drop-Handler).
//
//  Anders als StitchProject/DesignObject (Phase 8a, in-memory pro Dokument)
//  sind ThreadPalette/ThreadColor Teil des echten, projektübergreifenden
//  `sharedModelContainer` (SimplStitchApp) — `@Query` liest hier also aus der
//  tatsächlich auf Disk persistierten SwiftData-Datenbank, nicht aus einem
//  Dokument-lokalen Objektgraphen.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ThreadPalettesPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    @State private var isImporterPresented = false
    @State private var importError: String?

    private let importer: GPLPaletteImporting

    init(importer: GPLPaletteImporting = GPLPaletteImporter()) {
        self.importer = importer
    }

    var body: some View {
        VStack(spacing: 0) {
            if palettes.isEmpty {
                ContentUnavailableView(
                    "threads.panel.empty",
                    systemImage: "paintpalette",
                    description: Text("threads.panel.empty.description")
                )
            } else {
                List {
                    ForEach(palettes) { palette in
                        Section(palette.name) {
                            ForEach(palette.colors, id: \.name) { color in
                                swatchRow(for: color)
                            }
                        }
                    }
                    .onDelete(perform: deletePalettes)
                }
                .listStyle(.sidebar)
            }

            Divider()
            HStack {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("threads.import.button", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                Spacer()
            }
            .padding(8)
        }
        .navigationTitle(Text("threads.panel.title"))
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gpl") ?? .plainText]
        ) { result in
            handleImportResult(result)
        }
        .alert(
            "threads.import.error.title",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("threads.import.error.dismiss") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func swatchRow(for color: ThreadColor) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3)))
            Text(color.name.isEmpty ? "#\(color.red),\(color.green),\(color.blue)" : color.name)
                .lineLimit(1)
        }
        .draggable(DraggedThreadColor(
            name: color.name,
            red: color.red,
            green: color.green,
            blue: color.blue,
            catalogNumber: color.catalogNumber
        ))
    }

    private func deletePalettes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(palettes[index])
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let palette = try importer.importPalette(at: url)
            modelContext.insert(palette)
        } catch {
            importError = error.localizedDescription
        }
    }
}

#Preview {
    ThreadPalettesPanelView()
        .modelContainer(for: [ThreadPalette.self, ThreadColor.self], inMemory: true)
}
