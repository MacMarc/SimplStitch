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

    stitches = payload["stitches"]  # [[x, y, command], ...]
    output_path = payload["outputPath"]

    pattern = pyembroidery.EmbPattern()
    for x, y, command in stitches:
        pattern.add_stitch_absolute(command, x, y)
    pyembroidery.write_vp3(pattern, output_path)

    return {"writtenPath": output_path, "stitchCount": len(pattern.stitches)}


def cmd_read_embroidery(payload):
    import pyembroidery

    input_path = payload["inputPath"]
    pattern = pyembroidery.read(input_path)
    if pattern is None:
        raise ValueError(f"Konnte Datei nicht lesen (unbekanntes Format?): {input_path}")

    stitches = [[s[0], s[1], s[2]] for s in pattern.stitches]
    return {"stitches": stitches}


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


def cmd_generate_stitches(payload):
    """Generiert echte Stichkoordinaten für ein einzelnes DesignObject via InkStitch.

    Payload: {"canvasWidthMm", "canvasHeightMm", "objectSvg" (ein einzelnes SVG-Element-
    Fragment mit inkstitch:*-Attributen, siehe SVGDesignSerializer), "stitchType"
    ("tatami"/"straight"/"satin", siehe Swift StitchType)}.
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
