"""Remove unused GLB attributes with the existing pinned glTF Transform tool.

Run after build_historical_assets.py. Geometry, materials and cutaway node names
remain intact; no runtime decoder is required. --cli accepts a cached CLI.js.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path)
    args = parser.parse_args()
    command = ['node', str(args.cli)] if args.cli else ['npx', '--yes', '@gltf-transform/cli@4.3.0']
    directory = ROOT / 'game/assets/historical'
    registry = json.loads((directory / 'registry.json').read_text())
    report = []
    with tempfile.TemporaryDirectory(prefix='breach-historical-') as temporary:
        for asset_id, entry in registry.items():
            path = ROOT / entry['path'].replace('res://', 'game/')
            original = path.read_bytes()
            output = Path(temporary) / path.name
            subprocess.run(command + ['prune', str(path), str(output), '--keep-indices', 'true',
                                      '--keep-leaves', 'true', '--vertex-layout', 'separate'],
                           check=True, stdout=subprocess.DEVNULL)
            optimized = output.read_bytes()
            if len(optimized) < len(original):
                path.write_bytes(optimized)
            entry['bytes'] = path.stat().st_size
            entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
            report.append({'asset': asset_id, 'before_bytes': len(original), 'after_bytes': entry['bytes']})
    (directory / 'registry.json').write_text(json.dumps(registry, indent=2, ensure_ascii=False) + '\n')
    provenance_path = ROOT / 'licenses/provenance/SPECIAL_OPS_ASSET_PROVENANCE.json'
    provenance = json.loads(provenance_path.read_text())
    provenance['assets'] = registry
    provenance['optimization'] = 'glTF Transform 4.3.0 prune of unused attributes; geometry, PBR and cutaway nodes retained; no decoder dependency'
    provenance_path.write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
    report_path = ROOT / 'build/logs/historical-asset-optimization.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    before = sum(row['before_bytes'] for row in report)
    after = sum(row['after_bytes'] for row in report)
    print(f'Historical GLBs: {before:,} -> {after:,} bytes ({100 * (before - after) / before:.1f}% smaller)')


if __name__ == '__main__':
    main()
