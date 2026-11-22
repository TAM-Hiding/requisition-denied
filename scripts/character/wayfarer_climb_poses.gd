extends RefCounted
## Pose tracks use pitch/yaw/roll for the torso, vertical/forward offsets in
## meters and paired left/right joint pitches in radians. The physical path is
## sampled independently by OtisLocomotion.
const REST := [Vector3.ZERO, Vector2.ZERO, Vector4(0, 0, 0.10, 0.10), Vector4.ZERO]
# Each row is [path fraction, torso angles, hip shift, arms, legs].
# Arms = left shoulder, right shoulder, left elbow, right elbow.
# Legs = left hip, right hip, left knee, right knee.
const TRACKS := [
	[ # Scramble: catch left, pull both knees up, roll over the edge.
		[0.18, Vector3(-0.34, -0.11, 0.04), Vector2(-0.15, 0.08),
			Vector4(1.36, 0.38, 0.26, 0.28), Vector4(0.62, 0.47, -1.12, -0.86)],
		[0.40, Vector3(-0.52, 0.02, 0), Vector2(-0.27, 0.15),
			Vector4(1.46, 1.48, 0.85, 0.60), Vector4(1.18, 1.09, -2.04, -1.92)],
		[0.71, Vector3(-0.70, 0.01, -0.04), Vector2(-0.22, 0.12),
			Vector4(0.82, 0.9, 0.92, 0.82), Vector4(1.58, 1.44, -1.95, -1.86)],
		[0.86, Vector3(-0.41, 0, 0), Vector2(-0.15, 0.05),
			Vector4(0.52, 0.49, 0.42, 0.50), Vector4(0.68, 0.87, -1.34, -1.48)],
	],
	[ # Maintenance hoist: brace with both hands and step over one leg at a time.
		[0.22, Vector3(-0.27, 0, 0), Vector2(-0.19, 0.07),
			Vector4(1.53, 1.49, 0.16, 0.16), Vector4(0.66, 0.66, -1.24, -1.24)],
		[0.46, Vector3(-0.37, 0.03, 0), Vector2(-0.16, 0.11),
			Vector4(1.00, 1.05, 1.42, 1.37), Vector4(0.59, 0.54, -0.95, -0.94)],
		[0.66, Vector3(-0.56, -0.08, 0.12), Vector2(-0.11, 0.18),
			Vector4(0.79, 0.77, 1.0, 1.04), Vector4(1.68, 0.62, -1.87, -1.08)],
		[0.84, Vector3(-0.31, 0.07, -0.08), Vector2(-0.13, 0.08),
			Vector4(0.45, 0.56, 0.52, 0.58), Vector4(0.69, 1.17, -1.27, -1.45)],
	],
	[ # Awkward recovery: right hand first, twist into a late second hand and swing the hips over.
		[0.23, Vector3(-0.22, 0.28, -0.20), Vector2(-0.12, 0.07),
			Vector4(0.33, 1.68, 0.14, 0.34), Vector4(0.32, 0.67, -0.52, -1.13)],
		[0.43, Vector3(-0.28, 0.43, -0.27), Vector2(-0.16, 0.07),
			Vector4(0.74, 1.03, 0.32, 1.34), Vector4(0.92, 1.41, -1.14, -1.82)],
		[0.65, Vector3(-0.61, -0.30, 0.20), Vector2(-0.24, 0.17),
			Vector4(1.30, 0.71, 1.00, 0.96), Vector4(1.68, 1.10, -1.91, -1.75)],
		[0.86, Vector3(-0.38, -0.15, 0.08), Vector2(-0.12, 0.08),
			Vector4(0.62, 0.42, 0.59, 0.39), Vector4(0.83, 0.95, -1.25, -1.35)],
	],
]

static func sample(variant: int, progress: float) -> Array:
	if progress <= 0.0 or progress >= 1.0:
		return REST
	var from := REST
	var start := 0.0
	for key in TRACKS[variant]:
		if progress <= key[0]:
			return interpolate(from, key.slice(1), smoothstep(start, key[0], progress))
		from = key.slice(1)
		start = key[0]
	return interpolate(from, REST, smoothstep(start, 1.0, progress))

static func interpolate(from: Array, to: Array, weight: float) -> Array:
	return [from[0].lerp(to[0], weight), from[1].lerp(to[1], weight),
		from[2].lerp(to[2], weight), from[3].lerp(to[3], weight)]
