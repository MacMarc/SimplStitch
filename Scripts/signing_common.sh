#!/usr/bin/env bash
# Gemeinsame Signier-Funktionen für sign_embedded_binaries.sh (Xcode-Build-Phase beim Archivieren)
# und build_dmg.sh (DMG von Hand bauen). Wird per `source` eingebunden, nicht direkt ausgeführt.
#
# Hintergrund: Xcode signiert nur die App selbst, nicht die ~67 Mach-O-Dateien der gebündelten
# Python-Runtime unter Contents/Resources (python3.12, libpython, .so-Module von numpy/lxml/Pillow …).
# Apple lehnt die Notarisierung dann ab ("Hardened Runtime is Not Enabled", "not signed with a valid
# Developer ID certificate", "no secure timestamp"). Jede dieser Dateien wird deshalb einzeln mit
# Developer ID, Hardened Runtime und Zeitstempel signiert.

SIGNING_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_HELPER_ENTITLEMENTS="${SIGNING_COMMON_DIR}/PythonHelper.entitlements"

# Ermittelt die Developer-ID-Application-Identität und gibt ihren SHA-1-Hash aus.
# Reihenfolge: Umgebungsvariable SIGNING_IDENTITY, sonst die passende Identität im Schlüsselbund
# (gefiltert nach TEAM_ID bzw. Xcodes DEVELOPMENT_TEAM, falls gesetzt). Gibt nichts aus, wenn
# keine eindeutige Identität gefunden wurde.
resolve_developer_id() {
	if [ -n "${SIGNING_IDENTITY:-}" ]; then
		echo "${SIGNING_IDENTITY}"
		return
	fi
	local team="${TEAM_ID:-${DEVELOPMENT_TEAM:-}}"
	local matches
	matches="$(security find-identity -v -p codesigning 2>/dev/null \
		| grep "\"Developer ID Application: .*(${team:-[A-Z0-9]*})\"" || true)"
	if [ "$(printf '%s\n' "${matches}" | grep -c .)" = "1" ]; then
		printf '%s\n' "${matches}" | awk '{ print $2 }'
	fi
}

is_macho() {
	file -b "$1" | grep -q "Mach-O"
}

# sign_embedded_binaries <Resources-Ordner> <Identität>
# Signiert alle Mach-O-Dateien darunter, tiefste Pfade zuerst. Die Python-Programme unter
# python/bin bekommen PythonHelper.entitlements, damit sie die Sandbox der App erben.
sign_embedded_binaries() {
	local resources="$1"
	local identity="$2"
	local count=0 file
	while IFS= read -r file; do
		is_macho "${file}" || continue
		if [[ "${file}" == */python/bin/* ]]; then
			codesign --force --timestamp --options runtime --sign "${identity}" \
				--entitlements "${PYTHON_HELPER_ENTITLEMENTS}" "${file}"
		else
			codesign --force --timestamp --options runtime --sign "${identity}" "${file}"
		fi
		count=$((count + 1))
	done < <(find "${resources}" -type f | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
	echo "${count} eingebettete Binärdateien mit Hardened Runtime signiert"
}
