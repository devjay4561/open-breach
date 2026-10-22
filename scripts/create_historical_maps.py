#!/usr/bin/env python3
"""Generate the curated active special operation environments from authored specs."""
from pathlib import Path
import json
from mission_authoring import preserve_enemy_strengths
from historical_maps.rescue import build_maps as rescue
from historical_maps.modern import build_maps as modern
from historical_maps.historical import build_maps as historical
from historical_maps.compact import compact
from historical_maps.dossiers import fictionalize

ROOT=Path(__file__).resolve().parents[1]

def main():
    expected=json.loads((ROOT/'game/data/historical_roster.json').read_text())['active_ids']
    maps=[m for m in [*rescue(),*modern(),*historical()] if m['id'] in expected]
    registry=json.loads((ROOT/'game/assets/historical/registry.json').read_text())
    maps=[fictionalize(compact(m,registry)) for m in maps]
    ids=[m['id'] for m in maps]
    if sorted(ids)!=expected:raise ValueError(f'Expected curated operations, got {ids}')
    directory=ROOT/'game/data/historical';directory.mkdir(parents=True,exist_ok=True)
    for path in directory.glob('H*.json'):
        if path.stem not in expected: path.unlink()
    for data in maps:
        preserve_enemy_strengths(data, (directory/f'{data["id"]}.json'))
        (directory/f'{data["id"]}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(f'Generated {len(maps)} metre-scale special operations in {directory}')

if __name__=='__main__':main()
