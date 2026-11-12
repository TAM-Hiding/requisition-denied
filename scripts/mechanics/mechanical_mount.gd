class_name MechanicalMount
extends Node3D
## A fixed attachment retains the original live body and its children.
@export var definition: MountDefinition
var occupant: MechanicalComponent

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
	if component.state not in [InteractableObject.State.WORLD, InteractableObject.State.CARRIED]:
		return "Component is controlled by another interaction."
	if is_instance_valid(occupant):
		return "Mount occupied."
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

func can_acquire(component: MechanicalComponent, gap_squared: float) -> bool:
	var radius := maxf(definition.acquisition_distance, Vector2(definition.approach_distance, definition.position_tolerance).length())
	return gap_squared <= radius * radius and compatibility_error(component).is_empty() and access_blocker() == &""

func alignment_error(component: MechanicalComponent) -> String:
	var issue := compatibility_error(component)
	if not issue.is_empty():
		return issue
	var blocker := access_blocker()
	if blocker != &"":
		return "Clear %s first." % blocker
	var datum := component.global_transform * component.profile.mating_transform
	var offset := to_local(datum.origin)
	var tolerance := definition.position_tolerance
	if offset.length_squared() > tolerance * tolerance:
		if offset.z <= 0.0 or offset.z > definition.approach_distance:
			return "Move closer to the mount."
		if Vector2(offset.x, offset.y).length_squared() > tolerance * tolerance:
			return "Center the component on the mount."
	if _angle_from(datum) > deg_to_rad(definition.angle_tolerance_degrees):
		return "Align the component with the mount."
	return ""

func installation_error(component: MechanicalComponent) -> String:
	var issue := alignment_error(component)
	if not issue.is_empty():
		return issue
	var clearance := PlacementClearance.new()
	var pose := component.global_transform
	var destination := global_transform * component.profile.mating_transform.affine_inverse()
	var aligned := Transform3D(destination.basis, pose.origin)
	var motion := destination.origin - pose.origin
	var turn := pose.basis.orthonormalized().get_rotation_quaternion().angle_to(
		destination.basis.orthonormalized().get_rotation_quaternion())
	if (not clearance.configure(component) or not clearance.clear(pose)
			or not clearance.rotation_clear(pose, aligned, turn)
			or not clearance.slide(aligned, motion).origin.is_equal_approx(destination.origin)):
		return "Installation path blocked."
	return ""

func install(component: MechanicalComponent) -> String:
	var issue := installation_error(component)
	if issue.is_empty():
		_attach(component)
	return issue

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
