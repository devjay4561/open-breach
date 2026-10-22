"""Build redistributable SWAT motion exclusively from local CC0 GLBs.

Run: blender -b --factory-startup --python scripts/build_cc0_swat_motion.py
Default output: build/cc0-motion/combat-swat.glb (gitignored). Install by copying it to
game/assets/characters/, or set CQB_MOTION_OUT=game/assets/characters/combat-swat.glb.
No installed combat motion is read.
"""
import bpy
import hashlib
import json
import math
import os
from pathlib import Path
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ.get('CQB_MOTION_OUT', ROOT / 'build/cc0-motion/combat-swat.glb'))
TOON = ROOT / '.tools/asset-sources/toon-shooter/swat.glb'
KAYKIT = ROOT / '.tools/asset-sources/kaykit/KayKit_Character_Animations_1.1/Animations/gltf/Rig_Medium'
FPS = 30
REQUIRED = {'Death', 'RifleIdle', 'RifleWalk', 'RifleWalkBack', 'RifleRun',
            'RifleRunBack', 'RifleStrafeLeft', 'RifleStrafeRight', 'RifleFire',
            'RifleHit', 'RifleReload', 'RifleThrow', 'RifleTurnLeft',
            'RifleTurnRight', 'DoorOpenOut'}


def sample(rig, action, phase):
    rig.animation_data_create()
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    # GLTF actions omit unchanged channels; never inherit a previous clip pose.
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    frame = action.frame_range[0] + phase * (action.frame_range[1] - action.frame_range[0])
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
    return {b.name: b.matrix_basis.copy() for b in rig.pose.bones}


def global_poses(rig, channels):
    result = {}
    for b in rig.data.bones:
        base = result[b.parent.name] @ b.parent.matrix_local.inverted() @ b.matrix_local if b.parent else b.matrix_local
        result[b.name] = base @ channels[b.name]
    return result


def reach(rig, channels, side, point):
    """Two-bone solve in rig space; preserve the palm's grip rotation."""
    names = [n + '.' + side for n in ('UpperArm', 'LowerArm', 'Wrist')]
    poses = global_poses(rig, channels)
    a, b, c = [poses[n].translation for n in names]
    goal = rig.matrix_world.inverted() @ Vector(point)
    direction = (goal - a).normalized()
    first, second = (b - a).length, (c - b).length
    distance = min((goal - a).length, (first + second) * .999)
    distance = max(distance, abs(first - second) + 1e-6)
    bend = (b - a) - direction * (b - a).dot(direction)
    if bend.length < 1e-6:
        bend = direction.cross(Vector((0, 0, 1)))
    along = (first * first + distance * distance - second * second) / (2 * distance)
    elbow = a + direction * along + bend.normalized() * math.sqrt(max(0, first * first - along * along))
    wrist_rotation = poses[names[2]].to_quaternion()
    for index, destination in [(0, elbow), (1, a + direction * distance)]:
        poses = global_poses(rig, channels)
        bone = rig.data.bones[names[index]]
        origin = poses[bone.name].translation
        old = poses[names[index + 1]].translation - origin
        turn = old.rotation_difference(destination - origin).to_matrix().to_4x4()
        desired = turn @ poses[bone.name]
        desired.translation = origin
        base = poses[bone.parent.name] @ bone.parent.matrix_local.inverted() @ bone.matrix_local
        channels[bone.name] = base.inverted() @ desired
    poses = global_poses(rig, channels)
    wrist = rig.data.bones[names[2]]
    desired = wrist_rotation.to_matrix().to_4x4()
    desired.translation = poses[wrist.name].translation
    base = poses[wrist.parent.name] @ wrist.parent.matrix_local.inverted() @ wrist.matrix_local
    channels[wrist.name] = base.inverted() @ desired


def rotate_world(rig, channels, name, axis, angle):
    poses = global_poses(rig, channels)
    bone = rig.data.bones[name]
    world = rig.matrix_world @ poses[name]
    rotation = Quaternion(axis, angle).to_matrix().to_4x4()
    desired = rotation @ world
    desired.translation = world.translation
    base = poses[bone.parent.name] @ bone.parent.matrix_local.inverted() @ bone.matrix_local
    channels[name] = base.inverted() @ rig.matrix_world.inverted() @ desired


