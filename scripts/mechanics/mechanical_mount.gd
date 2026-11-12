class_name MechanicalMount
extends Node3D
## A fixed attachment retains the original live body and its children.
@export var definition: MountDefinition
var occupant: MechanicalComponent
var pending: MechanicalComponent

func _ready() -> void:
	if definition != null:
		transform = definition.attachment
		add_to_group(&"mechanical_mounts")

func access_blocker() -> StringName:
	var assembly := get_parent() as MechanicalAssembly
	for dependency in definition.requires_vacant:
		var guard := assembly.mount(dependency)
		if guard == null or is_instance_valid(guard.occupant):
			return dependency
	return &""

func compatibility_error(component: MechanicalComponent) -> String:
	if not is_instance_valid(component) or component.is_ancestor_of(self) or is_instance_valid(component.installed_mount):
		return "Component cannot attach here."
	if is_instance_valid(component.seating_mount) and component.seating_mount != self:
		return "Component is seating at another mount."
	if component.state not in [InteractableObject.State.WORLD, InteractableObject.State.CARRIED]:
		return "Component is controlled by another interaction."
	if is_instance_valid(occupant):
		return "Mount occupied."
	if is_instance_valid(pending) and pending != component:
		return "Mount reserved for installation."
	if definition.connection == null or definition.connection.kind != MechanicalConnection.Kind.FIXED:
		return "This connection type is not simulated."
	if component.profile != null:
		for tag in definition.accepted_tags:
			if component.profile.tags.has(tag):
				return ""
	return "Incompatible component."

func mating_distance_squared(component: MechanicalComponent) -> float:
	if component.profile == null:
		return INF
	return (component.global_transform * component.profile.mating_transform).origin.distance_squared_to(global_position)

func can_acquire(component: MechanicalComponent, gap_squared: float, tuning: Dictionary = {}) -> bool:
	var radius: float = tuning.get("acquisition_distance_m", definition.acquisition_distance)
	return gap_squared <= radius * radius and compatibility_error(component).is_empty() and access_blocker() == &""

func alignment(component: MechanicalComponent, tuning: Dictionary = {}) -> Dictionary:
	var issue := compatibility_error(component)
	if not issue.is_empty():
		return {"distance": INF, "axis": INF, "key": INF, "issue": issue}
	var datum := component.global_transform * component.profile.mating_transform
	var offset := to_local(datum.origin)
	var datum_basis := datum.basis.orthonormalized()
	var socket_basis := global_basis.orthonormalized()
	var axis_error := rad_to_deg(datum_basis.z.angle_to(socket_basis.z))
	var key_error := 180.0
	if axis_error < 179.9:
		var corrected_key := Quaternion(datum_basis.z, socket_basis.z) * datum_basis.x
		key_error = rad_to_deg(corrected_key.angle_to(socket_basis.x))
	var snap: float = tuning.get("snap_distance_m", definition.position_tolerance)
	var axis_tolerance: float = tuning.get("axis_tolerance_degrees", definition.angle_tolerance_degrees)
	var key_tolerance: float = tuning.get("key_rotation_tolerance_degrees", definition.key_tolerance_degrees)
	var blocker := access_blocker()
	if blocker != &"":
		issue = "Clear %s first." % blocker
	elif offset.length() > snap and (offset.z <= 0.0 or offset.z > definition.approach_distance
			or Vector2(offset.x, offset.y).length() > minf(snap, definition.position_tolerance)):
		issue = "Move closer to the mount."
	elif definition.keyed and axis_error > axis_tolerance:
		issue = "Align the insertion axis."
	elif definition.keyed and key_error > key_tolerance:
		issue = "Rotate to align the key."
	elif not definition.keyed and rad_to_deg(_angle_from(datum)) > axis_tolerance:
		issue = "Align the component with the mount."
	return {"distance": offset.length(), "axis": axis_error, "key": key_error, "issue": issue}

