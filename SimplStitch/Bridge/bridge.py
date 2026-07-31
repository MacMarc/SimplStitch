#!/usr/bin/env python3
"""SimplStitch Python-Bridge.

Liest zeilenweise JSON-Befehle von stdin, delegiert an pyembroidery und
InkStitch (vendored, siehe Vendor/inkstitch_lib/ im Repo bzw.
Contents/Resources/inkstitch_lib/ in der App-Bundle), und schreibt
zeilenweise JSON-Antworten auf stdout. Ein Befehl pro Zeile, eine Antwort
pro Zeile.

Envelope:
  Request:  {"command": "<name>", "payload": {...}}
  Response: {"ok": true,  "result": {...}}
         or {"ok": false, "error": "<message>"}
"""

import json
import os
import sys
import traceback
import unicodedata

# inkstitch_lib liegt als Geschwisterordner neben bridge.py (Contents/Resources/,
# siehe Scripts/bundle_python.sh) und muss als Package "lib" auflösbar sein —
# mehrere InkStitch-Module nutzen absolute Imports wie "from lib.utils...".
INKSTITCH_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "inkstitch_lib")
if INKSTITCH_LIB_DIR not in sys.path:
    sys.path.insert(0, INKSTITCH_LIB_DIR)


def cmd_ping(payload):
    return {"pong": True}


def cmd_write_vp3(payload):
    import pyembroidery

    stitches = payload["stitches"]  # [[x_mm, y_mm, command], ...]
    output_path = payload["outputPath"]

    pattern = pyembroidery.EmbPattern()
    for x, y, command in stitches:
        # pyembroidery speichert Stichkoordinaten intern in 1/10mm, siehe Kommentar bei
        # cmd_read_embroidery weiter unten (Issue #29, Punkt 2A).
        pattern.add_stitch_absolute(command, x * 10, y * 10)
    pyembroidery.write_vp3(pattern, output_path)

    return {"writtenPath": output_path, "stitchCount": len(pattern.stitches)}


def cmd_read_embroidery(payload):
    import pyembroidery

    input_path = payload["inputPath"]
    pattern = pyembroidery.read(input_path)
    if pattern is None:
        raise ValueError(f"Konnte Datei nicht lesen (unbekanntes Format?): {input_path}")

    # pyembroidery arbeitet intern in 1/10mm, nicht mm (siehe pyembroidery/GenericWriter.py:
    # "bounds[i] / 10.0  # convert to mm", vor dem Fix hier nie berücksichtigt). Ohne diese
    # Umrechnung kam ein 100mm breites Motiv aus einer Fremddatei als 1000mm breites
    # DesignObject an — Faktor 10 zu gross (Issue #29, Punkt 2A). cmd_write_vp3/
    # cmd_write_embroidery machen spiegelbildlich * 10 beim Schreiben, damit der
    # SimplStitch-eigene Roundtrip weiterhin in echten Millimetern konsistent bleibt.
    stitches = [[s[0] / 10, s[1] / 10, s[2]] for s in pattern.stitches]
    threads = [_thread_to_dict(thread) for thread in pattern.threadlist]
    return {"stitches": stitches, "threads": threads}


def _thread_to_dict(thread):
    return {
        "red": thread.get_red(),
        "green": thread.get_green(),
        "blue": thread.get_blue(),
        "name": thread.description,
        "catalogNumber": thread.catalog_number,
    }


def cmd_write_embroidery(payload):
    """Generischer Multi-Format-Export (Phase 7): Formatwahl läuft über die
    Dateiendung von outputPath (pyembroidery.write dispatcht selbst), nicht über
    einen eigenen Format-Parameter — deckt alle von pyembroidery unterstützten
    Schreib-Formate ab (u.a. vp3/pes/jef/exp/dst), ohne pro Format eine eigene
    Bridge-Funktion zu brauchen.

    Payload: {"stitches": [[x_mm, y_mm, command], ...], "threads": [{"red",
    "green", "blue", "name"?, "catalogNumber"?}, ...], "outputPath"}. `threads[i]`
    entspricht dem i-ten Farbblock (durch COLOR_CHANGE-Stiche getrennt) — dieselbe
    Zuordnung wie pyembroidery.EmbPattern.get_as_colorblocks.
    """
    import pyembroidery

    stitches = payload["stitches"]
    threads = payload.get("threads", [])
    output_path = payload["outputPath"]

    pattern = pyembroidery.EmbPattern()
    for thread in threads:
        pattern.add_thread(
            {
                "color": (thread["red"], thread["green"], thread["blue"]),
                "description": _ascii_safe_thread_text(thread.get("name")),
                "catalog": _ascii_safe_thread_text(thread.get("catalogNumber")),
            }
        )
    for x, y, command in stitches:
        # 1/10mm-Umrechnung wie cmd_write_vp3/cmd_read_embroidery (Issue #29, Punkt 2A) —
        # ohne * 10 schrieb diese Funktion physisch Motive, die auf der echten Maschine
        # zehnmal kleiner ankamen als am Bildschirm gezeichnet.
        pattern.add_stitch_absolute(command, x * 10, y * 10)
    pattern.end()

    pyembroidery.write(pattern, output_path)

    return {
        "writtenPath": output_path,
        "stitchCount": pattern.count_stitches(),
        "colorCount": max(pattern.count_color_changes() + 1, pattern.count_threads()),
    }


