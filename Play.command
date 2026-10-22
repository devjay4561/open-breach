#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -s dist/engine.wasm || ! -s dist/engine.pck || ! -f dist/index.html ]]; then
  npm run build
fi
python3 scripts/serve.py --open --reuse --find-port
