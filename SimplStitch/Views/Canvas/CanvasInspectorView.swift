//
//  CanvasInspectorView.swift
//  SimplStitch
//
//  Phase 8d: kombiniert Ebenen-Panel (5e) und Objekt-Inspektor (8d) in einem
//  einzigen `.inspector`-Bereich — SwiftUI erlaubt nur einen Inspector pro
//  Fenster, ähnlich der Format/Arrange-Tabs in Pages/Keynote. Wechselt
//  automatisch zur "Eigenschaften"-Ansicht, sobald ein Objekt selektiert wird
//  (wie das Format-Inspector-Verhalten in Pages/Keynote) — Nutzer können
//  jederzeit manuell zurück zu "Ebenen" wechseln.
//
//  Issue #14: der Tab-Picker sass ursprünglich als normales Geschwister-Element
//  über dem aktiven Panel in einem VStack — bei langem Panel-Inhalt (viele
//  Garnfarben/Ebenen) hat NICHT das jeweilige List/Form intern gescrollt,
//  sondern die umgebende `.inspector()`-Spalte hat den GESAMTEN VStack
//  (Picker inklusive) als einen Block gescrollt, weil der VStack ohne
//  explizite Höhenvorgabe keine verlässliche Scroll-Grenze für sein Kind-List
//  darstellt.
//
//  Issue #26 (Bug 2): der Fix von #14 (`.safeAreaInset(edge: .top)` auf einer
//  `Group`, deren `switch` zu Panes mit UNTERSCHIEDLICHEN Root-Containern
//  auflöst — mehrere `Form`s, aber `LayersPanelView` ein `VStack{List}`) löste
//  das Scroll-Problem, behielt aber ein zweites: das Inset wird pro Pane neu
//  reserviert, und da `Form`/`List` jeweils ihr eigenes oberes Content-Inset
//  mitbringen, verschob sich der sichtbare Header/Content-Start beim
//  Tab-Wechsel ("hüpft"). Fix: der Picker ist jetzt ein echtes Geschwister-
//  Element in einem `VStack`, NICHT mehr an eine `Group`/`safeAreaInset`
//  gehängt; die aktive Pane bekommt explizit `.frame(maxWidth: .infinity,
//  maxHeight: .infinity)`, damit sie (nicht die äussere Spalte) die verfügbare
//  Höhe bekommt und intern scrollt — unabhängig davon, ob die Pane ein `Form`,
//  eine `List` oder ein einfacher `VStack` ist, ist der Startpunkt jetzt für
//  alle identisch.
//
//  Issue #26 (Nachbesserung): der Menü-Pulldown aus Issue #20 (Fliesstext-
//  Wert + Chevron) wirkte im Nutzertest "doof" — durch einen echten
//  Icon-Segmented-Control ersetzt (SF Symbols + Mouseover-Tooltip via
//  `.help(_:)`), wie Xcodes eigene Inspector-Tableiste. Kein Textumbruch-
//  Problem mehr (der ursprüngliche Grund für den Menü-Pulldown), da Icons
//  keine variable Breite je nach Sprache haben.
//
//  Issue #26 (Nachbesserung 2, Opus-Konsultation): das Segmented-Control
//  selbst war schon richtig, aber `.background(.bar)` auf dem umgebenden
//  Header-VStack erzeugte eine SICHTBARE zweite Fläche (Control-eigene
//  Kapsel-Optik + `.bar`-Material + Inspector-Material darunter — drei
//  gestapelte Flächen), die als "weisses Rechteck hinter den Icons" auffiel.
//  Fix: kein eigener Hintergrund mehr, der Header sitzt bündig auf dem
//  Inspector-Hintergrund (wie Pages/Keynote/Numbers' Format-Tab-Leiste).
//  `.controlSize(.large)` behebt "Icons wirken zu klein".
//

import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case layers
    case object
    case project

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .layers: return String(localized: "inspector.tab.layers")
        case .object: return String(localized: "inspector.tab.object")
        case .project: return String(localized: "inspector.tab.project")
        }
    }

    /// SF Symbols, passend zur jeweiligen Pane — Ebenen-Stapel, Objekt-Eigenschaften
    /// (Schieberegler wie in Pages/Keynotes Format-Inspector) und Projekt-/Dokument-Eigenschaften.
    var systemImageName: String {
        switch self {
        case .layers: return "square.3.layers.3d"
        case .object: return "slider.horizontal.3"
        case .project: return "doc.text"
        }
    }
}

struct CanvasInspectorView: View {
    let store: CanvasStore

    @State private var selectedTab: InspectorTab = .layers

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            activePane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: store.selectedObjectIDs) { _, newValue in
            if !newValue.isEmpty {
                selectedTab = .object
            }
        }
    }

    /// Echtes Geschwister-Element statt eines `.safeAreaInset` auf der `Group` darunter (Issue #26,
    /// Bug 2) — bleibt dadurch unabhängig vom Root-Container der jeweils aktiven Pane fixiert.
    private var header: some View {
        // Issue #26: Icon-Segmented-Control statt Text-Pulldown (Issue #20) — Icons haben anders
        // als die deutschen Komposita-Bezeichnungen keine variable, sprachabhängige Breite, das
        // ursprüngliche Umbruch-Problem entfällt dadurch von selbst. Name je Tab per Mouseover
        // (`.help`) statt permanent sichtbarem Text.
        Picker("", selection: $selectedTab) {
            ForEach(InspectorTab.allCases) { tab in
                Image(systemName: tab.systemImageName)
                    .help(Text(tab.displayName))
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var activePane: some View {
        switch selectedTab {
        case .layers:
            LayersPanelView(store: store)
        case .object:
            if let object = store.selectedObject {
                ObjectInspectorView(object: object, store: store)
                    .id(object.id)
            } else if let groupID = store.selectedGroupID {
                GroupInspectorView(groupID: groupID, memberCount: store.selectedObjects.count, store: store)
            } else if store.selectedObjectIDs.count > 1 {
                // Issue #23: eine Mehrfachauswahl aus (noch) nicht gruppierten Objekten zeigte
                // bisher denselben "Kein Objekt ausgewählt"-Leerzustand wie gar keine Selektion —
                // dort fehlte die Möglichkeit zu gruppieren, obwohl "Gruppierung aufheben" für
                // eine bestehende Gruppe längst im Inspector verfügbar ist (GroupInspectorView).
                MultiSelectionInspectorView(memberCount: store.selectedObjectIDs.count, store: store)
            } else {
                ContentUnavailableView(
                    "inspector.object.empty",
                    systemImage: "square.dashed.inset.filled",
                    description: Text("inspector.object.empty.description")
                )
            }
        case .project:
            ProjectInspectorView(store: store)
        }
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return CanvasInspectorView(store: store)
}