func seating_path(component: MechanicalComponent, clearance: PlacementClearance) -> Array[Transform3D]:
	var pose := component.global_transform
	var seat := global_transform * component.profile.mating_transform.affine_inverse()
	var aligned := Transform3D(seat.basis, pose.origin)
	if not clearance.clear(pose) or not clearance.turn_path_clear(pose, aligned):
		return []
	if not clearance.translation_path_clear(aligned, seat):
		return []
	return [pose, aligned, seat]

func installation_error(component: MechanicalComponent, tuning: Dictionary = {}) -> String:
	var issue: String = alignment(component, tuning).issue
	if not issue.is_empty():
		return issue
	var clearance := PlacementClearance.new()
	if not clearance.configure(component) or seating_path(component, clearance).is_empty():
		return "Installation path blocked."
	return ""

func install(component: MechanicalComponent) -> String:
	if is_instance_valid(pending):
		return "Installation in progress."
	var issue := installation_error(component)
	if issue.is_empty():
		_attach(component)
	return issue

func reserve(component: MechanicalComponent) -> bool:
	if is_instance_valid(pending) or not compatibility_error(component).is_empty() or access_blocker() != &"":
		return false
	pending = component
	component.seating_mount = self
	return true

func finish_seating(component: MechanicalComponent) -> bool:
	if pending != component or not compatibility_error(component).is_empty() or access_blocker() != &"":
		return false
	if not (component.global_transform * component.profile.mating_transform).is_equal_approx(global_transform):
		return false
	cancel_seating(component)
	_attach(component)
	return true

func cancel_seating(component: MechanicalComponent) -> void:
	if pending == component:
		pending = null
		if is_instance_valid(component):
			component.seating_mount = null

func _exit_tree() -> void:
	cancel_seating(pending)

## Scene-authored components may start attached before their first physics tick.
func seed(component: MechanicalComponent) -> bool:
	if not compatibility_error(component).is_empty() or access_blocker() != &"" or component.state != InteractableObject.State.WORLD:
		return false
	_attach(component)
	return true

func remove() -> String:
	if not definition.removable:
		return "This mount is secured."
	var blocker := access_blocker()
	if blocker != &"":
		return "Clear %s first." % blocker
	return _detach()

func apply_impact(impact: float) -> bool:
	if not is_instance_valid(occupant) or definition.connection == null:
		return false
	if not definition.connection.fails(impact, occupant.integrity != MechanicalComponent.Integrity.INTACT):
		return false
	match definition.connection.failure_mode:
		MechanicalConnection.FailureMode.DETACH:
			return _detach().is_empty()
	return false

func _angle_from(pose: Transform3D) -> float:
	return pose.basis.orthonormalized().get_rotation_quaternion().angle_to(
		global_basis.orthonormalized().get_rotation_quaternion())

func _attach(component: MechanicalComponent) -> void:
	if not is_instance_valid(component.loose_parent):
		component.loose_parent = component.get_parent() as Node3D
	component.freeze = true
	component.linear_velocity = Vector3.ZERO
	component.angular_velocity = Vector3.ZERO
	component.reparent(self, false)
	component.transform = component.profile.mating_transform.affine_inverse()
	component.state = InteractableObject.State.WORLD
	component.support_carrier = null
	component.installed_mount = self
	occupant = component

func _detach() -> String:
	if not is_instance_valid(occupant):
		return "Mount vacant."
	var component := occupant
	if component.fastened:
		return "Remove freeform fasteners first."
	if not is_instance_valid(component.loose_parent):
		return "Component has no world parent."
	var pose := component.global_transform
	var travel := global_basis * definition.release_offset
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = pose
	motion.motion = travel
	# Existing floor contact may be separated from, but the release sweep must be clear.
	if travel.length_squared() > 0.0 and PhysicsServer3D.body_test_motion(component.get_rid(), motion):
		return "Removal path blocked."
	pose.origin += travel
	occupant = null
	component.installed_mount = null
	component.reparent(component.loose_parent)
	component.global_transform = pose
	component.freeze = component.mobility() == ObjectDefinition.Mobility.FIXED
	component.sleeping = false
	return ""
