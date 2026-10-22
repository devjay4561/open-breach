#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ -n "${GODOT_BIN:-}" ]]; then
  ENGINE="$GODOT_BIN"
elif [[ -x .tools/Godot.app/Contents/MacOS/Godot ]]; then
  ENGINE="$ROOT_DIR/.tools/Godot.app/Contents/MacOS/Godot"
elif [[ -x .tools/godot ]]; then
  ENGINE="$ROOT_DIR/.tools/godot"
elif command -v godot >/dev/null 2>&1; then
  ENGINE="$(command -v godot)"
else
  echo 'Godot 4.7.2 is missing. Run ./scripts/setup.sh first.' >&2
  exit 1
fi
ENGINE_VERSION="$("$ENGINE" --version)"
if [[ "$ENGINE_VERSION" != 4.7.2.stable* ]]; then
  echo "Godot 4.7.2.stable is required; found $ENGINE_VERSION" >&2
  exit 1
fi
BREACH_WEB_DIR="${BREACH_WEB_DIR:-$ROOT_DIR/build/web}"
export BREACH_WEB_DIR
mkdir -p "$BREACH_WEB_DIR" build/logs
node scripts/sync_equipment_catalog.mjs
python3 scripts/subset_fonts.py
python3 scripts/update_asset_manifest.py
python3 scripts/validate_assets.py
"$ENGINE" --headless --path game --editor --import --quit 2>&1 | tee build/logs/import.log
if grep -Eq '^SCRIPT ERROR:|^ERROR:|Parse Error' build/logs/import.log; then
  echo 'Godot import failed; inspect build/logs/import.log.' >&2
  exit 1
fi
GODOT_BIN="$ENGINE" python3 scripts/validate_missions.py --report build/logs/mission-validation.json
"$ENGINE" --headless --path game --export-release Web "$BREACH_WEB_DIR/engine.html" 2>&1 | tee build/logs/export.log
if grep -Eq '^SCRIPT ERROR:|^ERROR:|Parse Error' build/logs/export.log; then
  echo 'Godot export failed; inspect build/logs/export.log.' >&2
  exit 1
fi
node scripts/build.mjs --sync-runtime
python3 scripts/package_web.py
printf '\nPlayable build: %s\n' "$BREACH_WEB_DIR"
