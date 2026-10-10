# Services: chat, voice, moderation, progression, identity

## The sides are the conversation (chat and voice)

`bfh_services.gd`, over dot-game's `DotGameServices`. Four channels: all, team, admin, whisper. **Team is the one that matters**: two drivers against everybody else is two conversations that must not overhear each other. So team is also what **voice** defaults to (`_voice_default_channel`), where every other game here defaults to the whole server.

- **No proximity channel.** The bowl is 46 m across; a useful range would be most of it, and a channel that reaches nearly everybody lies about who can hear you.
- **No backlog on the team channel**, because of the swap: a backlog is handed to whoever joins, everybody changes sides every third round, and a replayed team line is one side's plan handed to the people it was about.
- **Push to talk** (`config.push_to_talk = true`). A runner being chased is breathing into a microphone; open mic on a side of six is six sets of breathing over the one thing anybody needs to hear.

## The moderator's live tools, and what this game refuses

`BfhServices` answers `_mod_abilities` with noclip, god, buddha, freeze, slay, slap, health, speed, gravity, rename, blind and beacon, and bring, goto, send and return through `_mod_position` / `_mod_teleport`. Every command is on the console and in chat (`!noclip`), with `@team:drivers` and `@team:runners`.

What it refuses, `modtools` prints with the reason: **respawn** (a runner who is out stays out until the next round, and putting one back decides who won); **give** and **strip** (the hammer is the only thing anybody holds); **burn** (no fire in the bowl). **Anything that moves a body is refused for a driver while they drive**: the bus is what moves, and the body is its passenger.

Blind and beacon are per-player flags replicated as state (see [netcode.md](netcode.md#per-player-state-owner-only-where-it-would-leak)); both outlive a new round (`PERSIST_ON_RESPAWN`), and `blind <player> <seconds>` is dot-moderation's timed toggle. **A round is everybody's new body**: `round_began` calls `mod_player_respawned` for every player, so noclip and freeze end with the round and god carries over. A check of a live tool must look at the body the moment the command returns, not a frame later, or a round starting under it undoes the command.

## A player's numbers, and what they earn

`bfh_stats.gd` declares five counters, each one side's half of the game: runners flattened (a driver's), rounds survived and seconds survived (the clock the runners win on), crates broken, and crates put in a bus's path. **No kill or death count**: a runner cannot kill and a driver cannot die, so a symmetric game's two most-read numbers would be one number and a column of zeros.

- **"In a bus's path" is measured by what happened next**, not guessed at the swing: a crate a runner's hammer moved and did not break, that a bus then drove into (`bus_struck`) within `BfhProgress.SHOVE_CREDIT_SEC` (3 s), credits that runner once.
- `bfh_awards.gd` is eight achievements in four series, **three of the four the runners'**, because the obvious list is the driver's. "Traffic Control" is secret rather than hidden: what it is, is the lesson the game teaches.
- `bfh_progress.gd` is a child of the **authoritative** world only (a client counting its own crates is a client awarding itself achievements), and it listens; nothing calls it. dot-stats and dot-achievements are joined by `DotAchievementStatsLink`. An unlock is `BfhGame.earned`, a notice to that player.
- **A bot is not counted**, so `is_bot` is `add_player`'s fifth argument: set on the line after, it was too late for `player_added`, which is what begins counting.
- **A signed-in player is filed under their scoped profile key** (`BfhProgress.durable_key_fn`, wired by the module from dot-platform); everybody else is `bfh-u<session>`, and that is why nothing is persisted: a guest's session id is handed out again after a restart, so a file store would give one guest's lifetime to the next. The key is fixed for the session when the player is added, so somebody seated before their profile arrived keeps the session key until they reconnect. Turning on persistence is one line the day guests are not counted. `bfh_stats [userid]` prints a session.

## Who somebody is

dot-game loads dot-platform beside the module; authentication stays the host's `dot_auth_server`. What the game draws:

- **A face is what a runner looks like**: one slot, `BfhAvatars.SKINS`, in `BfhFigure.RUNNER_ATLASES` order. **A driver wears `DRIVER_ATLAS` whatever their face**, because in an asymmetric game the side is the first thing to read off a body. The stock face is the old id hash, so a server without the platform draws everybody as before.

## Which addons this game links, and why not others

The `.gitignore` is the dependency manifest. Kept or dropped for a reason:

- **dot-player** stays, because dot-player-controller's controllers `extends DotPlayerComponent`; the game has no `DotPlayer` of its own.
- **dot-spawn** is not linked: there is no respawn, and the top-of-round scatter's keep-outs come from `BfhArena`'s one description; a catalogue of sites would be a second description to drift from it. (A late joiner placed in front of a moving bus is unmeasured.)
- **dot-team** is not linked: `sides` is two asymmetric entries capped by seats, not balanced, and its spectate bridge would restrict the camera to one's own side, which this game decided against.
- **dot-physics** is not linked: nothing names a layer or a surface.
- **dot-fx** is linked for the barrel's blast. It had once been linked for two weeks with no effect; a manifest line for an addon nobody uses is a dependency that lies.
- **dot-weapon / dot-loadout** are not linked: there is exactly one thing to hold. A catalogue of one is wrong the moment somebody adds a second entry and forgets its rules.

A pack can only use an addon the client shell was built with; adding a line here means checking dot-server-deploy vendors it.
