# OC-01 overhead bridge crane

[RD-015B suspended loads, Strap Mode, and playtest scenarios](suspended-loads.md)

OC-01 is a single-girder bridge crane in the Engineering Test Hall. Its rated capacity is 50,000 kg and the hook block has a nominal mass of 225 kg. These are equipment specifications. The hoist presents two visible chain falls and a physical hook that swings and swivels passively.

## Playtest

Use Godot 4.7.2 and run `godot --path .`. From the Systems Test Chamber spawn, turn around and enter the hall. The **OC-01 / REMOTE** tray is just inside on the left. Aim at the remote, press **E**, and pick it up. Equip it from inventory if stowed. **V** connects it to the crane while Otis is inside the hall. Otis keeps WASD movement and mouse look, and **C** changes between the existing cameras.

| Action | Default | Keyboard fallback |
| --- | --- | --- |
| Trolley hall +X / −X | Left / right mouse button | Right / Left |
| Bridge toward mezzanine / entry | G5 / G4, typically mouse Forward / Back | Up / Down |
| Raise / lower hook target | Wheel up / down | Page Up / Page Down |
| Precision | Hold Shift with input | Hold Shift with input |
| Connect / disconnect | V | V |
| Stow / drop | 1 / X | 1 / X |

Crane bindings are separate Godot actions with names starting `crane_` in Project Settings → Input Map. Mouse side-button mappings use Godot's XButton2 and XButton1. If your device profile emits different buttons or keyboard keys, bind those events to the corresponding actions. Active crane inputs take precedence over gameplay actions using those buttons. When Otis disconnects, changes equipment, leaves the hall, or enters a modal interface, the crane brakes and holds.

## Travel and tuning

Coordinates are relative to the hall, with positive Z toward the mezzanine. The runway running surfaces are 9.52 m above the ground floor. The bridge and trolley reach the central fabrication floor, machine areas, material-handling station, and the mezzanine.

| Axis | Range | Max speed | Acceleration | Braking |
| --- | --- | --- | --- | --- |
| Bridge, Z | 0.90–23.484 m | 1.65 m/s | 0.90 m/s² | 1.35 m/s² |
| Trolley, X | −8.254–8.254 m | 1.30 m/s | 0.95 m/s² | 1.50 m/s² |
| Hook center, Y | 0.44–7.97 m commanded | 0.85 m/s | 1.25 m/s² | 1.25 m/s² |

The wheel changes the target by 0.10 m per step, or 0.01 m in precision mode. Precision also caps powered speed at 25%. The physical block can rest against solid obstacles and raise away. Lift it above the deck or machinery before traversing.

## Maintenance

The relay cabinet just inside the entrance on the right provides ground-level access to eight individual components.

| Mechanism | Components |
| --- | --- |
| Trolley | Drive A, drive B |
| Hoist | Motor, brake |
| Bridge | Roller A, roller B, drive A, drive B |

Four qualifying horizontal end-stop impacts trigger one incident affecting three to five components, weighted toward the impacted axis and side. The bridge threshold is 1.25 m/s and the trolley threshold is 0.98 m/s, measured immediately before contact. Holding against a stop counts once until the crane moves away. Low-speed contact, hook obstructions, and vertical limits cause no damage.

Damaged components remain functional and emit light smoke and occasional sparks. Broken components emit dark smoke and heavier sparks and restrict their associated mechanism. A broken hoist motor prevents raising. A broken brake stops hoist travel. The hook remains suspended.

To test maintenance, raise the hook, drive the trolley into an end stop at full speed, reverse far enough to reach full speed again, and repeat four times. Disconnect the remote, aim at an affected relay, and press **E** to inspect and **E** again to repair. Repair clears the local effects and restores the associated function. Incident records last for the current Facility session. See the suspended-load guide for attachment, swing, and center-of-mass visualization.

Run the regression suite with `bash tests/validate.sh`.

## In-game views

[Hall span](hall-span.jpg) · [Crane over the mezzanine](mezzanine.jpg) · [Wireless remote](wireless-remote.jpg) · [Maintenance incident](maintenance-fault.jpg)

[Moving-platform playtest and Linux NVIDIA offload](moving-platforms.md)
