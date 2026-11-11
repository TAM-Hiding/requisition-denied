# RD-002 final polish: poses, retraction and stable configuration

## Equipment presentation

`HeldItemPresentation.Pose` supports NORMAL and LOWERED independently of WORLD /
HELD / STOWED ownership. Environmental manipulation emits a pose request when
it begins and another on release; Otis connects these to presentation. Neither
action knows the crate's identity, and ordinary inspection requests no pose.

The per-item `HeldItemProfile` authors a lowered camera-space offset and an
exponential transition rate. The wrench moves toward the bottom-right during
manipulation and smoothly returns afterward. Requests can reverse mid-transition
without detaching, stowing or cloning the item. Pose requests also survive while
no item is shown, so retrieval uses the appropriate presentation context.

Retraction now starts from the current interpolated pose and travels primarily
backward in camera space. Default elbow travel is 0.48 m backward with only
0.015 m downward movement and no lateral movement. A front-wall test verifies
that camera-space X stays within 1 cm of its normal offset. Sideways correction
is bounded to 0.22 m by default and used only when backward-only clearance is
blocked. All these values belong to the item profile, not an object name check.

The system can shorten backward travel if an obstacle behind the elbow blocks
the preferred endpoint while a more extended pose remains clear. Anticipation
margin starts retraction early, ordinary travel interpolates, and lateral
correction eases back after clearance returns. Swept volumes and final volume
checks remain authoritative in both poses. Sudden unsafe movement can still
force an immediate safety clamp; if no tested pose is clear, the model hides
until clearance returns. Neither the camera nor player body is displaced.

## Configuration rewrite investigation

The exact target engine was used: **4.7.2.stable.official.ed1daf0bf**.
The checked-in file used valid but hand-authored, noncanonical formatting.
Calling the engine's settings serializer reproduced the reported diff:

- `[input]` is written before `[physics]` and `[rendering]` in canonical order.
- Compact InputEventKey objects expand into the engine's complete serialized
  property representation, including physical keycodes and default fields.
- The explicit Jolt and renderer settings are retained at the bottom of the
  complete diff. Their removal from their earlier location is a section move,
  not evidence that these settings were discarded or unsupported.

No gameplay script writes ProjectSettings, and there is no editor plugin in the
shipped project changing them. No version mismatch or unsupported setting was
needed to reproduce this behavior. The engine-normalized representation is now
committed. No physics, renderer, color or physical-key binding value changed.

### Runtime backend verification

The active backend was checked using instantiated physics states, not merely
configuration text or the generic PhysicsServer3D singleton's class name:

| Runtime observation | Result |
| --- | --- |
| JoltPhysicsServer3D class available | Yes |
| Active world's direct-space state | JoltPhysicsDirectSpaceState3D |
| Created body's direct state in that world | JoltPhysicsDirectBodyState3D |
| RenderingServer current rendering method | gl_compatibility |
| RenderingServer current rendering driver | opengl3 |
| Graphical test adapter | Mesa llvmpipe (OpenGL 4.5) |

`tests/validate_project_configuration.gd` asserts these observations, physical
bindings, the pinned version and a byte-identical engine serialization round
trip without writing to the tracked configuration.

### Editor stability test

`tests/validate_editor_configuration.py` copies the project into a disposable
Git checkout, enables a temporary automation plugin there, imports and
normalizes that harness's additional setting, and records a clean baseline.
The plugin drives the real editor through public EditorInterface methods:
open -> save settings -> run main scene -> stop game -> close editor.
The test then compares the configuration bytes and checks the entire Git status.

**Result: game ran and stopped; project.godot unchanged; Git status clean.**
The temporary plugin is not enabled in the real project. The real project also
passes the configuration round-trip check independently without that plugin.

To repeat on a graphical Linux session:

```bash
GODOT_BIN=godot4 python3 tests/validate_editor_configuration.py
```

For a direct manual confirmation, start with `git status --short` empty, open
`project.godot` in Godot 4.7.2, run with F5, stop with F8, close the editor, and
run `git status --short` again. No project.godot change is expected.

## Results

| Suite | Headless checks | Graphical checks | Failures |
| --- | ---: | ---: | ---: |
| RD-001 regression | 61 | 63 | 0 |
| RD-002 mobility | 59 | 72 | 0 |
| RD-002 first follow-up | 43 | 54 | 0 |
| Equipment poses | 38 | 38 | 0 |
| Project configuration/backends | 16 | 16 | 0 |

Editor import, 120-frame main-scene startup, clean editor cycle and
`git diff --check` passed. Gameplay suites emitted no script errors or new physics
warnings. The lowered view was rendered and reviewed. Forward-push regression
remains at zero player/crate slide contacts, a 2.149 m minimum gap and 1.375 m/s
maximum player speed during the 100-frame measured run.

## Manual acceptance

1. Pick up the wrench. Approach a front wall slowly: it should move backward
   along its equipment position rather than slide toward the reticle. Test
   side walls, corners and the generator, then back away to check restoration.
2. Turn and pitch rapidly while walking near obstacles. Test both ordinary and
   lowered poses. No visible geometry penetration, camera kick or player jitter
   should appear; collision safety takes priority at abrupt obstructions.
3. Inspect the crate: the wrench stays in NORMAL. Choose Move: it lowers
   smoothly while remaining HELD. Push/drag, then release with E/G/Escape and
   verify a smooth return to NORMAL. Reverse start/stop repeatedly mid-pose.
4. Repeat pickup/stow/retrieve/drop, blocked drops and placement on the crate
   and generator. Check identity, knowledge and F3 equipment/pose diagnostics.
5. Run the clean configuration cycle above on the physical Linux installation.

## Limitations

Primitive models, conservative envelopes, no arm animations, horizontal crate
drive and session-only state remain. Fully blocked equipment may tuck out of
view or hide; unusually abrupt movement can require a safety correction.
Envelope shape/offsets must enclose each authored item. Only NORMAL/LOWERED poses
exist. No extra slots, rooms, puzzles, combat, damage or AI were added.

Graphical QA used Xvfb / Mesa llvmpipe rather than physical gaming hardware.
The editor-cycle environment emitted missing Vulkan-surface, X11 BadWindow and
unavailable ALSA-audio diagnostics while still completing play/stop and leaving
configuration unchanged; the standalone OpenGL gameplay suites used Dummy audio
and only reported the existing unsupported V-Sync warning. Those editor display
limitations do not establish hardware/editor visual quality. Physical mouse
feel, alt-tab and performance still need the manual Linux check above.
