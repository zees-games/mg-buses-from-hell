# The design, and the decisions that shape it

**The first asymmetric game in the family.** The drivers cannot lose except to the clock; the runners cannot win except on the clock. Neither side can hurt the other's *position*: a driver cannot be killed and a runner cannot outrun a bus. The only thing either side can change is **the shape of the bowl between them**, which is why the crates are the game rather than scenery in it. Every decision below follows from that.

## Metres and seconds, not a genre's units

game-g2gfast speaks a long-established community's units because its operators know them and its records must compare with theirs. Nothing here compares with anything, and a second set of units is a second place a ratio can drift. A bus does 22 m/s and the file says 22.

## The hammer cannot kill, and that is the runners' whole side

The obvious version gives the runners something to shoot the drivers with, and it is a deathmatch in a bowl: the buses and crates stop mattering and the round is decided by aim. The hammer changes the map instead: break the crate somebody is behind, shove one into a bus's line, open a path, close one. Every use is about geometry, the only thing a person on foot has against a vehicle.

It is deliberately **not** a `DotWeapon` and there is no dot-loadout: both are about choosing between things, and there is exactly one thing.

## Concrete blocks, so the last thirty seconds are a game

A round where every piece of cover can be removed ends the same way every time: the drivers flatten the crates and the runners have nowhere to be. A few blocks that cannot be broken or pushed are the floor under the round. They are the crate's `DotPropDef` with three fields different, and the suite asserts the design (data), not the code.

## No bunny hopping

Every other 3D game here turns auto-hop on, because their genres are about carrying speed. This one is about a top speed a bus beats comfortably: you **cannot** outrun it, so you put something between you and it. Measured: hopping on every landing is 5.23 m/s, slower than the 6.5 m/s run.

## Closing speed, never the bus's speed

A runner sprinting into a parked bus is not run over; nor is one running away from a bus reversing slower than them. Using the bus's own speed makes both kills, which reads as unfair in a way nobody can point at. Below `bus_lethal_speed` a runner is hurt in proportion and knocked away; above it they are gone. **Knocked away either way**: a bus passing through somebody and leaving them standing would look broken from every angle.

**Nothing above the roof is hit.** The bus hits whoever is in a generous sphere round its centre, and a sphere round a box wider than it is tall reaches over the top: a runner three crates up was killed by a bus driving along the foot of the stack. The roof is read off the bus's own collider (the art is a truck twice the hull's height, so the picture's number is wrong).

## Two sides, and dot-match must be told about both

`BfhGame.sides` is this game's answer to who is on which side, and dot-match's elimination rule counts survivors off its own teams. Keep them in step:

- dot-match's team setup lives in `_build_match` (the game's two teams, `force_balance` off, **`max_difference` 0**). `DotTeamManager.max_difference` defaults to 1 and refuses a join that puts one side more than one ahead; `force_balance = false` turns off the mover, not the refuser. A refused join is logged at ERROR.
- **A swap goes through `switch_team`**; flipping `sides` alone scored every later round on the old sides.
- A player who leaves leaves dot-match too.
- **A round with one side empty is an infinite loop**: elimination ends a round when a side has nobody alive, and a side with nobody at all satisfies that on the first tick.
- **Somebody has to be on foot, and only a person can be.** Bots only drive, and the module removes one that ends up on foot. So the first person on a server runs (`_side_for_new_player`), and a swap is skipped while nobody driving is a person (`_swap_sides`). Before, the first joiner of a dedicated server took a seat, a bot took the other, and the match sat in warmup for ever.

`headless_run` checks a 2-against-4 server and the round after a swap, the two shapes that show these; an exactly balanced four-player test shows neither.

## Seeds: one random manager per world

Two `DotRandomManager`s in one process fight over the registry name (the last to register wins), and two worlds in one process is the normal case here: a server and a client in one editor session, and every section of the suite. With it on, two worlds from one seed laid out different bowls. `_build_random` sets `register_as_service = false`; keep it off.

## What the addons gained

dot-props' notes listed both as deliberately absent; they were right about the boundary and wrong about the gap. Detail in [dot-props/docs/damage-and-carry.md](../../dot-props/docs/damage-and-carry.md).

- **`DotPropDamage`** holds hit points and decides when a prop breaks. It hurts nobody: a barrel *describes* its blast, and dot-combat's `explode()` turns that into hurt people.
- **`DotPropCarry`** is standing on a prop: riding it and pressing down on it. Outside the motor on purpose, because the motor's `DotFpsState.ground_id` is a local physics handle that is deliberately not part of the simulation.

## How the map grew

Each feature in [map.md](map.md) exists because the bowl had run out of something: the stacks (a turning circle, west), the hook (somewhere to lose a bus without crossing open floor), the tank farm (cover you cannot see through, east), the scaffold (height, made of crates so it is spent), the back yard and the stacks' second lane (covered ways to the height), and the colonnade (the drivers' empty quarter). Two halves of a bowl asking for different things is two things for a round to be about.

## The bowl vote

This game has no map files and no dot-map catalogue: its map is `BfhArena.build(radius)`. So the players vote between **bowls**, which are named radii (`game/bfh_bowls.gd`; see [map.md](map.md#minimum-radii)), over dot-vote (`game/bfh_vote.gd`, a `DotVoteDirector` over a `DotVoteListSource` of `BfhBowls.allowed`, narrowed by `bowl_ids`). The bowl is only ever rebuilt between rounds, so a ballot opens `bfh_vote_after` (20) seconds into every round (dot-vote's MANUAL trigger) and is applied at the round's end (`apply: END_OF_ROUND`), setting `BfhGame.next_bowl_id`, which the next round's start builds once (and drops, with a WARN, if the server no longer offers it). The module advances the director once a server tick (`self_advance` off, `round_based` on), calls `note_round_end` from `DotMatch.round_ended`, and starts the director over on every `round_began`; the warmup has no ballot. dot-vote's ROUND_END trigger would apply a choice one round late.

- **Rock the vote opens the ballot in the game, not in dot-vote.** Under MANUAL the director hands every opening to its host, a passed rock-the-vote included: without `BfhVote`'s handler on `director.clock.expired` (reason `rtv`), `!rtv` answered "Rocked. 1 of 1." and nothing opened. A rocked vote still waits for the round's end (`rtv_apply`): a wall moving through the people beside it is not a map change. `rtv_delay_sec` is 0, because dot-vote's two minutes are most of a round.
- The rebuild reaches clients as a BOWL event ([netcode.md](netcode.md#what-crosses)), and a client joining later gets the bowl in its HELLO as before, so `arena_radius` is still not a cvar: what changes the bowl is a round boundary, never a live setting.
- No time limit (`duration_sec` 0), the current bowl is on the ballot, no cooldown in plays. Bots do not vote, so a server of bots never opens one.
- dot-vote's commands (`vote`, `rtv`, `nominate`, …) are the module's, so `!vote 2` in chat reaches them through `_on_chat_command` as the player who typed it.
- The client shell draws the ballot from the `map_ballot` notice (`DotVoteBallotFeed` → `DotBallotPanel` down the right-hand side); nothing of it is in this game's client. `tools/shot.sh 8 ballot.png --ballot` draws the same panel from this game's own vote.
- An owner reshapes it in `user://cfg/buses_vote.json` or `game.yml`'s `metadata: bowl_vote:`, keyed as `DotVoteRules`; `{"enabled": false}` keeps the server's own bowl.

`examples/dedicated`'s "the bowl vote" drives it through the console as a player's chat would, through to the next round rebuilt in the voted bowl. Not yet tried in a browser.
