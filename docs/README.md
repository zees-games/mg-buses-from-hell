# mg-buses-from-hell docs

One subject per file. [CLAUDE.md](../CLAUDE.md) has the rules in one line each; these have the reasoning.

| File | What it covers |
| --- | --- |
| [design.md](design.md) | what the game is and the decisions that shape it: the hammer, concrete blocks, no auto-hop, closing speed, the bus's reach, keeping dot-match's teams in step with `sides`, one random manager per world, what dot-props gained, the bowl vote |
| [map.md](map.md) | the bowl: one obstacle description, the gap rule (`BUS_GAP`, `LANE_THROUGH`), doors versus refuges, minimum radii, the stacks and hook, the tank farm and back yard, the scaffold, the colonnade, the deck and ramp, the scatter, climbs and the barrel, the bowls on the ballot |
| [bots.md](bots.md) | the bus autopilot: the stuck rule, `steer_around` and its ceiling, detours, the ramp approach and turn, the live knobs, runner bots and pace |
| [netcode.md](netcode.md) | who is authoritative, prediction and `_mirror_owner`, what crosses the wire, owner-only state, interpolation and late joiners, entity ids, the self-preload rule, the module and services over dot-game |
| [services.md](services.md) | chat and voice (team is the conversation), moderation tools and refusals, stats and awards, identity and faces, which addons are linked and why |
| [client.md](client.md) | bodies, the spectator chain and policy, HUD and admin overlays, sound, the blast effect, scoreboard, settings, lighting and the grid |
| [delivery.md](delivery.md) | the pack: no `class_name`, `rebase` at definition and idempotent (seventh form), an imported model's texture dependency (sixth form), gravity and renderer, smaller deployment traps |
| [testing.md](testing.md) | the three suites, the rules they follow, asserting the mechanism, renders, and the real-deployment check |
| [history.md](history.md) | bug narratives worth recognising again |
| [not-yet.md](not-yet.md) | what a Workshop map can and cannot be here: a bowl document with a radius, no obstacles of its own |
