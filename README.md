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
| E tap | Use the workstation or open an object context menu within 3 m. Release an active Move interaction. |
| Left click | Select a menu action; recapture mouse when no menu is open |
| Escape | Close the terminal or context menu and resume. Cancel placement or release a grabbed load. Otherwise, release the mouse. |
| Hold E (0.35 s) | Stow the held item; never also triggers a tap |
| G tap / hold | Tap to drop or confirm handheld placement. Hold to place an equipped item, or to grab a targeted movable object with empty hands. Release G to let go of a world object. |
| 1 | Retrieve the first stored item into the active slot |
| F3 | Toggle developer diagnostics |

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

Look at the storage crate with empty hands and hold **G**. The crate follows
the camera using the same collision sweeps as precision placement. Scroll to
adjust range, hold **R** to rotate, and use **Shift** to cycle axes. Release **G**
or press **Escape** to let go. Loads above capacity use horizontal drag under
gravity. The **E → Move** action remains available. The plate measures suspended
weight through Otis's contact with the floor.

## Structure

- `scenes/facility.tscn`: project entry point, Otis and interaction UI.
- `scenes/otis.tscn`: reusable `CharacterBody3D`, capsule collider, camera.
- `scripts/world/`: authoritative object Resources, interactable body, primitive room builder.
- `data/objects/`: crate, generator, terminal and wrench definitions and their action lists.
- `scripts/actions/interaction_service.gd`: action permission and execution gate.
- `scripts/knowledge/player_knowledge.gd`: per-actor learned snapshots, independent of world Resources.
- `scripts/player/`: chassis, locomotion, equipment, large-object carry, push and drag,
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
