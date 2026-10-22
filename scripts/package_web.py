#!/usr/bin/env python3
"""Package the web shell, local assets, legal notices and compressed sidecars."""
from pathlib import Path
import argparse,gzip,shutil,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
try:
 import brotli
except ImportError:
 brotli=None

def package(destination,root=ROOT):
 destination=Path(destination).resolve()
 # The browser snapshot and Godot use the same authoritative equipment data.
 # Packaging must not silently ship a stale browser copy after engine export.
 if (root/'game/data/equipment_catalog.json').is_file():
  generated=subprocess.run(['node',str(root/'scripts/sync_equipment_catalog.mjs'),'--check'],cwd=root,capture_output=True,text=True)
  if generated.returncode: raise SystemExit(generated.stderr.strip() or generated.stdout.strip() or 'Equipment catalog is stale; rebuild before packaging.')
 required=['engine.js','engine.wasm','engine.pck']
 missing=[name for name in required if not (destination/name).is_file()]
 if missing: raise SystemExit('Export the Godot Web target before packaging: '+', '.join(missing))
 for source in (root/'web').rglob('*'):
  relative=source.relative_to(root/'web')
  if source.is_file() and not any(part.startswith('.') for part in relative.parts):
   target=destination/relative
   target.parent.mkdir(parents=True,exist_ok=True)
   shutil.copy2(source,target)
 shutil.copytree(root/'licenses',destination/'licenses',dirs_exist_ok=True)
 for notice in ['LICENSE','ASSETS-LICENSE.md']:
  shutil.copy2(root/notice,destination/notice)
 shutil.copy2(root/'asset-manifest.json',destination/'asset-manifest.json')
 (destination/'.nojekyll').touch()
 compressed=0
 for source in destination.rglob('*'):
  if source.is_file() and source.suffix in {'.wasm','.pck','.js','.css','.json','.html','.ttf','.wav','.txt'}:
   sidecar=source.with_name(source.name+'.gz')
   sidecar.write_bytes(gzip.compress(source.read_bytes(),compresslevel=9,mtime=0))
   os.utime(sidecar,(source.stat().st_atime,source.stat().st_mtime))
   compressed+=sidecar.stat().st_size
   if brotli:
    sidecar=source.with_name(source.name+'.br')
    sidecar.write_bytes(brotli.compress(source.read_bytes(),quality=11))
    os.utime(sidecar,(source.stat().st_atime,source.stat().st_mtime))
   else:
    source.with_name(source.name+'.br').unlink(missing_ok=True)
 missing=[name for name in ['index.html','app.js','style.css'] if not (destination/name).is_file()]
 if missing: raise SystemExit('Missing web build files: '+', '.join(missing))
 return compressed

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--directory',type=Path,default=Path(os.environ.get('BREACH_WEB_DIR',str(ROOT/'build/web'))))
 args=parser.parse_args()
 compressed=package(args.directory)
 print(f'Web package ready: {args.directory}; gzip sidecars {compressed/1024/1024:.2f} MiB; Brotli {"enabled" if brotli else "unavailable (gzip fallback)"}.')

if __name__=='__main__': main()
