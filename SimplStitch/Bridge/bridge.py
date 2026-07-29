#!/usr/bin/env python3
"""SimplStitch Python-Bridge.

Liest zeilenweise JSON-Befehle von stdin, delegiert an pyembroidery
(später zusätzlich InkStitch), und schreibt zeilenweise JSON-Antworten
auf stdout. Ein Befehl pro Zeile, eine Antwort pro Zeile.

Envelope:
  Request:  {"command": "<name>", "payload": {...}}
  Response: {"ok": true,  "result": {...}}
         or {"ok": false, "error": "<message>"}
"""

import json
import sys
import traceback


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


COMMANDS = {
    "ping": cmd_ping,
    "write_vp3": cmd_write_vp3,
    "read_embroidery": cmd_read_embroidery,
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
