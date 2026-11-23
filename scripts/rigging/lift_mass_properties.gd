class_name LiftMassProperties
extends RefCounted
## A cached mass snapshot in the canonical body's local frame.
## World motion is handled on demand by transforming the local center.

enum Confidence { UNKNOWN, ESTIMATED, KNOWN }

class Result:
	extends RefCounted

	var root: PhysicsBody3D
	var members: Array[PhysicsBody3D] = []
	var mass_kg := 0.0
	var local_center := Vector3.ZERO
	var confidence := Confidence.UNKNOWN
	var display_name := ""
	var solver_member_count := 0

	func world_center() -> Vector3:
		return root.to_global(local_center) if is_instance_valid(root) else Vector3.ZERO

	func is_liftable() -> bool:
		if not is_instance_valid(root) or not root is RigidBody3D or root.freeze \
				or root.has_meta(&"no_crane_lift") or solver_member_count != members.size() \
				or not is_finite(mass_kg) or mass_kg <= 0.0 or not is_equal_approx(mass_kg, root.mass):
			return false
		for member in members:
			if not is_instance_valid(member) or member.is_queued_for_deletion() \
					or (member is InteractableObject and (member.state != InteractableObject.State.WORLD \
					or member.mobility() == ObjectDefinition.Mobility.FIXED)):
				return false
		return true

const FIXTURE_PROPERTIES := &"lift_mass_properties"
const ORIGINAL_SOLVER_CENTER := &"rig_original_mass_center"

var _cached: Result
var _system: FasteningSystem
var _topology_revision := -1
var _solver_members: Array[PhysicsBody3D] = []
var _signature: Array = []
var _shape_resources: Array[Shape3D] = []
var _geometry_dirty := false


func resolve(target: PhysicsBody3D) -> Result:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return Result.new()
	var owner := _mount_owner(target)
	var system: FasteningSystem = owner.fastening_system if owner is InteractableObject and owner.fastened else null
	var root := system.physics_root(owner) if is_instance_valid(system) else owner
	if not is_instance_valid(root) or (not root is RigidBody3D and not root.has_meta(FIXTURE_PROPERTIES)) \
			or root.has_meta(&"no_crane_lift"):
		return Result.new()

	var revision := system.topology_revision if is_instance_valid(system) else -1
	if _cached == null or _cached.root != root or _system != system or _topology_revision != revision:
		_solver_members.assign(system.connected_members(root) if is_instance_valid(system) else [root])
		_topology_revision = revision
		_system = system

	var members: Array[PhysicsBody3D] = []
	for member in _solver_members:
		if is_instance_valid(member):
			_collect_mounted(member, members)
	var signature: Array = []
	for member in members:
		signature.append(_component_inputs(root, member, system))
	if _cached != null and _cached.root == root and not _geometry_dirty and _signature == signature:
		return _cached
	_signature = signature
	_cached = _build(root, members, signature)
	return _cached


func _mount_owner(target: PhysicsBody3D) -> PhysicsBody3D:
	var current := target
	while current is MechanicalComponent and is_instance_valid(current.installed_mount):
		var parent := current.installed_mount.get_parent().get_parent() as PhysicsBody3D
		if not is_instance_valid(parent):
			break
		current = parent
	return current


func _collect_mounted(body: PhysicsBody3D, members: Array[PhysicsBody3D]) -> void:
	if members.has(body):
		return
	members.append(body)
	for child in body.get_children():
		if child is MechanicalAssembly:
			for mount in child.get_children():
				if mount is MechanicalMount and is_instance_valid(mount.occupant):
					_collect_mounted(mount.occupant, members)


func _component_inputs(root: PhysicsBody3D, part: PhysicsBody3D, system: FasteningSystem) -> Array:
	var authored: Dictionary = part.get_meta(FIXTURE_PROPERTIES, {})
	var kilograms := 0.0
	var density := 0.0
	var override_center: Variant = authored.get("center")
	var confidence: int = authored.get("confidence", Confidence.KNOWN)
	var size_revision: Array = []
	if part is RigidBody3D:
		kilograms = system.uncombined_mass(part) if is_instance_valid(system) else part.mass
		var solver_center: Dictionary = part.get_meta(ORIGINAL_SOLVER_CENTER,
			{"mode": part.center_of_mass_mode, "center": part.center_of_mass})
		if solver_center.mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
			override_center = solver_center.center
		if part is InteractableObject and part.definition != null:
			var props: Dictionary = part.definition.properties
			override_center = props.get(&"center_of_mass_local", override_center)
			if props.get(&"center_of_mass_estimated", false):
				confidence = Confidence.ESTIMATED
			if part.definition.mass_kg <= 0.0:
				var value: Variant = props.get(&"density_kg_m3", 0.0)
				if value is float or value is int:
					density = float(value)
		for child in part.get_children():
			if child is CollisionShape3D and not child.disabled and child.shape != null \
					and not child.has_meta(&"fastener_body"):
				size_revision.append([child.shape, child.transform])
	else:
		kilograms = authored.get("mass_kg", 0.0)
	var integrity: int = part.integrity if part is MechanicalComponent else 0
	return [part, _relative_transform(root, part), kilograms, density, override_center,
		confidence, integrity, size_revision, authored.get("name", "")]


