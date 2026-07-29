//
//  ObjectInspectorView.swift
//  SimplStitch
//
//  Phase 8d: der "echte" Settings-Inspector, den StitchDevPanelView (Phase 6e)
//  immer schon als provisorisch angekündigt hat — ersetzt es vollständig
//  (inkl. der dort noch fehlenden Unterlage-Auswahl). Drei Sektionen:
//  Objekt-Eigenschaften (Transform), Farbe, Sticheinstellungen.
//
//  Verzerren (Issue #9): skewXDegrees/skewYDegrees haben jetzt sowohl einen interaktiven Griff
//  (⌥+Drag auf einem Kanten-Griff, CanvasStore.beginSkewDrag) als auch Rendering
//  (DesignObjectPath.visualTransform) — die früher bewusst fehlenden Eingabefelder sind daher
//  nachgeholt (zwei Slider, analog zur Rotation).
//
//  Farbe (Issue #13): kein freier ColorPicker mehr — gestickt werden kann nur, was als Garn in
//  einer Garnliste vorhanden ist. Setzt wie das bestehende Drag&Drop (`CanvasStore.assignColor`,
//  Phase 8e) direkt aus RGB-Werten statt über SwiftUI `Color`/Hex zu gehen — das war vermutlich
//  ohnehin die Ursache des alten "Füllfarbe bleibt schwarz"-Bugs (`Color.cgColor` ist für manche
//  vom System-Farbwähler gelieferte `Color`-Werte nicht zuverlässig auf konkrete RGB-Komponenten
//  auflösbar, `Color.hexString`s Schwarz-Fallback griff dann lautlos).
//
//  Farbe (Issue #20): der frühere zweistufige Picker (erst Garnliste, dann Garnfarbe darin) zeigte
//  ungefiltert ALLE importierten Garnlisten und liess seine Auswahl über lokalen @State laufen —
//  der resettete sich beim Weg- und Zurückwechseln des Objekts auf die erste Palette ("Garnliste
//  resettet sich immer zum Default"), weil `.id(object.id)` in CanvasInspectorView bewusst alles
//  lokale @State beim Objektwechsel verwirft. Nach weiterem User-Feedback (die erste kuratierte-
//  Farbliste-Fassung verursachte mit ~20'000 Zeilen spürbares Lag und gefiel nicht) jetzt ein
//  einziger flacher Picker über die Farben der EINEN projektweiten Standard-Garnliste
//  (`CanvasStore.defaultThreadPaletteID`, im Projekt-Eigenschaften-Tab gewählt) ohne eigenes
//  @State — die Auswahl wird direkt aus `object.threadColor` abgeleitet, kann sich also nie
//  "zurücksetzen".
//

import SwiftData
import SwiftUI

