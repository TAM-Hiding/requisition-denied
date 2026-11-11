# RD-002 — Object mobility and equipment

## Controls and manual acceptance

Run the project in Godot 4.7.2 on Linux. RD-001 movement, mouse-look, inspection,
Escape/click capture and F3 remain available.

1. Find the wrench on the floor near the middle of the room. Look down and tap
   E (press then release within 0.35 s). Choose Inspect, confirm its description,
   then choose Pick Up. The menu closes and the wrench appears below/right of
   the reticle. Walk and look around; neither the item nor its collider should
   block Otis or obscure the center of the view.
2. Hold E for at least 0.35 s. The wrench disappears into storage. Releasing E
   must not open a context menu. F3 should show no equipped item, one stored
   item and equipment state STOWED. Press 1: the same item returns to HELD,
   storage count becomes zero. Repeat several times and verify no duplication.
3. Press G in open space. The wrench drops, falls and settles on the floor.
   Target it and inspect it again: its ID is unchanged and the inspected-object
   count does not increase. Pick it up again.
4. Face a wall at close range and press G; also look straight down while holding
   it. A blocked drop should keep the wrench equipped and show concise feedback.
   Step away, look at open space and drop successfully.
5. Hold E empty-handed: confirm feedback rather than a menu. Press 1 with empty
   storage or while already equipped: confirm feedback without losing the item.
6. Tap E on the storage crate, then select Move. Walk slowly and turn to push or
   drag it; gravity remains active and it must stop against walls and equipment.
   Tap E or press G to release; Escape also releases it and frees the cursor.
   Walking out of reach, losing line of sight or alt-tabbing should release it.
   The crate never enters storage. Keep the wrench equipped while moving it;
   its identity and HELD state must survive the interaction. It should lower
   smoothly during manipulation and return to NORMAL on release.
7. Inspect the generator and terminal. Neither offers Pick Up or Move. Existing
   unavailable action placeholders remain clearly labeled.
8. With a context menu open, move keys and equipment shortcuts must not manipulate
   items. Close/Escape restores capture. Alt-tab during a partial E gesture, then
   return: the unfinished gesture must not become a tap or a stow.
9. Toggle F3 and verify target, mobility, target state, available actions, target
   distance, inspected-object count, equipped ID, stored count, equipment state,
   environmental manipulation flag, held obstruction and movement speed limit.
   Hide it again for ordinary gameplay.

## Automated validation

Run all suites and startup validation:

```bash
GODOT_BIN=/path/to/godot-4.7.2 tests/validate.sh
```

Run graphical assertions on a Linux display:

```bash
godot --path . --script tests/validate_facility.gd
godot --path . --script tests/validate_mobility.gd
godot --path . --script tests/validate_manipulation_followup.gd
godot --path . --script tests/validate_equipment_poses.gd
godot --path . --script tests/validate_project_configuration.gd
```

The mobility suite covers fixed/movable rejection, runtime mobility changes,
crate motion under bounded physics control and wall collision, the complete
WORLD → HELD → STOWED → HELD → WORLD lifecycle, defensive storage queries,
duplicate requests, full storage feedback, identity preservation, drop clearance,
gravity/floor settling, re-targeting and inspection deduplication. Graphical-only
checks exercise E tap/hold arbitration, 1/G controls, focus cancellation, actual
manipulation follow and release. Headless tests drive the crate's physics goal
directly because a headless display cannot capture a pointer.

`RD_SCREENSHOT=/absolute/path.png` captures the equipped wrench during the
graphical mobility suite. The validation wrapper fails on script/runtime error
messages as well as nonzero exits.

See [final polish and configuration investigation](rd-002-final-polish.md) for
pose tests, verified backends and the clean editor-cycle test.

## Recorded results

Godot **4.7.2.stable.official.ed1daf0bf**, Linux:

- RD-001 regression: 61 headless checks and 63 graphical checks, all passed.
- RD-002 mobility: 59 headless checks and 72 graphical checks, all passed.
- RD-002 follow-up: 43 headless checks and 54 graphical checks, all passed.
- Fresh editor import and 120-frame main-scene startup: passed without script errors.
- Equipped wrench screenshot reviewed for scale, orientation and HUD readability.
- `git diff --check`: passed.

Graphical tests use Xvfb / Mesa llvmpipe with the Dummy audio driver. The virtual
screen reports an unsupported V-Sync warning; physical hardware performance and
input feel are not established by that run.

## Architecture and extension points

- `ObjectDefinition.Mobility`: FIXED, MOVABLE, CARRYABLE, alongside existing IDs,
  mass, description and extensible properties.
- `InteractableObject`: one RigidBody3D implementation with runtime WORLD, HELD,
  STOWED and MOVING states. Fixed instances freeze in static mode. World movable
  and carryable instances use gravity and continuous collision detection.
- `set_mobility()` changes an instance's mobility in WORLD state without rewriting
  its shared definition; a future fastener action can use it. In-flight changes
  are rejected until manipulation ends.
- `InteractionService`: validates world requests against the current ray/range
  and derived actions, then dispatches to equipment. No AI-specific logic.
- `EquipmentController`: one active reference, a separate bounded storage list
  (capacity defaults to one), camera anchor and drop clearance. Environmental
  manipulation belongs to the independent `EnvironmentalManipulation` controller.
  No item is cloned or freed during transitions. Stored list
  queries return a copy. New slots can extend this owner rather than world data.
- Held/stowed bodies are frozen with collision layer/mask zero. Stowed bodies
  remain owned by the equipment container and hidden. Drops return the same
  instance to the scene root, with zero initial velocity and ordinary physics.
- The movable drive only controls horizontal velocity in `_integrate_forces`,
  with configurable speed/acceleration limits. Gravity, contacts and position
  integration remain Godot's responsibility. Otis updates the controller before
  movement and publishes the new goal plus actual-velocity feed-forward after
  movement. Rotation is locked for this simple stable interaction.
  No world-space teleportation drives the crate.
- `InteractionUI`: short/long E arbitration, shared state-aware contextual menu,
  equipment feedback and diagnostics. Pickup and Move close the menu to resume
  walking; Inspect leaves it open.

## Known limitations

One active slot, one stored item by default, no inventory UI, animations or tool
functionality. Objects use primitive models and a single direct child named
`CollisionShape3D` for drop-volume validation. Bodies use world layer 1 and player
layer 2. Carryable objects should have an authored origin suitable for the shared
camera anchor; oversized carryables need their own presentation offsets later.
Held models use collision-aware presentation; a fully obstructed retracted volume
hides the model until clear. Tight retraction may tuck the tool below the viewport.
Drop clearance is checked independently. All interactables have rotation locked,
and moving the crate controls only horizontal motion on the room floor. Otis
moves at a temporary constrained speed while manipulating; normal speed returns
on release. Lost line of sight or excessive reach ends manipulation. Session state
has no persistence. Hardware input feel, alt-tab and performance need a physical
Linux playtest. No combat, throwing, damage, AI, requisitions or crafting is added.
