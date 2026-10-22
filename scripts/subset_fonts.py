#!/usr/bin/env python3
"""Subset licensed fonts to runtime text while retaining supported user-input glyphs.

Three OFL families ship:
 - NotoSansKR: Korean + Latin body/UI text and existing user-input glyphs.
 - Oswald: condensed display face for logos, mode banners, result ranks.
 - JetBrainsMono: numerals, codes, clocks (tabular-nums).
Display and mono faces only need the Latin/digit/punctuation range used in
UI strings, not the Hangul corpus, so they get a smaller shared charset.
"""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def korean_corpus(root=ROOT):
 characters=set(chr(i) for i in range(32,256))
 characters.update(chr(i) for i in range(0x2000,0x2070))
 characters.update(chr(i) for i in range(0x2190,0x21A0))
 characters.update(chr(i) for i in range(0x3131,0x318F))
 characters.update('가나다라마바사아자차카타파하훈련완료주택진입표적대원선택이동방향대기신호민간인무력화계획실행일시정지재장전작전결과옵션')
 for folder in ('game/scripts','game/data','web'):
  for path in (root/folder).rglob('*'):
   if path.is_file() and path.suffix in ('.gd','.js','.html','.json','.css'):
    characters.update(path.read_text(errors='ignore'))
 # Existing subsets also support user-authored names; do not remove their glyphs.
 previous=root/'game/assets/fonts/NotoSansKR.ttf'
 if previous.is_file():
  try:
   from fontTools.ttLib import TTFont
   with TTFont(previous,lazy=True) as font:
    characters.update(chr(code) for code in font.getBestCmap())
  except ImportError:
   pass  # main() keeps the committed files when fonttools is unavailable.
 return characters

def latin_corpus():
 # Display/mono faces are only used for Latin headlines, mode banners,
 # mission codes and numerals -- no Hangul glyphs required.
 characters=set(chr(i) for i in range(32,256))
 characters.update(chr(i) for i in range(0x2000,0x2070))
 characters.update(chr(i) for i in range(0x2190,0x21A0))
 return characters

def build_static(source, ttf_out, woff_out, characters, axis_values, family_name=None):
 from fontTools import subset
 from fontTools.ttLib import TTFont
 from fontTools.varLib.instancer import instantiateVariableFont
 font=TTFont(source,recalcTimestamp=False)
 if 'fvar' in font and axis_values:
  font=instantiateVariableFont(font, axis_values)
 options=subset.Options()
 options.name_IDs=['*']; options.name_legacy=True; options.name_languages=['*']
 worker=subset.Subsetter(options=options)
 worker.populate(unicodes=sorted(ord(c) for c in characters))
 worker.subset(font)
 ttf_out.parent.mkdir(parents=True,exist_ok=True)
 woff_out.parent.mkdir(parents=True,exist_ok=True)
 font.save(ttf_out)
 font.flavor='woff2'; font.save(woff_out)
 return len(font.getGlyphOrder()), ttf_out.stat().st_size, woff_out.stat().st_size

def main():
 try:
  from fontTools import subset  # noqa: F401
  from fontTools.ttLib import TTFont  # noqa: F401
  import brotli  # noqa: F401
  have_tools=True
 except ImportError:
  have_tools=False

 jobs=[
  ('NotoSansKR', ROOT/'.tools/NotoSansKR-source.ttf', ROOT/'game/assets/fonts/NotoSansKR.ttf', ROOT/'web/assets/fonts/NotoSansKR.woff2', korean_corpus(), None),
  ('Oswald-700', ROOT/'.tools/Oswald-source.ttf', ROOT/'game/assets/fonts/Oswald-700.ttf', ROOT/'web/assets/fonts/Oswald-700.woff2', latin_corpus(), {'wght':700}),
  ('JetBrainsMono-500', ROOT/'.tools/JetBrainsMono-source.ttf', ROOT/'game/assets/fonts/JetBrainsMono-500.ttf', ROOT/'web/assets/fonts/JetBrainsMono-500.woff2', latin_corpus(), {'wght':500}),
 ]
 any_missing_source=False
 for name, source, ttf_out, woff_out, characters, axis_values in jobs:
  if not source.exists():
   if ttf_out.exists() and woff_out.exists():
    print(f'{name}: using committed subset (source not cached under .tools/).')
    continue
   any_missing_source=True
   print(f'{name}: source missing at {source} and no committed subset found.')
   continue
  if not have_tools:
   if ttf_out.exists() and woff_out.exists():
    print(f'{name}: using committed subset; install fonttools and brotli to regenerate.')
    continue
   raise SystemExit('Font generation requires: python3 -m pip install fonttools brotli')
  glyphs, ttf_bytes, woff_bytes = build_static(source, ttf_out, woff_out, characters, axis_values, name)
  print(f'{name}: {glyphs} glyphs; TTF {ttf_bytes:,} bytes; WOFF2 {woff_bytes:,} bytes')
 if any_missing_source:
  raise SystemExit('Some source fonts are missing. Run scripts/setup.sh --assets or place them under .tools/.')

if __name__=='__main__':
 main()
