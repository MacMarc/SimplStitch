#!/usr/bin/env bash
# Lädt eine minimale, in sich geschlossene CPython-Runtime (python-build-standalone)
# für Apple Silicon, installiert die Python-Abhängigkeiten und legt das Ergebnis
# am übergebenen Zielpfad ab.
#
# Wichtig: Das Ziel darf NICHT unter SimplStitch/ liegen. Xcodes File-System-
# Synchronized-Groups würden sonst jede einzelne Datei der Runtime (mehrere
# tausend .py/.pyc-Dateien) als Projektmitglied einlesen. Stattdessen kopiert
# die Xcode Run-Script-Build-Phase "Bundle Python Runtime" das Ergebnis dieses
# Skripts direkt nach ${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/python,
# also am Projektnavigator vorbei.
set -euo pipefail

PYTHON_VERSION="3.12.13"
PBS_RELEASE="20260728"
ARCHIVE="cpython-${PYTHON_VERSION}+${PBS_RELEASE}-aarch64-apple-darwin-install_only.tar.gz"
URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_RELEASE}/${ARCHIVE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST="${1:-${REPO_ROOT}/PythonRuntime}"
CACHE_DIR="${REPO_ROOT}/.build-cache"

mkdir -p "${CACHE_DIR}"

if [ ! -f "${CACHE_DIR}/${ARCHIVE}" ]; then
	echo "bundle_python.sh: lade ${ARCHIVE} ..."
	curl -fsSL -o "${CACHE_DIR}/${ARCHIVE}.tmp" "${URL}"
	mv "${CACHE_DIR}/${ARCHIVE}.tmp" "${CACHE_DIR}/${ARCHIVE}"
else
	echo "bundle_python.sh: verwende gecachtes ${ARCHIVE}"
fi

if [ -x "${DEST}/bin/python3" ] && [ -f "${DEST}/.bundle_version" ] && [ "$(cat "${DEST}/.bundle_version")" = "${PYTHON_VERSION}+${PBS_RELEASE}" ]; then
	echo "bundle_python.sh: Runtime bereits aktuell (${PYTHON_VERSION}+${PBS_RELEASE}) unter ${DEST}"
else
	echo "bundle_python.sh: entpacke Runtime nach ${DEST} ..."
	rm -rf "${DEST}"
	mkdir -p "${DEST}"
	tar -xzf "${CACHE_DIR}/${ARCHIVE}" --strip-components=1 -C "${DEST}"
	echo "${PYTHON_VERSION}+${PBS_RELEASE}" >"${DEST}/.bundle_version"
fi

PYTHON_BIN="${DEST}/bin/python3"

echo "bundle_python.sh: installiere Python-Abhängigkeiten ..."
"${PYTHON_BIN}" -m pip install --no-cache-dir --upgrade --quiet pip
"${PYTHON_BIN}" -m pip install --no-cache-dir --quiet -r "${REPO_ROOT}/SimplStitch/Bridge/requirements.txt"

# Aufräumen: Tests, __pycache__ und Bytecode-Caches der Runtime selbst reduzieren die App-Größe.
find "${DEST}/lib" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "${DEST}/lib" -type d -name "test" -prune -exec rm -rf {} +
find "${DEST}/lib" -type d -name "tests" -prune -exec rm -rf {} +

echo "bundle_python.sh: fertig. Runtime unter ${DEST}"
