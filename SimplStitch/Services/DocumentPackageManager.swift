//
//  DocumentPackageManager.swift
//  SimplStitch
//
//  Liest/schreibt ein `.stitchdesign` Document Package:
//    MeinDesign.stitchdesign/
//    ├── content.svg
//    ├── preview.png
//    └── assets/
//
//  Reiner I/O-Service (Protocol, kein SwiftUI-Bezug).
//
//  Zwei parallele APIs seit Phase 8a: die ursprüngliche URL-basierte (write/read,
//  Phase 4) sowie eine FileWrapper-basierte (makeFileWrapper/readProject) für
//  `StitchDesignDocument: ReferenceFileDocument` — SwiftUIs DocumentGroup arbeitet
//  mit FileWrapper-Bäumen, nicht mit realen Pfaden auf Disk. Beide teilen sich
//  denselben SVGDesignSerializer/PreviewImageRenderer-Kern, nur die "wohin/woher"-
//  Schicht unterscheidet sich.
//

import Foundation
import CoreGraphics

enum DocumentPackageError: Error, LocalizedError {
    case notAPackage(URL)
    case missingContentSVG(URL)
    case previewRenderingFailed

    var errorDescription: String? {
        switch self {
        case .notAPackage(let url):
            return "\(url.lastPathComponent) ist kein .stitchdesign-Paket."
        case .missingContentSVG(let url):
            return "content.svg fehlt in \(url.lastPathComponent)."
        case .previewRenderingFailed:
            return "Vorschaubild konnte nicht erzeugt werden."
        }
    }
}

protocol DocumentPackageManaging {
    @discardableResult
    func write(_ project: StitchProject, to packageURL: URL, importingBackgroundImageFrom sourceURL: URL?) throws -> URL
    func read(from packageURL: URL) throws -> StitchProject

    /// Kodiert content.svg + preview.png für ein Projekt, ohne sie irgendwohin zu schreiben —
    /// für `ReferenceFileDocument.snapshot(contentType:)` (Phase 8a), das reine `Sendable`-Daten
    /// braucht (ein fertiger `FileWrapper` ist nicht `Sendable`, da alte Foundation-Klasse).
    /// Assets/Hintergrundbild werden bewusst nicht hier behandelt — das durchreicht der Aufrufer
    /// direkt aus `WriteConfiguration.existingFile` (siehe StitchDesignDocument).
    func encodedContent(for project: StitchProject) throws -> (svgData: Data, previewPNGData: Data)
    func readProject(from fileWrapper: FileWrapper, projectName: String) throws -> StitchProject
}

final class DocumentPackageManager: DocumentPackageManaging {
    private let svgSerializer: SVGDesignSerializing
    private let previewRenderer: PreviewImageRendering
    private let fileManager: FileManager

    init(
        svgSerializer: SVGDesignSerializing = SVGDesignSerializer(),
        previewRenderer: PreviewImageRendering = PreviewImageRenderer(),
        fileManager: FileManager = .default
    ) {
        self.svgSerializer = svgSerializer
        self.previewRenderer = previewRenderer
        self.fileManager = fileManager
    }

    @discardableResult
    func write(_ project: StitchProject, to packageURL: URL, importingBackgroundImageFrom sourceURL: URL? = nil) throws -> URL {
        guard packageURL.pathExtension == "stitchdesign" else {
            throw DocumentPackageError.notAPackage(packageURL)
        }

        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        if let sourceURL {
            let assetsURL = packageURL.appendingPathComponent("assets", isDirectory: true)
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            let fileName = sourceURL.lastPathComponent
            let destinationURL = assetsURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            project.backgroundImageFileName = fileName
        }

        let canvasSize = CGSize(width: project.canvasWidthMillimeters, height: project.canvasHeightMillimeters)

        let svg = svgSerializer.encode(
            objects: project.objects,
            canvasSize: canvasSize,
            backgroundImageFileName: project.backgroundImageFileName,
            backgroundImageOpacity: project.backgroundImageOpacity,
            isBackgroundImageVisible: project.isBackgroundImageVisible,
            defaultThreadPaletteID: project.defaultThreadPaletteID
        )
        try svg.write(to: packageURL.appendingPathComponent("content.svg"), atomically: true, encoding: .utf8)

        guard let previewData = previewRenderer.renderPreviewPNG(objects: project.objects, canvasSize: canvasSize) else {
            throw DocumentPackageError.previewRenderingFailed
        }
        try previewData.write(to: packageURL.appendingPathComponent("preview.png"), options: .atomic)

        project.modifiedAt = Date()
        return packageURL
    }