struct ObjectInspectorView: View {
    let object: DesignObject
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    var body: some View {
        Form {
            Section("inspector.section.object") {
                TextField("inspector.object.name", text: nameBinding)

                LabeledContent("inspector.object.position") {
                    HStack {
                        TextField("X", value: positionXBinding, format: .number)
                            .labelsHidden()
                        TextField("Y", value: positionYBinding, format: .number)
                            .labelsHidden()
                    }
                }
                LabeledContent("inspector.object.size") {
                    HStack {
                        TextField("W", value: widthBinding, format: .number)
                            .labelsHidden()
                        TextField("H", value: heightBinding, format: .number)
                            .labelsHidden()
                    }
                }
                LabeledContent("inspector.object.rotation") {
                    Slider(value: rotationBinding, in: 0...360)
                }
                LabeledContent("inspector.object.skewX") {
                    Slider(value: skewXBinding, in: -CanvasStore.maxSkewDegrees...CanvasStore.maxSkewDegrees)
                }
                LabeledContent("inspector.object.skewY") {
                    Slider(value: skewYBinding, in: -CanvasStore.maxSkewDegrees...CanvasStore.maxSkewDegrees)
                }
                if object.kind == .rectangle {
                    LabeledContent("inspector.object.cornerRadius") {
                        Slider(value: cornerRadiusBinding, in: 0...maxCornerRadius)
                    }
                }
            }

            Section("inspector.section.color") {
                LabeledContent("inspector.color.current") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: object.fillColorHex) ?? .black)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3)))
                        Text(object.threadColor?.name.isEmpty == false ? object.threadColor!.name : object.fillColorHex)
                            .foregroundStyle(.secondary)
                    }
                }

                if projectThreadColors.isEmpty {
                    Text("inspector.color.noProjectThreads")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Picker("inspector.color.thread", selection: threadColorSelectionBinding) {
                        Text("inspector.color.pickPlaceholder").tag(UUID?.none)
                        ForEach(projectThreadColors) { color in
                            threadColorLabel(color).tag(Optional(color.id))
                        }
                    }
                }
            }

            Section("inspector.section.stitch") {
                // Issue #18: "hat Füllung" ist unabhängig von der Farbwahl — deaktiviert lässt
                // sich der Stichtyp zwar weiterhin einsehen/vorbereiten, wird aber beim Export/in
                // der Stichvorschau nicht mehr berücksichtigt (siehe FileExportService/CanvasStore).
                Toggle("inspector.fill.enabled", isOn: hasFillBinding)

                Picker("inspector.stitch.type", selection: stitchTypeBinding) {
                    Text("inspector.stitch.type.none").tag(StitchType?.none)
                    ForEach(StitchType.allCases, id: \.self) { type in
                        Text(displayName(for: type)).tag(StitchType?.some(type))
                    }
                }
                .disabled(!object.hasFill)

                if let settings = object.stitchSettings {
                    LabeledContent("inspector.stitch.density") {
                        Slider(value: densityBinding(settings), in: 0.1...2.0)
                    }
                    if settings.stitchType == .tatami {
                        LabeledContent("inspector.stitch.angle") {
                            Slider(value: angleBinding(settings), in: 0...180)
                        }
                    }
                    Picker("inspector.stitch.underlay", selection: underlayBinding(settings)) {
                        ForEach(UnderlayType.allCases, id: \.self) { underlay in
                            Text(displayName(for: underlay)).tag(underlay)
                        }
                    }
                }
            }

            Section("inspector.section.border") {
                Toggle("inspector.border.enabled", isOn: hasBorderBinding)

                if object.hasBorder {
                    LabeledContent("inspector.border.width") {
                        Slider(value: borderWidthBinding, in: 0.1...5)
                    }

                    LabeledContent("inspector.color.current") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: object.borderColorHex ?? object.fillColorHex) ?? .black)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3)))
                            Text(object.borderThreadColor?.name.isEmpty == false ? object.borderThreadColor!.name : (object.borderColorHex ?? "—"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if projectThreadColors.isEmpty {
                        Text("inspector.color.noProjectThreads")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("inspector.color.thread", selection: borderThreadColorSelectionBinding) {
                            Text("inspector.color.pickPlaceholder").tag(UUID?.none)
                            ForEach(projectThreadColors) { color in
                                threadColorLabel(color).tag(Optional(color.id))
                            }
                        }
                    }

                    Picker("inspector.stitch.type", selection: borderStitchTypeBinding) {
                        ForEach(StitchType.allCases, id: \.self) { type in
                            Text(displayName(for: type)).tag(type)
                        }
                    }
                    if let borderSettings = object.borderStitchSettings {
                        LabeledContent("inspector.stitch.density") {
                            Slider(value: densityBinding(borderSettings), in: 0.1...2.0)
                        }
                        Picker("inspector.stitch.underlay", selection: underlayBinding(borderSettings)) {
                            ForEach(UnderlayType.allCases, id: \.self) { underlay in
                                Text(displayName(for: underlay)).tag(underlay)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Objekt-Eigenschaften

    private var nameBinding: Binding<String> {
        Binding(get: { object.name }, set: { object.name = $0 })
    }

    private var positionXBinding: Binding<Double> {
        Binding(get: { object.positionX }, set: { object.positionX = $0; store.refreshStitchPreview() })
    }

    private var positionYBinding: Binding<Double> {
        Binding(get: { object.positionY }, set: { object.positionY = $0; store.refreshStitchPreview() })
    }

    private var widthBinding: Binding<Double> {
        Binding(get: { object.width }, set: { object.width = max($0, CanvasStore.minimumShapeSize); store.refreshStitchPreview() })
    }

    private var heightBinding: Binding<Double> {
        Binding(get: { object.height }, set: { object.height = max($0, CanvasStore.minimumShapeSize); store.refreshStitchPreview() })
    }

    private var rotationBinding: Binding<Double> {
        Binding(get: { object.rotationDegrees }, set: { object.rotationDegrees = $0; store.refreshStitchPreview() })
    }

    private var skewXBinding: Binding<Double> {
        Binding(get: { object.skewXDegrees }, set: { object.skewXDegrees = $0; store.refreshStitchPreview() })
    }

    private var skewYBinding: Binding<Double> {
        Binding(get: { object.skewYDegrees }, set: { object.skewYDegrees = $0; store.refreshStitchPreview() })
    }

    private var maxCornerRadius: Double {
        min(object.width, object.height) / 2
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(get: { object.cornerRadius }, set: { object.cornerRadius = min(max($0, 0), maxCornerRadius) })
    }

    // MARK: Farbe

    /// Farben der EINEN projektweiten Standard-Garnliste (Issue #20, `CanvasStore.
    /// defaultThreadPaletteID`, im Projekt-Eigenschaften-Tab gewählt), nach Namen sortiert
    /// (Bugfix: vorher waren Farben innerhalb einer Garnliste unsortiert).
    private var projectThreadColors: [ThreadColor] {
        guard let paletteID = store.defaultThreadPaletteID,
              let palette = palettes.first(where: { $0.id == paletteID }) else {
            return []
        }
        return palette.colors.sorted { $0.name < $1.name }
    }

    private var threadColorSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let current = object.threadColor else { return nil }
                return projectThreadColors.first {
                    $0.red == current.red && $0.green == current.green && $0.blue == current.blue
                }?.id
            },
            set: { newID in
                guard let newID, let color = projectThreadColors.first(where: { $0.id == newID }) else { return }
                store.assignColor(
                    name: color.name,
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    catalogNumber: color.catalogNumber,
                    to: object.id
                )
            }
        )
    }

    private func threadColorLabel(_ color: ThreadColor) -> some View {
        Label(
            color.name.isEmpty ? "#\(color.red),\(color.green),\(color.blue)" : color.name,
            systemImage: "circle.fill"
        )
        .foregroundStyle(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
    }

    // MARK: Füllung/Rand (Issue #18)

    private var hasFillBinding: Binding<Bool> {
        Binding(get: { object.hasFill }, set: { object.hasFill = $0; store.refreshStitchPreview() })
    }

    private var hasBorderBinding: Binding<Bool> {
        Binding(
            get: { object.hasBorder },
            set: { newValue in
                object.hasBorder = newValue
                // Randeinstellungen bleiben beim Deaktivieren erhalten (Datenverlust vermeiden) —
                // beim ERSTEN Aktivieren gibt es aber noch keine, die erzeugen wir hier vor.
                if newValue, object.borderStitchSettings == nil {
                    let settings = StitchSettings(stitchType: .straight, underlayType: UnderlayType.suggested(for: .straight))
                    settings.borderOwner = object
                    object.borderStitchSettings = settings
                }
                store.refreshStitchPreview()
            }
        )
    }

    private var borderWidthBinding: Binding<Double> {
        Binding(get: { object.borderWidthMillimeters }, set: { object.borderWidthMillimeters = max($0, 0.1) })
    }

    private var borderThreadColorSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let current = object.borderThreadColor else { return nil }
                return projectThreadColors.first {
                    $0.red == current.red && $0.green == current.green && $0.blue == current.blue
                }?.id
            },
            set: { newID in
                guard let newID, let color = projectThreadColors.first(where: { $0.id == newID }) else { return }
                store.assignBorderColor(
                    name: color.name,
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    catalogNumber: color.catalogNumber,
                    to: object.id
                )
            }
        )
    }

    private var borderStitchTypeBinding: Binding<StitchType> {
        Binding(
            get: { object.borderStitchSettings?.stitchType ?? .straight },
            set: { newType in
                if let settings = object.borderStitchSettings {
                    settings.stitchType = newType
                } else {
                    let settings = StitchSettings(stitchType: newType)
                    settings.borderOwner = object
                    object.borderStitchSettings = settings
                }
                store.refreshStitchPreview()
            }
        )
    }

    // MARK: Sticheinstellungen

    private func displayName(for type: StitchType) -> String {
        switch type {
        case .tatami: return String(localized: "inspector.stitch.type.tatami")
        case .straight: return String(localized: "inspector.stitch.type.straight")
        case .satin: return String(localized: "inspector.stitch.type.satin")
        }
    }

    private func displayName(for underlay: UnderlayType) -> String {
        switch underlay {
        case .none: return String(localized: "inspector.underlay.none")
        case .centerWalk: return String(localized: "inspector.underlay.centerWalk")
        case .edgeWalk: return String(localized: "inspector.underlay.edgeWalk")
        case .zigzagNet: return String(localized: "inspector.underlay.zigzagNet")
        }
    }

    private var stitchTypeBinding: Binding<StitchType?> {
        Binding(
            get: { object.stitchSettings?.stitchType },
            set: { newType in
                if let newType {
                    if let settings = object.stitchSettings {
                        settings.stitchType = newType
                    } else {
                        let settings = StitchSettings(stitchType: newType)
                        settings.designObject = object
                        object.stitchSettings = settings
                    }
                } else {
                    object.stitchSettings = nil
                }
                store.refreshStitchPreview()
            }
        )
    }

    private func densityBinding(_ settings: StitchSettings) -> Binding<Double> {
        Binding(
            get: { settings.density },
            set: { settings.density = $0; store.refreshStitchPreview() }
        )
    }

    private func angleBinding(_ settings: StitchSettings) -> Binding<Double> {
        Binding(
            get: { settings.angleDegrees },
            set: { settings.angleDegrees = $0; store.refreshStitchPreview() }
        )
    }

    private func underlayBinding(_ settings: StitchSettings) -> Binding<UnderlayType> {
        Binding(
            get: { settings.underlayType },
            set: { settings.underlayType = $0; store.refreshStitchPreview() }
        )
    }
}
