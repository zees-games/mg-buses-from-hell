# Bots, and the bus autopilot

A dedicated server is the deployment this game is for, and on one the buses are mostly driven by `BfhGame._autopilot`. The module keeps the driving seats full of bots (a bowl with nothing to run away from is a clock that never moves; no other game here needs that rule, because no other game is asymmetric), and `add_player` seats a new driver into any bus nobody is driving, because the common mid-round case is a person disconnecting and a bot filling the seat.

## The bus is a raycast vehicle, and that decides the rules

- **A wheel is a ray, not a collider.** A crate passes under a wheel and lifts the corner; the bus high-centres with a crate under the chassis and no speed left for the impact rule to break it. Lowering the hull to ram crates is worse (it drags). `_unstick` is the rule that works, and it is about **intent**: a bus asking for throttle and not moving is caught on something. It breaks what is under it after `bus_stuck_break_seconds` (1) and puts the bus back on its start line after `bus_stuck_reset_seconds` (5; refused below the break time).
- **The reset is the symptom of every steering bug here.** A bus aimed through a pillar holds full throttle and goes nowhere, which is exactly the stuck state, so it vanishes five seconds later. From the runner's side, standing behind a pillar deleted the bus. When a drive "is sent home", look at the steering first.
- `_upright` rolls a bus that is on its roof back over **where it lies** after two seconds, not to its start line, which would take it out of the chase.
- The suspension must hold the bus up at this game's gravity: see [history.md](history.md#the-bus-that-sat-on-its-hull). The regression guard is "the suspension holds the bus up rather than letting it rest on its hull", because every symptom is downstream of that.

## `steer_around` is a nudge, not a path

Before the target reaches `DotVehicleDriver`, the nearest obstacle in the corridor between the bus and its aim point moves the aim aside, by `_clearance(i)` (`radius + PILLAR_CLEARANCE`). Deliberately a nudge: it cannot solve the stacks as a maze, and a bus that comes round one pillar into another has to come round again.

