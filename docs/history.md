# History: what building this game found

Kept because each could come back, and the story is how to recognise it. Every one was found by running or rendering, and none of them errored. The lessons that are still rules are in the topic docs.

## The bus that sat on its hull

A bus with four wheels on the ground and 26 kN of engine force sat perfectly still; every reading was correct (not sleeping, mass, steering, engine force, wheel contact) and an impulse moved it. It was gravity: this project runs at 20 m/s², so a 2 t bus puts 10 kN through each wheel, and `VehicleWheel3D.suspension_max_force` defaults to 6000 N. The suspension could not lift the bus; it rested on its hull, whose friction beat the engine. The tell was in `describe()` all along (the body at y = 0.09 where its wheels should hold it at 1.37), and a raw-Godot reproduction with no addon in it made that the number being looked at. Earlier, at 45 stiffness the springs collapsed on the first frame for the same reason. The guard is "the suspension holds the bus up".

## Vehicle wiring, the first week

- **`DotVehicleRide` does not watch the spawner**: a bus removed under its driver left the ride believing they were aboard, and every later `enter` was refused for ever. And `occupants` is keyed by SEAT and valued by RIDER, so the first fix handed `exit` a seat name.
- **The bus spawned facing the wall** at full throttle: `DotVehicleSpawner.spawn` orients with `Basis.IDENTITY` unless told, which faces -Z, seven metres of wall.
- **`spawn_interval` defaults to 1.0 s**, so only the first bus of a round appeared, silently (a refused spawn is a refusal, not an error). dot-props' limits had to be opened up the same way: the world is placing its own furniture, not a player spamming a key.

## The ramp went the wrong way

For nine days the ramp rose from under the deck to 7.8 m over the middle of the bowl: a rotation of -18 degrees about +X lifts the +Z end, and +Z is the bowl. Every number that placed it was right except a sign, which no check about position can see. It explained two earlier diagnoses that were of a map that did not exist (a bus "beaching on the lip" of a ramp whose top was a cliff edge in mid-air). And "the throttle moves it" had been passing on gravity: the check's `simulate` re-drove the bus from the seated driver's own command (throttle 0), and the bus rolled down the backwards ramp the wrong way at 6 m/s. It now presses forward through the driver's command. The guard reads the built surface.

## Walking up a slope, and climbing a crate's side (both dot-player-controller's)

- **No slope in the family had been walked up.** `DotFpsMotor._categorise_ground` treated moving upward faster than 0.1 m/s as not grounded, so walking up an 18-degree ramp at 6.5 m/s read as a jump and the runner stalled. Fixed in dot-player-controller (velocity along the ground normal), with the ground snap measuring "leaving" against the floor the tick started on; this game carried a test-only stand-in motor until then.
- **A crate stack's side was a ladder.** Settled crates stand a few degrees off square, a corner stands proud of the face, and at the jump's apex the ground probe grazed it, `DotFpsPhysicsBody.sweep` guessed the contact normal as UP, and the runner was grounded on the side of the stack and jumped again (2.98 m of a 3 m face with a 1.15 m jump). Fixed in dot-player-controller (`[jumping-into-crate-1]`).

## Nothing drew a player (2026-09-24)

Three things at once, none visible to any check because every check read the simulation: there was no body at all (first-person runners, drivers as buses); `DotNetManager.interpolate_frame` was never called, so `_net_interpolated` was written and reached by nothing and every remote body stepped at snapshot rate (the render-jitter class this family has paid for in three games); and a runner who joined a live round stood at the origin until the next one. The jitter probe in `tools/shot.sh --net` measured it: interpolated, no frame standing still; without, 58 of 147. The same probe found that dot-net counted its interpolation delay in snapshots and subtracted it from ticks, extrapolating every remote entity; that was dot-net's to fix ([bugs-found](../../../docs/bugs-found.md)).

## A connected client predicted nothing (2026-09-25)

`_apply_join` built every mirror with owner 0, this client's included, so `is_owner` was false, `predicted()` was empty and `client_tick` simulated nobody: the runner moved a round trip behind the keys. No check saw it because a client adopting every snapshot agrees with the server, and "zero corrections" was zero because nothing was predicted. The camera, drawn from `render_state()` blending a stale previous tick with the newest snapshot, lurched metres at a time (median apparent eye speed 137.9 m/s against 6.5). Fixed by `_mirror_owner`; the same line was in two other games and has since been fixed there too. The rule that came out: [assert the mechanism](testing.md#assert-the-mechanism-not-the-symptom).

## The leak that was one line of a message

`dedicated` passed every check and leaked the whole script graph at exit (160 objects, 102 resources, eight dummy textures). `--verbose` said what, not why. **Bisected rather than read**: a bare `DotGameModule` whose only difference was `preload("net/bfh_net_bridge.gd")`, never instantiated, reproduced it, and so did preloading `bfh_event.gd` or `bfh_request.gd` alone. Both began `extends DotNetMessage` and `const BfhEvent := preload("bfh_event.gd")` (for a typed `static func of()`). The trigger needs `DotNetMessage` as the base and first load at runtime by a module a running `DotServer` loads; a self-preload over other bases, a two-script cycle, or a load from a bare scene does not do it. The mechanism is inside Godot 4.7.2 and was not chased; the fix is to not have one, and `dedicated` checks the source. The other games carried the same line and were cleaned up after.