    func read(from packageURL: URL) throws -> StitchProject {
        guard packageURL.pathExtension == "stitchdesign" else {
            throw DocumentPackageError.notAPackage(packageURL)
        }
        let svgURL = packageURL.appendingPathComponent("content.svg")
        guard fileManager.fileExists(atPath: svgURL.path) else {
            throw DocumentPackageError.missingContentSVG(packageURL)
        }

        let svg = try String(contentsOf: svgURL, encoding: .utf8)
        let decoded = try svgSerializer.decode(svg: svg)

        let name = packageURL.deletingPathExtension().lastPathComponent
        let project = StitchProject(
            name: name,
            lastKnownPath: packageURL.path,
            canvasWidthMillimeters: decoded.canvasSize.width,
            canvasHeightMillimeters: decoded.canvasSize.height
        )
        project.backgroundImageFileName = decoded.backgroundImageFileName
        project.backgroundImageOpacity = decoded.backgroundImageOpacity
        project.isBackgroundImageVisible = decoded.isBackgroundImageVisible
        project.defaultThreadPaletteID = decoded.defaultThreadPaletteID
        project.objects = decoded.objects
        for object in decoded.objects {
            object.project = project
        }
        return project
    }

    func encodedContent(for project: StitchProject) throws -> (svgData: Data, previewPNGData: Data) {
        let canvasSize = CGSize(width: project.canvasWidthMillimeters, height: project.canvasHeightMillimeters)
        let svg = svgSerializer.encode(
            objects: project.objects,
            canvasSize: canvasSize,
            backgroundImageFileName: project.backgroundImageFileName,
            backgroundImageOpacity: project.backgroundImageOpacity,
            isBackgroundImageVisible: project.isBackgroundImageVisible,
            defaultThreadPaletteID: project.defaultThreadPaletteID
        )
        guard let svgData = svg.data(using: .utf8) else {
            throw DocumentPackageError.previewRenderingFailed
        }
        guard let previewData = previewRenderer.renderPreviewPNG(objects: project.objects, canvasSize: canvasSize) else {
            throw DocumentPackageError.previewRenderingFailed
        }
        return (svgData, previewData)
    }

    func readProject(from fileWrapper: FileWrapper, projectName: String) throws -> StitchProject {
        guard fileWrapper.isDirectory,
              let svgData = fileWrapper.fileWrappers?["content.svg"]?.regularFileContents,
              let svg = String(data: svgData, encoding: .utf8)
        else {
            throw DocumentPackageError.missingContentSVG(URL(fileURLWithPath: projectName))
        }

        let decoded = try svgSerializer.decode(svg: svg)
        let project = StitchProject(
            name: projectName,
            lastKnownPath: "",
            canvasWidthMillimeters: decoded.canvasSize.width,
            canvasHeightMillimeters: decoded.canvasSize.height
        )
        project.backgroundImageFileName = decoded.backgroundImageFileName
        project.backgroundImageOpacity = decoded.backgroundImageOpacity
        project.isBackgroundImageVisible = decoded.isBackgroundImageVisible
        project.defaultThreadPaletteID = decoded.defaultThreadPaletteID
        project.objects = decoded.objects
        for object in decoded.objects {
            object.project = project
        }
        return project
    }
}
