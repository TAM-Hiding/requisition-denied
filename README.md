# Requisition Denied

Linux-first, low-poly immersive systems game built with **Godot 4.7.2 / GDScript**.

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
| E | Open the targeted object's contextual menu (within 3 m) |
| Left click | Select a menu action; recapture mouse when no menu is open |
| Escape | Close the menu and resume; otherwise release mouse |
| F3 | Toggle developer diagnostics |

Movement is suspended while a menu is open or the mouse is released. The menu
supports keyboard navigation with Tab / arrow keys and Enter. Inspect records
only the displayed name and description; repeated identical observations do not
create duplicate entries. Restarting the session clears knowledge.

## Structure

- `scenes/facility.tscn`: project entry point, Otis and interaction UI.
- `scenes/otis.tscn`: reusable `CharacterBody3D`, capsule collider, camera.
- `scripts/world/`: authoritative object Resources, interactable body, primitive room builder.
- `data/objects/`: crate, generator, terminal definitions and their action lists.
- `scripts/actions/interaction_service.gd`: action permission and execution gate.
- `scripts/knowledge/player_knowledge.gd`: per-actor learned snapshots, independent of world Resources.
- `scripts/player/`: configurable locomotion, camera, targeting ray.
- `scripts/ui/`: shared contextual menu, targeting hint, diagnostics.
- `tests/`: engine-level validation and startup smoke test.

World state does not contain an `inspected` flag: inspection state belongs to
Otis's `PlayerKnowledge`, queried by object ID. No other actor automatically
receives those records. Changed observations can produce additional snapshots
for the same object without increasing the inspected-object count.

To add an interactable, create an `ObjectDefinition` Resource with a stable,
unique ID, attach it to an `InteractableObject` body, and supply collision and
visual children. `properties` permits future world attributes. Resource action
IDs drive the shared menu. Only `inspect` is executable in RD-001; other IDs are
explicitly disabled placeholders. New executable actions belong in the service,
which revalidates line of sight, range and availability at execution time.

Otis's scene exposes movement speed, acceleration, mouse sensitivity, FOV,
gravity and interaction reach. Rendering uses Compatibility mode for a modest
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
```

Graphical validation additionally checks captured mouse state, movement and
mouse-look. Set `RD_SCREENSHOT=/absolute/path.png` to capture the inspection UI
at the end. Headless display servers cannot capture a real pointer, so those
pointer assertions are deferred to graphical validation.

See [manual testing and limitations](docs/rd-001-testing.md).
