# Requisition Denied

Linux-first, low-poly immersive systems game built with **Godot 4.7.2 / GDScript**.

RD-002 extends the foundation with a physical crate and a carryable wrench.
One active equipment slot and a separate one-item storage container support
pickup, stow, retrieve and safe drop. Held items retract around geometry, and
crate manipulation remains available with equipment held. Manipulation requests
a smooth lowered pose; release restores the normal pose. No full inventory UI is introduced.

RD-001 supplies a playable 12 × 12 × 4 m facility chamber, Otis's first-person
controller, contextual inspection, and actor-owned session knowledge. No AI or
external services are required. All room geometry uses built-in primitives.

## Run

Open `project.godot` in Godot 4.7.2 and press **F6** with `facility.tscn` selected,
or **F5** to run the project. From the repository root:

```bash
godot --path .
```

| Input | Action |
| --- | --- |
| WASD | Walk |
| Mouse | Look |
| Middle mouse + drag | Rotate the object during precision manipulation |
| Mouse wheel | Adjust placement distance during precision manipulation |
| E tap | Use the workstation or open an object context menu within 3 m. Choose Move to start precision manipulation. |
| Left click | Select a menu action; recapture mouse when no menu is open |
| Escape | Close the terminal or context menu and resume. Cancel placement or release a grabbed load. Otherwise, release the mouse. |
| Hold E (0.35 s) | Stow the held item; never also triggers a tap |
| G tap / hold | Hold for 0.2 s to manipulate an equipped item or a targeted movable object. Release the hold to keep manipulating. Tap G to place, or to drop ordinary equipment when idle. |
| 1 | Retrieve the first stored item into the active slot |
| F3 | Toggle developer diagnostics |
| F4 | Open or close Development / Mechanical Interaction |

Movement is suspended while a menu is open or the mouse is released. The menu
supports keyboard navigation with Tab / arrow keys and Enter. Inspect records
only the displayed name and description; repeated identical observations do not
create duplicate entries. Restarting the session clears knowledge.

## Administrative workstation

Approach the desk under the Facility sign and tap **E** while looking at the CRT.
Use the mouse or **Tab**, arrow keys, and **Enter** to navigate. **Escape** returns
to first person. The camera moves to the display while Otis stays in place and
world physics continues.

- **Messages** shows authored notices and tracks read state.
- **Requisitions** records deterministic decisions for the current session.
  Approvals do not deliver equipment or change access.
- **Inventory** displays equipment, storage capacity, and Otis's chassis diagnostics.
- **Records** displays what Otis has learned through inspection.
- **Settings** controls CRT text brightness for the current session.

## Chassis and carrying

Each Facility session generates Otis's physical capabilities within manufacturing
tolerances. See **Inventory → Unit Diagnostics** at the workstation for maximum
lift, walking speed, acceleration, and chassis mass.

Look at the storage crate with empty hands, hold **G** for 0.2 seconds, then
release the key. **E → Move** enters the same mode. Scroll to adjust range, hold
**middle mouse** and drag to rotate. Tap **G** to place or press
**Escape** to release the world object. The same hold activates persistent
placement for equipped items, which return to equipment on Escape. Overweight
objects drag horizontally under gravity. The plate measures suspended weight
through Otis's contact with the floor.

Middle-mouse rotation continues across complete revolutions. Adjust horizontal
and vertical rotation inversion independently in the F4 panel. The
`PrecisionPlacement` scene node still exposes rotation sensitivity and initial
inversion defaults. Both inversion flags are shipped off.

## Mechanical assembly

Use **E → Remove** on the generator service panel, move the panel clear, then
remove the power module. Use the precision controls to bring each part to its
mount. Press **E** when **Install** appears and wait for the part to seat.
Inspect the generator to verify Stage 3. Placing the module with **G** leaves it loose and
Stage 3 unavailable. Install the module before closing the service panel.

The independent battery fixture uses the same mounting system. Remove the
yellow cartridge and approach the dark socket with its silver terminal first
and raised ridge facing the top slot. The HUD can ask you to move closer,
align the insertion axis, or rotate the key. If the path is blocked, back out
and clear the approach. Press **E** to seat the cartridge or **Esc** to
interrupt seating and release it. A new obstruction during seating returns
control of the same part to precision manipulation.

Mount definitions carry the mating pose, compatibility tags, keying, access
dependencies, joint metadata, and optional failure strength. The snap path
checks a short alignment turn followed by a direct insertion sweep. Both
stages are checked again during seating. A fixed connection takes effect
when the original body reaches its exact mating pose. Revolute and prismatic
connections are available as definition data.

### Mechanical Interaction settings

