class_name InstalledFastener
extends RefCounted

enum State { RECOVERED, INSTALLED, FAILED }
var id: int
var grade: FastenerGrade
var a: PhysicsBody3D
var b: PhysicsBody3D
var local_a: Vector3
var local_b: Vector3
var local_orientation: Basis
var state := State.RECOVERED
var load_estimate := 0.0
var visual: Node3D

func recoverable() -> bool:
	return state != State.FAILED

func head() -> Vector3:
	return a.to_global(local_a)
