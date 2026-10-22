"""Refresh source/output hashes and actual GLB inventory after combat asset import."""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / 'licenses/provenance/COMBAT_ASSET_INVENTORY.json'
report = json.loads(REPORT.read_text())
motion = json.loads((ROOT / '.tools/asset-sources/cc0-swat-motion-inventory.json').read_text())
report['sources'] = [entry for entry in report['sources'] if entry['asset'] in ['SWAT model, death animation', 'Assault Rifle']]
report['sources'] += [
    {'asset': 'SWAT motion and original pose adaptations', 'author': 'Quaternius',
     'license': 'CC0-1.0', 'url': 'https://quaternius.com/packs/toonshootergamekit.html'},
    {'asset': 'Throw motion', 'author': 'Kay Lousberg',
     'license': 'CC0-1.0', 'url': 'https://kaylousberg.itch.io/kaykit-character-animations'},
]
paths = sorted({entry['source_file'] for entry in motion.values()}) + [
    'game/assets/characters/swat.glb', 'game/assets/characters/rifle.glb',
    'game/assets/characters/combat-swat.glb', 'game/assets/characters/combat-swat-gear.glb',
    'game/assets/characters/combat-swat.glb.import',
]
report['files'] = [{'path': path} for path in paths]
for entry in report['files']:
    data = (ROOT / entry['path']).read_bytes()
    entry.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
data = (ROOT / 'game/assets/characters/combat-swat.glb').read_bytes()
size = struct.unpack_from('<I', data, 12)[0]
gltf = json.loads(data[20:20 + size])
report.update(
    triangles=sum(gltf['accessors'][part['indices']]['count'] // 3
                  for mesh in gltf['meshes'] for part in mesh['primitives']),
    materials=len(gltf['materials']), meshes=len(gltf['meshes']),
    material_surfaces=sum(len(mesh['primitives']) for mesh in gltf['meshes']),
    skin_joints=len(gltf['skins'][0]['joints']),
    clips=[{'name': clip['name'], 'seconds': max(gltf['accessors'][sampler['input']]['max'][0]
             for sampler in clip['samplers'])} for clip in gltf['animations']],
)
report['motion'] = motion
report['adaptations'] = ['Direct CC0 Toon Shooter poses with shared rifle upper-body layering.', 'KayKit torso and arm rest-space rotation retarget; source-free original support-hand IK and turn shuffles.', 'Planar Root/Body motion removed; vertical bob retained.', 'Joined skinned meshes with original weights and four materials.']
report['reproduce'] = 'blender -b --factory-startup --python scripts/build_cc0_swat_motion.py'
report['source_distribution'] = 'All embedded animation sources are CC0-1.0; original pose adaptations are authored in the build script.'
report['validation'] = {'regression_script': 'game/tests/combat_asset_inspect.gd', 'preview_script': 'game/tests/cc0_motion_preview.gd', 'throw_release_normalized_phase': 0.58}
REPORT.write_text(json.dumps(report, indent=2) + '\n')
print(f"Combat GLB: {report['triangles']} triangles, {report['meshes']} mesh, "
      f"{report['material_surfaces']} surfaces, {report['skin_joints']} bones, {len(report['clips'])} clips")