Press **F4** during first-person gameplay. Values apply live to subsequent
installation attempts. **Save Settings** persists the profile in
`user://mechanical_interaction_settings.json`. **Reset to Defaults** restores
live defaults. Save afterward to keep the reset on restart.

| Field | Default | Range |
| --- | ---: | ---: |
| Acquisition distance | 0.30 m | 0.10–0.60 m |
| Snap distance | 0.20 m | 0.01–0.30 m |
| Insertion-axis tolerance | 30° | 1–60° |
| Key rotation tolerance | 35° | 1–75° |
| Snap duration | 0.20 s | 0.05–1.00 s |

Acquisition must be at least as wide as snap distance. The generator retains
its authored front approach allowance. Clearance checks still apply to all
mounts. **F3** displays the candidate, distance, axis and key errors, path
status, and installation eligibility. When enabled in F4, pickup diagnostics
also log the original pose, contacts, candidate extraction paths, and
clearance failure stage to the Godot console.

**Export Snapshot** writes `mechanical_interaction_<timestamp>_<ticks>.json`
in the project user-data directory and displays its absolute path. On Linux
the directory defaults to
`~/.local/share/godot/app_userdata/Requisition Denied/`, subject to
`XDG_DATA_HOME`. **Import Snapshot** opens a file picker and applies a valid
file live. Save separately to make it the launch profile.

The snapshot uses schema version 1.

```json
{
  "schema_version": 1,
  "installation": {
    "acquisition_distance_m": 0.3,
    "snap_distance_m": 0.2,
    "axis_tolerance_degrees": 30.0,
    "key_rotation_tolerance_degrees": 35.0,
    "snap_duration_seconds": 0.2
  },
  "pickup": { "show_clearance_diagnostics": true },
  "rotation": { "invert_horizontal": false, "invert_vertical": false },
  "debug": { "show_alignment_diagnostics": true }
}
```

## Structure

- `scenes/facility.tscn`: project entry point, Otis and interaction UI.
- `scenes/otis.tscn`: reusable `CharacterBody3D`, capsule collider, camera.
- `scripts/world/`: authoritative object Resources, interactable body, primitive room builder.
- `data/objects/`: crate, generator, terminal and wrench definitions and their action lists.
- `scripts/actions/interaction_service.gd`: action permission and execution gate.
- `scripts/knowledge/player_knowledge.gd`: per-actor learned snapshots, independent of world Resources.
- `scripts/player/`: chassis, locomotion, equipment, shared precision manipulation, supported drag,
  and the NORMAL/LOWERED presentation poses for handheld items.
- `scripts/ui/`: contextual HUD, terminal camera and input ownership, and the in-world terminal display.
- `scripts/administration/`: Facility-owned messages, requisition records and administrative events.
- `tests/`: engine-level validation and startup smoke test.

World state does not contain an `inspected` flag: inspection state belongs to
Otis's `PlayerKnowledge`, queried by object ID. No other actor automatically
receives those records. Changed observations can produce additional snapshots
for the same object without increasing the inspected-object count.

To add an interactable, create an `ObjectDefinition` Resource with a stable,
unique ID, attach it to an `InteractableObject` body, and supply collision and
visual children. `properties` permits future world attributes. Resource action
IDs drive the shared menu. `inspect`, `pick_up` and `move` execute through the
service. The workstation's `use_terminal` action transfers camera and input
ownership after the same range and sight check. Manipulation actions are
derived from current instance mobility and state.

The chassis supplies walking speed and acceleration. Otis's scene exposes mouse
sensitivity, FOV, gravity, interaction reach, and the E hold threshold. Rendering uses Compatibility mode for a modest
hardware baseline; lighting is deliberately simple.

## Validation

```bash
GODOT_BIN=/path/to/godot-4.7.2 tests/validate.sh
```

The wrapper imports a fresh checkout, runs the GDScript integration suite, and
launches the main scene for 120 physics frames. It fails on script/runtime error
diagnostics even when the engine returns zero. No third-party test addon is needed.

For graphical validation, run the suite without `--headless`:

```bash
godot --path . --script tests/validate_facility.gd
godot --path . --script tests/validate_mobility.gd
godot --path . --script tests/validate_manipulation_followup.gd
godot --path . --script tests/validate_terminal.gd
```

Graphical validation additionally checks captured mouse state, movement and
mouse-look. Set `RD_SCREENSHOT=/absolute/path.png` to capture the inspection UI
at the end. Headless display servers cannot capture a real pointer, so those
pointer assertions are deferred to graphical validation.

See [final pose/configuration validation](docs/rd-002-final-polish.md),
[RD-002 architecture, manual testing and limitations](docs/rd-002-testing.md)
and the [RD-001 regression walkthrough](docs/rd-001-testing.md).
