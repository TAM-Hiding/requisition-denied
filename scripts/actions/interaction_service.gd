class_name InteractionService
extends RefCounted
## Engine-side permission gate, independent of UI and any future AI actor.
func permitted(actor: Node3D, camera: Camera3D, target: InteractableObject, reach: float) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(camera) or not is_instance_valid(target):
		return false
	if target.definition == null or not actor.is_inside_tree() or not target.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * reach, 5)
	if actor is CollisionObject3D:
		query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == target

func request(action: StringName, actor: Node3D, camera: Camera3D,
		target: InteractableObject, reach: float, knowledge: PlayerKnowledge) -> Dictionary:
	if not permitted(actor, camera, target, reach):
		return {"ok": false, "message": "Object is no longer within reach or sight."}
	if not target.query_actions().has(action):
		return {"ok": false, "message": "Action unavailable."}
	if action in [&"pick_up", &"move"]:
		if not actor is OtisController:
			return {"ok": false, "message": "Actor has no equipment controller."}
		if actor.placement.is_active():
			return {"ok": false, "message": "Place or cancel the current object first."}
		if action == &"pick_up":
			return actor.equipment.pick_up(target)
		return {"ok": true} if actor.placement.begin_world(target) else {"ok": false, "message": "Cannot move this object from here."}
	if action != &"inspect":
		return {"ok": false, "message": "Action unavailable."}
	if knowledge == null:
		return {"ok": false, "message": "No actor knowledge state."}
	var information := target.inspection_information()
	knowledge.record_inspection(target.definition.object_id, information)
	return {"ok": true, "information": information}

func request_actor_action(action: StringName, actor: OtisController) -> Dictionary:
	if not is_instance_valid(actor) or actor.equipment == null or not actor.controls_enabled:
		return {"ok": false, "message": "Equipment unavailable."}
	if actor.placement.is_active():
		return {"ok": false, "message": "Place or cancel the current object first."}
	match action:
		&"stow": return actor.equipment.stow()
		&"equip_first": return actor.equipment.equip_first()
		&"drop": return actor.equipment.drop()
	return {"ok": false, "message": "Action unavailable."}