_GERMAN_TRANSLITERATION = str.maketrans(
    {"ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss"}
)


def _ascii_safe_thread_text(text):
    """Transliteriert Garnnamen/Katalognummern auf reines ASCII.

    Empirischer Befund: pyembroiderys VP3Writer schreibt die Byte-Länge eines
    Fadennamens anhand von Pythons `len()` (Zeichenanzahl), nicht der tatsächlichen
    UTF-8-Byte-Länge. Bei Umlauten (z.B. "Grün", 4 Zeichen aber 5 UTF-8-Bytes)
    verschiebt das nachfolgende Binärfelder um die Differenz — die Datei liest
    sich danach nicht mehr zurück ("read length must be non-negative or -1").
    Für ein DE/EN-lokalisiertes Garnnamen-Vokabular (Grün, Türkis, Rosé, …) ist
    das kein Rand-, sondern ein Regelfall — daher hier vorsorglich für alle
    Zielformate transliteriert, nicht nur für das VP3, an dem der Fehler
    gefunden wurde.
    """
    if not text:
        return text
    text = text.translate(_GERMAN_TRANSLITERATION)
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")


_STITCH_ELEMENT_CLASSES = None  # lazy: importiert erst bei erstem generate_stitches-Aufruf


def _stitch_element_classes():
    global _STITCH_ELEMENT_CLASSES
    if _STITCH_ELEMENT_CLASSES is None:
        from lib.elements.fill_stitch import FillStitch
        from lib.elements.satin_column import SatinColumn
        from lib.elements.stroke import Stroke

        _STITCH_ELEMENT_CLASSES = {
            "tatami": FillStitch,
            "straight": Stroke,
            "satin": SatinColumn,
        }
    return _STITCH_ELEMENT_CLASSES


