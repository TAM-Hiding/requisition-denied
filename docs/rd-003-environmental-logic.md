# RD-003 — Environmental Signals & Physical Load Systems

The east side of the existing chamber has a flush load platform, an 8 kg
calibration block and a vertical steel gate. Yellow markings link the platform
to the gate. The gate controls passage through its frame.

## Signals and actuation

The plate publishes a boolean through an EnvironmentalSignal node with a stable
source ID. The BarrierController has an exported list of inputs and an actuator
reference. The chamber configures these references when it builds the fixtures.
The controller reads the current value on connection and requires every input
to be present and active. An empty list, explicit disconnection or source exit
requests closure. Source exit clears the corresponding slot and disconnects its
callbacks. Identical source values produce no new notification.

The gate takes 1.5 seconds for full travel. Each physics step sweeps its solid
body toward the requested position before moving it. The visible panel and
collider share that body. A hit pauses travel in BLOCKED at its last clear
position. The gate retries on the next physics step and follows the latest
request from its current position. The same policy applies in either direction.

## Supported mass

The platform shares the continuous chamber floor collider so the crate can
slide across the plate boundary. An inspection-only collider identifies the
platform. The sensor defines its load-bearing region on that floor and uses
a tall Area3D to shortlist candidate bodies.

Each candidate must have a consistent upward-facing support within a short
distance of the bottom of its collision bounds. A center probe and four inset
probes must agree on the support body. Floor hits count only inside the plate
region. A chain of such contacts can end on the plate through other bodies.
The sensor sums each candidate's mass once. Otis contributes his configurable
80 kg only when grounded and supported through the same tests. The platform
needs at least 40 kg continuously for 0.4 seconds to activate. It releases
below 37 kg.

This is a supported-mass estimate for stable stacks with simple collision
shapes. It can undercount edge-balanced, irregular or partly supported loads.
The sensor does not apportion mass among supports, measure contact forces or
count bodies beyond its detection volume. The deck depression is visual so
the floor stays flush. As with other scene fixtures, author gate endpoints and
its initial position with clear space.

## Manual playtest

1. Run the chamber in Godot 4.7.2. Toggle F3 and inspect the striped platform.
   Confirm its ID, 40 kg threshold, measured load and inactive state.
2. Use Move on the crate to slide it onto the platform and release. F3 should
   show about 35 kg, with the gate closed.
3. Pick up the 8 kg calibration block. From just off the platform, aim level
   over the crate and press G to drop it on top. A stable 43 kg opens the gate
   after the dwell. Placing both on the platform side by side also works.
   The wrench contributes roughly 0.6 kg when supported and alone cannot make
   up the crate's shortfall.
4. Remove the block. Watch the gate close. Step onto the plate and wait for
   activation. Check the red/green indicator and gate collision in each state.
5. To test obstruction on your own, hold the gate open with the 43 kg stack.
   Pick up the wrench and drop it in the gate's travel path while
   the stack still holds the gate open. Return and remove the calibration
   block. The gate should stop above the wrench and finish closing when the
   wrench is removed.
6. Check equipment lowering during crate movement, retraction near the gate
   and inspection history. F3 prints meaningful signal/gate transitions when
   enabled.

Run the headless suite with `GODOT_BIN=godot4 tests/validate.sh`. Run the
environment test with a real display using
`godot4 --path . --script tests/validate_environment.gd`.
