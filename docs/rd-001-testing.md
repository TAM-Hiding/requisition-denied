# RD-001 testing

## Automated scope

`tests/validate.sh` runs Godot import, engine integration checks, and a main-scene
startup smoke test. The suite checks:

- Configured main scene, F3 binding, loadable definitions and unique IDs.
- Per-object action queries and isolation from accidental query mutation.
- Actual physics-ray targeting of crate, generator and terminal.
- Shared menu opening, inspect presentation and player-control locking.
- Inspection acquisition, duplicate prevention and per-actor knowledge isolation.
- Snapshot ownership: returned records and world edits cannot alter learned facts.
- Rejection of unavailable actions, out-of-range stale menus and wall occlusion.
- Collision sweeps against floor, ceiling, all four walls and all three objects.
- Diagnostics toggle and Escape/left-click handling.

Headless mode cannot assert actual pointer capture; the graphical suite checks
that, plus forward movement and mouse-look. This is a code-driven integration
suite, not a substitute for evaluating feel on physical hardware.

## Recorded results

Validated with Godot **4.7.2.stable.official.ed1daf0bf** on Linux:

- Headless import and startup smoke: passed, no script/runtime errors.
- Headless integration suite: **61 checks, 0 failures**.
- Graphical integration suite on Xvfb / Mesa llvmpipe: **63 checks, 0 failures**.
- Rendered inspection screenshot visually reviewed for room visibility, correct
  object information and readable menu layout.
- `git diff --check`: passed.

The virtual display does not establish real gaming-hardware performance or
physical input feel. The following manual walkthrough remains for that purpose.

## Manual acceptance walkthrough

1. Open in Godot 4.7.2 on Linux; run with F5. Confirm an enclosed lit chamber,
   visible crate, generator, wall terminal and unobtrusive controls legend.
2. Move with each WASD key, including diagonals. Look horizontally and vertically.
   Confirm a comfortable speed, pitch clamp and no rolling or camera clipping
   through walls. Walk into all room walls and objects; confirm collision.
3. Press Escape. Confirm free pointer and suspended walking/look. Left-click in
   the game to recapture and resume. Alt-tab away; confirm capture is released;
   return and click to resume.
4. Approach each object. Aim at its visible geometry within 3 m. Confirm the
   reticle changes color and shows its name and `[E]`. Aim at empty walls or
   step back beyond reach; confirm the prompt disappears.
5. Press E on the crate. Confirm mouse release and frozen movement/look. Click
   Inspect (or select with keyboard and Enter). Confirm the correct name and
   description appear. Close with the button; repeat using Escape. Both should
   restore capture without a stray camera turn.
6. Repeat for generator and terminal. Confirm each has its own text and explicitly
   unavailable extra actions. Clicking UI must not recapture or rotate the view.
7. Toggle F3. Confirm target ID, surface distance, available action IDs and the
   count of inspected objects. Inspect one object repeatedly: count stays fixed.
   Inspect all three: count reaches 3. Toggle F3 off: normal HUD remains uncluttered.
8. Restart. Confirm knowledge count resets. No network or AI service is required.
9. Resize the window; confirm the menu, targeting and help remain usable at the
   intended 1280 × 720 baseline.

## Known limitations

- Placeholder primitive art, static objects and simple unshadowed industrial lighting.
- The room is assembled at runtime by `facility.gd`; run the scene to view it.
- No inventory, carrying, damage, machinery simulation, AI, requisitions or persistence.
- Inspect learns displayed name and description only. Mass/condition remain world data.
- Generator activation and terminal Records access are disabled future-action examples.
- No jump, sprint, crouch, rebinding UI or settings UI; controller parameters are exports.
- Hardware feel, performance and alt-tab behavior still require manual Linux playtesting.
