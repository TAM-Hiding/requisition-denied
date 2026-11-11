# Requisition Denied

Linux-first, low-poly immersive systems game built with **Godot 4.7.2 / GDScript**.

RD-002 extends the foundation with a physical crate and a carryable wrench.
One active equipment slot and a separate one-item storage container support
pickup, stow, retrieve and safe drop. Held items retract around geometry, and
crate manipulation remains available with equipment held. No full inventory UI is introduced.

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
| E tap | Open context menu within 3 m; release active crate manipulation |
| Left click | Select a menu action; recapture mouse when no menu is open |
| Escape | Close the menu and resume; otherwise release mouse |
| Hold E (0.35 s) | Stow the held item; never also triggers a tap |
| G | Drop held item; release environmental manipulation |
| 1 | Retrieve the first stored item into the active slot |
| F3 | Toggle developer diagnostics |

Movement is suspended while a menu is open or the mouse is released. The menu
supports keyboard navigation with Tab / arrow keys and Enter. Inspect records
only the displayed name and description; repeated identical observations do not
create duplicate entries. Restarting the session clears knowledge.

## Structure

- `scenes/facility.tscn`: project entry point, Otis and interaction UI.
- `scenes/otis.tscn`: reusable `CharacterBody3D`, capsule collider, camera.
- `scripts/world/`: authoritative object Resources, interactable body, primitive room builder.
- `data/objects/`: crate, generator, terminal and wrench definitions and their action lists.
- `scripts/actions/interaction_service.gd`: action permission and execution gate.
- `scripts/knowledge/player_knowledge.gd`: per-actor learned snapshots, independent of world Resources.
- `scripts/player/`: locomotion, equipment owner, independent environmental manipulation,
  and held-item occupancy/presentation profiles.
- `scripts/ui/`: shared contextual menu, targeting hint, diagnostics.
- `tests/`: engine-level validation and startup smoke test.

World state does not contain an `inspected` flag: inspection state belongs to
Otis's `PlayerKnowledge`, queried by object ID. No other actor automatically
receives those records. Changed observations can produce additional snapshots
for the same object without increasing the inspected-object count.

To add an interactable, create an `ObjectDefinition` Resource with a stable,
unique ID, attach it to an `InteractableObject` body, and supply collision and
visual children. `properties` permits future world attributes. Resource action
IDs drive the shared menu. `inspect`, `pick_up` and `move` execute through the
service. Manipulation actions are derived from current instance mobility/state; other IDs remain
explicitly disabled placeholders. New executable actions belong in the service,
which revalidates line of sight, range and availability at execution time.

Otis's scene exposes movement speed, acceleration, mouse sensitivity, FOV,
gravity, interaction reach and the E hold threshold. Rendering uses Compatibility mode for a modest
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
```

Graphical validation additionally checks captured mouse state, movement and
mouse-look. Set `RD_SCREENSHOT=/absolute/path.png` to capture the inspection UI
at the end. Headless display servers cannot capture a real pointer, so those
pointer assertions are deferred to graphical validation.

See [RD-002 architecture, manual testing and limitations](docs/rd-002-testing.md)
and the [RD-001 regression walkthrough](docs/rd-001-testing.md).
