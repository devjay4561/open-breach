extends SceneTree
func _initialize():
 call_deferred("run")
func run():
 var model=load("res://assets/characters/combat-swat.glb").instantiate();root.add_child(model)
 await process_frame
 var player:AnimationPlayer=model.find_child("AnimationPlayer",true,false)
 var skeleton:Skeleton3D=model.find_child("Skeleton3D",true,false)
 player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var body:int=skeleton.find_bone("Body")
 var meshes=0
 for mesh in model.find_children("*","MeshInstance3D",true,false):
  meshes+=1
 print('MESHES ',meshes,' BONES ',skeleton.get_bone_count())
 for clip in ['RifleWalk','RifleRun','RifleWalkBack','RifleRunBack','RifleStrafeLeft','RifleStrafeRight']:
  player.play(clip);player.seek(0.0,true);player.advance(0.0);skeleton.force_update_all_bone_transforms()
  var start=(skeleton.global_transform*skeleton.get_bone_global_pose(body)).origin
  var max_drift=0.0
  var height_min=100.0;var height_max=-100.0
  for step in range(61):
   player.seek(player.get_animation(clip).length*float(step)/60.0,true);player.advance(0.0);skeleton.force_update_all_bone_transforms()
   var pos=(skeleton.global_transform*skeleton.get_bone_global_pose(body)).origin
   max_drift=maxf(max_drift,Vector2(pos.x-start.x,pos.z-start.z).length())
   await process_frame
   height_min=minf(height_min,pos.y);height_max=maxf(height_max,pos.y)
  print('INPLACE ',clip,' drift=',max_drift,' vertical_bounce=',height_max-height_min)
  assert(max_drift<0.0001)
  assert(height_max-height_min>0.02)
 model.queue_free();quit()
