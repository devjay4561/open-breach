"""Build metre-authored special operations props and normalize selected CC0 nature assets.

Run: Blender --background --python scripts/build_historical_assets.py
Optional: -- --only tanker_ship_hull,helicopter_naval --preview
Blender is Z-up; glTF export converts to Godot Y-up. Forward remains +X.
These are readable game reconstruction meshes, not verified engineering CAD.
Known outer dimensions are preserved; interiors/structural details are reconstructions.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/historical'
SOURCE = ROOT / 'assets/source/historical'
BLENDS = SOURCE / 'blender'
PREVIEWS = OUT / 'previews'
for folder in [OUT, BLENDS, PREVIEWS]:
    folder.mkdir(parents=True, exist_ok=True)

args = argparse.ArgumentParser()
args.add_argument('--only', default='')
args.add_argument('--preview', action='store_true')
args.add_argument('--preview-only', action='store_true')
OPTIONS = args.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
ONLY = set(OPTIONS.only.split(',')) if OPTIONS.only else {item['asset'] for path in (ROOT/'game/data/historical').glob('H*.json') for item in json.loads(path.read_text()).get('scenery',[])}
REGISTRY = json.loads((OUT / 'registry.json').read_text()) if (OUT / 'registry.json').exists() else {}
GENERATED = []
MATS = {}

COLORS = {
    'steel': ((.19, .24, .26, 1), .75, .45),
    'silver': ((.47, .53, .56, 1), .82, .32),
    'white': ((.79, .81, .77, 1), .1, .65),
    'ivory': ((.69, .67, .56, 1), .0, .8),
    'olive': ((.20, .25, .14, 1), .18, .76),
    'black': ((.024, .032, .037, 1), .1, .78),
    'glass': ((.08, .25, .31, 1), .45, .17),
    'deck': ((.13, .32, .22, 1), .2, .74),
    'red': ((.55, .12, .07, 1), .3, .68),
    'orange': ((.78, .26, .045, 1), .2, .54),
    'wood': ((.39, .26, .14, 1), 0, .87),
    'thatch': ((.52, .43, .23, 1), 0, .91),
    'concrete': ((.49, .48, .43, 1), 0, .91),
    'sandstone': ((.57, .49, .36, 1), 0, .89),
    'gold': ((.70, .47, .12, 1), .74, .42),
    'brick': ((.39, .22, .16, 1), 0, .91),
}


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj,do_unlink=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1.0


def mat(key):
    if key not in MATS:
        color, metal, rough = COLORS[key]
        m = bpy.data.materials.new('Historical_' + key)
        m.diffuse_color = color
        m.use_nodes = True
        bs = m.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Base Color'].default_value = color
        bs.inputs['Metallic'].default_value = metal
        bs.inputs['Roughness'].default_value = rough
        MATS[key] = m
    return MATS[key]


def material(obj, key):
    obj.data.materials.append(mat(key))
    return obj


def box(name, xyz, size, key='steel', bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    material(obj, key)
    if bevel:
        mod = obj.modifiers.new('small edge bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def mesh(name, verts, faces, key='steel'):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return material(obj, key)


def cylinder(name, xyz, radius, depth, key='steel', rotation=None, vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=xyz)
    obj = bpy.context.object
    obj.name = name
    if rotation:
        obj.rotation_euler = rotation
    material(obj, key)
    return obj


def sphere(name, xyz, size, key='steel', seg=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=xyz)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for p in obj.data.polygons:
        p.use_smooth = True
    return material(obj, key)


def beam(name, a, b, radius=.06, key='steel'):
    a, b = Vector(a), Vector(b)
    obj = cylinder(name, (a+b)*.5, radius, (b-a).length, key, vertices=8)
    obj.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return obj


def loft(name, sections, key='steel', segments=20, open_top=False):
    """Sections (x, half width, half height, centre z), closed ellipsoid rings."""
    verts = []
    for x, w, h, z in sections:
        for j in range(segments):
            angle = j*2*math.pi/segments
            verts.append((x, w*math.sin(angle), z+h*math.cos(angle)))
    faces = []
    for i in range(len(sections)-1):
        for j in range(segments):
            if open_top and (j <= 3 or j >= segments-3):
                continue
            faces.append((i*segments+j, i*segments+(j+1)%segments,
                          (i+1)*segments+(j+1)%segments, (i+1)*segments+j))
    faces += [tuple(range(segments-1, -1, -1)), tuple((len(sections)-1)*segments+j for j in range(segments))]
    obj = mesh(name, verts, faces, key)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def polygon_prism(name, points, bottom, top, key):
    n = len(points)
    v = [(x,y,bottom) for x,y in points] + [(x,y,top) for x,y in points]
    faces = [tuple(range(n-1,-1,-1)), tuple(range(n,2*n))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    return mesh(name, v, faces, key)


def bounds():
    bpy.context.view_layer.update()
    # Transformed local AABB corners overestimate angled long cylinders. Vertex
    # bounds are exact and prevent spurious grounding/scale changes to ladders.
    pts = [o.matrix_world @ vertex.co for o in bpy.context.scene.objects if o.type=='MESH' for vertex in o.data.vertices]
    lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    return lo, hi


def ground():
    lo, hi = bounds()
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            obj.location.z -= lo.z


def authored_envelope(length=None, width=None, height=None):
    """Bake metre targets at authoring time, never resize models at runtime."""
    bpy.context.view_layer.update()
    lo,hi=bounds();dims=hi-lo
    targets=[length,width,height]
    factors=[targets[i]/dims[i] if targets[i] else 1 for i in range(3)]
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        for v in obj.data.vertices:
            p=obj.matrix_world @ v.co
            v.co=Vector(((p.x-(lo.x+hi.x)*.5)*factors[0],(p.y-(lo.y+hi.y)*.5)*factors[1],(p.z-lo.z)*factors[2] if height else p.z))
        obj.parent=None;obj.matrix_world.identity()


def preview(asset):
    lo, hi = bounds()
    center = (lo+hi)*.5
    size = max(hi.x-lo.x, hi.y-lo.y, hi.z-lo.z)
    bpy.ops.object.camera_add(location=center+Vector((size*.73, -size*.90, size*.70)))
    camera=bpy.context.object
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'
    camera.data.ortho_scale=size*1.35
    bpy.context.scene.camera=camera
    bpy.ops.object.light_add(type='AREA', location=center+Vector((size*.3,-size*.4,size*1.3)))
    light=bpy.context.object
    light.data.energy=65*max(size,1)**2
    light.data.shape='DISK';light.data.size=max(size*.7,2)
    light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=20
    scene.world.color=(.12,.14,.16)
    scene.render.resolution_x=720;scene.render.resolution_y=520;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(PREVIEWS / (asset+'.png'))
    bpy.ops.render.render(write_still=True)


def save(asset, title, source_url='', verified=None, note='', floor_offset=.2, license='CC0-1.0', original_source=None):
    # Shared materials become one surface per material instead of hundreds of
    # independent draw calls. Retain only meaningful cutaway node groups.
    bpy.context.view_layer.update()
    groups={'VisibleGeometry':[], 'Roof_Cutaway':[], 'UpperShell_Cutaway':[], 'CabinSeats_Cutaway':[]}
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        group='CabinSeats_Cutaway' if obj.name.startswith('CabinSeat') else ('Roof_Cutaway' if obj.name.startswith('Roof_') else ('UpperShell_Cutaway' if obj.name.startswith('UpperShell_') else 'VisibleGeometry'))
        groups[group].append(obj)
    for name,objects in groups.items():
        if not objects:continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        if len(objects)>1:bpy.ops.object.join()
        objects[0].name=name
        # The chosen active mesh may have an angled cylinder transform. Bake it
        # so the exported root and its exact world-space AABB are identity.
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bpy.context.view_layer.update()
    lo, hi = bounds()
    scene=bpy.context.scene
    scene['human_reference_height_m']=1.78
    scene['forward']='+X'
    scene['historical_accuracy']='published outer dimensions where cited; reconstructed geometry, not as-built CAD'
    scene['asset_id']=asset
    path=OUT/(asset+'.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(BLENDS/(asset+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_animations=False,
                              export_yup=True, export_apply=True, export_extras=True,
                              export_texcoords=any(node.type == 'TEX_IMAGE' for m in bpy.data.materials
                                                   if m.use_nodes for node in m.node_tree.nodes))
    triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
    dims=[round(hi.x-lo.x,5),round(hi.z-lo.z,5),round(hi.y-lo.y,5)]
    title=asset.replace('_',' ').title()
    if not original_source:
        source_url=''
        note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.'
    entry={'path':'res://assets/historical/'+asset+'.glb','title':title,'dimensions_m':dims,'forward':'+X',
           'up':'+Y','origin':'horizontal centre, floor Y=0 except tanker hull with deck Y=0.2',
           'floor_offset':floor_offset,'license':license,'source_url':source_url,
           'verified_dimensions_m':verified or {},'accuracy_note':note,
           'source_blend':str((BLENDS/(asset+'.blend')).relative_to(ROOT)),
           'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'triangles':triangles,
           'bytes':path.stat().st_size,'author':'Kenney (adapted)' if original_source else 'CQB project / procedural Blender authoring'}
    if not original_source:
        entry.pop('source_url',None)
        entry['reference_note']='Public dimension or visual reference data informed proportions only; no source geometry copied. Interiors, contours and unmeasured details are design assumptions.'
    if original_source:
        entry['original_source']=original_source
        entry['processing']='Imported genuine CC0 GLB; baked world transforms; one uniform scale; centred and grounded. Original materials preserved.'
    REGISTRY[asset]=entry
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')
    GENERATED.append(asset)
    if OPTIONS.preview:
        preview(asset)
    print('HISTORICAL_ASSET',asset,json.dumps(dims),triangles,flush=True)


def nature(asset, source, target, axis):
    reset()
    bpy.ops.import_scene.gltf(filepath=str(SOURCE/'kenney'/(source+'.glb')))
    bpy.context.view_layer.update()
    lo,hi=bounds()
    scale=target/(hi[axis]-lo[axis])
    centre=(lo+hi)*.5
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        for vertex in obj.data.vertices:
            p=obj.matrix_world @ vertex.co
            vertex.co=(p-Vector((centre.x,centre.y,lo.z)))*scale
        obj.parent=None;obj.matrix_world.identity()
    save(asset,asset.replace('_',' '),'https://kenney.nl/assets/nature-kit',
         note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.',
         license='CC0-1.0',original_source={'archive':'assets/source/historical/kenney_nature-kit.zip',
         'archive_member':'Models/GLTF format/'+source+'.glb','author':'Kenney'})


def tanker():
    reset();L=145.5;W=23.7
    # Aft transom to flared bow. Deck top intentionally matches playable plane.
    outline=[(-L/2,-W*.46),(-L*.40,-W/2),(L*.30,-W/2),(L*.43,-W*.32),(L/2,0),
             (L*.43,W*.32),(L*.30,W/2),(-L*.40,W/2),(-L/2,W*.46)]
    n=len(outline)
    verts=[(x,y,.2) for x,y in outline]+[(x*.96,y*.75,-13.15) for x,y in outline]
    faces=[tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh('Tanker_FlaredHull',verts,faces,'red')
    polygon_prism('Tanker_WalkableDeck',outline,.05,.2,'deck')
    # Vertical hull stripes and fittings sit on sides, not over the walkable deck.
    for i in range(n):
        a=outline[i];b=outline[(i+1)%n]
        beam('BulwarkCap',(a[0],a[1],.29),(b[0],b[1],.29),.09,'white')
    for x in [-64,-45,-25,-5,15,35,49]:
        for y in [-11.4,11.4]:
            cylinder('MooringBollard',(x,y,.49),.20,.56,'black')
    # Rails are absent around entry openings; 1.05 m human waist-level safety rail.
    for side in [-1,1]:
        for x in range(-64,44,6):
            beam('RailPost',(x,side*11.4,.2),(x,side*11.4,1.25),.035,'white')
        beam('RailTop',(-64,side*11.4,1.25),(43,side*11.4,1.25),.035,'white')
    authored_envelope(L,W)
    save('tanker_ship_hull','Original procedural special operations prop',
         '',
         {'length':145.5,'beam':23.7,'moulded_depth':13.35,'loaded_draft':9.7},
         'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.',floor_offset=0)
    REGISTRY['tanker_ship_hull']['waterline_reference_m']={'deck':.2,'keel':-13.15,'water':-3.45,
        'draft_design':9.7,'period_report_draft':9.715,
        'note':'Waterline is a nominal loaded visualization; loading at the operation is not verified.'}
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')


def tanker_superstructure():
    reset();l=24;w=20.5;h=11.8
    # Four-deck aft accommodation exterior; open roof and open bow-facing wall.
    for y in [-w/2,w/2]:
        box('Facade_Side',(-2,y,h/2),(l,.22,h),'white',.08)
        for z in [2.2,5.1,8.0,10.6]:
            for x in range(-11,9,3):
                box('Facade_Porthole',(x,y*1.012,z),(1.1,.06,.7),'glass',.04)
    box('Facade_Aft',(-14,0,h/2),(.24,w,h),'white',.06)
    for z in [2.2,5.1,8,10.6]:
        for y in [-7,-3.5,0,3.5,7]:
            box('Facade_AftWindow',(-14.15,y,z),(.05,1.3,.8),'glass',.03)
    # Elevated bridge has glazing ribbons, no opaque horizontal roof.
    for y in [-w/2,w/2]:
        box('Facade_BridgeWindow',(5.5,y*1.014,10.5),(7.2,.05,1.2),'glass')
    box('Cutaway_GroundRear',(-10,0,.55),(.18,14,1.1),'white')
    for y in [-6,0,6]:
        box('Cutaway_CabinWall',(-5,y,.55),(8,.15,1.1),'white')
    cylinder('Funnel',(-6,0,13.0),1.15,3.8,'black',vertices=12)
    cylinder('Mast',(-.5,1,14.5),.10,6.5,'white')
    beam('MastCross',(-.5,-2.0,16.5),(-.5,4,16.5),.08,'white')
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH' and not obj.name.startswith('Cutaway_'):
            obj.name='UpperShell_'+obj.name
    save('tanker_superstructure','Original procedural special operations prop',
         '',
         note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')
    REGISTRY['tanker_superstructure']['cutaway_hide_meshes']=['UpperShell_Cutaway']
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')


def tanker_pipes():
    reset()
    for y in [-3.8,-2.4,2.4,3.8]:
        cylinder('CargoLongitudinalPipe',(0,y,.72),.14,86,'silver',(0,math.pi/2,0))
    for x in [-35,-20,-5,10,25,35]:
        for y in [-5.5,5.5]:
            cylinder('CargoTankHatch',(x,y,.35),.77,.40,'silver')
            cylinder('CargoHatchValve',(x,y,.79),.12,.38,'red')
        for y in [-3.8,3.8]:
            beam('PipeSupport',(x,y,.05),(x,y,.8),.1,'deck')
            cylinder('ValveHandwheel',(x,y,.89),.34,.05,'red')
    for y in [-3.8,3.8]:
        beam('Manifold',(-5,y,.72),(-5,y*1.8,.72),.17,'silver')
    save('tanker_deck_pipes','Original procedural special operations prop',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def container():
    reset();l,w,h=6.058,2.438,2.591
    box('ISO20ft_Shell',(0,0,h/2),(l,w,h),'deck',.035)
    for y in [-w/2,w/2]:
        for i in range(27):
            x=-l/2+.10+i*(l-.20)/26
            box('CorrugatedRib',(x,y,h/2),(.045,.015,h-.12),'steel',.005)
    for end in [-1,1]:
        for y in [-w/2+.08,w/2-.08]:
            box('CornerCasting',(end*(l/2-.055),y,.07),(.1,.13,.14),'silver')
            box('CornerCasting',(end*(l/2-.055),y,h-.07),(.1,.13,.14),'silver')
    for y in [-.55,.55]:
        box('RearDoor',(l/2+.007,y,h/2),(.014,1.12,h-.1),'deck')
        for yoff in [-.35,.35]:
            cylinder('DoorLock',(l/2+.03,y+yoff,h/2),.025,h-.27,'silver')
    # Exact bounds are standardized; lock/hinge visual details inset to avoid oversize.
    lo,hi=bounds();dims=hi-lo
    for obj in bpy.context.scene.objects:
        if obj.type=='MESH':
            for v in obj.data.vertices:
                p=obj.matrix_world @ v.co
                v.co=Vector(((p.x-(lo.x+hi.x)/2)*l/dims.x,(p.y-(lo.y+hi.y)/2)*w/dims.y,(p.z-lo.z)*h/dims.z))
            obj.matrix_world.identity()
    save('cargo_container','Original procedural special operations prop',
         '',
         {'length':l,'width':w,'height':h},'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def fence():
    reset()
    for x in [-2,0,2]:
        cylinder('FencePost',(x,0,1.1),.065,2.2,'steel')
    for z in [.25,1.0,1.85]:
        beam('FenceWire',(-2,0,z),(2,0,z),.012,'steel')
    # Chain-link diamonds are tubes, readable overhead without an alpha texture.
    for i in range(19):
        x=-2+i*.22
        beam('ChainLink',(x,0,.2),(min(2,x+1.65),0,1.85),.008,'silver')
        beam('ChainLink',(x,0,1.85),(min(2,x+1.65),0,.2),.008,'silver')
    save('fence_panel','Original procedural special operations prop',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def pipe(asset, elbow=False):
    reset()
    if not elbow:
        cylinder('Pipe',(0,0,.25),.25,4,'silver',(0,math.pi/2,0),24)
        for x in [-1.98,1.98]:
            cylinder('Flange',(x,0,.25),.34,.045,'steel',(0,math.pi/2,0),24)
    else:
        pts=[(1.4*math.cos(t*math.pi/2/12)-.7,1.4*math.sin(t*math.pi/2/12)-.7,.25) for t in range(13)]
        for a,b in zip(pts[:-1],pts[1:]):beam('Elbow',a,b,.25,'silver')
    ground();save(asset,'Metal pipe elbow' if elbow else '4m metal pipe',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def watchtower():
    reset()
    for x in [-1.6,1.6]:
        for y in [-1.6,1.6]:
            beam('TowerLeg',(x,y,0),(x*.75,y*.75,6),.12,'wood')
    box('Platform',(0,0,6),(3.5,3.5,.16),'wood')
    for y in [-1.7,1.7]:
        box('Parapet',(0,y,6.55),(3.5,.16,1),'wood')
    for x in [-1.7,1.7]:box('Parapet',(x,0,6.55),(.16,3.5,1),'wood')
    for y in [-1.6,1.6]:
        beam('Diagonal',(-1.6,y,.5),(1.6,y,5.8),.07,'wood')
    for y in [-.5,.5]:beam('Ladder',(-1.5,y,0),(-1.5,y,6),.05,'wood')
    for z in [i*.35 for i in range(18)]:beam('LadderRung',(-1.5,-.5,z),(-1.5,.5,z),.035,'wood')
    save('watchtower','Original procedural special operations prop',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def radar():
    reset()
    box('TrailerBase',(0,0,.35),(2.7,1.7,.55),'olive',.04)
    for y in [-.95,.95]:
        for x in [-.9,.9]:cylinder('TrailerWheel',(x,y,.35),.35,.18,'black',(math.pi/2,0,0))
    cylinder('RadarTurntable',(0,0,1.2),.38,1.2,'steel')
    # 3m paraboloid, facing +X at elevation 20deg, not large 7m dish.
    verts=[(0,0,0)];faces=[];n=48;rings=7
    for r in range(1,rings+1):
        radius=1.5*r/rings
        for j in range(n):
            t=2*math.pi*j/n
            verts.append((radius*radius/.95, radius*math.cos(t),radius*math.sin(t)))
    for j in range(n):faces.append((0,1+j,1+(j+1)%n))
    for r in range(rings-1):
        for j in range(n):
            a=1+r*n+j;b=1+r*n+(j+1)%n;faces.append((a,b,b+n,a+n))
    dish=mesh('Dish_3mReflector',verts,faces,'olive')
    # Shallow parabolic depth corrected to .42m outer depth.
    for v in dish.data.vertices:v.co.x*=.42/(1.5*1.5/.95)
    dish.location=(-.6,0,2.2);dish.rotation_euler.y=-math.radians(20)
    beam('FeedArm',(-.6,-1.2,1.7),(.65,0,2.6),.055,'steel')
    beam('FeedArm',(-.6,1.2,1.7),(.65,0,2.6),.055,'steel')
    sphere('RotatingFeed',(.65,0,2.6),(.14,.14,.14),'black')
    ground();save('radar_dish','Original procedural special operations prop',
         '',
         {'dish_diameter':3},'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def shell(asset, l, w, h, key='concrete'):
    reset()
    # Full height outer side walls; entrance face is divided around a 2m door.
    for y in [-w/2,w/2]:
        box('Facade_Side',(0,y,h/2),(l,.28,h),key,.025)
        for x in range(int(-l/2)+2,int(l/2),3):
            if h>2.3:box('Facade_Window',(x,y*1.013,1.75),(1.2,.04,1.15),'glass')
    box('Facade_Back',(-l/2,0,h/2),(.28,w,h),key,.025)
    for y in [-w/4-.5,w/4+.5]:box('Facade_Entrance',(l/2,y,h/2),(.28,w/2-1,h),key)
    # Raised roof line is absent: these are deliberate gameplay cutaways.
    for x in [-l/4,l/4]:box('Cutaway_InternalWall',(x,0,.55),(.14,w*.56,1.1),key)
    save(asset,asset.replace('_',' '),note=f'Game reconstruction shell {l}m × {w}m × {h}m, 2m entrance; outer walls retain realistic floor height, roof omitted for overhead visibility. Interior is not surveyed.')


def landmark_shell(asset, l, w, h, kind):
    reset()
    key='brick' if kind=='courtyard' else ('ivory' if kind=='townhouse' else 'concrete')
    # Long facades are full height but placed on the rear/sides of a cutaway core.
    for y in [-w/2,w/2]:
        box('UpperShell_Facade',(0,y,h/2),(l,.3,h),key,.05)
        for z in range(2,int(h),3):
            for x in range(int(-l/2)+2,int(l/2),3):
                box('UpperShell_Window',(x,y+math.copysign(.175,y),z),(.95,.04,1.35),'glass',.05)
    box('UpperShell_Rear',(-l/2,0,h/2),(.3,w,h),key,.05)
    for y in [-w/4-.6,w/4+.6]:box('UpperShell_Entrance',(l/2,y,h/2),(.3,w/2-1.2,h),key)
    for y in [-w/2,w/2]:box('Cutaway_Foundation',(0,y,.55),(l,.3,1.1),key,.035)
    if kind=='townhouse':
        for x in [-l*.27,0,l*.27]:
            box('UpperShell_Cornice',(x,0,h+.14),(l*.30,w+.5,.28),'ivory')
        for y in [-w/2,w/2]:
            box('UpperShell_Balcony',(0,y*1.10,5.8),(l*.9,1.0,.12),'ivory')
    elif kind=='compound':
        for x in [-l*.26,l*.26]:
            box('UpperShell_Balcony',(x,0,3.4),(l*.38,w+1,.16),'concrete')
        cylinder('UpperShell_WaterTank',(-l*.25,0,h+.7),.85,1.4,'silver')
    elif kind=='industrial':
        box('UpperShell_TallIndustrialWing',(-l*.28,0,h/2+1.8),(l*.28,w*.75,h+3.6),'concrete',.06)
        for y in [-w/2,w/2]:
            for x in [-l*.40,-l*.18,l*.04,l*.26]:
                box('UpperShell_IndustrialWindowGrid',(x,y+math.copysign(.175,y),h*.52),(l*.16,.04,h*.68),'glass')
                for z in [h*.25,h*.45,h*.65]:
                    box('UpperShell_GridMullion',(x,y+math.copysign(.21,y),z),(l*.16,.045,.12),'ivory')
        cylinder('UpperShell_Chimney',(-l*.39,w*.35,h+4),.55,8,'brick')
    elif kind=='courtyard':
        for x in [-l*.38,0,l*.38]:
            cylinder('UpperShell_Drum',(x,0,h+1),w*.13,2.5,'ivory',vertices=24)
            sphere('UpperShell_RedDome',(x,0,h+3.4),(w*.17,w*.17,3.1),'red',28,16)
            cylinder('UpperShell_Finial',(x,0,h+6.7),.09,1.1,'gold')
        for y in [-w/2,w/2]:
            box('UpperShell_WhiteCornice',(0,y,h*.65),(l,.40,.35),'ivory')
    save(asset,asset.replace('_',' '),note=f'Fictional building shell, {l}m × {w}m × {h}m main block is reconstruction, not a surveyed original footprint. Roof and tall upper facades use UpperShell_ nodes and can be hidden for playable overhead interior. '+
         {'courtyard':'Red central/corner domes and white/red hotel facade identify Courtyard Palace; no measured room arrangement claimed.',
          'compound':'Enclosed residence with balconies; inner footprint is a fictional layout.',
          'townhouse':'Tall narrow terrace facade, cornices and balconies; embassy interior reconstructed.',
          'industrial':'Industrial high-window hall, tower wing and chimney; Vemork-shaped factory reconstruction.'}[kind])
    REGISTRY[asset]['cutaway_hide_meshes']=['UpperShell_Cutaway']
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')


def terrace_townhouse():
    reset()
    # Shared 1:1 terrace exterior. Upper floors hide together over the playable ground floor.
    w, d, h = 9.6, 22, 14.4
    for x in [-w / 2, w / 2]:
        box('UpperShell_PartyWall', (x, 0, h / 2), (.2, d, h), 'ivory')
    for y in [-d / 2, d / 2]:
        for x in [-2.66, 2.66]:
            box('UpperShell_EntranceSide', (x, y, 1.05), (4.275, .2, 2.1), 'white')
        box('UpperShell_Facade', (0, y, 8.25), (w, .2, 12.3), 'white')
        for z in [2.9, 5.8, 8.7, 11.6, 14.3]:
            box('UpperShell_Cornice', (0, y, z), (w + .2, .28, .12), 'ivory')
        for z in [1.3, 4.4, 7.3, 10.2, 13.1]:
            for x in [-3.15, 0, 3.15]:
                if z == 1.3 and x == 0: continue
                box('UpperShell_Window', (x, y + math.copysign(.12, y), z), (1.1, .04, 1.65), 'glass')
        for x in [-4.6, 4.6]:
            box('Facade_BasePier', (x, y, .42), (.2, .24, .84), 'ivory')
    save('terrace_townhouse', 'Original procedural special operations prop',
         source_url='',
         note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def bunker():
    reset()
    # Low heavy concrete casemate, open roof for gameplay.
    for y in [-4.5,4.5]:box('ConcreteSide',(0,y,1.45),(10,1,2.9),'concrete',.08)
    box('ConcreteRear',(-5,0,1.45),(1,9,2.9),'concrete',.08)
    for y in [-3,3]:box('FrontEmbrasure',(5,y,1.45),(1,3,2.9),'concrete',.08)
    box('SlitLower',(5,0,.7),(1,3,1.4),'concrete');box('SlitUpper',(5,0,2.5),(1,3,.8),'concrete')
    save('bunker','Original procedural special operations prop',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def lighthouse():
    reset()
    bpy.ops.mesh.primitive_cone_add(vertices=24,radius1=2.3,radius2=1.5,depth=16,location=(0,0,8))
    material(bpy.context.object,'white');bpy.context.object.name='LighthouseMasonry'
    cylinder('LanternGallery',(0,0,16.05),2.2,.22,'steel',vertices=32)
    cylinder('LanternGlass',(0,0,17.1),1.35,2,'glass',vertices=16)
    bpy.ops.mesh.primitive_cone_add(vertices=24,radius1=1.8,radius2=.1,depth=1,location=(0,0,18.55))
    material(bpy.context.object,'red');bpy.context.object.name='LanternRoof'
    for a in range(16):
        t=a*math.pi/8;x=2.1*math.cos(t);y=2.1*math.sin(t)
        beam('GalleryRail',(x,y,16.1),(x,y,17.1),.035,'steel')
    save('lighthouse','Original procedural special operations prop',note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def bridge(asset, bascule=False):
    reset();l=42 if bascule else 54;w=6.6 if bascule else 6
    box('BridgeDeck',(0,0,-.18),(l,w,.36),'steel')
    for y in [-w/2,w/2]:
        beam('LowerGirder',(-l/2,y,.1),(l/2,y,.1),.18,'steel')
        beam('TopGirder',(-l/2,y,2.5),(l/2,y,2.5),.13,'steel')
        for i in range(10):
            x=-l/2+i*l/10
            beam('TrussVertical',(x,y,.1),(x,y,2.5),.1,'steel')
            beam('TrussDiagonal',(x,y,.1),(x+l/10,y,2.5),.1,'steel')
    if bascule:
        for y in [-3,3]:
            beam('BasculeTower',(-17,y,.1),(-17,y,9),.26,'steel')
            beam('BasculeCantilever',(-17,y,9),(-4,y,5.2),.25,'steel')
            beam('CounterweightArm',(-17,y,9),(-21,y,7),.25,'steel')
        box('Counterweight',(-20,0,6.7),(3.2,5.8,1.5),'concrete')
    save(asset,'Lift rolling-lift bridge' if bascule else 'Glider steel truss bridge',
         '',
         note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def wheel(name, xyz, r=.4, depth=.24):
    return cylinder(name,xyz,r,depth,'black',(math.pi/2,0,0),20)


def vehicle(asset, truck=False):
    reset();l=6.4 if truck else 3.36;w=2.3 if truck else 1.57
    box('Frame',(0,0,.6),(l,w*.78,.25),'steel',.04)
    if truck:
        box('TruckCab',(1.65,0,1.55),(2,w,1.65),'olive',.12)
        box('TruckWindshield',(2.68,0,1.95),(.03,w*.85,.8),'glass',.02)
        box('CargoBed',(-1.3,0,1.0),(3.9,w,.32),'olive',.04)
        for y in [-w/2,w/2]:box('CargoSideboard',(-1.3,y,1.6),(3.9,.1,.9),'wood')
        for x in [-2.3,-1.3,2.2]:
            for y in [-1.07,1.07]:wheel('TruckWheel',(x,y,.5),.5,.32)
    else:
        box('UtilityVehicleTub',(-.35,0,.92),(2.3,w,.68),'olive',.06)
        box('Hood',(1.15,0,1.14),(1.05,w*.90,.38),'olive',.07)
        box('Grille',(1.67,0,.95),(.045,w*.85,.7),'olive')
        for y in [-.48,-.32,-.16,0,.16,.32,.48]:box('GrilleSlot',(1.7,y,.93),(.015,.075,.38),'black')
        box('WindshieldFrame',(.37,0,1.80),(.075,1.48,.78),'olive')
        box('Windshield',(.415,0,1.80),(.012,1.34,.62),'glass')
        for x in [-1.02,1.1]:
            for y in [-.75,.75]:wheel('UtilityVehicleWheel',(x,y,.36),.36,.21)
        for y in [-.48,.48]:
            box('Seat',(-.5,y,1.2),(.55,.48,.2),'black',.04)
            box('SeatBack',(-.78,y,1.5),(.16,.48,.55),'black',.04)
        wheel('SpareWheel',(-1.75,0,1.1),.36,.21).rotation_euler=(0,math.pi/2,0)
        for y in [-.56,.56]:sphere('RoundHeadlamp',(1.73,y,1.17),(.04,.13,.13),'ivory')
    ground();save(asset,'coastal-style utility utility_vehicle' if not truck else 'Period 6×6 transport truck',
         note='Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def boat(asset, kind):
    reset();l,w=(7.0,2.6) if kind=='rhib' else ((8.5,3.2) if kind=='lifeboat' else (4.8,.78))
    outline=[(-l*.5,-w*.25),(-l*.38,-w*.5),(l*.28,-w*.5),(l*.5,0),(l*.28,w*.5),(-l*.38,w*.5),(-l*.5,w*.25)]
    polygon_prism('BoatHull',outline,0,.45,'orange' if kind=='lifeboat' else 'steel')
    if kind=='rhib':
        for side in [-1,1]:
            loft('InflatableTube',[(-l*.45,.28,.28,.55),(l*.26,.28,.28,.55),(l*.43,.12,.17,.5)],'black',16).location.y=side*w*.43
        box('Console',(-.6,0,.95),(.8,.85,.9),'steel',.1)
        box('Windscreen',(-.16,0,1.53),(.04,.82,.38),'glass')
        for y in [-.65,.65]:box('Bench',(-1.8,y,.65),(.7,.5,.3),'black',.05)
        box('Outboard',(-3.7,0,.43),(.55,.55,.9),'black',.1)
    elif kind=='lifeboat':
        loft('EnclosedLifeboatCanopy',[(-3.6,.25,.30,.8),(-2.2,1.45,1.05,1.2),(1.4,1.45,1.05,1.2),(3.7,.28,.4,.8)],'orange',20)
        for y in [-1.44,1.44]:
            for x in [-1.2,.0,1.2]:box('LifeboatWindow',(x,y,1.48),(.65,.025,.43),'glass',.04)
    else:
        for x in [-1.15,1.15]:box('CanoeSeat',(x,0,.45),(.35,.67,.06),'wood')
        beam('Paddle',(-.8,-.9,.4),(.8,.9,.4),.025,'wood')
        box('PaddleBlade',(.85,.95,.4),(.28,.3,.035),'wood',.05)
    ground();save(asset,kind.replace('_',' '),note=f'Generic {l}m × {w}m {kind} reconstruction; lifeboat depicts enclosed orange rescue craft, not a claimed original manufacturer.')


def patrol_ship():
    reset();l,w=95.81,9.3
    outline=[(-l/2,-w*.35),(-l*.4,-w/2),(l*.36,-w/2),(l/2,0),(l*.36,w/2),(-l*.4,w/2),(-l/2,w*.35)]
    polygon_prism('PatrolShipHull',outline,-2.5,.2,'steel')
    box('Bridge',(-9,0,2.0),(12,6.2,3.6),'olive',.18)
    for x in [-17,0]:cylinder('CutDownFunnel',(x,0,3.3),1,3.3,'black')
    for y in [-3.8,3.8]:box('RaidArmour',(-11,y,1.35),(25,.12,2.3),'steel')
    cylinder('ForedeckGunBase',(26,0,.65),.65,.9,'steel')
    beam('DeckGunBarrel',(26,0,1.2),(28.2,0,1.55),.07,'steel')
    cylinder('Mast',(-5,0,6),.08,9,'steel')
    save('patrol_ship_hull','Original procedural special operations prop',
         '',
         {'length':95.81,'beam':9.3},'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.',floor_offset=0)


def escort_ship():
    reset();l,w=155.448,20.1168
    # Primary NHHC ship-history gives escort vessel itself as 510 x 66 feet; preserve
    # that footprint instead of scaling an unrelated tanker to a stern room.
    outline=[(-l/2,-w/2),(-l*.43,-w/2),(l*.32,-w/2),(l*.43,-w*.31),(l/2,0),
             (l*.43,w*.31),(l*.32,w/2),(-l*.43,w/2),(-l/2,w/2)]
    n=len(outline);bottom=-13.2036
    verts=[(x,y,.2) for x,y in outline]+[(x*.97,y*.65,bottom) for x,y in outline]
    faces=[tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh('EscortShipNavalHull',verts,faces,'steel')
    polygon_prism('EscortShipGreyDeck',outline,.07,.2,'steel')
    # Flight-deck marking belongs to the aft, not a modern container deck.
    centre=-l*.35
    for x in [centre-8,centre+8]:box('FlightDeckWhiteMark',(x,0,.208),(.11,14,.014),'ivory')
    for y in [-7,7]:box('FlightDeckWhiteMark',(centre,y,.208),(16,.11,.014),'ivory')
    for y in [-1.3,1.3]:box('HelipadH',(centre,y,.209),(4.0,.16,.015),'ivory')
    box('HelipadHCrossbar',(centre,0,.209),(.16,2.6,.015),'ivory')
    for side in [-1,1]:
        for x in range(-72,42,6):
            beam('NavalRailPost',(x,side*(w/2-.15),.2),(x,side*(w/2-.15),1.20),.03,'silver')
        beam('NavalRailTop',(-72,side*(w/2-.15),1.20),(41,side*(w/2-.15),1.20),.03,'silver')
    # The game uses the aft 80m as a selected deck region. Forward deck and
    # outlines are visual context; detailed combat systems are intentionally
    # absent because this asset is the ship's hull, not a complete warship CAD.
    authored_envelope(l,w)
    save('escort_ship_hull','Original procedural special operations prop',
         '',
         {'length':l,'beam':w,'published_draft':9.7536},
         'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.',floor_offset=0)


def temple():
    reset();s=12.3444
    # Sanctum is a protected background landmark, not an assault interior.
    box('MarblePlinth',(0,0,.6),(20.4216,20.4216,1.2),'ivory',.05)
    box('SanctumLower',(0,0,3.6),(s,s,6),'ivory',.07)
    box('SanctumUpper',(0,0,8.1),(s,s,3),'gold',.07)
    for y in [-s/2,s/2]:
        for x in [-4,-2,0,2,4]:
            box('GoldenPilaster',(x,y,5.3),(.17,.19,7.2),'gold')
            box('ArchInset',(x,y*1.01,3.2),(1.15,.025,2.25),'glass',.3)
    cylinder('MainDomeDrum',(0,0,10.2),2.65,1.2,'gold',vertices=32)
    sphere('GoldOnionDome',(0,0,11.4),(3,3,2.15),'gold',32,20)
    cylinder('DomeFinial',(0,0,14),.12,1.6,'gold')
    for x in [-4.8,4.8]:
        for y in [-4.8,4.8]:
            cylinder('CornerChattri',(x,y,10.4),.75,1.6,'gold')
            sphere('CornerDome',(x,y,11.5),(.9,.9,.75),'gold')
    save('temple_sanctum','Original procedural special operations prop',
         '',
         {'sanctum_side':12.3444,'plinth_side':20.4216},'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def aircraft(asset, l, span, height, type_):
    reset();bodyw=4.0 if type_=='transport_turboprop' else (2.9 if type_=='glider' else 3.76)
    if type_=='reartwin':bodyw=3.35
    if type_=='business_twinjet':bodyw=1.60
    z=3.0 if type_=='transport_turboprop' else (1.8 if type_=='glider' else (1.6 if type_=='business_twinjet' else 3.1))
    key='olive' if type_ in ['transport_turboprop','glider'] else 'white'
    sections=[(-l/2,.06,.10,z),(-l*.42,bodyw*.27,bodyw*.32,z),(-l*.28,bodyw/2,bodyw/2,z),
              (l*.26,bodyw/2,bodyw/2,z),(l*.39,bodyw*.40,bodyw*.43,z),(l/2,.035,.05,z-.15)]
    # Positive X is nose. Distinct tail-first loft taper maintained.
    loft('FuselageCutaway',sections,key,28,open_top=True)
    # Upper cap remains a separate node: scenery renderer may hide it for cabin play.
    cap=loft('Roof_FuselageCap',sections,key,28)
    keep=set()
    for p in cap.data.polygons:
        if p.center.z > z+bodyw*.32:keep.add(p.index)
    import bmesh
    bm=bmesh.new();bm.from_mesh(cap.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES')
    bm.to_mesh(cap.data);bm.free()
    box('CabinFloor',(0,0,z-bodyw*.30),(l*.65,bodyw*.77,.1),'ivory')
    if type_ not in ['transport_turboprop','glider']:
        for x in [i*.90-l*.28 for i in range(int(l*.57/.9))]:
            for side in [-1,1]:
                for y in [.60,1.12]:
                    box('CabinSeat',(x,side*y,z-bodyw*.30+.48),(.42,.43,.55),'glass',.06)
    sweep=.16 if type_ in ['transport_turboprop','glider'] else .43
    chord=l*.16
    wingx=-l*.035 if type_=='transport_turboprop' else (-l*.10 if type_=='glider' else -l*.025)
    wingz=z+bodyw*.38 if type_ in ['transport_turboprop','glider'] else z-bodyw*.28
    for side in [-1,1]:
        points=[(wingx+chord*.5,side*bodyw*.3),(wingx+chord*.5-span*sweep*.5,side*span*.5),
                (wingx-chord*.4-span*sweep*.5,side*span*.5),(wingx-chord*.5,side*bodyw*.3)]
        polygon_prism('HighWing' if type_ in ['transport_turboprop','glider'] else 'SweptWing',points,wingz-.1,wingz+.1,key)
    # Tailplane and fin; RearTwin tailplane mounted high (T-tail).
    tailx=-l*.39
    tailz=z+(2.6 if type_=='reartwin' else 1.7) if type_ in ['reartwin','business_twinjet'] else z+.25
    tailspan=span*.34
    for side in [-1,1]:
        polygon_prism('HorizontalTail',[(tailx+1.5,0),(tailx-.5,side*tailspan*.5),(tailx-3,side*tailspan*.5),(tailx-1.5,0)],tailz-.08,tailz+.08,key)
    finverts=[(tailx-2,0,z),(tailx+1.4,0,z),(tailx-.7,0,height),(tailx-3.5,0,height*.84)]
    fin=mesh('VerticalFin',finverts,[(0,1,2,3)],key)
    solid=fin.modifiers.new('Fin thickness','SOLIDIFY');solid.thickness=.17
    bpy.context.view_layer.objects.active=fin;bpy.ops.object.modifier_apply(modifier=solid.name)
    if type_=='transport_turboprop':
        for y in [-span*.30,-span*.15,span*.15,span*.30]:
            loft('TurbopropNacelle',[(wingx-2,.6,.55,wingz-.55),(wingx+1.6,.6,.55,wingz-.55),(wingx+2.3,.25,.25,wingz-.55)],key,16).location.y=y
            cylinder('PropSpinner',(wingx+2.42,y,wingz-.55),.24,.5,'black',(0,math.pi/2,0))
            for a in range(4):
                t=a*math.pi/2
                beam('Propeller',(wingx+2.68,y+math.cos(t)*.28,wingz-.55+math.sin(t)*.28),(wingx+2.68,y+math.cos(t)*2.0,wingz-.55+math.sin(t)*2.0),.095,'black')
        box('RearRamp',(-l*.40,0,.45),(4.6,2.8,.16),'steel')
    elif type_!='glider':
        engineys=[-span*.19,span*.19] if type_ in ['twinjet','quadjet'] else [-bodyw*.69,bodyw*.69]
        if type_=='quadjet':engineys += [-span*.32,span*.32]
        for y in engineys:
            ex=wingx+.15 if type_ not in ['reartwin','business_twinjet'] else -l*.31
            ez=wingz-.72 if type_ not in ['reartwin','business_twinjet'] else z+.05
            es=.50 if type_=='business_twinjet' else 1.0
            loft('JetNacelle',[(ex-1.4*es,.38*es,.38*es,ez),(ex-.8*es,.72*es,.72*es,ez),(ex+1.4*es,.68*es,.68*es,ez)],'silver',20).location.y=y
            cylinder('DarkIntake',(ex+1.42*es,y,ez),.55*es,.02,'black',(0,math.pi/2,0))
        if type_=='business_twinjet':
            for side in [-1,1]:
                loft('WingtipTank',[(-l*.20,.06,.08,wingz),(-l*.10,.25,.25,wingz),(l*.02,.25,.25,wingz),(l*.09,.04,.07,wingz)],'silver',16).location.y=side*(span/2-.15)
    # Window rows follow fuselage radius. Cockpit is at positive X.
    for side in [-1,1]:
        if type_ not in ['transport_turboprop','glider']:
            for i in range(int(l*.65)):
                x=-l*.30+i*.85
                if x>l*.34:break
                box('PassengerWindow',(x,side*(bodyw/2+.014),z+.28),(.32,.025,.40),'glass',.07)
        for i in range(3):
            box('CockpitWindow',(l*.36+i*.48,side*bodyw*.38,z+.70),(.42,.025,.45),'glass',.035)
    # Landing gear tires are actual human-scale, not implicit object resizing.
    for x,y,r in [(l*.33,0,.38),(-l*.08,-bodyw*.65,.5),(-l*.08,bodyw*.65,.5)]:
        beam('GearStrut',(x,y,r),(x,y,z-.5),.08,'silver')
        wheel('LandingWheel',(x,y,r),r,.22)
    ground();authored_envelope(l,span,height)
    floor=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('CabinFloor'))
    bpy.context.view_layer.update()
    cabin_floor_y=max((floor.matrix_world@v.co).z for v in floor.data.vertices)
    save(asset,asset.replace('_',' ').upper(),
         source_url=AIRCRAFT_SOURCES.get(asset,''),verified={'length':l,'wingspan':span,'published_height':height},
         note='Published outer length and wingspan authored in metres. Recognition features: '+
              {'transport_turboprop':'high wing, four turboprops, rear ramp','twinjet':'twin underwing engines, swept low wing','reartwin':'rear twin engines and T-tail','quadjet':'four underwing jet nacelles','glider':'engine-free high wooden wing and rounded cargo fuselage','business_twinjet':'small tapered business-jet cabin, rear engines, T-tail and wingtip tanks'}[type_]+
              '. Grounded on landing gear; cockpit, cabin and fine dimensions are reconstructed. Upper cap uses Roof_ node; cutaway interior floor and seats remain visible with the cap hidden. World navigation still uses mission collision geometry.')
    REGISTRY[asset]['cutaway_hide_meshes']=['Roof_Cutaway']+(['CabinSeats_Cutaway'] if type_ not in ['transport_turboprop','glider'] else [])
    REGISTRY[asset]['cabin_floor_y_m']=round(cabin_floor_y,6)
    REGISTRY[asset]['cabin_floor_note']='Source model floor surface before scenery placement offset, not ground or landing gear height. Character feet and playable seat props must be placed at the same floor height.'
    if type_=='glider':
        REGISTRY[asset]['verified_dimensions_m'].pop('published_height')
        REGISTRY[asset]['authored_height_design_m']=height
        REGISTRY[asset]['accuracy_note']+=' Glider height6.4m is a reconstruction assumption; museum source verifies only length/span.'
    if type_=='business_twinjet':
        REGISTRY[asset]['accuracy_note']+=' Small business twinjet proportions; variant details are design assumptions.'
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')


AIRCRAFT_SOURCES = {
    'transport_turboprop':'',
    'airliner_twinjet':'',
    'airliner_reartwin':'',
    'airliner_quadjet':'',
    'cargo_glider':'',
    'business_twinjet':'',
}


def cargo_twinprop():
    reset();l,w,h=12.21,19.79,4.60
    box('BoxCargoFuselage',(-.3,0,1.85),(9.4,2.5,2.6),'olive',.13)
    loft('SkyvanShortNose',[(3.7,1.25,1.1,1.8),(5.8,.78,.85,1.8),(6.1,.12,.3,1.65)],'olive',20)
    for side in [-1,1]:
        box('CockpitGlazing',(4.3,side*1.23,2.25),(1.4,.05,.78),'glass',.08)
        box('StraightHighWing',(-.25,side*w*.25,3.25),(2.15,w*.50,.14),'olive',.04)
        beam('WingBrace',(0,side*1.23,1.05),(-.1,side*5.4,3.2),.06,'silver')
        y=side*3.9
        loft('TwinTurboprop',[(-1.0,.38,.38,3.0),(1.6,.38,.38,3.0),(2.2,.15,.2,3.0)],'olive',16).location.y=y
        for a in range(3):
            t=a*2*math.pi/3
            beam('ThreeBladeProp',(2.3,y+math.cos(t)*.20,3.0+math.sin(t)*.20),(2.3,y+math.cos(t)*1.05,3.0+math.sin(t)*1.05),.065,'black')
        box('TwinTailFin',(-5.1,side*1.65,3.45),(1.15,.12,2.05),'olive',.08)
        wheel('FixedMainWheel',(-1.4,side*1.3,.40),.40,.25)
    box('HorizontalTail',(-5.1,0,2.55),(1.4,4.5,.11),'olive',.04)
    wheel('NoseWheel',(4.1,0,.27),.27,.18)
    box('RearCargoRamp',(-5.1,0,.64),(2.0,2.15,.12),'steel')
    ground();authored_envelope(l,w,h)
    save('cargo_twinprop','Original procedural special operations prop',
         '',
         {'length':l,'wingspan':w,'height':h},
         'Procedural game geometry. Generic public dimension data informed proportions where recorded; interiors, contours and unmeasured details are authored design assumptions, not surveyed plans.')


def helicopter(asset, body_length, rotor, h, family, color='olive'):
    reset()
    heavy=family in ['tandem','cargo','heavy_lift','transport','rescue']
    width={'naval':2.0,'utility':2.4,'light':1.45,'tandem':3.6,'cargo':2.9,'heavy_lift':3.0,'transport':4.7,'rescue':2.8}[family]
    body=body_length*(.83 if family=='tandem' else .53)
    z=1.9 if heavy else (1.0 if family=='light' else 1.5)
    if family=='light':
        sphere('LittleBirdBubble',(body_length*.23,0,z),(.94,.74,.86),'glass',28,16)
        sphere('SmallCabin',(body_length*.10,0,z-.07),(1.18,.75,.77),color)
    else:
        loft('Cabin', [(-body*.45,width*.38,width*.35,z),(-body*.22,width*.5,width*.45,z),
                       (body*.34,width*.5,width*.45,z),(body*.53,width*.27,width*.31,z-.05)],color,24)
        # Airframe-specific cockpit glass panels at tapered nose.
        for side in [-1,1]:
            obj=sphere('CockpitGlass',(body*.38,side*width*.37,z+.22),(body*.17,.09,width*.27),'glass',16,10)
            obj.rotation_euler.z=side*-.18
            for x in [-body*.22,0,body*.16]:
                box('CabinWindow',(x,side*(width*.503),z+.15),(.65,.02,.57),'glass',.05)
    if family=='tandem':
        for x in [-5.9,5.9]:
            cylinder('TandemPylon',(x,0,z+1.7),.5,1.35,color)
            rotor_height=h-.0325 if x<0 else h-.40
            cylinder('TandemRotorMast',(x,0,rotor_height-.25),.12,.6,'silver')
            for a in range(3):
                t=a*math.pi*2/3+(.25 if x<0 else 0)
                obj=box('TandemRotorBlade',(x+math.cos(t)*rotor*.27,math.sin(t)*rotor*.27,rotor_height),
                        (rotor*.49,.36,.07),'black');obj.rotation_euler.z=t
        box('RearRamp',(-body*.46,0,.6),(1.7,width*.75,.13),'steel')
        for side in [-1,1]:
            loft('AftEngine',[(-body*.45,.45,.4,z+1.2),(-body*.2,.45,.4,z+1.2)],color,16).location.y=side*1.4
    else:
        tail_end=-body_length*.57
        loft('TailBoom',[(tail_end,.10,.12,z+.7),(-body*.32,.28,.34,z+.3)],color,16)
        # Vertical tail stabilizer / tail rotor differ by family geometry.
        finh=1.2 if family in ['light','naval'] else 1.8
        polygon_prism('Tailplane',[(tail_end+.5,-1.1),(tail_end-.7,-1.1),(tail_end-.7,1.1),(tail_end+.5,1.1)],z+.6,z+.69,color)
        box('TailFin',(tail_end,0,z+1.1),(.60,.13,finh),color,.1)
        for a in range(4 if family in ['utility','naval'] else 5):
            t=a*2*math.pi/(4 if family in ['utility','naval'] else 5)
            beam('TailRotor',(tail_end,.22,z+1.2),(tail_end+math.cos(t)*.85,.22,z+1.2+math.sin(t)*.85),.055,'black')
        rotorx=0 if family!='light' else body_length*.12
        cylinder('MainMast',(rotorx,0,h-.38),.12,.75,'silver')
        blades={'naval':4,'utility':4,'light':6,'cargo':5,'heavy_lift':5,'transport':6,'rescue':4}[family]
        for a in range(blades):
            t=a*2*math.pi/blades+.13
            obj=box('MainRotorBlade',(rotorx+math.cos(t)*rotor*.27,math.sin(t)*rotor*.27,h),
                    (rotor*.46,.30 if heavy else .23,.065),'black');obj.rotation_euler.z=t
        if family in ['cargo','heavy_lift','transport','utility']:
            for side in [-1,1]:
                loft('TwinEngine', [(-1.7,.4,.40,z+1.12),(.8,.4,.40,z+1.12)],color,16).location.y=side*.64
        if family=='cargo':
            for side in [-1,1]:
                cylinder('CargoSideFuelTank',(-body*.06,side*width*.55,z-.68),.34,body*.65,color,(0,math.pi/2,0),20)
            sphere('CargoRoundCockpit',(body*.42,0,z+.18),(body*.16,width*.43,width*.38),'glass',20,12)
        if family=='transport':
            for side in [-1,1]:
                sphere('LargeSponson',(-1.6,side*2.0,1.15),(2,.66,.66),color)
                cylinder('ExternalTank',(-.7,side*2.5,1.1),.42,2.8,color,(0,math.pi/2,0))
            box('TransportMinesweepingWinch',(-body*.42,0,.73),(1.4,1.5,.65),'steel',.08)
        if family=='heavy_lift':
            for side in [-1,1]:sphere('BoatHullSponson',(-1.0,side*1.5,.86),(1.6,.40,.43),color)
            beam('HeavyLiftRefuellingProbe',(body*.41,-width*.30,z-.25),(body*.80,-width*.30,z-.18),.055,'steel')
        if family=='rescue':
            sphere('RescueDeepNose',(body*.50,0,1.1),(.95,1.1,.8),color)
            cylinder('NoseIntake',(body*.52,0,1.25),.40,.25,'black',(0,math.pi/2,0))
        if family=='naval':
            sphere('NavalNavalRadarNose',(body*.50,0,z-.30),(.65,.60,.44),color,20,12)
            for side in [-1,1]:
                box('NavalSideDoor',(-.3,side*1.02,1.45),(1.25,.035,1.15),color,.05)
                box('DoorWindow',(-.3,side*1.045,1.8),(.75,.035,.6),'glass',.07)
    if family=='light':
        for side in [-1,1]:
            beam('LandingSkid',(-1.0,side*.75,.12),(2.3,side*.75,.12),.06,'black')
            for x in [0,1.3]:beam('SkidSupport',(x,side*.3,.8),(x,side*.75,.12),.06,'black')
            box('ExternalBench',(.0,side*1.0,1.03),(1.30,.34,.09),'black')
    else:
        gearxs=[-body*.26,body*.34] if family=='tandem' else [-body*.28,body*.33]
        for x in gearxs:
            for side in [-1,1]:
                y=side*width*.47
                beam('LandingStrut',(x,y,.38),(x,y,z-.4),.08,'steel')
                wheel('LandingTire',(x,y,.32),.32,.18)
    # Authored fuselage/tail envelope follows the reference family length. Main/tail
    # rotor blades retain their independently authored disc dimensions.
    body_objects=[o for o in bpy.context.scene.objects if o.type=='MESH' and not any(k in o.name for k in ['RotorBlade','TailRotor','MainMast','TandemPylon','TandemRotorMast'])]
    bpy.context.view_layer.update()
    pts=[o.matrix_world@v.co for o in body_objects for v in o.data.vertices]
    xmin=min(p.x for p in pts);xmax=max(p.x for p in pts)
    xf=body_length/(xmax-xmin)
    for obj in body_objects:
        for v in obj.data.vertices:
            p=obj.matrix_world@v.co;v.co=Vector((p.x*xf,p.y,p.z))
        obj.parent=None;obj.matrix_world.identity()
    ground();authored_envelope(height=h)
    save(asset,asset.replace('helicopter_','').upper()+' helicopter',
         source_url=HELICOPTER_SOURCES.get(family,''),
         verified=HELICOPTER_VERIFIED[family],
         note='Distinct recognition mesh in metre units: '+{'naval':'compact naval cabin, four rotor blades, conventional tail','utility':'long utility cabin, twin top engines, swept conventional tail','light':'small bubble canopy, external benches, skids','tandem':'long cargo cabin, two separate tandem rotors, rear ramp','cargo':'round cargo cabin, five-blade rotor, twin roof engines','heavy_lift':'amphibious fuselage/sponsons, five-blade rotor','transport':'large sponsons, six-blade rotor, external tanks','rescue':'high cockpit/deep intake nose, four-blade rotor'}[family]+
              '. Details and contours are authored design assumptions.')
    REGISTRY[asset]['authored_family_dimensions_m']={'fuselage_length_design':body_length,'rotor_disc_diameter':rotor,'height_design':h}
    (OUT/'registry.json').write_text(json.dumps(REGISTRY,indent=2,ensure_ascii=False)+'\n')


HELICOPTER_SOURCES={
    'naval':'',
    'utility':'',
    'light':'',
    'tandem':'',
    'cargo':'',
    'heavy_lift':'',
    'transport':'',
    'rescue':'',
}
HELICOPTER_VERIFIED={
    'naval':{'fuselage_length_naval':13.3,'rotor_naval':12.8,'height_naval':3.7},
    'utility':{'overall_length_UtilityM':19.76},
    'light':{'overall_length_LightM':9.77,'rotor_LightM':8.38,'height_LightM':2.72},
    'tandem':{'overall_length_TandemF':30.1,'fuselage_length_TandemF':15.6,'rotor_TandemF':18.3,'height_TandemF':5.7},
    'cargo':{'airframe_length_Mi8_17_family':18.99,'rotor_Mi8_17_family':21.30,'height_Mi8_17_family':5.55},
    'heavy_lift':{'overall_length_HeavyLiftE':22.25,'rotor_HeavyLiftE':18.90,'height_HeavyLiftE':5.51},
    'transport':{'fuselage_length_transport_proxy':20.48,'rotor_transport_proxy':22.02,'height_transport_proxy':7.59},
    'rescue':{'overall_length_rescue':20.07,'rotor_rescue':17.07,'height_rescue':4.83},
}


BUILDERS={
 'tanker_ship_hull':tanker,'tanker_superstructure':tanker_superstructure,'tanker_deck_pipes':tanker_pipes,
 'rock_small':lambda:nature('rock_small','rock_smallA',1.2,0),
 'rock_medium':lambda:nature('rock_medium','rock_largeA',2.6,0),
 'rock_large':lambda:nature('rock_large','rock_tallA',4.0,2),
 'pine_tree':lambda:nature('pine_tree','tree_pineTallA_detailed',11.0,2),
 'palm_tree':lambda:nature('palm_tree','tree_palmDetailedTall',9.0,2),
 'bush':lambda:nature('bush','plant_bushDetailed',1.0,2),
 'cargo_container':container,'fence_panel':fence,
 'pipe_straight':lambda:pipe('pipe_straight'),'pipe_elbow':lambda:pipe('pipe_elbow',True),
 'watchtower':watchtower,'radar_dish':radar,'bunker':bunker,'lighthouse':lighthouse,
 'hangar_shell':lambda:shell('hangar_shell',36,28,8.5,'steel'),
 'hut':lambda:shell('hut',6,4,2.6,'wood'),
 'terminal_shell':lambda:shell('terminal_shell',56,22,6.8,'ivory'),
 'fortress_shell':lambda:shell('fortress_shell',62,24,5.5,'concrete'),
 'compound_shell':lambda:landmark_shell('compound_shell',28,18,7.2,'compound'),
 'townhouse_shell':lambda:landmark_shell('townhouse_shell',22,14,14,'townhouse'),
 'terrace_townhouse':terrace_townhouse,
 'courtyard_hotel_shell':lambda:landmark_shell('courtyard_hotel_shell',74,28,21,'courtyard'),
 'industrial_shell':lambda:landmark_shell('industrial_shell',66,28,13,'industrial'),
 'lift_bridge':lambda:bridge('lift_bridge',True),'girder_bridge':lambda:bridge('girder_bridge'),
 'transport_turboprop':lambda:aircraft('transport_turboprop',29.79,40.41,11.73,'transport_turboprop'),
 'airliner_twinjet':lambda:aircraft('airliner_twinjet',30.53,28.35,11.38,'twinjet'),
 'airliner_reartwin':lambda:aircraft('airliner_reartwin',36.4,28.4,8.4,'reartwin'),
 'airliner_quadjet':lambda:aircraft('airliner_quadjet',46.61,43.40,12.85,'quadjet'),
 'cargo_glider':lambda:aircraft('cargo_glider',20.42,26.82,6.4,'glider'),
 'business_twinjet':lambda:aircraft('business_twinjet',14.71,11.97,3.71,'business_twinjet'),
 'cargo_twinprop':cargo_twinprop,
 'helicopter_naval':lambda:helicopter('helicopter_naval',13.3,12.8,3.67,'naval','silver'),
 'helicopter_utility':lambda:helicopter('helicopter_utility',15.26,16.36,5.13,'utility','black'),
 'helicopter_light':lambda:helicopter('helicopter_light',7.62,8.38,2.72,'light','black'),
 'helicopter_tandem':lambda:helicopter('helicopter_tandem',15.6,18.3,5.7,'tandem'),
 'helicopter_cargo':lambda:helicopter('helicopter_cargo',18.99,21.30,5.55,'cargo'),
 'helicopter_heavy_lift':lambda:helicopter('helicopter_heavy_lift',17.45,18.90,5.51,'heavy_lift'),
 'helicopter_transport':lambda:helicopter('helicopter_transport',20.47,22.02,7.6,'transport'),
 'helicopter_rescue':lambda:helicopter('helicopter_rescue',14.75,17.07,4.83,'rescue'),
 'utility_vehicle':lambda:vehicle('utility_vehicle'),'cargo_truck':lambda:vehicle('cargo_truck',True),
 'rhib':lambda:boat('rhib','rhib'),'lifeboat':lambda:boat('lifeboat','lifeboat'),
 'canoe':lambda:boat('canoe','canoe'),'patrol_ship_hull':patrol_ship,'temple_sanctum':temple,
 'escort_ship_hull':escort_ship,
}

if __name__=='__main__':
    if OPTIONS.preview_only:
        for asset in REGISTRY:
            if ONLY and asset not in ONLY:continue
            reset()
            bpy.ops.import_scene.gltf(filepath=str(OUT/(asset+'.glb')))
            # glTF importer is Z-up again, preserving metre dimensions.
            preview(asset)
        sys.exit(0)
    for asset, builder in BUILDERS.items():
        if ONLY and asset not in ONLY:continue
        builder()
    archive=SOURCE/'kenney_nature-kit.zip'
    provenance={'built_at':'2026-10-09','human_reference_height_m':1.78,
                'coordinate_convention':'Source Blender Z-up; exported GLB Y-up, forward +X; 1 unit = 1 metre; uniform runtime scale 1.',
                'accuracy_policy':'Verified external dimensions separated from reconstructed geometry. Building plan, unknown interiors, bridge spans and vegetation placement remain design assumptions. Procedural meshes are readable low/mid-poly reconstruction assets, not photogrammetry or exact CAD.',
                'sources':[{'author':'Kenney','url':'https://kenney.nl/assets/nature-kit',
                    'download_url':'https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip',
                    'license':'CC0-1.0','license_path':'licenses/special-ops-assets-kenney-nature.txt',
                    'archive_path':'assets/source/historical/kenney_nature-kit.zip',
                    'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest() if archive.exists() else None}],
                'assets':REGISTRY}
    (ROOT/'licenses/provenance/SPECIAL_OPS_ASSET_PROVENANCE.json').write_text(json.dumps(provenance,indent=2,ensure_ascii=False)+'\n')
    print('Built',len(GENERATED),'assets; registry contains',len(REGISTRY),flush=True)
