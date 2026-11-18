class_name InventoryContainer
extends Node
signal changed
var definition: ContainerDefinition
var accessible := true
## Optional future physical packing gate: (InventoryItem) -> rejection string.
var packing_validator: Callable
var _records: Array[InventoryItem] = []

func _prune_deleted() -> void:
	_records = _records.filter(func(record: InventoryItem) -> bool: return is_instance_valid(record.body))


func records() -> Array[InventoryItem]:
	_prune_deleted()
	return _records.duplicate()

func items() -> Array[InteractableObject]:
	var result: Array[InteractableObject] = []
	for record in _records:
		if is_instance_valid(record.body):
			result.append(record.body)
	return result

func contains(item: InteractableObject) -> bool:
	return items().has(item)

func mass_kg() -> float:
	var total := 0.0
	for item in items():
		total += item.mass
	return total

func volume_m3() -> float:
	var total := 0.0
	for record in _records:
		if is_instance_valid(record.body):
			total += record.volume_m3()
	return total

func admission(item: InteractableObject, outgoing: InteractableObject = null) -> String:
	_prune_deleted()
	if not accessible or not is_inside_tree():
		return "Container inaccessible."
	if definition == null or definition.container_id.is_empty() or not is_finite(definition.capacity_m3) or not is_finite(definition.maximum_mass_kg) or definition.capacity_m3 < 0.0 or definition.maximum_mass_kg < 0.0:
		return "Container configuration unavailable."
	if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion() \
			or item.definition == null or item.definition.object_id.is_empty():
		return "Item identity unavailable."
	if item.storage_owner != null or contains(item):
		return "Item already belongs to a container."
	if item.fastened or item.mobility() == ObjectDefinition.Mobility.FIXED:
		return "Fixed equipment and connected assemblies cannot be stored."
	if item.state not in [InteractableObject.State.WORLD, InteractableObject.State.HELD]:
		return "Finish manipulating this object before storing it."
	for entry in _records:
		if entry.body != outgoing and entry.body.definition.object_id == item.definition.object_id:
			return "Duplicate item identity."
	var record := InventoryItem.from_body(item)
	var size := record.dimensions()
	if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0:
		return "Item collision dimensions unavailable."
	var item_axes := [size.x, size.y, size.z]
	var opening := [definition.insertion_dimensions.x, definition.insertion_dimensions.y, definition.insertion_dimensions.z]
	item_axes.sort()
	opening.sort()
	for index in 3:
		if not is_finite(opening[index]) or item_axes[index] > opening[index] + 0.000001:
			return "Item dimensions exceed the container opening."
	var mass := mass_kg() - (outgoing.mass if contains(outgoing) else 0.0) + item.mass
	if not is_finite(item.mass) or item.mass <= 0 or mass > definition.maximum_mass_kg + 0.000001:
		return "Container structural mass rating exceeded."
	var volume := volume_m3() + record.volume_m3()
	if contains(outgoing):
		volume -= InventoryItem.from_body(outgoing).volume_m3()
	if volume > definition.capacity_m3 + 0.000001:
		return "Container volume capacity exceeded."
	if packing_validator.is_valid():
		var issue: String = packing_validator.call(record)
		if not issue.is_empty():
			return issue
	if definition.physical_packing:
		var candidates: Array[InventoryItem] = []
		for existing in records():
			if existing.body != outgoing:
				candidates.append(existing)
		candidates.append(record)
		if ContainerPacking.plan(candidates, definition.insertion_dimensions).size() != candidates.size():
			return "No reliable physical placement in the container."
	return ""

func insert(item: InteractableObject) -> String:
	var issue := admission(item)
	if not issue.is_empty():
		return issue
	if item.equipment_owner != null:
		return "Use equipment Unequip to transfer this item."
	commit_insert(item)
	changed.emit()
	return ""

## Transfer coordinator validates before committing; commits never yield.
func commit_insert(item: InteractableObject) -> void:
	item.storage_owner = self
	item.state = InteractableObject.State.STOWED
	item.freeze = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.collision_layer = 0
	item.collision_mask = 0
	item.top_level = false
	item.reparent(self)
	item.hide()
	item.process_mode = Node.PROCESS_MODE_DISABLED
	_records.append(InventoryItem.from_body(item))
	initialize_packing()

