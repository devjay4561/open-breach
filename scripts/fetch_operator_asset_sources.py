"""Fetch the verified CC0 GLBs needed by the offline operator asset pipeline.
Uses the pinned URLs and expected original hashes in the adoption receipts.
Any upstream file change must be reviewed before the expected hash is changed.
"""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'.tools/asset-sources/operator-customization'
CACHE.mkdir(parents=True,exist_ok=True)
receipts=json.loads((ROOT/'licenses/provenance/model-source-receipts.json').read_text())['sources']
for source in receipts:
 target=CACHE/(source['key']+'.glb')
 if not target.exists():
  subprocess.run(['curl','--fail','--location','--silent','--show-error','--user-agent','Mozilla/5.0',source['download_url'],'--output',str(target)],check=True)
 actual=hashlib.sha256(target.read_bytes()).hexdigest()
 if actual!=source['original_sha256']:
  raise SystemExit(f"Upstream/cache hash differs for {source['key']}; expected {source['original_sha256']}, got {actual}. Review source and license before continuing.")
 print('Verified CC0 source:',source['key'])
