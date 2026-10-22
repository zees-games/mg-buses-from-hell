# Bot soak

`./game.sh soak [bowl] [minutes]` runs `tools/soak.tscn`: four bot-driven buses in the real `BfhGame` on one bowl (a map here is a bowl id: `bfh_bowl` by default, `bfh_small_bowl`, `bfh_big_bowl`, or a district id), driven by dot-bot's `DotBotSoak` with dot-spawn's `DotSpawnWatch` for stuck and fell-out verdicts, ticked externally at 64 Hz. The movers are the buses (the bot drivers' vehicles); a mover has a goal while any runner is alive. There is no runner bot in play, so the three runners stand still and rounds end when the buses have run them down. The report is `.godot/test-logs/soak-<bowl>.json` plus one `SOAK {...}` line, and the exit code is 1 on failure. There is no navigation mesh, so off-nav and unreachable are off; the harness does not see this game's combat, so its kill and damage counters stay 0.

**Needs the linked `addons/dot_spawn`** (gitignored like the other links, made by dot-bootstrap or `ln -s ../../dot-spawn/addons/dot_spawn addons/dot_spawn`; used by the tool only, never by the game), and an `--import` after adding it.

Object growth is allowed 40 percent (the default is 25), as in the other games' soaks.

First run, 2026-10-22, 1 simulated minute per bowl: no fell-out, no object growth, tick p95 0.5 to 0.7 ms, worst tick 3.6 ms, one round each (stationary runners on a one-minute run).

- Stuck verdicts: `bfh_bowl` d2 11.0 s, `bfh_small_bowl` d0 14.5 s (fail, limit 10 s), `bfh_big_bowl` 8.5 s (pass). A bus standing against cover while a runner stands unmoving inside its clearance ring is the open decision in [bots.md](bots.md) (give up on a quarry the bus is stopped behind); the in-game stuck rule sends it home after 5 s, which the watch does not know about, so the soak counts the whole stand. Filed on the nightly board.