func commit_remove(item: InteractableObject) -> void:
	for record in _records:
		if record.body == item:
			_records.erase(record)
			break
	item.storage_owner = null
	item.process_mode = Node.PROCESS_MODE_INHERIT

func initialize_packing() -> bool:
	if not definition.physical_packing or _records.is_empty():
		return true
	var poses := ContainerPacking.plan(records(), definition.insertion_dimensions)
	if poses.size() != _records.size():
		return false
	for record: InventoryItem in poses:
		record.internal_pose = poses[record]
		record.packed = true
	return true

func fullness() -> StringName:
	var ratio := volume_m3() / maxf(definition.capacity_m3, 0.000001)
	if ratio <= 0:
		return &"empty"
	if ratio < 0.65:
		return &"partially_full"
	return &"full" if ratio < 0.9 else &"bulging"

func snapshot() -> Dictionary:
	_prune_deleted()
	var entries: Array[Dictionary] = []
	for record in _records:
		entries.append(record.snapshot())
	return {"version": 1, "container_id": String(definition.container_id),
		"type": String(definition.container_type), "items": entries}

## Restores a manifest against a live object registry. World save/load will
## supply that registry. No generic objects are created from inventory data.
func restore_manifest(data: Dictionary, registry: Dictionary) -> String:
	_prune_deleted()
	if not accessible or not is_inside_tree() or definition == null \
			or not is_finite(definition.maximum_mass_kg) or not is_finite(definition.capacity_m3):
		return "Container inaccessible."
	if data.get("version") != 1 or data.get("container_id") != String(definition.container_id) or not data.get("items") is Array:
		return "Unsupported inventory manifest."
	var staged: Array[InventoryItem] = []
	var seen := {}
	var total_mass := 0.0
	var total_volume := 0.0
	for entry in data.items:
		if not entry is Dictionary or not entry.get("item_id") is String:
			return "Invalid item record."
		var id: String = entry.item_id
		var item := registry.get(id) as InteractableObject
		if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion() \
				or seen.has(id) or (item.storage_owner != self and item.storage_owner != null) \
				or item.equipment_owner != null or item.fastened \
				or (item.state == InteractableObject.State.STOWED and item.storage_owner != self) \
				or item.state not in [InteractableObject.State.WORLD, InteractableObject.State.STOWED]:
			return "Invalid or conflicting inventory ownership."
		if item.definition == null or String(item.definition.object_id) != id or item.mobility() == ObjectDefinition.Mobility.FIXED:
			return "Invalid item identity."
		var pose: Variant = InventoryItem.parse_pose(entry.get("internal_pose"))
		var record := InventoryItem.from_body(item)
		if pose == null or entry.get("gameplay") != InventoryItem.serialized_state(item):
			return "Manifest requires world-state restoration before inventory resolution."
		var dims := record.dimensions()
		var axes := [dims.x, dims.y, dims.z]
		var opening := [definition.insertion_dimensions.x, definition.insertion_dimensions.y, definition.insertion_dimensions.z]
		axes.sort()
		opening.sort()
		for index in 3:
			if axes[index] <= 0 or axes[index] > opening[index]:
				return "Stored dimensions exceed container constraints."
		if packing_validator.is_valid():
			var issue: String = packing_validator.call(record)
			if not issue.is_empty():
				return issue
		if not is_finite(item.mass) or item.mass <= 0:
			return "Invalid item mass."
		total_mass += item.mass
		total_volume += record.volume_m3()
		if total_mass > definition.maximum_mass_kg or total_volume > definition.capacity_m3:
			return "Manifest exceeds container capacity."
		record.internal_pose = pose
		record.packed = entry.get("packed", false)
		staged.append(record)
		seen[id] = true
	if definition.physical_packing:
		var poses := ContainerPacking.plan(staged, definition.insertion_dimensions)
		if poses.size() != staged.size():
			return "Manifest has no reliable physical arrangement."
		for record: InventoryItem in poses:
			record.internal_pose = poses[record]
			record.packed = true
	# Existing contents cannot disappear through a partial manifest.
	for record in _records:
		if not seen.has(String(record.body.definition.object_id)):
			return "Manifest omits an owned item."
	var packed_poses := {}
	for record in staged:
		packed_poses[record] = record.internal_pose
		if record.body.storage_owner == null:
			commit_insert(record.body)
	_records = staged
	for record in staged:
		record.internal_pose = packed_poses[record]
	changed.emit()
	return ""
