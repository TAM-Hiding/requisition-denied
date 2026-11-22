extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	for frame in 6:
		await physics_frame
	var editor: LayoutEditor = facility.get_node("InteractionUI").layout_editor
	var workspace := editor.workspace
	var source := LayoutStorage.read(LayoutReference.PATH)
	check(source.ok and source.records.size() == 26, "The approved export contains its 26 authored records")
	check(workspace.items.size() == 28, "Default hall contains all approved records and two separate supports")
	for original: Dictionary in source.records:
		var current := workspace.record(original.id)
		check(not current.is_empty() and current.position == original.position and current.size == original.size
			and current.yaw == original.yaw and current.properties == original.properties,
			"Approved transform and properties are unchanged for " + original.id)
		if not current.is_empty():
			var converted: bool = original.id in LayoutReference.RACK_IDS
			check(current.type == ("horizontal_stock_rack" if converted else original.type),
				"The two designated rack IDs use their stock-rack type")
			if not converted:
				check(current.name == original.name, "Original display name is retained")
	for id in LayoutReference.RACK_IDS:
		var rack := workspace.items.get(id) as LayoutPlaceholder
		check(rack != null and rack.get_node("PlaceholderCollision").get_child_count() > 6,
			"Rack keeps its original ID and uses open-frame collision")
		var record := workspace.record(id)
		var occupied := LayoutWorkspace.occupied_box(record.type, record.size)
		var rack_frame := Vector3(occupied.position.x, 0.0, 0.0)
		var arm_tip := Vector3(occupied.end.x, 0.0, 0.0)
		var frame_x: float = record.position.x + (rack.basis * rack_frame).x
		var tip_x: float = record.position.x + (rack.basis * arm_tip).x
		var wall_x: float = workspace.hall.get("width") * 0.5
		check(frame_x < wall_x and wall_x - frame_x < 0.04 and tip_x < frame_x - 0.8,
			"Cantilever frame sits by the east wall with its arms projecting inward")
	for id in LayoutReference.DOOR_IDS:
		var marker := workspace.items.get(id) as LayoutPlaceholder
		check(marker != null and not marker.get_node("PlaceholderGeometry").visible,
			"Architectural door supersedes the visual marker outside the editor")
	var saw := workspace.record(LayoutReference.SAW_ID)
	var infeed := workspace.record("rd014c-bandsaw_infeed_stand")
	var outfeed := workspace.record("rd014c-bandsaw_outfeed_support")
	check(not infeed.is_empty() and not outfeed.is_empty() and infeed.position.z < saw.position.z
		and outfeed.position.z > saw.position.z and infeed.position.x == saw.position.x and outfeed.position.x == saw.position.x,
		"Independent stand entities align with the saw feed direction")
	check(infeed.position.z + infeed.size.z / 2.0 < saw.position.z - saw.size.z / 2.0
		and is_equal_approx(infeed.size.z, 0.60), "Compact infeed fits between the rack and the unchanged saw")
	check(is_equal_approx(outfeed.position.z, 6.55) and is_equal_approx(outfeed.size.z, 0.92),
		"The outfeed remains in its original position and dimensions")
	check(is_equal_approx(infeed.size.y, saw.size.y * LayoutCatalog.SAW_BED_TOP)
		and is_equal_approx(outfeed.size.y, infeed.size.y), "Infeed and outfeed tops match the static cutting bed")
	var space := facility.get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	var hallway := workspace.hall
	var ray := PhysicsRayQueryParameters3D.create(hallway.to_global(Vector3(7.0, 1.0, 1.2)),
		hallway.to_global(Vector3(7.0, 1.0, 7.1)), 1)
	check(space.intersect_ray(ray).is_empty(), "Operator lane stays open past stock racks and supports")
	var stock := BoxShape3D.new()
	stock.size = Vector3(0.06, 0.06, 3.40)
	var transfer := PhysicsShapeQueryParameters3D.new()
	transfer.shape = stock
	transfer.collision_mask = 1
	transfer.transform.origin = hallway.to_global(Vector3(8.40, 0.735, 2.72))
	transfer.motion = hallway.global_basis * (Vector3.BACK * 2.63)
	var clearance := space.cast_motion(transfer)
	check(space.intersect_shape(transfer, 1).is_empty() and clearance[0] >= 0.999,
		"A 3.4 m stock proxy clears the low rack tier, infeed, cutting bed, and outfeed")
	var support_ray := PhysicsRayQueryParameters3D.create(hallway.to_global(Vector3(8.25, 1.0, 6.55)),
		hallway.to_global(Vector3(8.25, 0.55, 6.55)), 1)
	var support_hit := space.intersect_ray(support_ray)
	check(not support_hit.is_empty() and support_hit.collider.get_parent() == workspace.items[outfeed.id],
		"The unchanged outfeed still provides a physical support surface")
	var snapshots := workspace.records()
	var reload := LayoutStorage.decode(LayoutStorage.encode(snapshots))
	var issue: String = workspace.replace_all(reload.records) if reload.ok else reload.error
	check(issue.is_empty(), "The complete approved hall reloads successfully: " + issue)
	var unchanged := true
	for record in snapshots:
		var next := workspace.record(record.id)
		unchanged = unchanged and not next.is_empty() and next.position == record.position and next.size == record.size \
			and is_equal_approx(next.yaw, record.yaw) and next.properties == record.properties and next.type == record.type
	check(unchanged, "Schema 1 save-load preserves the approved transforms and IDs")
	var older: Array[Dictionary] = snapshots.duplicate(true)
	for record in older:
		if record.id in LayoutReference.RACK_IDS:
			record.type = "storage_room_marker"
			record.name = "Storage Room Marker"
			record.position = Vector3(7.25, 0, 2.5 if record.id == LayoutReference.RACK_IDS[0] else 5.5)
			record.yaw = 0.0
		elif record.id == infeed.id:
			record.position.z = 2.95
			record.size.z = 0.92
	var old_wire := LayoutStorage.decode(LayoutStorage.encode(older))
	var old_issues := workspace.replace_all(LayoutReference.migrate(old_wire.records))
	check(old_wire.ok and old_issues.is_empty(), "Legacy rack layout still reloads: " + old_issues)
	for id in LayoutReference.RACK_IDS:
		var old_record := workspace.record(id)
		check(old_record.position == Vector3(7.25, 0, 2.5 if id == LayoutReference.RACK_IDS[0] else 5.5)
			and old_record.yaw == 0.0 and old_record.type == "horizontal_stock_rack",
			"Loading a legacy save leaves the supplied rack pose in place")
	facility.queue_free()
	await process_frame
	print("RD-014C approved layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
