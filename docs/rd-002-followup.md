# RD-002 follow-up: held occupancy and stable manipulation

## Root cause and measurements

The original player target speed was 4 m/s; the crate's horizontal drive capped
at 2.5 m/s. Its proportional position correction also needed tracking error to
produce motion. The actor kept walking independently, so the actor caught up
with the crate and introduced collision corrections. The target distance was
fixed after a 3D-distance clamp to 1.5–2.5 m, without accounting for collider
sizes. The equipment child updated the goal after the actor's movement; there
was no explicit before/after movement coordination. The distance was not being
repeatedly increased, and there was no second explicit force controller.

A reproducible 100-frame forward-push run in Godot 4.7.2, from the same 2.2 m
starting separation, measured:

| Metric | Original PR head | Follow-up |
| --- | ---: | ---: |
| Maximum player speed | 4.000 m/s | 1.375 m/s |
| Minimum horizontal center separation | 0.989 m | 2.149 m |
| Player/crate slide contacts | 4 | 0 |
| Crate backwards steps over 5 mm | 0 | 0 |

This reproduces the unwanted player contact underlying the reported stutter;
it does not claim every possible oscillation pattern was reproduced. The new
regression also continues pushing into a wall and checks collision, separation,
unchanged anchor distance, held identity and normal-speed restoration.

## Changes

`EnvironmentalManipulation` owns the active environmental object independently
of `EquipmentController`. The actor can keep, retrieve or stow equipment without
changing environmental ownership. Existing E/G/Escape release behavior stays:
G releases an active manipulation first, and can drop the held item afterward.

The controller captures one intended horizontal distance, with conservative
radii derived from actor/object collision shapes and a clearance/tracking margin.
It never ratchets this distance from body contacts. During manipulation only,
Otis's speed is capped to 55% of the object's configured movement capability and
acceleration is limited too. Radial velocity limits prevent closing inside the
minimum separation or walking away from a blocked dragged object. Goal rotation
is bounded relative to the object's current direction so a sudden turn does not
request a straight pull through the player's body.

Otis validates manipulation before walking and updates the goal afterward using
actual movement velocity as feed-forward. The rigid body's bounded velocity
controller still leaves contacts, gravity and position integration to Godot.
No collision exceptions disable player/crate or wall/object collision. Stopping
manipulation restores normal speed without rewriting Otis's configured speed.

`HeldItemProfile` supplies a per-item Shape3D envelope, local envelope transform,
camera-relative retracted position, margin and restoration speed. The wrench's
Resource authors a box envelope; other items can supply a capsule/sphere/box,
or fall back to their existing collision shape. `HeldItemPresentation` keeps
the existing camera anchor and frozen/layer-zero held object architecture.

Before each rendered frame it checks initial and final volumes and sweeps toward
the normal pose. A conservative enclosing sphere guards inter-frame travel and
rotation changes. Obstruction clamps retraction immediately; clearance restores
extension smoothly. The conservative outward bound also avoids repeated
restore/retract cycles. If even the retracted volume is blocked, presentation
hides until clear, preserving HELD ownership. No forces, damage, camera motion,
player displacement or rigid-body feedback loop is introduced.

## Manual follow-up checks

1. Pick up the wrench. Approach all four walls, the generator and the crate from
   several angles. It should retract before penetrating solid geometry. Back
   away and confirm smooth restoration, without repeated bobbing while still.
2. Stand beside an obstacle and turn/pitch quickly through it. Check both slow
   and fast mouse movements and diagonals while walking. Otis's movement/look
   must remain controlled with no camera kick or equipment impulses.
3. Inspect the crate while holding the wrench, then Move. Verify the wrench
   stays HELD. Push forward slowly, then hold W for several seconds. Otis should
   follow at deliberate speed, maintaining a stable gap. Repeat against walls,
   the generator, and while dragging backward or turning.
4. Release with E, G or Escape. The wrench must remain equipped. Normal walking
   speed must return immediately as the effective limit is removed. Check
   stow/retrieve/drop afterward; G while already moving releases the crate first.
5. Repeat the confirmed placement tests: drop on the floor, crate top and
   generator top, and attempt blocked wall/fixture drops. Verify original item
   identity, ordinary physics, inspection and knowledge deduplication.
6. Alt-tab during a push or partial E gesture. Return and recapture the cursor.
   Check release/cancellation behavior and F3 obstruction/speed diagnostics.

## Validation and limitations

Godot 4.7.2 on Linux: RD-001 regression 61 headless / 63 graphical checks;
RD-002 regression 59 / 72; follow-up 43 / 54; all passed. Headless import and
120-frame startup passed without script/runtime errors. Graphical tests used
Xvfb / Mesa llvmpipe and Dummy audio; only the existing unsupported V-Sync
warning appeared. There were no new physics warnings. The near-wall held view
was visually reviewed.

The envelope is conservative and can retract earlier than the exact mesh would
require. Authors must enclose their models with the configured profile; this
is not exact animated-mesh collision. Strong retraction can tuck the item out
of view; complete obstruction temporarily hides it. The camera itself never
moves to accommodate equipment. The current floor interaction keeps object
rotation locked and uses horizontal drive; steep terrain/advanced grabbing are
outside this work order. Physical mouse feel, other frame rates and hardware
performance still need a manual Linux playtest. Inventory expansion, force
transfer, throwing, combat and damage remain deferred.
