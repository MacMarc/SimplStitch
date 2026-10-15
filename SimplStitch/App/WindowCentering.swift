//
//  WindowCentering.swift
//  SimplStitch
//
//  Marcs Wunsch (Okt. 2026): Das Startfenster zum Öffnen/Anlegen eines Dokuments (das
//  NSOpenPanel, das DocumentGroup beim Start zeigt) und das Einstellungen-Fenster erscheinen
//  jedes Mal in der Mitte des Bildschirms. Das Öffnen-Fenster bekommt dabei eine feste
//  Standardgrösse — macOS merkt sich sonst die letzte (oft sehr grosse) Grösse.
//
//  Umsetzung: Beobachtet, wann ein Fenster sichtbar wird (Occlusion-Benachrichtigung). Jedes
//  Erscheinen wird genau einmal zentriert; verschiebt der Nutzer das Fenster danach, bleibt es,
//  wo er es hingestellt hat, bis es wieder geschlossen wird.
//

import AppKit
import SwiftUI

final class WindowCentering {
    static let shared = WindowCentering()

    /// Standardgrösse des Öffnen-Fensters, etwa wie im Finder-Dialog anderer Apps.
    static let openPanelSize = NSSize(width: 820, height: 520)

    /// Fenster, die beim Erscheinen zentriert werden (zusätzlich zu jedem `NSOpenPanel`).
    private var registeredWindows: Set<ObjectIdentifier> = []
    /// Fenster, die seit ihrem letzten Erscheinen schon zentriert wurden.
    private var centeredWindows: Set<ObjectIdentifier> = []
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.windowVisibilityChanged(window) }
        }
    }

    /// Für Fenster, die sich nicht am Typ erkennen lassen (Einstellungen): beim Erscheinen zentrieren.
    func register(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard !registeredWindows.contains(id) else { return }
        registeredWindows.insert(id)
        windowVisibilityChanged(window)
    }

    private func windowVisibilityChanged(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        let isOpenPanel = window is NSOpenPanel
        guard isOpenPanel || registeredWindows.contains(id) else { return }

        // Nur echtes Ausblenden zählt — ein von anderen Fenstern verdecktes Fenster bleibt sichtbar.
        guard window.isVisible else {
            centeredWindows.remove(id)
            return
        }
        guard !centeredWindows.contains(id) else { return }
        centeredWindows.insert(id)

        var frame = window.frame
        if isOpenPanel {
            frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.openPanelSize)).size
        }
        // Exakt mittig auf dem Bildschirm des Fensters — `NSWindow.center()` setzt Fenster bewusst
        // etwas oberhalb der Mitte.
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        frame.origin = NSPoint(
            x: (visible.midX - frame.width / 2).rounded(),
            y: (visible.midY - frame.height / 2).rounded()
        )
        window.setFrame(frame, display: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowCentering.shared.start()
    }
}

/// Meldet das Fenster, in dem die View steckt, bei `WindowCentering` an (für das Einstellungen-
/// Fenster, das sich nicht am Typ erkennen lässt).
struct CenteredWindowRegistration: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        RegisteringView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class RegisteringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowCentering.shared.register(window) }
        }
    }
}
