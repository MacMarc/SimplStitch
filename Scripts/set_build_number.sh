#!/usr/bin/env bash
# Xcode-Build-Phase "Set Build Number": setzt die Build-Nummer (CFBundleVersion) der gebauten App
# automatisch auf die Anzahl Git-Commits des aktuellen Stands. Jeder neue Commit ergibt so eine
# höhere Build-Nummer, ohne dass jemand von Hand hochzählen muss. Die Version (z.B. 0.1-alpha,
# CFBundleShortVersionString) bleibt weiterhin von Hand gesetzt.
#
# Schreibt nur in die Info.plist im Build-Ordner, nicht ins Repo. Ohne Git (z.B. Quellen als ZIP)
# bleibt die Build-Nummer aus den Projekteinstellungen stehen.
set -euo pipefail

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if ! COUNT="$(git -C "${SRCROOT}" rev-list --count HEAD 2>/dev/null)"; then
	echo "warning: Build-Nummer nicht gesetzt, Git-Verlauf nicht lesbar."
	exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${COUNT}" "${PLIST}"
echo "Build-Nummer: ${COUNT}"
