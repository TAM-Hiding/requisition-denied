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

## Uni-Bolt™ fastening and structural tests

The installation tool is on the floor ahead and left of Otis's spawn. Stock
plates, angles, a bar and a gusset are grouped along the southwest side. The
orange-faced structural test ram is west of the storage crate.

| Input | Action |
| --- | --- |
| Left mouse | Install or remove an individual fastener with the tool equipped |
| Right mouse (hold) | Aim down sights and pin a suspended workpiece at its current world pose |
| R | Switch INSTALL / REMOVE |
| G (hold / tap) | Acquire a loose workpiece / place the grabbed workpiece while carrying the Uni-Bolt |
| 1 | Stow the equipped Uni-Bolt or retrieve it from storage, including during a world grab |
| X | Drop the equipped Uni-Bolt using the ordinary collision-safe drop check |
| F5 | Extend or retract the ram |
| F6 / Shift+F6 | Increase or decrease the ram force limit |
| F7 | Reset and retract the ram |
| F8 / F9 | Cycle test grades / refill the selected grade while equipped |

To fasten while holding a part, equip the tool and hold **G** on a loose
plate or angle. You can also stow the tool with **1**, start manipulating a
workpiece, then press **1** to retrieve the tool and keep adjusting the part.
With empty storage, look at a loose tool in reach and press **1** during a
world grab to equip it. Holding **RMB** pins the workpiece and aligns the
sights with the center ray. Releasing **RMB** smoothly resumes camera-relative
positioning. Use the wheel and middle mouse to adjust the workpiece outside ADS.
Aim through the part into its backing and click. The first successful bolt
transfers control to the assembly immediately. Additional clicks at separate
locations reinforce that body pair. Press **R** and aim at each bolt head to
remove it. Removing the last bolt on an edge restores ordinary interaction
where the resulting island is free.

The installation ray follows the center sight. A short second ray along the
surface normal identifies the backing material and a reverse ray checks that
the entry body is close to it. A bolt is 152.4 mm long. The tool allows a 25 mm
maximum gap at the interface and reserves 6 mm of engagement. The crate can be
anchored through its exposed lower skids by aiming down at them from the side.
The full crate body is too thick for a through-fastener.

| Grade | Strength units | Finish |
| --- | ---: | --- |
| Standard | 100 | Satin steel |
| Grade 8 | 300 | Polished champagne brass |
| MegaBolt | 9,999 | Dark bronze with a faint violet identification ring |

The 20-round magazine holds one grade. Intact rounds recover with their
original IDs and grades. Full or mismatched recoveries go to reserve. The
development grade selector loads matching reserves before topping up with
test rounds. Failed bolts leave a visible remnant.

The ram applies a capped impulse to a free specimen and stalls under a fixed
reaction. Force presets range from 60 to 24,000 units. For a sideways load
test, put an angle against the narrow reaction web near the end of the ram
stroke. Leave the free leg projecting into the ram's path. F3 shows body pair,
depth, group, individual loads and strengths, and recent failures. The ram
readout includes configured and estimated force, travel, displacement and
the last failed group. The piston sleeves follow the actual swept pushing
plate, including at stalls. Reset retracts the ram while preserving damage.
F3 labels applied load and rated strength separately. A zero applied load
is the expected reading for a newly installed fastener.

Freeform groups retain original bodies, local attachment transforms and
individual bolt records. Each connected island uses one simulated compound
collider. When a group splits, the detached bodies recover their original
collision and inherit the island's velocity. The load estimate shares direct
force and adds a moment based on application point, direction and bolt
spacing. The most overloaded bolt fails first and the surviving bolts are
evaluated again. Anchored islands use the shortest available path to a fixed
support. This is an authored gameplay model for ram and explicit test loads.
Ordinary collisions do not accumulate fastener damage. Compound islands can
be pushed physically. To precision-grab an individual member, detach it
first. Fastening data and ammunition remain session-local.

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
- `scripts/fastening/`: physical attachment graph, grade and bolt records, installation tool and ram.
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
