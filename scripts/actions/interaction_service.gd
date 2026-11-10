class_name InteractionService
extends RefCounted
## Engine-side permission gate, independent of UI and any future AI actor.
func permitted(actor: Node3D, camera: Camera3D, target: InteractableObject, reach: float) -> bool:
	if not is_instance_valid(actor) or not is_instance_valid(camera) or not is_instance_valid(target):
		return false
	if target.definition == null or not actor.is_inside_tree() or not target.is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * reach, 1)
	if actor is CollisionObject3D:
		query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == target

func request(action: StringName, actor: Node3D, camera: Camera3D,
		target: InteractableObject, reach: float, knowledge: PlayerKnowledge) -> Dictionary:
	if not permitted(actor, camera, target, reach):
		return {"ok": false, "message": "Object is no longer within reach or sight."}
	if not target.query_actions().has(action) or action != &"inspect":
		return {"ok": false, "message": "Action unavailable."}
	if knowledge == null:
		return {"ok": false, "message": "No actor knowledge state."}
	var information := target.definition.inspection_information()
	knowledge.record_inspection(target.definition.object_id, information)
	return {"ok": true, "information": information}