def retarget_rotations(source, target, mapping, channels):
    """Rest-space world rotations; unmapped bones inherit their parent."""
    poses = {}
    target_rotation = target.matrix_world.to_quaternion().to_matrix()
    for bone in target.data.bones:
        base = poses[bone.parent.name] @ bone.parent.matrix_local.inverted() @ bone.matrix_local if bone.parent else bone.matrix_local.copy()
        desired = base @ channels[bone.name]
        if bone.name in mapping:
            sb = source.data.bones[mapping[bone.name]]
            rest = (source.matrix_world @ sb.matrix_local).to_quaternion().to_matrix()
            pose = (source.matrix_world @ source.pose.bones[sb.name].matrix).to_quaternion().to_matrix()
            target_rest = (target.matrix_world @ bone.matrix_local).to_quaternion().to_matrix()
            rotation = target_rotation.inverted() @ pose @ rest.inverted() @ target_rest
            desired = rotation.to_4x4()
            desired.translation = base.translation
        channels[bone.name] = base.inverted() @ desired
        poses[bone.name] = desired
    return channels


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=str(TOON))
    target = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    originals = {a.name.split('|')[-1]: a for a in bpy.data.actions}
    target_objects = set(bpy.context.scene.objects)
    upper = {b.name for b in target.data.bones if b.name == 'Abdomen' or any(p.name == 'Abdomen' for p in b.parent_recursive)}
    # The source's shooting pose aims forward; its pointing idle aims backwards.
    source_aim = sample(target, originals['Idle_Gun_Shoot'], 0)
    aim = {n: m.copy() for n, m in source_aim.items()}
    def inplace(channels):
        for bn in ['Root', 'Body']:
            world = target.matrix_world.to_3x3() @ channels[bn].translation
            world.x = world.y = 0
            channels[bn].translation = target.matrix_world.to_3x3().inverted() @ world
    inplace(aim)
    # Match the existing simulation's barrel sockets without changing ballistics.
    firing_hand = Vector((-.11562, -.19507, 1.38491))
    support_hand = Vector((-.11562, -.37522, 1.49108))
    reach(target, aim, 'R', firing_hand)
    reach(target, aim, 'L', support_hand)
    rotate_world(target, aim, 'Wrist.L', (1, 0, 0), -math.pi / 2)
    for finger in ['Index', 'Middle', 'Ring', 'Pinky']:
        for digit, curl in [(2, -.75), (3, -1.1), (4, -.65)]:
            name = f'{finger}{digit}.L'
            rotation = aim[name].to_euler()
            rotation.x = curl
            closed = rotation.to_matrix().to_4x4()
            closed.translation = aim[name].translation
            aim[name] = closed
    inventory = {}
    baked = []

    def build(name, source_name, modify=None, reverse=False, seconds=None):
        source = originals[source_name]
        duration = seconds or (source.frame_range[1] - source.frame_range[0]) / FPS
        count = round(duration * FPS)
        samples = []
        for i in range(count + 1):
            phase = i / count
            channels = sample(target, source, 1 - phase if reverse else phase)
            if name != 'Death':
                # World Z remains untouched: the vertical body bounce survives.
                inplace(channels)
            if modify:
                modify(channels, phase)
            samples.append(channels)
        baked.append((name, samples))
        inventory[name] = {'source_pack': 'Quaternius Toon Shooter', 'source_file': str(TOON.relative_to(ROOT)),
                           'source_clip': source.name, 'frames': count + 1, 'seconds': count / FPS,
                           'modifications': ['30 fps sampling; planar Root/Body displacement removed'] if name != 'Death' else ['Original CC0 death retained']}
        return inventory[name]

    def layer(channels, phase):
        original = global_poses(target, channels)
        for name in upper:
            channels[name] = aim[name].copy()
        # Strafe clips turn Body; compensate at the upper root so the rifle
        # faces forward while the source legs keep their lateral orientation.
        bone = target.data.bones['Abdomen']
        base = original[bone.parent.name] @ bone.parent.matrix_local.inverted() @ bone.matrix_local
        desired = global_poses(target, aim)['Abdomen'].copy()
        desired.translation = base.translation
        channels['Abdomen'] = base.inverted() @ desired

    build('Death', 'Death')
    build('RifleIdle', 'Idle_Gun_Shoot', layer, seconds=5/3)['modifications'].append('Forward shooting pose held; authored two-hand grip IK and closed left fingers; source body bob')
    for name, src, reverse in [('RifleWalk', 'Walk', False), ('RifleWalkBack', 'Walk', True),
                               ('RifleRun', 'Run_Shoot', False), ('RifleRunBack', 'Run_Back', False),
                               ('RifleStrafeLeft', 'Run_Left', False), ('RifleStrafeRight', 'Run_Right', False)]:
        entry = build(name, src, layer, reverse)
        entry['modifications'] += ['RifleIdle upper body layered', 'Reversed cycle' if reverse else 'Original lower-body cycle']
    def support(channels, phase):
        motion = {n: m.copy() for n, m in channels.items()}
        layer(channels, phase)
        for name in upper:
            if name.endswith('.R'):
                channels[name] = aim[name] @ source_aim[name].inverted() @ motion[name]
    build('RifleFire', 'Idle_Gun_Shoot', support)['modifications'].append('Shooting rotation deltas over two-hand authored support pose')
    def hit(channels, phase):
        motion = {n: m.copy() for n, m in channels.items()}
        layer(channels, phase)
        for name in ['Abdomen', 'Torso', 'Chest', 'Head']:
            channels[name] = channels[name] @ motion[name]
    build('RifleHit', 'HitRecieve', hit)['modifications'].append('Torso reaction over rifle grip; runtime support-hand IK')
    def door(channels, phase):
        for name in channels:
            if not name.endswith('.R') or not any(x in name for x in ['Arm', 'Wrist', 'Shoulder']):
                channels[name] = aim[name].copy()
    build('DoorOpenOut', 'Interact', door)['modifications'].append('Right-arm reach only over RifleIdle')
    for name, sign in [('RifleTurnLeft', 1), ('RifleTurnRight', -1)]:
        def turn(channels, phase, sign=sign):
            channels.update({n: m.copy() for n, m in aim.items()})
            # A closed in-place shuffle; simulation owns actor yaw.
            for side, offset in [('L', 0), ('R', .5)]:
                lift = max(0, math.sin((phase - offset) * math.tau)) * .035
                for bn in ['Foot.' + side, 'PT.' + side]:
                    world = target.matrix_world.to_3x3() @ channels[bn].translation
                    world.z += lift
                    world.y += sign * math.sin(phase * math.tau) * .025 * (1 if side == 'L' else -1)
                    channels[bn].translation = target.matrix_world.to_3x3().inverted() @ world
        entry = build(name, 'Walk', turn, seconds=1)
        entry.update(source_pack='OPEN BREACH procedural adaptation of Quaternius Toon Shooter',
                     source_clip='Idle_Gun_Shoot + original foot shuffle',
                     modifications=['Original procedural closed foot shuffle over CC0 aim pose; no baked actor yaw'])

    # KayKit torso/arm rotations transfer by rest space. Keep target fingers and
    # legs; source rigs have no compatible phalanges and different proportions.
    for name, file, clip, side_only in [('RifleReload', 'CombatRanged', 'Ranged_2H_Reload', False),
                                        ('RifleThrow', 'General', 'Throw', True)]:
        before = set(bpy.data.objects)
        path = KAYKIT / ('Rig_Medium_' + file + '.glb')
        old_actions = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=str(path))
        source = next(o for o in set(bpy.data.objects) - before if o.type == 'ARMATURE')
        source_action = next(a for a in set(bpy.data.actions) - old_actions if a.name == clip)
        mapping = {'Abdomen': 'spine', 'Chest': 'chest'}
        for side in (['R'] if side_only else ['L', 'R']):
            for dest, src in [('UpperArm', 'upperarm'), ('LowerArm', 'lowerarm'), ('Wrist', 'wrist')]:
                mapping[dest + '.' + side] = src + '.' + side.lower()
        count = round(source_action.frame_range[1] - source_action.frame_range[0])
        samples = []
        for i in range(count + 1):
            sample(source, source_action, i / count)
            channels = retarget_rotations(source, target, mapping, {n: m.copy() for n, m in aim.items()})
            # Fade to the common ready pose at the clip boundaries.
            weight = min(1, i / 5, (count - i) / 5)
            channels = {n: aim[n].lerp(m, weight) for n, m in channels.items()}
            samples.append(channels)
        if name == 'RifleReload':
            # KayKit's proportions leave the support hand off the magazine on
            # this short-armed rig. Author a closed, reachable reload instead.
            samples = []
            magazine = firing_hand + Vector((0, -.06, -.18))
            keys = [(0, support_hand), (.22, magazine),
                    (.43, Vector((.12, -.18, .98))), (.64, magazine),
                    (.82, support_hand + Vector((0, 0, -.10))), (1, support_hand)]
            for i in range(count + 1):
                phase = i / count
                channels = {n: m.copy() for n, m in aim.items()}
                lower = math.sin(math.pi * phase) ** 2
                rotate_world(target, channels, 'Head', (1, 0, 0), .16 * lower)
                reach(target, channels, 'R', firing_hand + Vector((0, .05 * lower, -.16 * lower)))
                for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
                    if t0 <= phase <= t1:
                        weight = (phase - t0) / (t1 - t0)
                        weight = weight * weight * (3 - 2 * weight)
                        reach(target, channels, 'L', Vector(p0).lerp(Vector(p1), weight))
                        break
                samples.append(channels)
        baked.append((name, samples))
        inventory[name] = {'source_pack': 'KayKit Character Animations 1.1', 'source_file': str(path.relative_to(ROOT)),
                           'source_clip': clip, 'frames': count + 1, 'seconds': count / FPS,
                           'modifications': ['Rest-space torso/arm rotation retarget; target limb lengths retained', 'Aim fingers and lower body held; five-frame boundary blends', 'Right arm only; left supports rifle' if side_only else 'Both arms retargeted']}
        if name == 'RifleReload':
            inventory[name]['source_pack'] = 'OPEN BREACH procedural adaptation of Quaternius Toon Shooter'
            inventory[name]['source_file'] = str(TOON.relative_to(ROOT))
            inventory[name]['source_clip'] = 'Idle_Gun_Shoot + original reload key poses'
            inventory[name]['modifications'] = ['Original two-bone IK reload: lower rifle, reach magazine, reach belt, insert, return', 'KayKit Ranged_2H_Reload retarget evaluated and rejected: support-hand contact mismatch', 'Closed fingers and aim lower body retained; 1.6 second cycle']
        for obj in set(bpy.data.objects) - before:
            bpy.data.objects.remove(obj, do_unlink=True)
    target.animation_data_clear()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for name, samples in baked:
        assert samples and all(math.isfinite(value) for channels in samples
                               for matrix in channels.values() for row in matrix for value in row)
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        target.animation_data_create()
        target.animation_data.action = action
        for frame, channels in enumerate(samples):
            for bone in target.pose.bones:
                bone.rotation_mode = 'QUATERNION'
                bone.matrix_basis = channels[bone.name]
                for prop in ['location', 'rotation_quaternion', 'scale']:
                    bone.keyframe_insert(data_path=prop, frame=frame, group=bone.name)
        print('BAKED', name, inventory[name], flush=True)
    assert set(inventory) == REQUIRED
    assert len(target.data.bones) == 62
    for entry in inventory.values():
        entry['source_sha256'] = hashlib.sha256((ROOT / entry['source_file']).read_bytes()).hexdigest()
    target.animation_data_clear()
    for bone in target.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    meshes = [o for o in target_objects if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(o for o in meshes if o.name == 'Swat_Body')
    bpy.ops.object.join()
    target.animation_data_create()
    target.animation_data.action = bpy.data.actions['RifleIdle']
    target.animation_data.action_slot = target.animation_data.action.slots[0]
    bpy.context.scene.frame_set(0)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = target
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_merge_animation='ACTION',
        export_force_sampling=True, export_frame_range=False, export_optimize_animation_size=True,
        export_skins=True, export_all_influences=False, export_def_bones=True,
        export_materials='EXPORT', export_cameras=False, export_lights=False)
    (ROOT / '.tools/asset-sources/cc0-swat-motion-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    print('CC0_MOTION_COMPLETE', OUTPUT, flush=True)


if __name__ == '__main__':
    main()