def _offset_border_node(node, distance_px, canvas_width_px, canvas_height_px):
    """Issue #30 (Rand-Ausrichtung innen/aussen): SVG/CoreGraphics kennt keinen Inside/Outside-
    Stroke, ein Rand liegt immer zentriert auf der Kontur — für "nur innen"/"nur aussen" muss die
    tatsächliche Stichgeometrie VOR der InkStitch-Übergabe um `distance_px` versetzt werden
    (negativ = einwärts/schrumpfen, positiv = auswärts/wachsen). `element.paths` liefert die
    bereits vollständig transformierte (Rotation/Skew/Viewbox-Skalierung, siehe
    `EmbroideryElement.parse_path`/`apply_transforms`) Stichgeometrie in genau demselben Pixel-
    Raum, in dem InkStitch selbst rechnet — exakt WYSIWYG mit dem, was ohne Offset gestickt würde.

    Geschlossene Teilpfade (erster ≈ letzter Punkt) werden zu Shapely-Polygonen (inkl. Löcher bei
    ineinander verschachtelten Konturen, z.B. Buchstaben mit Innenkontur) und per `buffer()`
    versetzt; offene Teilpfade über `offset_curve()` (Vorzeichen = links/rechts der Zeichenrichtung
    — für eine offene Linie gibt es kein eindeutiges "innen", das ist eine bewusste Näherung).

    Ergebnis ist ein NEUER, freistehender `<path>`-Knoten in einem frisch aufgebauten 1:1-
    skalierten SVG-Dokument (viewBox == Breite/Höhe in Pixeln) — dadurch wird die bereits in
    `element.paths` enthaltene Viewbox-Skalierung nicht ein zweites Mal angewendet, wenn der
    Aufrufer den Knoten erneut einliest. Alle Original-Attribute (id, style, inkstitch:*, fill)
    werden übernommen, nur `transform` entfällt (bereits in den Offset-Koordinaten verrechnet).
    Gibt den unveränderten Original-Knoten zurück, wenn keine Geometrie zum Versetzen da ist.
    """
    import inkex
    from shapely.geometry import LineString, Polygon
    from shapely.ops import unary_union

    from lib.elements.element import EmbroideryElement

    subpaths = EmbroideryElement(node).paths

    closed_rings = []
    open_lines = []
    for points in subpaths:
        if len(points) < 3:
            continue
        first, last = points[0], points[-1]
        is_closed = abs(first[0] - last[0]) < 0.01 and abs(first[1] - last[1]) < 0.01
        (closed_rings if is_closed else open_lines).append(points)

    offset_geoms = []
    if closed_rings:
        polys = [Polygon(ring) for ring in closed_rings]
        polys = [p for p in polys if p.is_valid and not p.is_empty]
        # Grössere Ringe zuerst: ein kleinerer Ring, der innerhalb eines grösseren liegt, wird
        # dessen Loch (z.B. Innenkontur eines Buchstabens) — sonst ist er eine eigenständige,
        # unabhängige Form (z.B. der Punkt auf einem "i"). Deckt die häufigen Fälle ab (eine Form,
        # eine Form mit Löchern, mehrere getrennte Formen), ohne eine vollständige Polygon-
        # Verschachtelungsanalyse zu brauchen.
        polys.sort(key=lambda p: p.area, reverse=True)
        shells = []  # [(exterior_poly, [hole_coords, ...])]
        for poly in polys:
            placed = False
            for shell_poly, holes in shells:
                if shell_poly.contains(poly.representative_point()):
                    holes.append(list(poly.exterior.coords))
                    placed = True
                    break
            if not placed:
                shells.append((poly, []))
        shapes = [Polygon(shell.exterior.coords, holes) for shell, holes in shells]
        combined = unary_union(shapes) if len(shapes) > 1 else shapes[0]
        buffered = combined.buffer(distance_px, join_style="mitre", mitre_limit=5.0)
        if not buffered.is_empty:
            offset_geoms.append(buffered)
    for points in open_lines:
        line = LineString(points)
        if line.length > 0:
            offset_geoms.append(line.offset_curve(distance_px))

    if not offset_geoms:
        return node

    d = _shapely_geoms_to_svg_path(offset_geoms)
    if not d:
        return node

    wrapper_svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:inkstitch="http://inkstitch.org/namespace" '
        f'width="{canvas_width_px}px" height="{canvas_height_px}px" '
        f'viewBox="0 0 {canvas_width_px} {canvas_height_px}"></svg>'
    )
    wrapper_root = inkex.load_svg(wrapper_svg.encode("utf-8")).getroot()
    new_node = inkex.PathElement()
    new_node.attrib.update(node.attrib)
    if "transform" in new_node.attrib:
        del new_node.attrib["transform"]
    new_node.set("d", d)
    wrapper_root.append(new_node)
    return new_node


def _shapely_geoms_to_svg_path(geoms):
    """Baut einen SVG-`d`-String aus Shapely-Geometrien (Polygon/MultiPolygon inkl. Löcher,
    LineString/MultiLineString) — Gegenstück zu `_offset_border_node`s Punkt-zu-Shapely-Weg."""
    from shapely.geometry import GeometryCollection, LineString, MultiLineString, MultiPolygon, Polygon

    def ring_path(coords, closed):
        points = list(coords)
        if len(points) < 2:
            return ""
        parts = [f"M{points[0][0]:.4f},{points[0][1]:.4f}"]
        parts.extend(f"L{x:.4f},{y:.4f}" for x, y in points[1:])
        if closed:
            parts.append("Z")
        return " ".join(parts)

    segments = []

    def add(geom):
        if geom is None or geom.is_empty:
            return
        if isinstance(geom, Polygon):
            segments.append(ring_path(geom.exterior.coords, True))
            for interior in geom.interiors:
                segments.append(ring_path(interior.coords, True))
        elif isinstance(geom, MultiPolygon):
            for part in geom.geoms:
                add(part)
        elif isinstance(geom, LineString):
            segments.append(ring_path(geom.coords, False))
        elif isinstance(geom, MultiLineString):
            for part in geom.geoms:
                add(part)
        elif isinstance(geom, GeometryCollection):
            for part in geom.geoms:
                add(part)

    for geom in geoms:
        add(geom)

    return " ".join(segment for segment in segments if segment)


