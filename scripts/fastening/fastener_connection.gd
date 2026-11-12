class_name FastenerConnection
extends MechanicalConnection

var a: PhysicsBody3D
var b: PhysicsBody3D
var id: int
var bolts: Array[InstalledFastener] = []

func other(body: PhysicsBody3D) -> PhysicsBody3D:
	return b if body == a else a

## Equal direct load plus moment distributed by projected spacing about the
## moment axis. Small spacing has a nonzero floor for a single fastener.
func estimate(point: Vector3, force: Vector3) -> void:
	if bolts.is_empty():
		return
	var center := Vector3.ZERO
	for bolt in bolts:
		center += bolt.head()
	center /= bolts.size()
	var moment := (point - center).cross(force)
	var axis := moment.normalized()
	var spread := 0.0
	var radii: Array[float] = []
	for bolt in bolts:
		var radius := (bolt.head() - center).cross(axis).length()
		radii.append(radius)
		spread += radius * radius
	var direct := force.length() / bolts.size()
	var denominator := maxf(spread, bolts.size() * 0.035 * 0.035)
	for index in bolts.size():
		bolts[index].load_estimate = direct + moment.length() * maxf(radii[index], 0.035) / denominator
