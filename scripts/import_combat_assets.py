"""Import selected CC0 combat assets from cached original archives."""
from pathlib import Path
from zipfile import ZipFile
import subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
cache=ROOT/'.tools/asset-sources'
with ZipFile(cache/'particles.zip') as archive:
 out=ROOT/'game/assets/vfx';out.mkdir(parents=True,exist_ok=True)
 for name in ['smoke_05.png','fire_01.png']:
  (out/name).write_bytes(archive.read('PNG (Transparent)/'+name))
 (ROOT/'licenses/Kenney-Particles.txt').write_bytes(archive.read('License.txt'))
subprocess.run([sys.executable,str(ROOT/'scripts/import_tactical_audio.py')],check=True)
print('Imported smoke, flash, four recorded rifle shots and three contact sounds')
