"""Normalize selected CC0 models and author equipment overlays, offline in Blender.
Run: blender -b --factory-startup --python scripts/import_operator_assets.py
Cached original GLBs and source-page evidence live under .tools/asset-sources/operator-customization.
No commercial game's assets or branded markings are used.
"""
import bpy, bmesh, json, math, hashlib, os
from pathlib import Path
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'.tools/asset-sources/operator-customization'
OUT=ROOT/'game/assets/equipment';OUT.mkdir(parents=True,exist_ok=True)
report={'schema_version':1,'processed_at':'2026-10-11','assets':[],'source_head_center':[]}
def reset():bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 n=m.node_tree.nodes.get('Principled BSDF');n.inputs['Base Color'].default_value=(*color,1);n.inputs['Roughness'].default_value=.88
 return m
def box(name,location,dimensions,material,bevel=.008):
 bpy.ops.mesh.primitive_cube_add(size=1,location=location);o=bpy.context.object;o.name=name;o.scale=dimensions
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Soft plate edges','BEVEL');mod.width=bevel;mod.segments=1
  bpy.ops.object.modifier_apply(modifier=mod.name)
 o.data.materials.append(material);return o
def cylinder(name,location,radius,depth,material,axis='X'):
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=radius,depth=depth,location=location)
 o=bpy.context.object;o.name=name
 o.rotation_euler.y=math.pi/2 if axis=='X' else 0
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 o.data.materials.append(material);return o
def export(name,objects=None):
 if objects is None:objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 # Every static equipment piece follows one bone. Fuse components into one
 # normalized mesh so plate pouches/straps do not each require a draw call.
 bpy.context.view_layer.objects.active=objects[0]
 if len(objects)>1:
  bpy.ops.object.join();objects=[bpy.context.object]
 for o in objects:
  world=o.matrix_world.copy()
  for vertex in o.data.vertices:vertex.co=world@vertex.co
  o.matrix_world=Matrix.Identity(4)
 path=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False)
 triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH')
 report['assets'].append({'id':name,'path':str(path.relative_to(ROOT)),'triangles':triangles,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 return path
gear_only = os.environ.get('CQB_OPERATOR_GEAR_ONLY') == '1'
if gear_only:
 report = json.loads((ROOT/'licenses/provenance/imported-geometry.json').read_text())
 report['assets'] = [entry for entry in report['assets'] if entry['id'] != 'combat-swat-gear']
else:
 # Preserve the creators' unbranded low-poly silhouettes, normalize meters/pivot/axis.
 for source,name,length in [('rifle','tern_c1',.86),('smg','mica_s2',.62),('shotgun','flint_b1',1.02),('pistol','pico_p1',.23)]:
  reset();bpy.ops.import_scene.gltf(filepath=str(CACHE/(source+'.glb')))
  objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
  vs=[o.matrix_world@v.co for o in objects for v in o.data.vertices];lo=min(v.x for v in vs);hi=max(v.x for v in vs);scale=length/(hi-lo)
  for o in objects:
   world=o.matrix_world.copy()
   for v in o.data.vertices:v.co=(world@v.co)*scale
   o.matrix_world=Matrix.Identity(4);o.name=name
   for m in o.data.materials:
    if m and m.use_nodes:m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.9
  # Barrel socket follows the foremost ring of the original model, not a guessed offset.
  front=[v*scale for v in vs if v.x>hi-(hi-lo)*.004]
  muzzle=sum(front,Vector())/len(front)
  report['assets'] # retain normalized geometry bounds and original creator source
  path=export(name,objects)
  report['assets'][-1].update({'source':source,'length':length,'muzzle':[muzzle.x,muzzle.z,-muzzle.y], 'grip':[0,0,0]})
 # Detachable head unit is derived from the original SWAT CC0 helmet/mask geometry.
 reset();bpy.ops.import_scene.gltf(filepath=str(CACHE/'swat.glb'))
 arm=next(o for o in bpy.data.objects if o.type=='ARMATURE');arm.animation_data_clear()
 for b in arm.pose.bones:b.matrix_basis=Matrix.Identity(4)
 bpy.context.view_layer.update()
 head=bpy.data.objects['Swat_Head'];center=arm.matrix_world@arm.data.bones['Head'].head_local
 report['source_head_center']=[center.x,center.z,-center.y]
 verts=[head.matrix_world@v.co-center for v in head.data.vertices]
 faces=[list(p.vertices) for p in head.data.polygons]
 material_ids=[p.material_index for p in head.data.polygons]
 materials=list(head.data.materials)
 material_names=[m.name for m in materials]
 for name,heavy in [('crown_h1',False),('crown_h2',True)]:
  bpy.ops.object.select_all(action='DESELECT')
  mesh=bpy.data.meshes.new(name);mesh.from_pydata([list(v) for v in verts],[],faces);mesh.update()
  o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
  for m in materials:mesh.materials.append(m)
  for p,idx in zip(mesh.polygons,material_ids):p.material_index=idx
  bpy.context.view_layer.objects.active=o;o.select_set(True)
  modifier=o.modifiers.new('Web helmet budget','DECIMATE');modifier.ratio=.72
  bpy.ops.object.modifier_apply(modifier=modifier.name)
  objs=[o]
  if heavy:
   dark=mat('Heavy helmet guard',(.16,.18,.17))
   # Distinct side and rear coverage, with the original goggles still visible.
   objs += [box('Left side guard',(-.12,.04,-.005),(.035,.14,.12),dark),box('Right side guard',(.12,.04,-.005),(.035,.14,.12),dark),box('Rear guard',(0,.115,-.035),(.22,.035,.12),dark)]
  export(name,objs)
  for a in list(bpy.context.selected_objects):bpy.data.objects.remove(a,do_unlink=True)
 # A cloth mask/goggles unit lets an explicit no-helmet profile show an actual
 # unarmored head. Face details derive from the same CC0 source; skull is original.
 reset();dark=mat('Cloth mask',(.12,.14,.13));skin=mat('Unarmored head',(.52,.43,.34))
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,location=(0,-.025,.065))
 skull=bpy.context.object;skull.name='Unarmored head';skull.scale=(.10,.105,.135);skull.data.materials.append(skin)
 selected=[];selected_material=[]
 for face,idx in zip(faces,material_ids):
  center=sum((verts[i] for i in face),Vector())/len(face)
  if center.z<.08 and ('black' in material_names[idx].lower() or 'visor' in material_names[idx].lower()):
   selected.append(face);selected_material.append(idx)
 mesh=bpy.data.meshes.new('Original goggles and mask');mesh.from_pydata([list(v) for v in verts],[],selected);mesh.update()
 mask=bpy.data.objects.new('Cloth mask and goggles',mesh);bpy.context.collection.objects.link(mask)
 for i in range(3):mesh.materials.append(dark)
 export('mask_h0',[skull,mask])
 # Original armor overlays fit the original CC0 SWAT torso; detachable and unbranded.
 # Blender native Z is vertical; local origin is measured chest level in runtime.
 for name,color,width,height,sideguard in [('veil_v1',(.18,.25,.22),.37,.31,False),('frame_v2',(.20,.23,.22),.42,.38,True),('swift_v3',(.46,.41,.29),.36,.33,False),('bastion_v4',(.25,.29,.22),.47,.44,True)]:
  reset();cloth=mat('Carrier fabric',color);plate=mat('Plate panels',tuple(x*.72 for x in color));strap=mat('Webbing',(.11,.13,.12))
  # forward is -Y in Blender, matching the original source actor.
  for y,label in [(-.18,'Front'),(.09,'Back')]:
   box(label+' armor panel',(0,y,0),(width,.050,height),plate,.014)
   for x in [-width*.29,width*.29]:box(label+' shoulder strap',(x,y,height*.45),(.045,.062,.20),strap,.006)
  if sideguard:
   for x in [-width*.5,width*.5]:box('Side armor panel',(x,-.045,-.005),(.045,.28,height*.72),cloth,.01)
  for x in [-.10,0,.10]:box('Magazine pouch',(x,-.221,-.04),(.083,.06,.15),cloth,.005)
  if name=='bastion_v4':
   box('Lower abdomen panel',(0,-.173,-.26),(.31,.045,.16),plate,.013)
   for x in [-.22,.22]:box('Shoulder guard',(x,-.01,.20),(.15,.24,.07),plate,.01)
  export(name)
 # Original tiny attachment/tool geometry uses no third-party logos or textures.
 for name in ['dot','scope','suppressor','extended_mag','probe_c1','flare_f1','haze_s1','knock_b1']:
  reset();dark=mat('Matte equipment',(.12,.15,.16));light=mat('Equipment accent',(.35,.42,.40));lens=mat('Lens',(.15,.44,.53))
  if name=='dot':
   box('Sight rail',(0,0,.018),(.07,.055,.024),dark,.003)
   box('Sight frame',(0,0,.05),(.028,.055,.05),light,.003)
   box('Sight glass',(.016,0,.05),(.004,.037,.030),lens,.001)
  elif name=='scope':
   cylinder('Scope body',(0,0,.032),.028,.17,dark)
   cylinder('Objective lens',(.088,0,.032),.023,.008,lens)
   box('Scope mount',(0,0,0),(.10,.040,.025),light,.002)
  elif name=='suppressor':
   cylinder('Suppressor',(.10,0,0),.024,.20,dark)
   cylinder('Muzzle rim',(.199,0,0),.026,.012,light)
  elif name=='extended_mag':box('Extended magazine',(0,0,-.045),(.06,.036,.15),dark,.006)
  elif name=='probe_c1':
   box('Camera handset',(0,0,0),(.085,.035,.13),dark,.006)
   box('Observation screen',(0,-.021,.012),(.060,.005,.076),lens,.002)
   cylinder('Camera stem',(0,0,.15),.005,.17,light,axis='Z')
   cylinder('Camera head',(.014,0,.235),.013,.03,dark)
  elif name in ['flare_f1','haze_s1']:
   cylinder('Grenade body',(0,0,0),.035,.11,dark if name=='flare_f1' else light,axis='Z')
   box('Safety lever',(.024,0,.045),(.015,.018,.073),light,.002)
  else:box('Entry charge',(0,0,0),(.11,.05,.17),dark,.01)
  export(name)
# CC0 combat animation mesh becomes gear-ready by removing its
# head unit. Skeleton, all skin weights, and imported authored clips survive.
reset();bpy.context.scene.render.fps=30
bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/characters/combat-swat.glb'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
body=next(o for o in bpy.data.objects if o.type=='MESH' and len(o.vertex_groups)>0)
head_group=body.vertex_groups.get('Head')
remove={v.index for v in body.data.vertices if any(g.group==head_group.index and g.weight>.99 for g in v.groups)}
bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table();bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.index in remove],context='VERTS');bm.to_mesh(body.data);bm.free()
# No extra meshes or original archive are shipped.
bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);body.select_set(True)
path=ROOT/'game/assets/characters/combat-swat-gear.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_merge_animation='ACTION',export_force_sampling=True,export_frame_range=False,export_optimize_animation_size=True,export_skins=True,export_all_influences=False,export_def_bones=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
report['assets'].append({'id':'combat-swat-gear','path':str(path.relative_to(ROOT)),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'removed_head_vertices':len(remove),'animation_count':len(bpy.data.actions)})
(ROOT/'licenses/provenance/imported-geometry.json').write_text(json.dumps(report,indent=2)+'\n')
print('OPERATOR_ASSETS_READY',len(report['assets']))
