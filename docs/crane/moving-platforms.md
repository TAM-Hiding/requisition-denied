# RD-015D · Moving platforms

Otis uses Godot's character sweeps and floor inheritance to ride moving bodies. The rigid solver no longer treats him as an immovable peer for loose world objects and the crane hook. A grounded stance applies Otis's weight, including carried mass, at the floor point. Intentional walking contacts transfer bounded traction at the actual hit point. The response accounts for the surface's linear and angular velocity and the effective mass at the point of contact.

## What the fixtures measured

An occupied 360 kg test deck moved 0.171 m on the merged base under a 1.6 m hoist command. The strap tension implied about 1,550 kg of extra load because the rising body was solving against Otis's kinematic collider. With the new contact path the deck moved 1.578 m, carried Otis up 1.506 m, and supported about 94 kg of additional weight. Taking off from a moving platform inherited its lateral velocity. A separate low lifting point tipped and shed the rider.

The first-person look path pitches the camera node and yaws the character body. The two-bolt cage fixture verified standing contact during broad yaw and near-vertical pitch without measurable swing pumping. The fixture did not independently reproduce the reported camera-only swing increase on the old branch. The new contact path removes rigid-solver reactions to the character's kinematic pose while keeping actual shape clearance, load, and walking contact.

The isolated W12×50 test found shape-derived inertia of about 13.4 kg·m² along the beam and 4,713–4,723 kg·m² across it. The initial off-center angular response matched the applied strap impulse within 1%. A centered strap leaves yaw free to decay naturally. No changes were made to beam inertia, damping, strap physics, or crane tuning.

## Hands-on playtest

1. Build a deck from existing stock and Uni-Bolts, with a lifting point well above the deck center of mass. Rig it, climb onto it at floor level, and raise it slowly while standing toward its center.
2. Walk across the raised deck and observe its balance. Use slow trolley movement and jump to check takeoff momentum. Repeat with a deliberately low lifting point to check that an unstable deck can tip and lose its rider.
3. Add side members to make a cage. While stationary inside, turn through a full circle and look up and down. Compare the swing to standing still. Then walk as a physical comparison.
4. Lift the W12×50 by its center and give it room to yaw. Lower and rerig away from the center to compare gravity-driven rotation. Use the existing remote for timed swing amplification and cancellation.

The tests verify floor riding, jumping, and side contact. A moving member can briefly overlap the character between physics ticks before sweep recovery separates them. Standing on an unsafe lifting point can still tip the load. The original playtest cage and the RTX 3060 are still useful hands-on coverage.

## NVIDIA PRIME offload on Linux

On an existing hybrid-GPU setup with PRIME render offload enabled, launch Godot for this project with:

```sh
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia godot --path .
```

For editor playtesting, add `--editor` and launch the editor the same way. Verify the renderer in Godot's startup output. This process-local launch option is separate from the physics changes. The reported Intel `i915` hang was not diagnosed as a physics failure. [NVIDIA PRIME Render Offload](https://download.nvidia.com/XFree86/Linux-x86_64/530.41.03/README/primerenderoffload.html)
