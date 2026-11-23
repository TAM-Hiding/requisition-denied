# RD-015B · Suspended loads and Strap Mode

OC-01 can lift one independently simulated body or a movable Uni-Bolt assembly at a time. The crane retains its accepted bridge, trolley, remote, and maintenance controls.

## Playtest

From `rd-015b-suspended-loads`, launch Godot 4.7.2 on Linux.

```sh
godot --path .
bash tests/validate.sh
```

The wireless remote is inside the Engineering Test Hall on the left. Pick it up through the usual **E** interaction menu. **V** connects or disconnects crane control. LMB/RMB moves the trolley, G5/G4 moves the bridge, and the wheel reels the hoist. Arrow keys and Page Up/Down remain available. Shift keeps the existing quarter-speed movement and 1 cm hoist steps.

Use the development scrap terminal in the Systems Test Chamber to dispense a **Long square tubing** piece and a **Solid block** for the scenarios below. Carry or precision-place them into a clear part of the hall. The doorway and stairs remain available.

| Strap Mode input | Action |
| --- | --- |
| H | Toggle Strap Mode with the remote disconnected |
| Look at an object | Show its name, mass confidence, center marker and vertical line |
| LMB on a load surface | Choose the actual contact point, shown in cyan |
| E while aiming at the hook | Connect an already selected point after positioning the hook within 0.95 m of it |
| RMB | Clear the selection or release an attached load by aiming at it or the hook |
| Escape | Leave Strap Mode while preserving a connected load |

A pending point can be selected before using the remote to position the hook. The point stays relative to the selected part. Disconnect the remote, reopen Strap Mode and aim at the hook to connect. Lower and support the load before releasing. Stowing the remote or using the Uni-Bolt leaves the suspended load in the physics simulation. Release the strap before grabbing the load in precision placement or putting it in inventory.

### Scenarios

1. **Unloaded pendulum.** Lower the hook in a clear aisle. Drive across the hall, release the trolley button and watch the hook continue to swing. Repeat with the hook raised. The longer paid-out line has the slower oscillation.
2. **Mezzanine obstruction.** Lower the hook just in front of the upper guardrail, around guard height. Move the bridge toward the deck. Watch the block contact or the line reach the guard and check for **HOOK PATH OBSTRUCTED**. Raise the hook clear, then continue.
3. **Centered lift.** Set long square tubing on the floor. Select the center of its upper face and connect. Raise it slowly and wait for it to settle approximately level.
4. **Off-center lift.** Lower and release the same tube. Pick a point near one end and repeat with room for the free end to swing down. The center of mass moves below the lifting point as the tube rotates.
5. **Composite center of mass.** Uni-Bolt the solid block near one end of the tube. Inspect the combined structure in Strap Mode. Remove the block and inspect again to see the center return toward the tube midpoint.
6. **Place onto the mezzanine.** Rig the tube near its center. Raise it until the load clears the guardrail, bridge into a clear area above the deck, and lower until deck-supported. Pay out a little more line to see slack, then release in Strap Mode from the deck.

## Physics and mass properties

The 225 kg block is a Jolt rigid body with simple continuous collision shapes. It can contact Otis, the floor, the deck, rails and equipment. OC-01 pays out a single tension-only suspension. The solver applies one bounded inward impulse when motion would extend the line beyond its paid-out length. A second one-way point constraint models a short strap, using the load's inverse mass and inertia at the chosen point. Load bodies keep their native gravity, collision and mass, and remain independent of the trolley. The strap starts with 3 cm of slack and contacts can unload both constraints. Native damping settles swing and yaw over time.

Normal swing is up to 15°. Resistance ramps in at 20° and outward crane travel is inhibited at the 25° operating limit. Brief transient sway can exceed that target before damping brings it back. Inward travel stays available. Chain-path and side-load limits use the existing obstruction warning and do not incur maintenance damage. At surfaces, motor payout limits free hook slack to 0.50 m. The lower motor limit gives the physical block enough travel to rest on the slab. The 50,000 kg nominal capacity is checked on attachment and when adding material to a suspended movable assembly.

Standalone bodies use authored centers when supplied and volume-weighted collider estimates otherwise. Procedural steel stock uses its modeled cross-section centroid and density. Connected members contribute their local centers and masses to a mass-weighted average in the canonical body's frame. Membership, material, geometry and mass changes invalidate that result, while ordinary motion transforms the cached center. Strap Mode uses **green** for known, **amber** for estimated, and **gray** for insufficient information. Static mill, lathe, table and cabinet placeholders show estimates and remain fixed.

The twin chain falls render a single span over the actual hook position with bounded visual geometry. The physical constraint represents slack without simulating separate links or wraparound. Independently colliding mechanical mount children can contribute to a mass estimate and remain ineligible as one lift. The movable solver root is preserved when joining new movable members to a strapped assembly. Joining a fixed support or losing the selected point can release the strap. The full 50-tonne rating is a gameplay limit. Extreme off-center loads can have more visible constraint compliance than ordinary workshop stock.

## In-game captures

[Angled hook](angled-hook.jpg) · [Centered suspended load](centered-lift.jpg) · [Off-center lift](offset-lift.jpg) · [Center-of-mass overlay](strap-mode-com.jpg) · [Load positioned on the mezzanine](mezzanine-placement.jpg)
