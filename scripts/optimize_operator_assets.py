"""Prune and deduplicate GLBs without runtime compression or animation changes.
Uses pinned glTF Transform CLI. Run after import_operator_assets.py.
"""
from pathlib import Path
import subprocess,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
for path in sorted((ROOT/'game/assets/equipment').glob('*.glb')):
 temporary=path.with_name(path.stem+'-optimized.glb')
 subprocess.run(['npx','--yes','@gltf-transform/cli@4.3.0','dedup',str(path),str(temporary)],check=True,stdout=subprocess.DEVNULL)
 subprocess.run(['npx','--yes','@gltf-transform/cli@4.3.0','prune',str(temporary),str(path)],check=True,stdout=subprocess.DEVNULL)
 temporary.unlink()
report=ROOT/'licenses/provenance/imported-geometry.json'
data=json.loads(report.read_text())
for a in data['assets']:
 path=ROOT/a['path'];a['bytes']=path.stat().st_size;a['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
data['optimization']='glTF Transform 4.3.0 dedup + prune; no Draco/Meshopt/KTX2 decoder dependency'
report.write_text(json.dumps(data,indent=2)+'\n')
print('Optimized',len(data['assets'])-1,'static equipment GLBs')
