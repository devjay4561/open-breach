#!/usr/bin/env python3
"""Fetch official Godot 4.7.2 and only install its Web export templates."""
from pathlib import Path
from urllib.request import urlopen
import argparse, hashlib, os, platform, shutil, stat, zipfile
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'.tools'
VERSION='4.7.2-stable'
BASE=f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}'
FONT_REV='4efc2774c63917927efe769ca845def6bd6debae'
FONT_SHA='194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252'

def fetch(url,path):
 if path.is_file(): return
 print(f'Downloading {path.name} …',flush=True)
 temporary=path.with_suffix(path.suffix+'.download')
 with urlopen(url,timeout=60) as src, temporary.open('wb') as out:
  shutil.copyfileobj(src,out,2**20)
 temporary.replace(path)

def verify(path,expected,algorithm='sha512'):
 with path.open('rb') as data: actual=hashlib.file_digest(data,algorithm).hexdigest()
 if actual!=expected: raise SystemExit(f'Checksum mismatch for {path}; remove it and retry.')
 print(f'Verified {path.name}',flush=True)

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--assets',action='store_true',help='Also fetch the font source for regeneration')
 args=parser.parse_args()
 CACHE.mkdir(exist_ok=True)
 system=platform.system(); arch=platform.machine().lower()
 if system=='Darwin':
  archive='Godot_v4.7.2-stable_macos.universal.zip'
  binary=CACHE/'Godot.app/Contents/MacOS/Godot'
  templates=Path.home()/'Library/Application Support/Godot/export_templates/4.7.2.stable'
 elif system=='Linux':
  cpu='arm64' if arch in ('aarch64','arm64') else 'x86_64'
  archive=f'Godot_v4.7.2-stable_linux.{cpu}.zip'
  binary=CACHE/'godot'
  templates=Path(os.environ.get('XDG_DATA_HOME',str(Path.home()/'.local/share')))/'godot/export_templates/4.7.2.stable'
 else:
  raise SystemExit('Use the Godot 4.7.2 editor and Web export templates installer on Windows.')
 checksum_path=CACHE/'SHA512-SUMS.txt'
 fetch(BASE+'/SHA512-SUMS.txt',checksum_path)
 checks={line.split()[1]:line.split()[0] for line in checksum_path.read_text().splitlines() if line.strip()}
 if not binary.exists():
  editor_zip=CACHE/'godot.zip'
  fetch(BASE+'/'+archive,editor_zip); verify(editor_zip,checks[archive])
  with zipfile.ZipFile(editor_zip) as z:
   if system=='Darwin':
    z.extractall(CACHE)
   else:
    name=next(n for n in z.namelist() if not n.endswith('/'))
    binary.write_bytes(z.read(name))
  binary.chmod(binary.stat().st_mode|stat.S_IXUSR|stat.S_IXGRP|stat.S_IXOTH)
 if not (templates/'web_nothreads_release.zip').is_file():
  name='Godot_v4.7.2-stable_export_templates.tpz'
  archive_path=CACHE/'export_templates.tpz'
  fetch(BASE+'/'+name,archive_path); verify(archive_path,checks[name])
  templates.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(archive_path) as z:
   for member in z.namelist():
    basename=Path(member).name
    if basename.startswith('web_') or basename=='version.txt':
     (templates/basename).write_bytes(z.read(member))
 if args.assets:
  font=CACHE/'NotoSansKR-source.ttf'
  fetch(f'https://raw.githubusercontent.com/google/fonts/{FONT_REV}/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf',font)
  verify(font,FONT_SHA,'sha256')
 print(f'Godot: {binary}\nWeb templates: {templates}\nReady: ./scripts/build.sh',flush=True)

if __name__=='__main__': main()
