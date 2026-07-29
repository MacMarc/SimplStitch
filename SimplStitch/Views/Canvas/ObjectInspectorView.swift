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
//  einer Garnliste vorhanden ist. Die Sektion ist daher ein zweistufiger Picker (Garnliste, dann
//  Garnfarbe innerhalb dieser Liste), der wie das bestehende Drag&Drop (`CanvasStore.assignColor`,
//  Phase 8e) direkt aus RGB-Werten setzt statt über SwiftUI `Color`/Hex zu gehen — das war
//  vermutlich ohnehin die Ursache des alten "Füllfarbe bleibt schwarz"-Bugs (`Color.cgColor` ist
//  für manche vom System-Farbwähler gelieferte `Color`-Werte nicht zuverlässig auf konkrete RGB-
//  Komponenten auflösbar, `Color.hexString`s Schwarz-Fallback griff dann lautlos).
//

import SwiftData
import SwiftUI

struct ObjectInspectorView: View {
    let object: DesignObject
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]
    @State private var selectedPaletteID: UUID?
    @State private var selectedThreadColor: ThreadColor?

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

                if palettes.isEmpty {
                    Text("inspector.color.noPalettes")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Picker("inspector.color.palette", selection: paletteBinding) {
                        ForEach(palettes) { palette in
                            Text(palette.name).tag(Optional(palette.id))
                        }
                    }
                    Picker("inspector.color.thread", selection: $selectedThreadColor) {
                        Text("inspector.color.pickPlaceholder").tag(ThreadColor?.none)
                        ForEach(currentPaletteColors) { color in
                            threadColorLabel(color).tag(ThreadColor?.some(color))
                        }
                    }
                    .onChange(of: selectedThreadColor) { _, newValue in
                        guard let newValue else { return }
                        store.assignColor(
                            name: newValue.name,
                            red: newValue.red,
                            green: newValue.green,
                            blue: newValue.blue,
                            catalogNumber: newValue.catalogNumber,
                            to: object.id
                        )
                    }
                }
            }

            Section("inspector.section.stitch") {
                Picker("inspector.stitch.type", selection: stitchTypeBinding) {
                    Text("inspector.stitch.type.none").tag(StitchType?.none)
                    ForEach(StitchType.allCases, id: \.self) { type in
                        Text(displayName(for: type)).tag(StitchType?.some(type))
                    }
                }

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

    private var effectivePaletteID: UUID? {
        selectedPaletteID ?? palettes.first?.id
    }

    private var paletteBinding: Binding<UUID?> {
        Binding(get: { effectivePaletteID }, set: { selectedPaletteID = $0 })
    }

    private var currentPaletteColors: [ThreadColor] {
        palettes.first { $0.id == effectivePaletteID }?.colors ?? []
    }

    private func threadColorLabel(_ color: ThreadColor) -> some View {
        Label(
            color.name.isEmpty ? "#\(color.red),\(color.green),\(color.blue)" : color.name,
            systemImage: "circle.fill"
        )
        .foregroundStyle(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
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