- **Each side is scored by how much room is actually there** (`_room_at`, measured to surfaces), with the side the geometry indicates winning a tie. Picking the side the bus leaned towards drove it at a point beside one pillar it could not occupy because another stood there.
- **The ceiling is lane width.** Below `LANE_THROUGH` both sides of a lane are in the corridor and the nudge sends the bus beside one into the other. A lane-threading exemption (skip an obstacle when the line passes between it and a neighbour with room) was tried: it took the bus through the narrow courtyard lanes and wedged it in the stacks, because the corridor test cannot tell a gap the bus is lined up on from one it crosses at an angle. Telling them apart needs heading and turning circle, which is a path. Not committed; see [map.md](map.md#the-gap-rule-no-gap-a-bus-cannot-take) for what this costs (doors, and the hook).
- **A detour is passed through, not arrived at.** `_autopilot` hands the driver `[detour, point past the quarry]` as a route, so the detour is passed at `waypoint_radius` with no slowing, with `look_ahead` 0. As the only (so last) waypoint, the driver braked into it inside `arrive_radius` and lost its line round the next pillar; blending the detour towards the quarry cut inside the clearance and wedged the colonnade drive. Not when ramp-bound, whose line-up points are meant to be arrived at.
- **Parked on a waypoint**: a bus at a standstill within `PARKED_ON_WAYPOINT` (1 m) of its waypoint is sent on along its line to the quarry. Only at a standstill: at any speed it broke the west ramp start and the stacks' pillar drive.
- **The aim is past the quarry** (`bot_aim_past`, 8 m), so the bot never eases off for arriving. A bot within 5% of a person holding the throttle down a straight is asserted.

**Live knobs**, all authority-only so no client has anything to agree with, applied from the next tick: `bfh_bot_aim_past`, `bfh_bot_steer_clearance` (the steering's `PILLAR_CLEARANCE`, 3.6 m; only the bots read it, the map's rules keep the constant), `bfh_bus_stuck_break`, `bfh_bus_stuck_reset`.

**A decision left open**: a bot chasing a runner through a narrow lane still stands against a drum until the stuck rule sends it home, which reads like a bug from the runner's side. Whether a bot should give up on a quarry it is stopped behind and pick another is Christian's call.

## Up the ramp onto the deck

Until 2026-10-01 no bot bus could reach a runner on the deck: the ramp is 5 m of slab for a 2.5 m bus. What makes it work, in order of what the bus meets:

- **Line-up and climb on the centreline** (`_up_the_ramp`, `lining_up`, `ramp_bound`). A ramp-bound bus goes to `RAMP_LINE_UP` (11 m) in front of the foot, rounding the foot's corner first if its line would cross the slab; on the line-up strip or the ramp it aims `RAMP_LOOKAHEAD` (6 m) up the centreline, not at the quarry; only the deck releases it to the quarry. `RAMP_SPEED` 9 m/s, because at full speed the line-up overshoots. The strip reaches `RAMP_STRIP_PAST` (3 m) past the line-up point: ending exactly there, a bus that arrived was 0.08 m outside and parked on its own target.
- **A turn planned against the floor** (`_turn_round_for_the_ramp`, ahead of the older timed `_turn_for_the_ramp`, which north-east approaches still use). A bus facing more than `RAMP_FACING_AWAY` (110) degrees off the ramp's axis drives at `RAMP_TURN_APPROACH` (8 m/s) to `ramp_turn_point()`, the point 5-11 m in front of the foot with the most clear floor (`floor_clear_at`; 7.5 m out with 7.1 m clear on the shipped bowl, against the 4.33 m a bus needs to turn; the line-up point has only 4.1). Then full-lock legs, forward one way and reverse the other, the side chosen once. **A leg ends on the floor, not the clock**: a corner or end coming within `RAMP_TURN_MARGIN` (0.8 m) of anything (`_end_blocked`), a corner `RAMP_TURN_REACH` (8 m) from the turning point, the middle `RAMP_TURN_ACROSS` (2.5 m) off the centreline, or a stall; `RAMP_LEG_LONGEST` (3 s) is only a backstop, and the bounds wait `RAMP_LEG_FREE` (0.4 s) into a leg, or a bus already outside them stands still. Then the line: steer for the heading from which a full-lock straightening (`RAMP_LINE_RADIUS`, 12 m) lands on the centreline, slow (`RAMP_LINE_SLOW`) until within `RAMP_LINED_X` (1 m); if within `RAMP_LINE_COMMIT` (4 m) of the foot not lined up, back off straight along the axis to `RAMP_LINE_BACK_TO` (9 m) and try again.
- **The edge rule is on the ramp, not at the foot**: on the first `RAMP_EDGE_CHECK` (10 m) of slab, more than `RAMP_EDGE_X` (1.5 m) off the middle going up, the bus backs down and lines up again. At the foot it cannot tell a start that will wedge from its mirror image that climbs. It costs the east and west starts about 3 s each; printed every run.

Tried and dropped, each measured worse: stopping before the first leg, choosing the turn's side every tick, steering by the direction of motion, an open-floor turn point 16 m out, ending the turn when facing straight up the ramp, capping speed when facing the bowl. The turning always worked; the problem was where it began and the hand-off back to the ordinary drive.

`headless_run` drives eight starts (both spawn lanes, in front of the foot near and far, east, north-east, south-west, west) and asserts all of them, plus that the floor in front of the foot has room to turn. Other diagonal approaches are not measured.

## Runner bots

`_run_route` presses keys, so it moves a runner the way a person does. A held jump jumps once and must be released (auto-hop is off), which is why pressing jump near a face is safe here and would not be in an auto-hop game. A tick with no command repeats the last one (what a netcode wants of a lost packet), so a route that ends must stop pressing, or the runner walks on.

**Every route prints its distance against its length and its average against the configured speed, and asserts on it**: a walk to `RUN_PACE` (0.9), a route with jumps to `CLIMB_PACE` (0.55). The old bars ("it gets moving at all") passed a bot at 30% of its speed; a climb reached the top at 23% speed and only the pace check said so. Bus drives assert they pass `bus_lethal_speed` on the way, because a bus crawling round cover at a speed that cannot hurt anybody used to pass.

## Getting stuck (2026-10-15)

Bot buses wedged and crawled on the bowl and on every district: 2.65 to 8.1 m/s over 45 s, two to five sends home, and stalls of 5.1 s (the stuck rule's reset) on every map. Three causes, each fixed where it lives:

- **The start lanes.** `steer_around` nudged a target round the ramp, then round the obstacles, and the second nudge could put the point back across the ramp's flank, so a bus leaving a spawn lane drove at the ledge and sat there. The nudged point is now checked against the ramp again.
- **District streets.** A nudge cannot plan: a street is a maze of buildings and a point-at-a-time sidestep wedges in it. Districts now plan a route (`bfh_route.gd`, an `AStarGrid2D` of 0.8 m cells over the same `_obstacles` the nudge reads, plus the ramp and ledge slabs, built lazily by `BfhArena.street_route`), string-pulled and followed as `set_route` waypoints. `steer_around` stays a nudge, for the bowl. The grid keeps `bfh_bot_route_clearance` (3.4 m) off a surface: a bus swings wider than its body, and at 2.8 m the route hugged buildings and the bus touched them.
- **No recovery.** The stuck rule only broke props and sent the bus home 5 s later. A bus against something for `bfh_bot_unwedge_after` (0.5 s) now reverses for `bfh_bot_unwedge_seconds` (1.4 s), steering so the nose swings toward its target.

Measured (45 s, `_test_bot_pace`, m/s and sends home): bowl 3.93 and 3; downtown 8.10 and 2; hill town 6.07 and 3; suburb 2.65 and 5, before; none sent home and no stall over a second after, 6.5 to 11.9 m/s. The suburb is the slowest and still has short stalls against buildings when a runner stands inside a building's clearance ring.
