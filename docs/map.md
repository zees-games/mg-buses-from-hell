# The bowl

`game/bfh_arena.gd` builds the bowl in code on both ends: floor, wall, ledge (the deck), ramp, the stacks and their two lanes, the hook, the tank farm and its back yard, the scaffold, the colonnade, sun and sky. Every feature was added because the map had run out of something for a round to be about; each section below says what.

## One description, and everything is derived from it

`PILLAR_LAYOUT` and `TANK_LAYOUT` (and the colonnade's points) are appended by `build` into one `_obstacles` array with a radius each. The meshes, the colliders, the scatter keep-out, the steering (`steer_around`) and the gap rule all read **that**, never a feature's own list. `pillars()` and `tanks()` are views for the map's own checks and the cameras. Nothing that reasons about the floor may care which feature a cylinder belongs to, because a bus wedged nose-on does not. This family has shipped the same list twice and watched the copies drift; do not add a second one.

**Measure to surfaces, not centres.** The stacks were eleven copies of one 1.2 m cylinder, so every rule was a centre distance against a constant; the first 4.4 m tank broke all of them at once (`steer_around` would have driven into it, `_room_at` ranked sides by axis distance, the scatter keep-out was inside the drum). Every rule is per obstacle now: `_clearance(i)` is `radius + PILLAR_CLEARANCE`, and the gap rule is measured face to face.

## The gap rule: no gap a bus cannot take

Two obstacles closer than a bus leave floor behind them where a runner is safe **by standing still**, which in a game of two drivers against everybody is a win condition nobody designed.

- `BUS_GAP := 2 * (PILLAR_CLEARANCE - PILLAR_RADIUS)` is 4.8 m of clear floor: "a bus fits". It is written as a gap, not a spacing, so it holds for every obstacle size.
- `narrowest_gap()` is the map-wide rule, measured on the **built** arena, face to face. It is the one measurement that cannot be taken off constants somebody edits. (`narrowest_pillar_gap()` is static, stack-local and radius-blind; it only answers for the two original rows.)
- `LANE_THROUGH` (`2 * PILLAR_CLEARANCE`, 7.2 m) is the separate, derived number for "the **autopilot** drives straight through". `steer_around` keeps `radius + PILLAR_CLEARANCE` off every axis, so a line down a lane narrower than that has both sides in the way and is threaded by nudges, which wedge. **A room is enterable when the steering can enter it, not when a bus would fit.**
- The aim point matters too: the bot aims `bot_aim_past` (8 m) past its quarry, so a lane is only a straight line in if the line beyond the quarry is clear as well.
- A layout that leaves any gap, or the scaffold's clearance, under `BUS_GAP` is still built, and logged at WARN.

**Doors versus refuges.** A narrow lane (under `LANE_THROUGH`) is a door a runner shuts behind them: the bot cannot follow through it and has the long way round. That is allowed. A place where a runner standing still is never reached is a refuge, and is not. `yard_refuges(index)` lists the narrow lanes, derived from `LANE_THROUGH` and the layout. Christian's call (2026-10-06): no lane may be a refuge.

## Minimum radii

Every feature is **placed** as a fraction of `arena_radius` but **spaced** for a bus, which is the same size in every bowl. So a smaller bowl walks the features towards each other and the binding limit is the floor between clusters closing. Below its minimum a feature is left out with a log line, never silently: `STACK_MIN_RADIUS` 36, `TANK_MIN_RADIUS`, `SCAFFOLD_MIN_RADIUS` 45, `COLONNADE_MIN_RADIUS` 45 (44 left a 6.996 m door). `headless_run` builds the arena at each minimum and asks the map-wide rules of it, because a constant nobody checks is a number somebody guessed. The shipped bowl is 46 m.

**The bowls on the players' ballot** (`BfhBowls`) are radii for the same reason: `bfh_bowl` is the operator's `arena_radius`, `bfh_small_bowl` is 40 m (the tank farm's minimum: stacks and tanks, no scaffold or colonnade, open floor between), `bfh_big_bowl` 54 m. `headless_run`'s "every bowl on the ballot" builds each and holds it to the gap rule, and refuses two bowls of one radius. A bowl added there is a map: it gets that check, a `--plan` render (`tools/shot.sh 4 plan.png --plan --bfh-arena-radius=<r>`) and a look at what the bots do in it. The bots have not been measured in the small and big bowls the way they have in the shipped one.

## Districts: three maps that are places

`game/bfh_districts.gd` plans three more maps (`bfh_downtown` R60, `bfh_hill_town` R52, `bfh_suburb` R56) and `BfhBowls.all` lists them after the plain bowls, so the vote and the map menu offer them with no other change. A district replaces the stacks, the tank farm and the colonnade: `BfhArena._build_district` asks `BfhDistricts.plan` for buildings (circles) and painted roads, and every building goes through `_add_obstacle`, so steering, scatter, toys and the gap rule see them as they see a pillar. Roads are flat meshes with no collider. The plan refuses a building that would break the rules (`STREET` of clear floor to any other, wall room, scaffold room, the buses' start lanes, another road), so the gap rule holds by construction and `headless_run` still measures it. They are drawn by hand, from no map data. The district id travels in HELLO and BOWL, so a client builds the same town; see [netcode](netcode.md).

## The stacks (west)

Concrete pillars, 1.2 m across, 5.4 m tall, permanent. What a person on foot has against a vehicle is **a turning circle**: a bus is nine metres long and a runner turns on the spot, so a cylinder to orbit is cover that does not have to survive anything. A pillar is also the one obstacle a raycast vehicle handles honestly: taller than the hull, it simply stops the bus.

- **Staggered rows with lanes, not a scatter.** Scattered pillars make every gap the same gap. A lane a bus can take at speed makes its middle the most dangerous floor and its edges the safest. The lane does **not** run clean through: a pillar across the far end, offset, means a driver committed to the fast line must leave it. Yaw 25 degrees, so the lane is not a corridor lined up from the ramp.
- **Two lanes** (`STACK_LANES`, stack-local z 0 and 9.6; `STACK_LANE_END` 14). The first is 6.8 m and threaded by nudges; the second is 7.6 m, past `LANE_THROUGH`, **on purpose**: it leads to the scaffold, and a lane the bot could not chase down would make the height a refuge. The second lane's row is appended after the hook in `PILLAR_LAYOUT`, so indices 0-10 are unchanged; `HOOK_FIRST` names the hook.
- **The hook**: three pillars in an arc past the dog-leg, the one place where losing a bus does not mean crossing open floor. Its two gaps (5.56 and 5.59 m) fit a bus and not the autopilot, and the interior is almost entirely inside some pillar's steering ring, so **a runner standing in either gap is not reached by a bot** from 8, 11 or 14 m out. This is a known refuge against bots (a human driver fits). No layout was found that fixes it and keeps every rule; `BfhConfig.hook_layout` selects `"tight"` (default, as built) or `"wide"` (middle pillar at stack-local x 30.3, both gaps past `LANE_THROUGH`, but 3.48 m to the scaffold, under `BUS_GAP`, and still a refuge from 11 m). `headless_run` **pins** the finding; a hook that fixes it fails those checks and gets them turned round. Christian's call; nightly item `runner-standing-1`. What would move it is a change to the steering (a path rather than a nudge) or to the hook's neighbours.

## The tank farm (east)

Storage tanks, 2.2 to 4.4 m in radius and 6.8 m tall, around two courtyards. **A pillar is cover you see through; a tank is cover you cannot.** Behind a 1.2 m column a runner watches the bus pick a side, so the west is about reacting; a 4.4 m drum hides a nine-metre bus, so the east is a guess by both people at once. Four sizes, because what a runner chooses between is how much floor a piece of cover hides. No yaw: a ring of drums has no axis to hide.

- `TANK_YARDS` declares each room as its drums in order round it; `yard_middle`, `yard_lanes` and `yard_lane_middle` come from it.
- **The courtyard** has four lanes. North and south are the straight-line ways in (the suite asserts exactly those two). The west lane is 7.6 m since 2026-10-07 (it was 6.6 and a runner standing in it was safe from the bot); it is `BfhConfig.courtyard_west_lane` (`COURTYARD_WEST_LANE` 7.6, `COURTYARD_WEST_LANE_NARROW` 6.6 is the farm as first built), placing tank 0 through `layout_with_west_lane`. The east lane (5.38 m) is the one door left. A bot chasing a runner in the courtyard's middle from the west still wedges (the aim point beyond the middle crosses the east drum's ring); the runner there is reached through the other three lanes, so the room is not a refuge.
- **The back yard** (two more drums) joins the farm to the scaffold: its two wide lanes face each other so one straight line runs through both rooms to the scaffold; its two narrow ones (to the hook, to the rim) are the runner's doors.

**`courtyard_west_lane` and `hook_layout` are layout, not cvars.** The map is built on every client, so both travel in the HELLO and a client builds the server's layout; a live change would move a drum under the people connected. JSON, environment or argv, and a restart.

## The scaffold (south-east): height, made of crates

Crates as a saddle `SCAFFOLD_STEPS = [1, 1, 2, 2, 3, 3, 2, 2, 1, 1]`, two columns to a step, climbable from both ends. A bus cannot climb it; from the top the whole bowl is visible.

- **Built of crates, and that is the design.** Permanent height is a place to win by standing on, which the gap rule forbids on the flat. Crates break at cruising speed and shove below it, so the top is safe exactly as long as the drivers leave it standing, and bringing it down costs them cover.
- **Two columns to a step**: a standing jump clears a one-metre rise by 9 cm and misses one time in three; two metres of step is a landing and a run-up.
- **A saddle, not a staircase**: a staircase told the drivers which end to break, and a runner on top had nowhere to go but off the sheer side. Now a bus that comes through one end leaves the other standing.
- The arena says where each crate stands (`scaffold_cells()`, the one description: spawn points, settled check, keep-out, declared climbs); the world spawns them as ordinary replicated props, so a client builds none and a round reset rebuilds it.
- **Drop, do not place.** A crate spawned touching the floor is driven into it (the floor is one huge convex, and zero-separation contact is unreliable), so every layer is dropped from `SCAFFOLD_DROP`. The scatter has always dropped from above for the same reason.
- **The scatter keeps out of it**, by `scaffold_scatter_margin` (4 m to a prop's centre, never under the 2.2 m every obstacle keeps; cvar `bfh_scaffold_margin`), read through `arena.scaffold_keep_out`. A barrel 2.4 m off its west end braced it enough that the bus could no longer bring a runner down.
- `scaffold_clearance()` is the gap rule for the scaffold against every pillar and drum; it is asked at `SCAFFOLD_MIN_RADIUS` as well as at 46.

## The colonnade (north-west)

Four concrete pillars on an arc `COLONNADE_WALK` (7.6 m) off the wall, `COLONNADE_SPACING` (10.4 m) apart, from the deck's west corner towards the stacks: a covered way along the rim in the quarter where buses turn out of their start. **Along the rim, not in the middle**: the first design put a drum and posts in the open floor and wedged the west bus on the post nearest its start. No door: the walk and every gap are past `LANE_THROUGH`. `colonnade_points`, `colonnade_walk_point`, `colonnade_clearance` are the one description.

## The deck and the ramp

The ledge (deck) along the north edge is height for a runner; the buses start on the sand in lanes either side of the ramp, under the slab, facing the bowl.

- **The ramp is 5 m wide.** At thirteen it was a road.
- **Its collider is eight boxes in one plane, not one.** One 26 m box made the ground probe miss a floor the runner was standing on (the large-convex failure dot-player-controller documents, on a tilted convex). A seam in one plane is invisible to a sliding capsule; a trimesh's interior edges are not.
- **It is tucked 0.3 m under the deck.** A ramp that reaches the deck's height only under the deck is `tuck x tan(18)` short at its edge; at a metre that was a 0.32 m lip that is still a wall, because the slide off the deck's face leaves the runner moving upward, the motor calls that airborne, and a step is only tried from the ground.
- **Its direction is asserted on the built surface** (higher at the deck than at the foot). For nine days it rose the wrong way, every position correct and one sign wrong; see [history.md](history.md#the-ramp-went-the-wrong-way).
- `steer_around` knows the ramp is there: it is the one thing a bus cannot come round on either side, so a line crossing the slab is sent round its foot, measured against the slab itself (not the slab widened by a bus, which sent buses merely beside it into the hook).

## The scatter

Crates, barrels and concrete blocks are scattered each round from a seeded stream, with keep-outs from `_obstacles` (radius + 2.2 m), the scaffold margin, and **lanes in front of every bus start** (`keep_start_lanes`, set by `_lay_out_bowl`; `scatter_clears_bus_lanes` on, `bus_lane_width` 6 m, `bus_lane_length` 24 m, cvar `bfh_bus_lane_width`, 0 for off). A block once landed 13 m in front of the east start and the bus spent its first seconds against it.

**Concrete blocks** are the floor under the round: whatever the drivers flatten, this much cover remains. A sixth as many as crates and never fewer than three. Same `DotPropDef` as a crate with three fields different (`max_health = 0`, `rideable = false`, `break_impact_speed = 0`): the design is data.

## What a runner can climb

`bfh_reach.gd`'s `jump_reach` and `climb_limit` delegate to `DotFpsTunables.jump_reach` and `climb_limit(CLIMB_MARGIN)` on the tunables `BfhPlayer.tunables_for(config)` builds, so there is no copy of the numbers or the formula. A climb is held to 0.9 of the standing jump's apex, the family's margin.

**`BfhArena.climbs(config)` is the part worth copying**: the map declares which two surfaces are a route and how (STEP, JUMP, WALK up a slope, THROW by a barrel), and every number is measured off the colliders (props through `BfhContent`'s size constants, asserted against the scenes; the ramp off its built transform; the scaffold off its cells). `headless_run` prints each with its margin before asserting it.

**The barrel's throw** sets the runner AIR as it adds the lift (otherwise the ground snap takes it back next tick) and is a **height**, `barrel_lift_height` (4.2 m at the barrel, falling off with the blast), sized so the weakest throw from the hammer's full reach clears a stack of two. In practice it does not put a runner ON a stack beside the barrel, because the same blast shoves the stack apart; there is nothing in the bowl the blast cannot move to land on. That is an open design question, not a bug.

## Toys

Six of dot-props' loose toys (beach balls, barrels, a tyre) stand on a ring two thirds of the way out (`BfhArena.toy_placements`, from `_find_toy_spots`: clear of every obstacle by `TOY_ROOM` and of the scaffold). A pure function of the build, so both ends place the same toys in the same order and pair them by index; not clear of the bus lanes, which are the game's per round and a client never sets, and a bus ploughing a ball is the point. The scatter keeps off them (`_on_a_toy`), so a crate is never dropped on one. They are on their own collision bit (`BfhGame.TOY_LAYER`, layer 10) masking the bowl's layer 1, so buses, crates and the bowl meet them in the solver and a person's motor never does: a walk pushes one through `BfhGame._advance_toys`, a hammer whacks one off (`BfhHammer.TOY_WHACK`, dot-props' `shot`), nobody stands on one or hides behind one. Every round's start puts them home before the scatter. Replicated as `net/bfh_toy_net.gd` through TOYS (after every build, and to a joiner after HELLO); a client registers every mirror the moment TOYS arrives and pairs them when its bowl is built, because dot-net stops reading a snapshot at the first entity a client does not know.