## Steering bugs whose symptom was a vanishing bus

- Aimed through a pillar, the bus held throttle against it and the stuck rule sent it home: standing behind a pillar deleted the bus. Hence `steer_around`.
- The hook: the waypoint beside one pillar was chosen without asking what else stood there; an arc puts a second pillar there. The guard is a drive at the hook, because **the shape that exposed the bug is the shape the check has to use**; the tidy two-row lane never would.
- The first tank: every rule was a centre distance against a 1.2 m constant. See [map.md](map.md#one-description-and-everything-is-derived-from-it).
- `_autopilot` had no coverage until a check first set `is_bot`: every driver in every earlier check was a person pressing nothing, and the only thing that drives a bus on a dedicated server was untested.
- The ramp autopilot took two attempts (an unmerged branch, then a nightly run whose reverse-only turn dithered forever) before the floor-planned turn in [bots.md](bots.md#up-the-ramp-onto-the-deck). The two legs found on the way: a line-up strip that ended 0.08 m short of its own point, and a bus parked at the seam between waypoint-following and the stuck rule.

## Order-dependent drives (2026-09-30)

The courtyard's east lane read "sent home" or "works free and reaches" depending on which section ran first. Every world shared the root viewport's physics space, and its history changed contact outcomes on a knife edge, though a shape query found nothing left in it. Each world now gets its own space. What the fresh space then showed: a runner standing in the courtyard's west lane (6.6 m then) was safe from the bot from every start, which the shared space had hidden; the lane was widened on 2026-10-07.

## Seed-sensitive drives (2026-10-07)

Moving the scatter (start lanes, then the scaffold margin) made three drives fail on most seeds. Clearing props changed nothing. Printing per tick showed the **target** differed: the sections "held" the quarry by setting `global_position`, the runner's next tick wrote it back from controller state, and the bot chased the runner's scatter spot. Fixed with `_put`. The trace also found a real game bug: the bot braked into a detour point given as its last waypoint and lost its line round the next pillar, on every seed, passing only by luck.

## The scoreboard's two bugs (2026-09-27)

dot-match's side setup had drifted to the end of `_build_progress`, below two early returns, so a client world and any server with `track_progress` off kept dot-match's default pair and balancing; it is back in `_build_match`. And assigning `teams.teams` did not re-index `DotTeamManager`, so team 1 answered "Red" on every world; the ids matched, every rule worked, and the first render said Red and Blue. dot-match's setter re-indexes since (`[team-reindex-1]`); the explicit `reindex()` here is now belt and braces.

## Other games' missing effects (cross-repo)

Wiring the barrel's blast found that four other games declared dot-fx scenes under `res://scenes/fx/…` that did not exist, and dot-fx refused each as `missing` at DEBUG. Those games have since shipped their scenes.

## A tracking check that failed on main (2026-10-08)

"Every frame draws them on the path the server ran them along" failed three runs in four with nothing changed. The run started beside whoever the client's runner was, sometimes beside the ramp, and the runner fell off its edge: an accelerating curve drawn a snapshot apart rounds by a quarter metre. The drawing was fine; the setup was not. It now starts on the most open floor (`floor_clear_at` over a grid), with the bots out of their buses, measuring to the track's segments.

## The scaffold was never held to the gap rule below 46 m

Its clearance was measured inline at the shipped radius only; at the then-minimum 40 m it was 1.2 m from a hook pillar. `scaffold_clearance()` now, asked at the minimum, which rose to 45.

## Warmup for ever with one person on the server (2026-10-11)

Found by dot-server-deploy's game-vote harness, which joins one real client to a dedicated server: the match stayed in WARMUP past its ten seconds with two players. The person had joined before the module's first bot check and taken the first driving seat (`_side_for_new_player` filled seats first), the bot quota put a bot in the second, and with nobody on foot `sides_are_playable` refused every tick. The offline client never showed it because it puts its player on foot by hand. The same shape came back after any side swap on a server whose seats were all bots: the people became drivers, the bots became runners and were removed. The bus seen falling at y=-2000 in the same run is a separate harness artefact: the shell's copy of the bowl shares the server's World3D in that one-process harness, and the two buses overlap.

The same harness then found `bfh_round_seconds` writing only `config.round_seconds`: the HUD counted down an owner's 50 s while dot-match's rule, built once from the config, ended every round at 180. `BfhGame.set_round_seconds` writes both; `dedicated` checks the rule.

## The brakes were a wall (2026-10-12)

dot-vehicle handed Godot's wheels the brake in newtons where Godot reads an impulse per physics step, so a bus stopped from 15 m/s in 1.9 m on the foot brake and 4.5 m on the handbrake (that one limited by the rear tyres), whatever `brake_force` said. Fixed in dot-vehicle 4f4afaf; measured here after it: 22 kN, the old figure as a force, stopped the bus in 9.9 m and the bot's three-point turn under the deck settled between legs slowly enough that the deck chases took up to 2.8 s longer (west 14.5 s to 17.3 s). 30 kN gives 7.6 m and the chases within 1.3 s of before; the handbrake's 40 kN is 6.3 m. A person's S never used the brake: it is reverse thrust (21 m from 15 m/s) and did not change.

