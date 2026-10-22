"""Extract the CC0 Kenney door leaf, keeping authored handle and materials.
The top is cut away for the overhead camera; below the cut, proportions remain.
Run with Blender --background --python scripts/import_door_asset.py.
"""
import bpy,bmesh,json,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'.tools/asset-sources/doorway.glb'))
leaf=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name=='door')
# Bake local axes into Z-up world and normalize the existing door leaf.
points=[leaf.matrix_world @ v.co for v in leaf.data.vertices]
low=Vector(tuple(min(p[i] for p in points) for i in range(3)))
high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
size=high-low
for v,p in zip(leaf.data.vertices,points):
 v.co=Vector(((p.x-low.x)/size.x,(p.y-(low.y+high.y)*.5)/size.z*1.95,(p.z-low.z)/size.z*1.95))
leaf.parent=None;leaf.matrix_world.identity()
bm=bmesh.new();bm.from_mesh(leaf.data)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=0.00001,plane_co=(0,0,1.14),plane_no=(0,0,1),clear_outer=True,clear_inner=False)
bm.to_mesh(leaf.data);bm.free();leaf.data.update()
for obj in bpy.context.scene.objects:obj.select_set(obj==leaf)
bpy.context.view_layer.objects.active=leaf
out=ROOT/'game/assets/environment/doorLeaf.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False)
report={'source':'https://kenney.nl/assets/furniture-kit','archive_member':'Models/GLTF format/doorway.glb','license':'CC0-1.0','output':str(out.relative_to(ROOT)),'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'processing':'Extract original door leaf with handle/materials, normalize width1 and full height1.95; cut away above1.14 for overhead view. Runtime stretches width to map opening; no new geometry authored.'}
(ROOT/'licenses/provenance/door-provenance.json').write_text(json.dumps(report,indent=2)+'\n')
