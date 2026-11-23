# RD-015C · Industrial test stock

Run `godot --path .` with Godot 4.7.2 on Linux. Open the **Development scrap rack** terminal in the Systems Test Chamber and select one of the four **Industrial test stock** entries. The terminal still dispenses one article at a time. Industrial items arrive inside the yellow corners labeled **Industrial Delivery** on the Engineering Test Hall floor. The pad refuses deliveries while occupied. Standard stock arrives beside the terminal.

| Article | Dimensions | Mass | Collider |
| --- | --- | ---: | --- |
| Flat Bar — 20 ft | 6,096 × 152.4 × 12.7 mm, length × width × thickness | 92.62 kg | One box |
| Round Bar — 20 ft | 6,096 × 76.2 mm, length × diameter | 218.23 kg | One cylinder |
| Wide-Flange Beam — 30 ft | 9,144 × 309.88 × 205.232 mm, length × depth × flange width | 676.12 kg | Separate flanges and web |
| Machinery Test Block — 5 t | 1,500 × 1,000 × 800 mm, length × width × height | 5,000 kg | One chamfered convex hull |

Steel stock uses 7,850 kg/m³. The W12×50 follows the AISC 12.20 in depth, 8.08 in flange width, 0.640 in flange thickness, 0.370 in web, and 14.60 in² section area. Its mass includes the material represented by the published area. The simple colliders omit small root fillets. The symmetric casting uses a specified test mass and a centered mass model. Jolt derives inertia from these collision shapes and the assigned mass. [AISC Shapes Database v16.0](https://www.aisc.org/aisc/publications/steel-construction-manual/shapes-database-v160/) · [W12×50 section record](https://beamlib.com/en/american/aisc/w-shapes/w12x50/)

## Playtest

1. Dispense and inspect each article. Try a midpoint lift using the existing OC-01 remote and Strap Mode. Use the green center guide to compare the selected lifting point to the center of mass.
2. Select a point away from the midpoint on the beam's upper flange. Lift with ample space for the lower end to swing toward the slab. Bring it back down before releasing. The hall dimensions constrain how much of the beam can hang vertically.
3. Move the 5 t casting along both crane axes, then lower it until the strap goes slack. Lift the round bar from its midpoint, lower and release, then nudge it across its axis to watch it roll.
4. Place the beam across two level supports along its length. For a compound lift, Uni-Bolt a plate to a flat bar where the tool can reach both surfaces, then inspect, lift, and release the assembly.

Long stock responds to contact across its full length. A tall end-first drop of the slender round bar can leave it precessing on the rim for an extended time in Jolt. Controlled lowering and ordinary rolling work. The 5 t casting can settle on any stable face after an off-center release. Uni-Bolt still requires suitable local surfaces within its ordinary reach. [Crane controls and Strap Mode](../crane/suspended-loads.md)

[Off-center beam lift](beam-off-center.jpg) · [5 t casting in transport](casting-transport.jpg)