def cmd_generate_stitches(payload):
    """Generiert echte Stichkoordinaten für ein einzelnes DesignObject via InkStitch.

    Payload: {"canvasWidthMm", "canvasHeightMm", "objectSvg" (ein einzelnes SVG-Element-
    Fragment mit inkstitch:*-Attributen, siehe SVGDesignSerializer), "stitchType"
    ("tatami"/"straight"/"satin", siehe Swift StitchType), optional "borderWidthMm"/
    "borderAlignment" ("centered"/"inside"/"outside", nur beim Rand-Stichpass gesetzt, siehe
    StitchGenerationService.generateBorderStitches) — löst vor der InkStitch-Übergabe ein
    echtes Pfad-Offsetting aus (`_offset_border_node`); "centered" bzw. fehlender Wert lässt die
    Geometrie unverändert (die native Bedeutung von `stroke-width`)}.
    Ergebnis: {"stitches": [[x_mm, y_mm, command], ...]} — command ist die pyembroidery-
    Konstante (STITCH=0/JUMP=1/TRIM=2/STOP=3/COLOR_CHANGE=5), dieselbe Konvention wie
    write_vp3/read_embroidery, direkt weiterverwendbar.
    """
    import inkex
    import pyembroidery
    from lib.svg.units import PIXELS_PER_MM

    canvas_width_mm = payload["canvasWidthMm"]
    canvas_height_mm = payload["canvasHeightMm"]
    object_svg = payload["objectSvg"]
    stitch_type = payload["stitchType"]
    border_width_mm = payload.get("borderWidthMm")
    border_alignment = payload.get("borderAlignment", "centered")

    element_classes = _stitch_element_classes()
    element_class = element_classes.get(stitch_type)
    if element_class is None:
        raise ValueError(f"Unbekannter Stichtyp: {stitch_type!r}")

    svg_document = (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:inkstitch="http://inkstitch.org/namespace" '
        f'width="{canvas_width_mm}mm" height="{canvas_height_mm}mm" '
        f'viewBox="0 0 {canvas_width_mm} {canvas_height_mm}">{object_svg}</svg>'
    )
    document = inkex.load_svg(svg_document.encode("utf-8"))
    node = next(document.getroot().iterchildren(), None)
    if node is None:
        raise ValueError("objectSvg enthält kein Element")

    if border_alignment in ("inside", "outside") and border_width_mm:
        sign = -1 if border_alignment == "inside" else 1
        distance_px = sign * (border_width_mm / 2) * PIXELS_PER_MM
        node = _offset_border_node(
            node, distance_px, canvas_width_mm * PIXELS_PER_MM, canvas_height_mm * PIXELS_PER_MM
        )

    element = element_class(node)
    try:
        stitch_groups = element.embroider(None, None)
    except Exception as exc:  # InkStitchs eigene Exceptions (z.B. NotStitchableError)
        raise ValueError(f"Stichgenerierung fehlgeschlagen: {exc}") from exc

    stitches = []
    for group in stitch_groups:
        for stitch in group.stitches:
            if stitch.color_change:
                command = pyembroidery.COLOR_CHANGE
            elif stitch.stop:
                command = pyembroidery.STOP
            elif stitch.trim:
                command = pyembroidery.TRIM
            elif stitch.jump:
                command = pyembroidery.JUMP
            else:
                command = pyembroidery.STITCH
            stitches.append([stitch.x / PIXELS_PER_MM, stitch.y / PIXELS_PER_MM, command])

    return {"stitches": stitches}


COMMANDS = {
    "ping": cmd_ping,
    "write_vp3": cmd_write_vp3,
    "read_embroidery": cmd_read_embroidery,
    "generate_stitches": cmd_generate_stitches,
    "write_embroidery": cmd_write_embroidery,
}


def handle_line(line):
    try:
        request = json.loads(line)
        command_name = request.get("command")
        handler = COMMANDS.get(command_name)
        if handler is None:
            raise ValueError(f"Unbekannter Befehl: {command_name!r}")
        result = handler(request.get("payload", {}))
        return {"ok": True, "result": result}
    except Exception as exc:  # noqa: BLE001 - Fehler wird strukturiert zurückgegeben
        return {"ok": False, "error": str(exc), "traceback": traceback.format_exc()}


def main():
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        response = handle_line(line)
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
