# Testing

`./game.sh test` parses every script and runs the three suites; `./game.sh test headless_net` runs one. `headless_run` also takes `-- --only=<method>` to run one section while working on it.

| Suite | What it covers |
| --- | --- |
| `examples/headless_run` | the simulation offline: rounds, sides, props, buses, the map's rules at the shipped and minimum radii, every bot drive and route, the climbs, sounds, the HUD's overlays |
| `examples/headless_net` | both ends over a loopback link (real encoders, bridge, events; no OS socket, dropping one snapshot in five where it matters): prediction, bodies and interpolation, spectating, identity, effects, the scoreboard; and no engine error over the whole run (an `EngineErrors` logger: two minigames' suites printed `!is_inside_tree()` from a toy pulled after a mid-tick rebuild, green) |
| `examples/dedicated` | as a server: the console, the live moderation tools, identity admission, and the source check for self-preloading messages |

## Rules the suites follow

- **Every suite counts sections as well as checks.** Each section calls `_done()` at its end and before every early return, and the run fails unless `SECTIONS` of them did, because a script error aborts a section after it announced itself. Adding a section means raising `SECTIONS`.
- **Every world gets its own physics space**: `_world()` puts each `BfhGame` in a `SubViewport` with `own_world_3d` (never rendered), freed by `_dispose`. A physics space outlives every world freed from it, and its broadphase and solver history change contact outcomes: a bus wedged against a drum is a knife edge, and with one shared space the courtyard drives gave different answers depending on which section ran first.
- **Move a runner with `_put`** (node and controller state), never `global_position` alone: the next tick writes the node back from `controller.state.position`, so a "held" quarry never left its scatter spot and the bot chased that. This one made three drives pass or fail by seed.
- **Clear the floor where you set a bus down** (`_clear_round`, never the scaffold's crates); on some seeds a scattered crate was under it.
- **Bot drives assert pace**, not arrival: a route's average against the configured speed (`RUN_PACE`, `CLIMB_PACE`), and a bus passing `bus_lethal_speed`. See [bots.md](bots.md#runner-bots).
- **A drive's start must be on clear floor.** `_clear_line` turns a drive's line about the gap's middle until the strip a bus sweeps has `START_ROOM` of floor; a start inside a drum threw the bus out at 121 m/s and the table read it as "wedges".
- **Pin a finding you have not fixed.** The hook's refuge is asserted as it is; a fix fails those checks and they get turned round, as the west lane's were.
- **Physics timing**: an impulse is not readable in `linear_velocity` until the step that consumes it has run; and a physics assertion that does not say what it is excluding is measuring gravity (a falling crate passed "not shoved" at 0.16 m/s).
- **A probe that hangs has already printed its answer and lost it** (stdout to a pipe is fully buffered). Put diagnostics in `describe()` and read them from a tool that exits.

## Assert the mechanism, not the symptom

A connected client that predicted nothing passed "a runner moves" (client agrees with server) and "zero corrections" (zero because the predictor never ran). **Agreement between client and server is something the fixed and the broken code share; only the mechanism tells them apart.** The prediction section asserts the local entity is owned and in `predicted()`, a key moves the runner on the client within the tick it is pressed with no snapshot between, an admin teleport is corrected and converges, and a mirror unclaimed at HELLO is claimed. Likewise the scoreboard checks the round just played is already counted, and the client's world draws a server's blast in its own World3D, not the server's.

## Arm every new check

Break the thing the check is about, watch it fail, put it back. Most checks here were armed that way, and several found that the old check passed the bug (a slow bot, a bus crawling round cover, a death camera measured to the wrong point).

## Renders: what no assertion reaches

Four of this game's bugs (flat lighting, no grid, the stacked HUD, the bus facing the wall) and the jitter of every remote body were only visible in a picture. After any change to what is drawn, render it: `tools/shot.sh <seconds> <file.png> [flags]` (`./game.sh shot` wraps it). Flags frame the feature: `--stacks`, `--tanks`, `--scaffold`, `--yard[=courtyard]`, `--lane`, `--hook` (with `--bfh-hook-layout=wide`), `--west-lane`, `--ramp`, `--deck`, `--plan` (the bowl from above, north up), `--blind`, `--beacon [--bus]`, `--watch=follow`, `--settings`, `--blast`, `--scoreboard`. `--net` renders a connected client watching another runner and prints a per-frame movement probe (standing-still frames and frames off the median speed); `--net --walk` runs the client's own runner and reports key-to-motion latency, corrections per second and eye smoothness; `--close` brings the other runner near; `--no-interp` turns interpolation off for comparison. `tools/drive_shot.sh stop|handbrake|turn` draws a person driving a bus from straight above, eight frames a quarter of a second apart on one contact sheet (`screenshots/drive_<how>.png`): S from 15 m/s, Ctrl and D from 12 m/s, and D alone to compare.

## The deployment is the only test of this

The loopback suite runs both ends in one process: it proves encoders, prediction, reconciliation and ordering, and cannot see Godot's RPC routing, a pack being mounted, or a project setting that did not travel. Everything in [delivery.md](delivery.md) was found by:

```bash
# in dot-server-deploy
./server pack buses --source games/mg-buses-from-hell
./server --game buses
# then connect the client shell to 127.0.0.1:6070
```

`./game.sh online` does the same with the browser client.