func _relative_transform(root: PhysicsBody3D, part: PhysicsBody3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var current := part as Node3D
	while current != root and current != null:
		relative = current.transform * relative
		current = current.get_parent_node_3d()
	return relative if current == root else root.global_transform.affine_inverse() * part.global_transform


func _build(root: PhysicsBody3D, members: Array[PhysicsBody3D], inputs: Array) -> Result:
	for resource in _shape_resources:
		resource.changed.disconnect(_on_geometry_changed)
	_shape_resources.clear()
	_geometry_dirty = false
	var result := Result.new()
	result.root = root
	result.members = members
	result.solver_member_count = _solver_members.size()
	result.display_name = String(root.name)
	if root is InteractableObject and root.definition != null:
		result.display_name = root.definition.display_name
	elif not inputs.is_empty() and not String(inputs[0][8]).is_empty():
		result.display_name = inputs[0][8]
	result.confidence = Confidence.KNOWN
	var weighted := Vector3.ZERO
	for input: Array in inputs:
		var sample := _sample_component(input)
		var kilograms: float = sample[0]
		var center: Vector3 = sample[1]
		var relative: Transform3D = input[1]
		if not is_finite(kilograms) or kilograms <= 0.0 or not center.is_finite():
			result.confidence = Confidence.UNKNOWN
			continue
		result.confidence = mini(result.confidence, sample[2])
		weighted += relative * center * kilograms
		result.mass_kg += kilograms
	if result.mass_kg > 0.0 and is_finite(result.mass_kg) and weighted.is_finite():
		result.local_center = weighted / result.mass_kg
	else:
		result.mass_kg = 0.0
		result.confidence = Confidence.UNKNOWN
	return result


func _sample_component(input: Array) -> Array:
	var kilograms: float = input[2]
	var density: float = input[3]
	var authored: Variant = input[4]
	var confidence: int = input[5]
	var volume := 0.0
	var geometric_moment := Vector3.ZERO
	for geometry: Array in input[7]:
		var shape: Shape3D = geometry[0]
		if not _shape_resources.has(shape):
			_shape_resources.append(shape)
			shape.changed.connect(_on_geometry_changed)
		if authored is Vector3 and density <= 0.0:
			continue
		var pose: Transform3D = geometry[1]
		var measure := _shape_measure(shape)
		var weighted_volume: float = measure[0] * absf(pose.basis.determinant())
		volume += weighted_volume
		var center: Vector3 = measure[1]
		geometric_moment += (pose * center) * weighted_volume
	if is_finite(density) and density > 0.0 and volume > 0.0:
		# Estimates can be inspected before a generator supplies a matching runtime mass.
		kilograms = density * volume
		confidence = Confidence.ESTIMATED
	if authored is Vector3 and authored.is_finite():
		return [kilograms, authored, confidence]
	if volume > 0.0:
		return [kilograms, geometric_moment / volume, Confidence.ESTIMATED]
	return [kilograms, Vector3.ZERO, Confidence.UNKNOWN]


func _shape_measure(shape: Shape3D) -> Array:
	if shape is BoxShape3D:
		return [shape.size.x * shape.size.y * shape.size.z, Vector3.ZERO]
	if shape is SphereShape3D:
		return [4.0 / 3.0 * PI * pow(shape.radius, 3), Vector3.ZERO]
	if shape is CylinderShape3D:
		return [PI * shape.radius * shape.radius * shape.height, Vector3.ZERO]
	if shape is CapsuleShape3D:
		var volume: float = PI * shape.radius * shape.radius * maxf(0.0, shape.height - 2.0 * shape.radius)
		return [volume + 4.0 / 3.0 * PI * pow(shape.radius, 3), Vector3.ZERO]
	var debug_mesh := shape.get_debug_mesh()
	if debug_mesh != null:
		var bounds := debug_mesh.get_aabb()
		return [bounds.get_volume(), bounds.get_center()]
	return [0.0, Vector3.ZERO]


func _on_geometry_changed() -> void:
	_geometry_dirty = true
