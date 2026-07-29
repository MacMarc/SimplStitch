# SimplStitch

![License](https://img.shields.io/badge/License-GPL--3.0-blue) ![Platform](https://img.shields.io/badge/Platform-macOS%2026%2B%20(Apple%20Silicon)-lightgrey) ![Status](https://img.shields.io/badge/Status-active%20development-orange)

[🇩🇪 Deutsch](README.md) · 🇬🇧 English

**You draw. It becomes a stitch file.**

SimplStitch is a macOS app that lets you draw directly on screen — shapes, text, lines — and automatically turns your drawing into a ready-to-sew stitch file for your home embroidery machine. No embroidery expertise required: stitch type, density and underlay get sensible defaults, but you can always fine-tune them yourself.

Project mascot: **Bobbi the Twister**, a small bobbin character forever twisting thread.

> ⚠️ **Early development stage.** SimplStitch has not been released yet and is subject to change. Feedback is very welcome — see [Feedback & Issues](#feedback--issues).

---

## Contents

- [About this project](#about-this-project)
- [Why not on the Mac App Store?](#why-not-on-the-mac-app-store)
- [What SimplStitch can do](#what-simplstitch-can-do)
- [How it works](#how-it-works)
- [Libraries used](#libraries-used)
- [Requirements & installation](#requirements--installation)
- [Building from source](#building-from-source)
- [Project status](#project-status)
- [License](#license)
- [Feedback & Issues](#feedback--issues)

---

## About this project

SimplStitch is a **vibe-coding project**: the vast majority of the code was not written by hand line by line in the classic sense, but developed together with an AI assistant ([Claude Code](https://claude.com/claude-code)) — the author describes what's needed in natural language, reviews and steers the outcome, and the AI writes most of the actual implementation.

Concretely, this means:

- It's a **hobby/learning project** by a single author, not a commercial product built by a team.
- The development history (including design decisions, bugs found, and deliberate simplifications) is openly documented in [`CLAUDE.md`](CLAUDE.md) — that file is the technical working brief for the AI assistance, but it's also the most honest changelog this project has.
- Code quality and test coverage are taken seriously (automated tests run on every change), but as with any open-source project: **no warranty, use at your own risk** (see [License](#license)).
- Given this development style, finding rough edges, bugs, or unclear code is entirely possible. Please report them rather than silently working around them — see [Feedback & Issues](#feedback--issues).

## Why not on the Mac App Store?

SimplStitch uses [InkStitch](https://inkstitch.org/) for the actual stitch generation, a library licensed under **GPL-3.0**. As a result, SimplStitch itself is necessarily also licensed under GPL-3.0 (see [License](#license)).

The Mac App Store's terms of use (including additional distribution and usage restrictions, DRM requirements) conflict with the terms of the GPL-3.0, which explicitly forbids imposing such further restrictions on recipients of the software. This conflict isn't unique to SimplStitch — the best-known example is VLC, which for the same reason was unavailable on the App Store for a long time.

SimplStitch is therefore distributed **exclusively via [GitHub Releases](https://github.com/MacMarc/SimplStitch/releases)** as a notarized DMG, not through the App Store.

## What SimplStitch can do

- **Drawing:** shapes (rectangle, circle, star, line, freehand path) and text directly on the canvas, all sharing the same handles for scaling, rotating, skewing and corner-rounding (like PowerPoint/Keynote)
- **Automatic stitch-type suggestions:** narrow, elongated shapes automatically get suggested satin stitch, filled areas get tatami fill — always manually overridable
- **Per-object stitch types:** running stitch, satin stitch, tatami fill, including density, angle and underlay
- **Independent fill & border:** every object can have a fill and/or a border, each with its own stitch settings and thread colors
- **Live stitch preview** right on the canvas as you change settings
- **Thread palettes:** 74 built-in default palettes (including Madeira, Isacord, DMC, Robison-Anton) plus import of your own `.gpl` palettes
- **Multi-select & grouping** of objects
- **Export** to VP3 (Pfaff), PES (Brother), JEF (Janome), EXP (Bernina/Melco), DST (Tajima) or SVG
- **Import** of 46 embroidery file formats (best-effort reconstruction as running stitch)
- Fully **localized in German and English**
- Planned: AI-assisted image-to-stitch-file conversion, fully on-device (no internet, no external API)

## How it works

SimplStitch consists of two parts that come together in a single app:

1. **The SwiftUI/SwiftData app** (macOS, Apple Silicon) — canvas, object management, project files, the entire user interface.
2. **A bundled Python backend** — runs as a background process inside the app (no system Python required, no internet access), responsible for the actual embroidery-domain logic:
   - **[InkStitch](https://inkstitch.org/)** computes the actual stitch coordinates from a drawn shape (vector path → needle positions)
   - **[pyembroidery](https://github.com/EmbroidePy/pyembroidery)** reads and writes the embroidery file formats (VP3, PES, JEF, EXP, DST, …)

Swift and Python communicate over a lightweight JSON interface via stdin/stdout — the app sends a request ("compute the stitches for this object"), the backend replies with the resulting coordinates.

Your design is saved as a `.stitchdesign` document — a macOS document package (looks like a single file in Finder, but is internally a folder) containing an editable `content.svg` as the source of truth, a `preview.png` for the Finder thumbnail, and an `assets/` folder for background images.

More technical detail (architecture, data model, development history) lives in [`CLAUDE.md`](CLAUDE.md).

## Libraries used

| Library | Purpose | License |
|---|---|---|
| [InkStitch](https://inkstitch.org/) | Stitch generation (vector path → stitch coordinates); vendored under [`Vendor/inkstitch_lib/`](Vendor/inkstitch_lib/), including the 74 bundled thread palettes under [`Vendor/inkstitch_palettes/`](Vendor/inkstitch_palettes/) | GPL-3.0 |
| [pyembroidery](https://github.com/EmbroidePy/pyembroidery) | Format I/O: reads 46, writes 20 embroidery formats (incl. VP3, PES, JEF, EXP, DST) | MIT |
| [inkex](https://pypi.org/project/inkex/) | Inkscape SVG foundations, used by InkStitch | GPL-2.0-or-later |
| [Shapely](https://pypi.org/project/shapely/), [NumPy](https://pypi.org/project/numpy/), [NetworkX](https://pypi.org/project/networkx/), [lxml](https://pypi.org/project/lxml/) | Geometry, numerics and XML processing, used by InkStitch | BSD-3-Clause |
| [trimesh](https://pypi.org/project/trimesh/) | 3D/mesh helpers, used by InkStitch | MIT |
| [colormath2](https://pypi.org/project/colormath2/) | Color-space conversion, used by InkStitch | BSD-3-Clause |
| CPython | Bundled Python runtime, no system Python dependency | PSF License |

The full list of transitive Python dependencies (including less central packages like Pillow, cssselect, pyparsing, scour, tinycss2 — all permissively licensed under MIT/BSD/Apache-2.0) is in [`SimplStitch/Bridge/requirements.txt`](SimplStitch/Bridge/requirements.txt). Details on the InkStitch vendoring (commit reference, the one required patch) are in [`Vendor/inkstitch_lib/VENDOR_PATCHES.md`](Vendor/inkstitch_lib/VENDOR_PATCHES.md).

## Requirements & installation

- **macOS 26 or newer**
- **Apple Silicon (arm64)** — Intel Macs are not supported

Prebuilt releases will be available under [GitHub Releases](https://github.com/MacMarc/SimplStitch/releases) as a notarized DMG — download, open, drag to Applications.

## Building from source

```bash
git clone https://github.com/MacMarc/SimplStitch.git
cd SimplStitch
open SimplStitch.xcodeproj
```

Building in Xcode runs a build-script phase that automatically downloads a matching CPython runtime and bundles it together with the Python dependencies (InkStitch, pyembroidery, …) into `Contents/Resources/`. This requires an internet connection on the first build (`ENABLE_USER_SCRIPT_SANDBOXING = NO`).

## Project status

SimplStitch is under active development. The canvas engine, stitch generation, import/export, and the core UI (toolbar, menu bar, sidebar, settings) are functional. Larger open items:

- Apple Intelligence integration (image → stitch file via Vision/Foundation Models)
- Release pipeline (notarization, automated GitHub releases)

For a detailed, continuously updated progress log, see the "Aktueller Stand" (current status) section in [`CLAUDE.md`](CLAUDE.md).

## License

SimplStitch is licensed under the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE) / [`COPYING`](COPYING) for the full license text.

Short summary (not legal advice, the license text governs): you're free to use, modify and redistribute SimplStitch, including commercially — but derivative works must also be distributed under GPL-3.0 with complete source code. The software is provided **without any warranty**.

## Feedback & Issues

Found a bug, have a feature idea, or something's just unclear? Please file a [GitHub Issue](https://github.com/MacMarc/SimplStitch/issues) — that's the central and preferred channel for feedback on this project.
