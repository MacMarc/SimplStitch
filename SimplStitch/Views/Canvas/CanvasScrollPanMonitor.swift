//
//  CanvasScrollPanMonitor.swift
//  SimplStitch
//
//  Issue #12: Zweifinger-Scroll (Trackpad) bzw. Mausrad pannt die Zeichenfläche, wie in nativen
//  macOS-Canvas-Apps. SwiftUI-Gesten liefern keine `scrollWheel`-Events, daher ein lokaler
//  NSEvent-Monitor statt einer eigenen `NSViewRepresentable` — so bleiben Hit-Testing und Gesten
//  des SwiftUI-`Canvas` unangetastet.
//

import AppKit

@MainActor
final class CanvasScrollPanMonitor {
    private var monitor: Any?

    /// `handler` bekommt jedes Scroll-Event der App und entscheidet selbst, ob es den Canvas
    /// betrifft: `true` = verbraucht (pannen), `false` = normal weiterreichen.
    func start(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { handler(event) } ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
