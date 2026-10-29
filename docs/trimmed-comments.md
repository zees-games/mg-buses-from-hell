# Trimmed comment text

Long comment blocks cut to the three-line rule by the comments gate burn-down, kept here in full by file and original line.

### examples/dedicated.gd (was line 15)

Boots a real [DotServer], loads this game into it as a module, and runs the commands an operator would actually type.

[codeblock] godot --headless --path . res://examples/dedicated.tscn [/codeblock]

[b]This is the seam the family's own notes say is never run.[/b] `headless_run` tests the joins between the gameplay addons and `headless_net` tests the wire; this tests the join between the game and the SERVER — the module lifecycle, the console, the cvars, and `sv_tickrate` travelling from a line in a config file all the way into the netcode's own configuration.

Nothing here opens a socket to a client. A dedicated server that never accepts one is still a dedicated server as far as its console, its cvars and its modules are concerned, and those are what this is about.

### examples/dedicated.gd (was line 34)

Everything this run writes, and it is deleted on the way in and on the way out.

[b]A suite that writes to `user://` is a suite whose result depends on the last run.[/b] This one used to write the real punishment store, the server's ban and admin files and its audit log, all at their defaults — so every run appended to all four, and the live tools' warnings alone had reached 134 records in a store a real server enforces. `headless_net` had already failed on its second run for the same reason, over a gag.

### examples/dedicated.gd (was line 134)

Takes the server down before quitting, and this run does not end without it.

[b]`get_tree().quit()` on a booted [DotServer] does not end the process.[/b] The listener is open, stdin console input is on and the transport is holding the main loop, so the run prints its results, reports success, and hangs — which in a CI job is a timeout on a suite that passed, and on a developer's machine is a terminal that has to be interrupted. Measured here: 33 passed, 0 failed, killed at 110 seconds.

### examples/dedicated.gd (was line 171)

Profiles, names and faces on a real server: dot-platform's identity layer, its module, the three events this game redraws a player on, and the key what they keep is filed under.

[b]Both orders a real join has.[/b] Admission runs off dot-server's state changes and is not awaited, so a player is admitted before they are seated when the profile store is quicker than the content download — the usual case — and after when it is slower. Late, the world has to be TOLD; early, it has to ask. Each order is driven here the way dot-server drives it.

### examples/dedicated.gd (was line 297)

The loaded module, looked up rather than kept.

[b]Looked up every time, because the last section unloads it.[/b] A field would be a dangling reference the moment it did. Typed [DotModule] rather than as its own class, because `bfh_module.gd` has NO `class_name` — it is loaded by path, which is the shape a module delivered in a dot-cloud pack must have.

### examples/dedicated.gd (was line 307)

Runs a line the way the console does and captures what came back.

[b]Through `reply_sink`, not by reading `output` off a context built by hand.[/b] A command's reply goes wherever its context sends it — a socket, RCON, stdout — and the sink is that seam. A context constructed with `new()` and poked at is not the object a real command is handed.

### examples/dedicated.gd (was line 331)

[b]The one line that made this suite leak its whole script graph at exit.[/b]

A script that `extends DotNetMessage` and preloads ITSELF, first loaded from a module a running [DotServer] loads — which is how every deployed server loads this game — left 111 scripts, the grid textures in `bfh_textures.gd`'s static cache and eight texture RIDs alive at exit, on 4.7.2. `bfh_event.gd` and `bfh_request.gd` both did it, for a typed `of()` factory. `headless_run` and `headless_net` preload the same files at scene load and never saw it.

[b]Asserted on the source, because the symptom is where no check can reach.[/b] The leak is reported after `quit()`, by the engine, as warnings a CI filter already treats as noise; an assertion here runs before any of it exists. So this checks the cause instead: every message script in `game/`, read as text.

### examples/dedicated.gd (was line 397)

The tick rate is set the way an operator actually sets it: a line in a config file the server execs at boot.

[b]`startup_config`, not `autoexec_config`.[/b] `sv_tickrate` is FLAG_STARTUP_ONLY — a live server cannot re-negotiate its tick rate — and dot-server execs `server.cfg` BEFORE the listener for exactly that reason, while `autoexec.cfg` runs after and would have it refused.

### examples/dedicated.gd (was line 430)

[b]Off, or this run never ends.[/b] The stdin console reads on its own thread, and a thread blocked in a read is a thread Godot will not exit without — so the suite prints its results, calls `quit()`, and hangs. It is the right default for a real dedicated server, where an operator types into the terminal; a test has nobody at the keyboard. Kept after dot-server 5f46687, which no longer reads a pipe unless `stdin_console_pipes` is on: a terminal is still read, and a suite takes no commands from either.

### examples/dedicated.gd (was line 471)

[b]The world is built AFTER the server and BEFORE the module, and both halves of that order matter.[/b] After the server, because the server is what set the engine's tick rate and the world reads it — which is the ordering a real deployment has. Before the module, because a module refuses to load without a world to run: it cannot build one, since the world outlives it across a `module reload`.

### examples/dedicated.gd (was line 497)

Into this run's own directory. See [constant SERVER_DIR].

Through the script, loaded here, rather than a `preload` at the top of this file: a preload would load the module when this scene loads, long before the host does, and the order scripts load in is what decides whether Godot 4.7.2 leaks them at exit. See [method _run_exit_probe]. This is the order a deployed server has.

### examples/dedicated.gd (was line 593)

The players' vote decides the next bowl, end to end through what a player types: a nomination, the ballot opening on its own clock with the nomination on it, a vote by number, the round's end handing the winner to the world, and the next round REBUILDING the bowl to it; then rock-the-vote opening a ballot early. Commands run at the console, which is where a `!vote` typed in chat lands (`_on_chat_command` runs it as the player); the console's voter is "console", so the voter list is that one name. Bots are not voters, and a server of bots never opens a ballot by itself.

Synchronous from the round's end to the round begun: the bots' rounds are running, and one that started in a frame between would build the voted bowl itself and leave the check reading nothing. Last before unloading, because it leaves the bowl a different size.

### examples/dedicated.gd (was line 723)

Rocked in the warmup, which is what an empty current id means, so the same ballot also shows it is drawn there. The feed was polled after the warmup return, so a ballot opened in the warmup (rocked, or one the server's game vote made wait) was open and counted and no client ever drew it.

### examples/dedicated.gd (was line 753)

`cfg/maps.yml`: which bowls rotate. The format is dot-map's selftest's; this is what the GAME does with it: a bowl left out is installed and loadable and is never drawn, never on a ballot, never nominated, marked in the map list; a switch of rotation takes effect; a renamed command is registered; no file means every bowl.

### examples/dedicated.gd (was line 868)

[b]`time_up: finish_round` waits for a round being played, never for warmup.[/b] The game hands dot-vote its match's answer (`round_in_progress_fn`); without it a limit that ran out in warmup held the change for `finish_round_max_sec` over a round that had not started. Run on a director of its own carrying the game's own hook, so the real vote's clock is untouched; the match's state is set by hand and put back.

### examples/dedicated.gd (was line 1058)

The seats fill themselves, because this game has nothing for one side alone.

[b]Asymmetric games are the reason this is here.[/b] A deathmatch with nobody on it is a map somebody can walk around; this is a bowl with nothing in it to run away from, and `sides_are_playable` correctly refuses to start a round — so the first visitor to an empty server would watch a clock that never moves and leave.

### examples/dedicated.gd (was line 1101)

[b]A person who takes a seat takes it from a bot, and leaving gives it back[/b]: DotBotQuota's fill mode, counted in driving seats. One bot in two seats leaves one free, so a person added through the bridge (peer zero, the way a test's player is) joins into it as a driver, once somebody is already on foot: the first person on a server runs, because a bot cannot. The roster check is called rather than waited for, so nothing else moves under the count.

### examples/dedicated.gd (was line 1191)

Chat, voice and moderation, as a module actually builds them.

[b]The netcode suite drives the routers directly; this is the other half.[/b] What is being checked here is that [DotGameModule] found the layer, that [DotGameServices] built all three in the right order, and that the operator's own surface — `bfh_say`, an admission check, a describe line — is there. The ordering is the part with a bug behind it: moderation publishes the mute source both routers look up when they START, and a chat router built first enforces no gag for the life of the server.

### examples/dedicated.gd (was line 1251)

dot-moderation's live tools, built by dot-game's services layer BY PATH, with this game's verbs in them — the first game to get them from the shared layer rather than writing its own.

A runner joins through the roster the way a real client does (an adopted session and the `client_spawn` dot-server fires), and the commands go through the console. What is asserted is the body: noclipped, then dead. And the refusals, which are this game's to explain: a runner who is out stays out, and there is nothing to give.

### examples/dedicated.gd (was line 1310)

Each body is looked at the moment the command returns, not after a frame. A lone runner makes the sides playable, so a round can start under this section — and a round start is a new body here, which is exactly when the tools switch a noclip off and the game stands a slain runner back up. The first run of this section asserted a frame late and failed all three for that reason, with every command having worked.

### examples/dedicated.gd (was line 1476)

A module reload must leave ONE link under the server, still named for the client's route, and a real client must still be sent to over it.

[b]Over a real socket, because the loopback cannot see it.[/b] Before the bridge opened its link through [DotGameLink], every load added another under the server, Godot renamed the live one `@Node@n`, and an RPC to a real client found no node at that path and vanished without an error. Reloaded twice here, before the client joins.

### examples/dedicated.gd (was line 1643)

How long the copy may run before it is killed and this probe fails. A copy that is still running this long after it started is hung, and the likeliest reason is the one that says nothing at all: a scene whose script failed to parse never reaches `quit()` and prints nothing. `-- --exit-probe-seconds N` lowers it, which is how the deadline itself is armed — any N shorter than the suite takes is a copy that is still running when it expires.

### examples/dedicated.gd (was line 1663)

Runs this same suite in a fresh process: `[exit code, its stdout, its stderr, whether it had to be killed, the seconds it was allowed]`.

[b]A leak is reported after `quit()`, by the engine, where nothing in the process that leaked can read it.[/b] "N ObjectDB instances were leaked at exit" is printed once the scene tree is gone, so the only process that can check a run's exit is another one. On Godot 4.7.2 a script that names itself, loaded after its base, cuts the engine's exit teardown short and every script loaded before it is reported leaked — hundreds of lines a passing run printed for weeks, which is why this is a check now and not a warning.

[b]First, before this run opens a port[/b], so the two never contend for a socket — and so this run is always the second one against the same `user://`, which is the other thing no single run can see.

[b]Not `OS.execute`.[/b] That blocks until the copy exits, so a copy that hangs held this run for ever; and when the outer `timeout` then killed this run, the copy was left behind holding the suite's directory and port. So the copy is started, polled against a deadline and killed at it. Two deadlines, because Godot dies on SIGTERM without running a line of script — nothing in this process can clean up after it is killed:

- coreutils `timeout` wraps the copy where it exists. It is an exec wrapper, not a shell,   and it outlives this process, so a copy orphaned by the outer `timeout` still dies on   time. Its exit status 124 is how its expiry is recognised. - this loop's own deadline, a little later, for a platform without it.

`execute_with_pipe` rather than `create_process`, because the latter captures nothing and the whole point is reading what the copy printed. Non-blocking, and drained on every pass rather than once at the end: a pipe holds 64 KiB, and a copy that fills it blocks on its next print — a hang this probe would then report as the suite's own. The copy's stdin is the other end of a pipe this process holds open, which is why every suite turns the server's stdin console off: a reader blocked on it never lets the copy exit.

### examples/dedicated.gd (was line 1756)

Every leak line is the engine's, and the engine writes them to stderr; both are searched so that stays a fact about the engine rather than an assumption here. Shown apart, because a pipe each is two streams whose interleaving is lost, and where a hung copy had got to is the end of its stdout.

### examples/dedicated.gd (was line 1794)

[b]A runner behind its loading cover is not run over, and is once the cover lifts.[/b] A real [DotClientLink] joins over the server's ENet socket and says nothing, as a client still loading its level does. A bus hit and a barrel's blast must do nothing to it; an operator's damage (a slay or slap goes straight to dot-combat) still lands. The client then sends `game.cover` on the real wire and the same hits land.

### examples/headless_config.gd (was line 3)

BfhConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff and the workbench round trip.

[codeblock] godot --headless --path . res://examples/headless_config.tscn [/codeblock]

### examples/headless_mapcfg.gd (was line 6)

A bowl gets its `cfg/` file's values and the next bowl gets the previous values back, on the server's cvars and on the client's hooks.

[codeblock] godot --headless --path . res://examples/headless_mapcfg.tscn [/codeblock]

The cvars start away from the file's values; the file is written for the run and removed after it.

### examples/headless_net.gd (was line 3)

game-buses-from-hell over the wire: a real server, a real client, and a lossy loopback between them.

[codeblock] godot --headless --path . res://examples/headless_net.tscn [/codeblock]

[b]Everything here is the real path minus the socket.[/b] Two [BfhGame]s, two [DotNetManager]s, two [BfhNetBridge]s and two links, with [member BfhNetLink.loopback] standing in for the RPC — which means the encoders, the schema seal, the snapshot build, the interest decision, the prediction and the reconciliation all run. What it cannot test is Godot's own RPC routing, and that is what `dedicated.gd` and a real client are for.

[b]The client world lives in its own [World3D], and that is a finding rather than tidiness.[/b] Both halves are in one scene tree, so without it they share one physics space: the client's mirrored crates are frozen bodies sitting exactly where the server's real ones are, and every server crate spends the round being pushed out of a copy of itself. Nothing errors — the positions just stop agreeing, which reads as the replication being wrong when it is the test harness that is wrong.

[b]And the client is deliberately put on a different tick rate and a different bowl size than the server.[/b] One process has one engine rate and one default config, so two halves agree by construction and a check that asserts they agree is passing for the wrong reason. A real client is a separate program with its own export and its own `user://` config. Make them disagree, and let HELLO correct it.

### examples/headless_net.gd (was line 90)

Every encoder against its decoder, because nothing else checks that they are inverses.

This family has already shipped a serialisation whose two ends never met: dot-moderation wrote `"voice muted"` and read back a warning, and the one thing that addon existed for silently did nothing.

### examples/headless_net.gd (was line 392)

A mirrored body has to be where the server says, and it has to have got there from a SNAPSHOT rather than from the announcement: the PROP event carries a spawn position, so a client that never applied a snapshot would still pass a naive comparison. The crates are dropped from above and settle, so their y moves after the announcement — which is what makes this check meaningful.

### examples/headless_net.gd (was line 510)

[b]Off the replicated layout, not off the node.[/b] A bus goes over the wire through [DotVehicleNetSync] — three floats, a quantised quaternion, a speed and a steering angle — and NOT through the `net_position` a crate uses. Reading the wrong one gets the zero the property was constructed with, which is a mirror that looks like it is parked at the origin.

### examples/headless_net.gd (was line 547)

[b]At what speed, not only whether.[/b] "More than a metre in 40 ticks" is a sixth of what 40 ticks at `runner_speed` covers, so a runner the server moved at a fifth of their speed passed it. The distance is short of the full 4.3 m by the input lead (the first commands are still in flight when the window opens), so the speed on the last tick is the number that says the commands arrived whole. Printed, always.

### examples/headless_net.gd (was line 604)

[b]The local runner is predicted, and nobody else is.[/b]

Until 2026-09-25 `BfhNetBridge._apply_join` mirrored every player with owner 0, this client's own included, so `is_owner` was false for the local runner, `predicted()` was empty, and the runner moved only when a snapshot came back. "A runner moves" passed throughout, because a client adopting the server's answer also agrees with the server, and its "without being corrected" passed with zero corrections because the predictor never ran. So these assert the MECHANISM rather than the agreement: who owns the entity, what the registry predicts, that a key moves the runner in the tick it is pressed with no snapshot in between, and that a disagreement is corrected and converges.

### examples/headless_net.gd (was line 710)

[b]A disagreement the client cannot know about[/b]: an admin moves the runner on the server. The client predicted standing still, so the next snapshot is a correction — and the proof that the predictor RUNS rather than the client simply adopting what it is sent is that the correction counter moves.

### examples/headless_net.gd (was line 769)

[b]A JOIN that beat its HELLO.[/b] `_admit` sends HELLO first, so the order this guards is not one the server produces today — which is exactly why it is driven through the real path rather than trusted: the local entity is put back to how an early JOIN would have built it (owned by nobody here), and the server admits the peer again, so a real HELLO arrives for a player the client already has.

### examples/headless_net.gd (was line 1115)

[b]The one piece of state in this suite that outlives the process.[/b] A punishment store is a FILE, and a gag issued by the last run is loaded by this one — so the check that a line goes through BEFORE the gag fails on the second run and passes on the first, which is the worst way for a test to be wrong. Removed rather than scoped: a suite that leaves punishments in `user://` is a suite that changes what the next one measures.

### examples/headless_net.gd (was line 1163)

Through `issue`, with the SUBJECT spelling dot-moderation uses — `key_for_peer` above answers the same way, and a gag against a differently-spelled subject is a gag that silences nobody and reports success. Awaited, because a punishment MAY be written to an HTTP store; a file store runs to completion inside the call and returns like an ordinary function.

### examples/headless_net.gd (was line 1247)

A snapshot bigger than [member DotNetConfig.mtu] arrives in parts, through this game's own link and bridge, and every body ends up where the server's is.

[b]The round's spawn is the snapshot that needed it.[/b] A full bowl is about 88 crates, barrels and buses, all new and all falling at once, at about 16.6 bytes each: 1450 to 1478 bytes, over the 1392 that Godot's ENet peer carries in one unreliable packet, so ENet fragmented it and a native client lost it whenever it lost either fragment. This suite's bowl is ten crates, so the MTU is lowered to give the same shape here: every body thrown up at once, more state than one packet holds.

### examples/headless_net.gd (was line 1331)

An administrator's blind and beacon, through this game's real handlers, over a link that drops one snapshot in five.

[b]The audience is the whole point of both.[/b] This client owns player 42 and does not own the bot driver. A blind is its owner's screen and nobody else's, so the client must be told about its own and must NOT be told about the bot's — a driver who could read a runner's blind would know who cannot see the bus coming, and this is the same audience rule seen from the other seat. A beacon is for everybody, so the client must get both. Asserted on the client's own copies of the players, which is what its HUD and its beacon markers read.

### examples/headless_net.gd (was line 1452)

Another runner has a body, it is where the server has them, and it moves every frame.

[b]Nothing on a networked client drew anybody else until 2026-09-24,[/b] and two things were missing at once: there was no body to draw (a runner is first person and a driver is a bus, so no person had ever been on screen), and `DotNetManager.interpolate_frame` was never called — so even a body would have moved only when a snapshot landed, a third of the ticks here. Every section above passed throughout, because every one of them reads the simulation and none reads the screen.

Driven through `BfhClient.present_frame`, the function the real client's `_process` calls, so a client that stops interpolating or stops building bodies fails here rather than in a screenshot. Who somebody is reaches every client: the face they were seated with, and a new name and face when the server learns them — which is what dot-platform's admission, a wardrobe change and an operator's rename all end in.

[b]Asserted on the drawn figure, not on the field.[/b] A client that stored the avatar and drew the hash anyway would pass every check about the document; the atlas the figure was BUILT with is the thing a player sees. A runner, because a driver wears the uniform whatever their face.

### examples/headless_net.gd (was line 1651)

Somewhere a person can run in a straight line: the most open floor in the bowl, asked of the arena, with the run's 6.4 m inside the clear circle (yaw 90 runs toward -x, so the start is 3 m to +x of its middle). Placed on the server, as a respawn would be; the client learns it from snapshots.

[b]Not "2 m beside this client's own runner", which is where it started until 2026-10-08[/b]: wherever that runner happened to stand, which on three runs in four was beside the ramp's slab, so the run went off its edge and FELL — 21.65 m of path in 60 ticks, an accelerating curve that drawing between snapshots rounds by 0.25 m, and a failure of the tracking check below that had nothing to do with tracking.

### examples/headless_net.gd (was line 1705)

Tracking: every frame's body is within a hand of the path the server really ran them along. Not the latest position, because a remote player is drawn an interpolation delay in the past on purpose.

[b]The path, as the segments between ticks, and not the tick positions alone.[/b] A frame drawn between two ticks lies between two of them, and its distance from the nearer one is up to half a tick's travel, which at anything faster than a run (a throw, a fall) is most of the tolerance.

### examples/headless_net.gd (was line 1741)

Smoothness: at a steady running speed each frame should advance the body by about the same distance. A client that draws only at snapshot arrivals moves it on one frame in twelve and not at all on the other eleven, which is the jitter the family measured as a 47% change in apparent speed.

### examples/headless_net.gd (was line 1783)

The players voted for another bowl: the server rebuilds its own at the next round's start and the client rebuilds to match, from a BOWL sent between the last round's PROP_GONEs and this round's PROPs. Without it the client keeps the bowl it joined on, with the wall where the server has floor, which is the bug the HELLO's radius exists to prevent on joining. Late in the run, because every section after it would be in a different bowl.

### examples/headless_net.gd (was line 1979)

[b]Somebody else first, because that is the half a client is told about.[/b] A peer that disconnects is not sent its own LEAVE — it has gone — so removing this client proves nothing about whether the message works. The bot has no socket and leaves the same way a second player would.

### examples/headless_net.gd (was line 2021)

Run down on the server, the client's camera goes where the server says, and every noise and cue on the way reaches the client's world as the same signal an offline one emits.

[b]The server decides and the client draws.[/b] What crosses is the view as per-player, owner-only state (`net_watch`, `net_watch_target`) and each click as a request; the camera itself is computed on the client from the positions it is already drawing. So the checks are that the client's mirror is in the view the server chose, that its camera is on the client's OWN copy of the bus, and that a click is answered by the server's list.

### examples/headless_net.gd (was line 2093)

At the client's copy's CAB, which is where `BfhSpectate.pose_of` puts a bus's eyes and so what a death camera looks at — not at the hull's centre. Measured to the centre this held only at range: once the runner was flattened 6.5 m from the bus, the cab 3.8 m up and 1.2 m forward of it read as 0.88 of the way there, with the camera exactly right. What makes it the client's OWN copy is `client_bus`, not the point.

### examples/headless_net.gd (was line 2228)

The server sets a barrel off; the client draws it, where it went off and as far as it reached, from the BLAST alone.

Through [BfhFx] listening to the client's world, which the bridge makes emit `barrel_exploded` from the BLAST — the path [BfhClient] builds. Armed by not connecting that signal in `BfhFx.setup` (the drawing checks fail) and by not calling `configure` on the spawned node (the radius and the drawn reach fail).

### examples/headless_net.gd (was line 2318)

The client's scoreboard over the real match: both sides from the roster the server sent, the tallies dot-match kept on the server, up on its own at a round's end with that round already counted, and on Tab.

Armed: with the CLOCK sent after the ROUND in `_on_round_over`, "already counted" fails; with the tables' `custom_minimum_size` removed, the size check fails; with the teams put back at the end of `_build_progress`, or without `teams.reindex()`, the sides check fails.

### examples/headless_run.gd (was line 23)

Proves the bowl, the crates, the hammer, the barrels and the buses all actually work.

[codeblock] godot --headless --path . res://examples/headless_run.tscn [/codeblock]

[b]The checks that matter are the ones that cross an addon boundary.[/b] dot-props, dot-combat, dot-match and dot-vehicle are each tested in their own repository and each of them passes there; what has never run before this game is the joins, and the family's own record says that is where everything is found. So the sections here are named after joins rather than after classes — a player standing on a crate, a hammer against a prop's health, a barrel against a person's, a bus against both.

[b]It steps the world by hand.[/b] `BfhGame._physics_process` drives itself on a server; a suite that let it would be asserting against a tick count it does not control, so `set_physics_process(false)` goes on first and every section advances the world itself.

### examples/headless_run.gd (was line 66)

The same for a route with jumps in it, and it is lower for a reason rather than for slack: the route bot stops pressing forward inside 0.2 m of each waypoint, turns to the next, and lands every jump with a tick of friction, so a crate from a run reads 73% and the scaffold's climbs 65%. A floor under those rather than at them, so it catches a bot that crawls (the failure `[bot-drive-1]` found: a seventh of the speed) without failing on a bot that climbs the way a person does.

### examples/headless_run.gd (was line 166)

A bus on its roof rights itself.

[b]Found by looking at a delivered client, not by a check.[/b] A screenshot of a real server showed a bus lying on its roof at the foot of the ramp with a round still running — a quarter of this game's whole threat removed, for a reason the runners can neither see nor cause. Nothing in the simulation is wrong when that happens: an inverted rigid body is a legitimate state and every number about it reads correctly.

### examples/headless_run.gd (was line 339)

An administrator's blind and beacon, as a client draws them.

[b]What the server decides is `dedicated`'s and who is told is `headless_net`'s; this is the picture.[/b] The world here is authoritative, which is an offline client — the same flags a snapshot would have set, read by the same HUD and the same player. What no assertion can say is whether it LOOKS right: `tools/shot.sh` with `--blind` and `--beacon` is that.

[b]The viewport is 64 × 64 here[/b] (docs/testing.md), so the coverage check says the rect is the viewport's, not that the viewport is the window's. It was armed by moving the HUD's root in from the edge with the per-frame sizing taken out.

### examples/headless_run.gd (was line 505)

[b]And a physics space of its own, for the same reason.[/b] Every world here used to be added straight under this node, so all of them shared the root viewport's World3D and so ONE physics space, which outlives every world freed from it. A bus wedged against a drum is contact physics sensitive enough to read that history: the courtyard's east lane was "sent home at 6.22 s" after two earlier drives and "works free, reaches at 3.73 s" with the stacks' second lane run first, or with nothing run first at all. A SubViewport that owns its World3D gives each world a fresh space, freed with it; it never renders, so it costs nothing headless.

### examples/headless_run.gd (was line 527)

Takes a world down NOW rather than at the end of the frame.

[b]`queue_free` was what this file used and it is why the run leaked.[/b] A queued free happens on the next idle frame, and the last few sections are followed by `quit()` — so the worlds they built were still alive when the engine tore down, which Godot reports as leaked ObjectDB instances. It reads exactly like a reference cycle in the game and is a test that stopped one line early.

### examples/headless_run.gd (was line 553)

Whether a bus moved further in one tick than it can drive: the stuck rule's teleport.

[b]A jump, not a place.[/b] These checks used to ask whether the bus was within 4 m of its start line, which was a teleport detector only by luck: the start line sat under the ramp, where no chase ever went. Moved out beside the ramp on 2026-09-23, it was 2.8 m from the line a bus takes round the first tank, and a bus that came round the drum perfectly was reported as sent home. At its top speed a bus covers 0.4 m a tick.

### examples/headless_run.gd (was line 564)

Called once a tick by every chase this file drives, with a fresh [param what] (and [param first] true) on its first tick.

[b]A bus can lose a chase three ways, and only two of them were ever looked for.[/b] It can be run home by the stuck rule, it can wedge, and it can PARK: stand still with the throttle off, which the stuck rule never answers because it reads intent, so it sits there for the rest of the round with the runner in plain view. `steer_around` did it for a week (a bus handed the point it was already standing on, beside a pillar, which the driver calls arrived), and every table here printed it as "never reached them".

### examples/headless_run.gd (was line 631)

[b]The layout's two choices (2026-10-07), as data.[/b] The courtyard's west lane ships at the decision (past LANE_THROUGH) with the old 6.6 m selectable, still a bus's gap. The hook ships as built, because the decided "wide" hook breaks the gap rule at the scaffold (see `BfhArena.HOOK_LAYOUTS`); "wide" is selectable and its gaps are the bot's.

### examples/headless_run.gd (was line 706)

Every bowl the players can vote for holds the map-wide rules the shipped one is held to: no gap under a bus's width between any two obstacles, nor between an obstacle and the scaffold. A bowl is a radius, and the features are placed as fractions of it, so a new radius is a new map nobody has measured until this has.

### examples/headless_run.gd (was line 859)

One bot bus chasing a runner who stands still wherever the scatter put them, and who is moved to a fresh spot each time the bus gets within [constant REACH_M] of them (or after [constant REACH_GIVE_UP] seconds without). Returns `{covered, seconds, resets, reaches, stalls, longest_stall, stall_at}`: how far the bus travelled, how many times the stuck rule put it back on its start line, how many runners it got to, and how long it stood throttling at nothing, and where.

### examples/headless_run.gd (was line 932)

What a bot bus is held to over [constant PACE_SECONDS] of chasing runners who stand wherever the scatter puts them. Measured 2026-10-15 before the street route, the unwedge and the ramp-side nudge: 2.65 to 8.1 m/s average (suburb the slowest), two to five sends home and stalls of 5.1 s (the stuck rule's reset) on every map; after, 6.5 to 11.9, none sent home and no stall over a second. The floor is under every "after" with room and over the slowest "before", and the other bars are what separate the rest.

### examples/headless_run.gd (was line 971)

A full table of bot buses, as a server runs: [constant PACK_BUSES] bots driving at [constant PACK_RUNNERS] runners standing wherever the stream puts them. One bus alone never meets another, and a pair wedged nose to flank is a stall no single-bus drive can show. Returns `{buses, covered, resets, longest_stall, stall_at}`, the longest per bus.

### examples/headless_run.gd (was line 1095)

[b]Seeded, so two servers on the same seed lay the same round out.[/b] Asserted against the SCATTER rather than against where the crates ended up, and the first version of this check did the latter: it built a second world, stepped it, and compared prop positions. Two worlds in one process share one physics space, so the second world's crates landed on the first world's and settled a few millimetres elsewhere — and the check failed for a reason that had nothing to do with the seed. Where the seed puts a crate is the thing being tested; what gravity and its neighbours then do to it is not.

### examples/headless_run.gd (was line 1198)

The stacks, which are the only permanent geometry on the floor.

[b]This section used to be the only one at the shipped bowl radius.[/b] `_world` built a 30 m bowl, the stacks are left out below 34 m on purpose, and so every other check in this file ran a map the game never ships. Overriding it here fixed the symptom and left the trap; `_world` runs the shipped radius now, and this section no longer has anything to say about it.

### examples/headless_run.gd (was line 1258)

[b]And the same question of the WHOLE layout, which the check above cannot ask.[/b] That one filters on `local.x < 14.0` -- it is about the two rows, it was written when the two rows were all there was, and it goes on passing about them however many pillars are added past the dog-leg. A pair anywhere on this map closer than 2 * PILLAR_CLEARANCE is a gap `steer_around` will not take a bus through, and the floor behind it is somewhere a runner is safe by standing still. Two drivers against everybody on foot is not a game a runner may win by not moving.

### examples/headless_run.gd (was line 1326)

The check the rest of this section cannot make: a bot bus actually gets past one.

[b]The failure this guards against is not a bus that crashes, it is a bus that vanishes.[/b] `_unstick` reads "throttle held, not moving" as caught on a crate, and after five seconds it puts the bus back on its start line. Nose-on against a pillar is that state exactly, with no crate to blame -- so before [method BfhArena.steer_around] existed, standing behind a pillar deleted the bus chasing you.

### examples/headless_run.gd (was line 1339)

[b]`is_bot`, and nothing else in this file sets it.[/b] `add_player` leaves it false, so every other section's driver is a person who never presses anything -- which is why the bus in them only ever moves when a check drives it by hand, and why `_autopilot` had no coverage at all until this section. A dedicated server with bot drivers is the deployment this game is for, and its steering was the one path in the drive loop nothing had ever executed.

### examples/headless_run.gd (was line 1387)

[b]Put, not moved: `_put` writes the controller's state as well as the node.[/b] This set `global_position` alone, which the runner's next tick overwrites from its state, so the quarry was never behind the pillar at all: the bot chased wherever the round had scattered the runner (the `spawns` stream), and the drive was a different drive on every seed. That was `bfh-stacks-drive-seed-1` (2026-10-07): it passed on one seed, "covering 45 m for a 27 m line", and no prop, driver or layout reset changed it, because the thing that differed was the target.

### examples/headless_run.gd (was line 1441)

--- Through the hook

[b]The same drive against the hook, where the bus has to come round TWO pillars rather than one.[/b] The lane is two tidy rows and every avoidance in it is sideways into open floor; the hook is an arc, so the waypoint beside its first pillar has its second one standing near it. That is the case `steer_around` got wrong until the hook existed to expose it — it chose a side without asking what else was there, drove the bus at a point it could not occupy, and left it holding the throttle against a pillar, which `_unstick` reads as a crate and answers by teleporting the bus to its start line. A steering bug whose symptom is a bus vanishing. By name: the hook was the last three of the layout until the second lane's row was appended after it.

### examples/headless_run.gd (was line 1508)

The tank farm, which is the east half of the bowl and a different question from the stacks.

[b]Four drums of four sizes, and the checks over them are about what a bus can do rather than about where they are.[/b] The stacks got away with a fixed-radius rule because every pillar in them is 1.2 m across; the moment one obstacle on this floor is 4.4 m and another 2.6, every measurement written as a centre distance is answering a question about the wrong thing. So this section asks the two questions [BfhArena.narrowest_gap] exists for -- is there a gap here a bus cannot take, and is there anywhere behind these that a bus cannot get to -- and it asks them of the built map rather than of the layout, because the two clusters are both placed as a fraction of the radius and the floor between them is therefore a function of it.

### examples/headless_run.gd (was line 1559)

[b]The courtyard, and the reason it is the point of the farm.[/b] Four tanks in a diamond leave open floor in the middle, and open floor surrounded by cover is only a place worth standing if the thing chasing you can come into it. Every one of the four lanes between neighbouring tanks is asked directly rather than inferred from the map-wide minimum, because the map-wide minimum is currently a pair in the stacks and would go on passing if the courtyard sealed itself shut.

### examples/headless_run.gd (was line 1587)

[b]And the same question at the smallest bowl that has both features, which is the one nobody would think to ask.[/b] Both clusters are positioned as a fraction of the radius, so shrinking the bowl walks them towards each other while the width a bus needs stays 4.8 m of absolute floor. `TANK_MIN_RADIUS` is that limit written down; an arena built exactly at it has to still be playable, or the constant is a number somebody guessed.

### examples/headless_run.gd (was line 1608)

Nothing is dropped inside a drum. The keep-out used to be a flat `PILLAR_RADIUS + 2.2`, which is 1.4 m INSIDE the biggest tank -- and a crate sharing a volume with a static body is resolved by the physics throwing it across the bowl on the first step.

### examples/headless_run.gd (was line 1624)

--- The steering, at a radius the constant does not cover

[b]The failure mode here is not a bus that misses by too little, it is an aim point inside the drum.[/b] `steer_around` offset its waypoint by `PILLAR_RADIUS + PILLAR_CLEARANCE` -- 4.8 m, a metre and a half less than the radius of the biggest tank plus a bus -- so a driver told to come round this one would have been sent at a point in the middle of it, arrived nowhere, held the throttle, and been teleported home by the stuck rule. The stacks' own version of this check cannot see it: every pillar is narrower than the offset.

### examples/headless_run.gd (was line 1650)

The check the rest of that section cannot make: a bot bus gets round a drum.

[b]The same drive as the stacks and the hook, at the shape neither of them is.[/b] A pillar is narrower than the bus coming round it and a tank is wider, which changes the one thing the driver is doing -- the waypoint beside a 4.4 m drum is eight metres off its axis, so the bus turns earlier, further and for longer, and it does all of that with the quarry out of sight behind the thing it is going round. Nothing in this repository had ever asked the autopilot to come round something bigger than itself.

### examples/headless_run.gd (was line 1739)

Every way up the bowl, measured against what a runner can actually do, and then done.

[b]The family's reach question, asked of this game, and two of its routes were never possible.[/b] The ramp to the ledge was built backwards on the first day — it rose from under the deck to 7.8 m over the middle of the bowl — so the ledge had no way up at all. And the barrel, documented as "the one way onto a crate stack", lifted a runner 7 cm: its upward velocity was added to somebody the motor still had on the ground, and the ground snap ate it. Nothing checked either, because nothing here had ever driven a runner anywhere; every section placed them by hand.

The arithmetic is [code]DotFpsTunables[/code]'s, reached through [code]bfh_reach.gd[/code], over the tunables a real runner gets. The routes are declared by the map and measured off the colliders. Then three of them are driven, because arithmetic that agrees with itself is not a runner on a crate.

### examples/headless_run.gd (was line 1815)

--- Up the ramp, on the stock motor. Until 2026-09-24 dot-player-controller read any upward speed over 0.1 m/s as airborne, so this printed how far the real motor got (0.8 to 2 m) and the check ran on a test-only subclass with the one-comparison fix. The fix is in the addon now and the stand-in is gone.

### examples/headless_run.gd (was line 1842)

A barrel throws a runner onto two crates, which nothing else does.

[b]From the farthest a runner can set one off from[/b] — the hammer's reach to the barrel's face — because that is the weakest throw anybody gets and the one the declared climb is measured at.

### examples/headless_run.gd (was line 1860)

[b]No stack beside them, and that is a finding.[/b] The same blast shoves every loose prop in its radius: measured, a stack of two 4 m from the barrel came apart before the runner came down — the bottom crate 2.5 m along, the top one 6.4 m — while the runner's arc passed over exactly where it had stood. So what is asserted is the throw: high enough for a stack of two, from the farthest a runner can set a barrel off, and survivable from there. That a loose stack is still there to land on is not true, and docs/map.md says so under "What a runner can climb".

### examples/headless_run.gd (was line 1933)

Drives a runner through [param waypoints] the way a person would: run at each one and jump when it is higher and close. Returns the highest the feet got.

[b]The first thing in this file that moves a runner by pressing keys.[/b] A waypoint is where to stand, with the height of what you stand on in [code]y[/code]; one is done when the runner is standing within half a metre of it at that height.

### examples/headless_run.gd (was line 1992)

Prints how the last [method _run_route] went — the ground it covered next to the route's length, the time, and the average speed next to the runner's [code]max_speed[/code] — and returns that average as a fraction of it.

[b]Printed whether or not anything is asserted on it.[/b] A detail line shows only on failure, so a speed that is only asserted is a speed nobody reads again once it passes; `[bot-drive-1]` found game-playground's bots crossing its maps at a seventh of their speed behind checks that had passed for as long as they existed.

### examples/headless_run.gd (was line 2025)

The height a runner can climb and a bus can take away, which is the whole level.

[b]Two drives, and the second is the point.[/b] A runner bot climbs the three steps to the top in three jumps, and that proves the height is reachable. Then a bot bus is pointed at them — the ordinary autopilot, chasing the nearest runner, with nothing told about the scaffold — and the check is that the runner ends up on the sand. A height a bus could not bring down would be a place to win the round by standing on, and this map has a rule against those.

### examples/headless_run.gd (was line 2068)

[b]And on the smallest bowl that has it,[/b] which nobody had asked until the back yard put two drums beside it. Its position and both clusters' scale with the radius and none of their sizes do, so the floor between them closes as the bowl shrinks: at the 40 m this minimum used to be, 1.2 m from a hook pillar.

### examples/headless_run.gd (was line 2114)

[b]With the scaffold where it was[/b], so a way up made by shoving crates is not a climb. [b]And this check alone does not tell the saddle from the old sheer end:[/b] held against that 3 m face and jumping, a runner reached 2.98 m with no crate moved, which is dot-player-controller's airborne creep up a face too steep to stand on (`[steep-climb-1]` in the nightly list). The peak check above is what does.

### examples/headless_run.gd (was line 2161)

Against the scaffold as the round laid it out. Once the scatter began keeping the start lanes clear every prop in the bowl moved, a barrel landed 2.44 m off the scaffold's west end, and this bus could not bring the runner down (34 of 36 crates standing): the barrel braced it. This section cleared the scatter round the scaffold until the scatter kept its own margin there (`scaffold_scatter_margin`, 4 m); now it asks of the real layout, and the bowl layout section asserts the margin.

### examples/headless_run.gd (was line 2172)

Standing still, and told so every tick: a tick with no command REPEATS the last one, which is what a netcode wants of a lost packet — and the last one was "run along the top step", so the first version of this watched the runner walk off the far end 0.7 s before the bus arrived and called it the bus's doing.

### examples/headless_run.gd (was line 2196)

[b]Out of its cells, not broken.[/b] The first version of this asserted crates BROKEN and the bus brought the runner down with every crate intact: it hit the low end at the speed the chase allowed, under the 5 m/s a crate breaks at, and shoved the steps apart instead. That is the same outcome for the runner and a cheaper one for the drivers, and it is what the property is about — the height is gone.

### examples/headless_run.gd (was line 2219)

The farm's second room, between the courtyard and the scaffold, and the two things it is for: a runner goes through it, and a bus comes into it.

[b]Driven both ways, because a room is two claims.[/b] That a runner can get from the middle of the farm through the yard to the top of the scaffold -- the covered way the yard exists to make -- and that a bus, the ordinary autopilot told nothing about the yard, can come into it at a speed that kills and run down somebody standing in its middle. A yard a bus could not get into would be a place to win the round by standing in, and the lane widths alone do not say whether the steering can thread them.

### examples/headless_run.gd (was line 2371)

The third row and the lane it makes, and the three claims a lane is: it is a bus's width and a straight line for the autopilot, a runner can take it to the scaffold, and a runner who stands in it is run down.

[b]Driven both ways, like the back yard,[/b] because a lane that leads to the one height in the bowl is a covered way only if a bus can still come down it: one the steering could not follow a runner along would make the height somewhere to win the round by getting to.

### examples/headless_run.gd (was line 2514)

The north-west rim: four pillars a walk's width off the wall, from the stacks' west end to the deck's west corner.

[b]What it holds.[/b] The walk and every gap in the row are lanes the autopilot drives straight down, on the shipped bowl and on the smallest that has the colonnade, and a smaller one leaves it out; a runner bot goes from the stacks' first lane, out of its west mouth and along the whole walk to the deck's corner at a runner's pace; and the bot bus runs down a runner standing still anywhere in it -- in each gap, on the walk behind each gap, and on the walk from either end -- at a speed that kills. A covered way a bus could not come down would be a place to win by standing still.

[b]What it does not hold, and prints.[/b] The bus from where the west bus starts a round, facing the way it starts, at a runner on the walk. Measured on 2026-10-03 with no colonnade at all, that bus missed a runner standing still on the open floor anywhere 26 to 38 m out across this quarter and ended against the wall; it does the same here. The turn out of the start is the autopilot's, not the colonnade's.

### examples/headless_run.gd (was line 2719)

Which lanes into the courtyard the bot bus can come through, driven rather than computed, and the answer held as a property of the map.

[b]`steer_around` is a nudge, and this is its ceiling written down.[/b] It keeps each drum's radius plus PILLAR_CLEARANCE off the line, so only a lane of [constant BfhArena.LANE_THROUGH] (7.2 m) or more lets it drive straight through; the back yard was laid out to that on 2026-09-27 from a failed drive, and the courtyard's own 5.4 and 6.6 m lanes were computed, not driven, to admit no bot bus. Here each lane is driven twice from 8 m outside it -- once at a runner standing in the courtyard's middle, once at one standing in the lane itself -- and the table is printed.

8 m rather than the back yard's 14 because the east lane's mouth is 31 m from the bowl's centre and a runner's floor ends at 40: 14 m out is inside the wall.

What it holds: through the middle, the drive agrees with the rule in every lane (the wide ones at a speed that kills); nobody standing IN any lane is safe, so a narrow lane is a door that shuts behind a runner and not a place to win by standing still; every room keeps a lane the bus can come in by; and the courtyard has two of each.

### examples/headless_run.gd (was line 2790)

[b]Held to the steering's own test, and since 2026-10-07 not to the lane's width alone.[/b] A lane of LANE_THROUGH is necessary for a straight line to the middle and it is not sufficient: the bot aims 8 m PAST its quarry, so the line has to be clear beyond the middle too. With the west lane widened to 7.6 m the line through it crosses the east drum's ring 8 m past the middle (5.2 m off its axis against 6.6), and the bus wedges in the lane from 7 to 12 m out: a runner in the middle is reached by the other three lanes, not that one. So a lane whose straight line `steer_around` leaves alone is held to "comes straight through", and the rest are printed: past a blocked line what happens is contact physics on a knife edge (the east lane's bus reaches from 7, 8 and 12 m out and wedges from 10; on 2026-09-30, before the west lane moved the courtyard's middle by 0.24 m, it was sent home from 8.1), and it was that edge, read through a physics space every world in this file used to share, that made this section depend on which ran first (see `_world`).

### examples/headless_run.gd (was line 2830)

[b]Nobody, in any lane, and since 2026-10-07 without an exception.[/b] At 6.60 m the west lane (3) was one: a runner standing in its mouth was sent home from every start 7-12 m out, run down only from 6 (`courtyard-west-lane-1`). It is 7.6 m now, past LANE_THROUGH, so this asks every lane with no list of known refuges in it.

### examples/headless_run.gd (was line 2875)

One drive of the autopilot into the courtyard through its [param lane]th lane, at a runner standing in the courtyard's middle, from [param out_by] metres outside the lane. Returns what happened: [code]outcome[/code] ("reaches", "wedges" or "sent home"), [code]wedged[/code], the first second it stood still after moving off (-1 if never), [code]peak[/code] m/s, [code]seconds[/code] to the outcome, and [code]nearest[/code], the closest the bus got to the runner in metres.

A fresh world each time, so one lane's bus cannot be the next lane's obstacle.

### examples/headless_run.gd (was line 2892)

The drive [method _drive_a_lane] makes, into any gap: [param where] is given the built arena and returns [code][mouth, middle, out][/code] — the gap's middle, where the runner stands when not in it, and the unit direction out of the gap. The bus starts [param out_by] metres along [code]out[/code] from the mouth, facing in.

### examples/headless_run.gd (was line 2967)

The direction to put a drive's bus out along: [param out] itself if a bus started [param out_by] metres along it from [param mouth] stands on clear floor with a clear line to the gap, otherwise the nearest direction either side of it, in 2.5 degree steps up to 45, that does. [param out] unchanged if none does, which [method _line_room] then reports.

[b]A start is not a place until it is asked whether it is floor.[/b] The hook's middle-north gap faces the back yard's west drum (2.6 m), whose axis stands 13.1 m out on the line square to the gap: the 14 m start put the bus's middle 1.07 m from that axis, inside the drum, and the physics threw it out at 121 m/s on the first step (a bus tops out at 22). The 8 m start was inside it too, by 0.2 m at the tail. Both rows were reported as drives at the gap; they were ejections and a drive round a drum. The line is turned rather than shortened so the run-up stays what the row says it is.

### examples/headless_run.gd (was line 2990)

How far the bus is from touching anything on a drive started [param out_by] metres along [param out] from [param mouth]: the least, over every pillar and drum, of the distance from its surface to the strip a bus sweeps from the mouth to the tail of a bus parked at the start, less half a bus's width. Negative is inside something. Every pillar and drum, and the wall; the scaffold's crates are in none of the gaps' lines and the ramp and ledge are across the bowl.

### examples/headless_run.gd (was line 3008)

[b]The hook's two narrow gaps, driven.[/b] `[steer-3]` measured these on 2026-09-29 with a drive that was never kept, through the physics space every world here used to share; the courtyard's west lane read differently once each world had its own. This is that measurement, kept. [b]A bot bus chases a runner up the ramp onto the deck.[/b] Until 2026-10-01 none could: from every start here the bus wedged against the slab or circled the foot, and a runner on the deck was safe from bots for as long as they stood there. Eight starts, a runner standing still on the deck's middle, twenty seconds each; a start counts when the bus kills them.

[b]All eight are asserted since 2026-10-08.[/b] `spawn` and `spawn_west` are where the buses actually begin (beside the slab, either side of it, facing the bowl), and with `sw` they were printed and not asserted for a week: the bus has to turn round in front of the foot, which the timed turn could not do, and `sw` came at the foot across the line and wedged on the ramp's edge. `BfhGame._turn_round_for_the_ramp` is the answer; see docs/bots.md, "Up the ramp".

### examples/headless_run.gd (was line 3113)

[b]Pinned, not fixed (`runner-standing-1`, 2026-10-07).[/b] Both gaps are a bus's (BUS_GAP) and not the bot's (LANE_THROUGH), and a runner standing still in either is never reached by a bot bus: sent home from 8, 11 and 14 m out, each start turned by `_clear_line` onto open floor if the square line is not (the 14 m middle-north start once began inside the back yard's west drum, and the physics threw the bus out at 121 m/s). The decided fix, the middle pillar at x = 30.3, is `hook_layout = "wide"`: it breaks the gap rule at the scaffold, so it is selectable and not shipped (see `BfhArena.HOOK_LAYOUTS`). Pinned so that a hook which does fix it fails these and gets them turned round, as the courtyard's west lane was.

### examples/headless_run.gd (was line 3218)

[b]And nothing REFUSES them either, which `force_balance` alone does not say.[/b] dot-match's team manager has a second rule, `max_difference`, that refuses a join putting one side more than one ahead — so the fifth person here was left on no team in dot-match while `sides` called them a runner. The elimination rule counts survivors off dot-match's teams, so a round ended as soon as the runners it KNEW about were down, with the rest still on their feet. Two against four is the smallest server that shows it.

### examples/headless_run.gd (was line 3267)

Gravity LEFT ON, and the first version of this check turned it off. A crate with no gravity still takes the player's weight — that is the whole point of `DotPropCarry.stand` — so it accelerates downward out from under them and they are carried for about four ticks. The floor is what holds a crate up; removing gravity removes the floor's half of that and measures the bug it was written to catch.

### examples/headless_run.gd (was line 3704)

[b]And the round AFTER the swap is decided by the sides as they are now.[/b] The elimination rule reads teams off dot-match's scoreboard, not off `sides`, so a swap that only flipped `sides` left the rule scoring the old ones: the drivers ran the new runner down and the round was announced as the RUNNERS' win, because the team that had nobody left alive was the one the scoreboard still called the drivers. Every round after the first swap of a server's life had its winner backwards.

### examples/headless_run.gd (was line 3757)

A driver who arrives mid-round gets the bus that is standing empty.

[b]The bot rule is what makes this the common case rather than a corner.[/b] When a person driving disconnects, their bus stays where it is with nobody in it, and the module puts a bot in the seat within two seconds -- in `sides`. Seating only ever happened at the top of a round, so that bot stood on the sand as an untouchable pedestrian and the bus sat still for the rest of the round: half the drivers' threat gone for up to three minutes, from one dropped connection.

### examples/headless_run.gd (was line 3800)

[b]Three checks, and the middle one is the regression guard for the bug that took longest to find.[/b] A bus spawned, seated a driver, collided, ran people over and broke crates — and did not move under its own throttle. Four wheels reported contact, 26 kN of engine force sat on a 2 tonne body, and the speedometer read 0.00 m/s. The cause was not in the drive path at all: this project runs at 20 m/s² because that is what the character movement wants, so each wheel carries 10 kN, and `VehicleWheel3D.suspension_max_force` defaults to 6000 N. The suspension could not lift the bus. It sank until its own hull rested on the ground and the hull's friction held it there.

So the check that matters is not "does it drive" but "is it standing on its wheels": every symptom of that bug is downstream of the body being on the floor.

### examples/headless_run.gd (was line 3856)

[b]Through the driver's own command, the way a person presses W.[/b] This used to drive the chassis directly and then call `simulate`, which drives it AGAIN from the seated driver's pending command — nobody's, so throttle 0. The check passed anyway, for nine days, because the bus's start line was under the ramp, which was built backwards and low at that end: the bus rested on it at y = 3.45 and ROLLED north, the wrong way, at 6 m/s. On flat floor the same check read 0.05 m/s. So it was never a check of the throttle, and the path a human driver's keys take into a bus had no check at all.

### examples/headless_run.gd (was line 3878)

[b]Printed, because it is not the number it looks like.[/b] This start lane has one of the round's concrete blocks 13 m in front of it (the scatter keeps blocks out of the pillars, the tanks and the scaffold, and not out of a bus's lane), so the bus peaks at 10.6 m/s and ends the second and a half against it at about 5.5. "Faster than 1 m/s and more than a metre along" passed on that, and would pass on a throttle delivering a tenth of its force. What the throttle reaches on open floor is measured in "what a bot actually travels at".

### examples/headless_run.gd (was line 3900)

How far a bus takes to stop, three ways, from 15 m/s on the south straight, and that S then reverses.

[b]Distances, because "it stopped" passed for the bug.[/b] dot-vehicle handed Godot's wheels the brake in newtons where Godot reads an impulse per step, so the handbrake (Ctrl) stopped a 2 t bus from 15 m/s in about a metre and the bot's foot brake almost as hard: a bus that can stop dead is a bus a runner cannot read. Since dot-vehicle 4f4afaf they are forces. A person's S was reverse thrust until 2026-10-12 and took 21 m; it is the foot brake now until the bus has stopped (`DotVehicleCommand.brake_then_reverse`), so it is measured as the foot brake and then as reverse.

### examples/headless_run.gd (was line 3962)

How far the bus takes from 15 m/s to a standstill on the south straight, by [param how]: "handbrake" (Ctrl held), "brake" (the foot brake, as the bot's autopilot uses it) or "back" (S held, which then goes on holding it two seconds more). `stop` is metres to the standstill; for "back", `back` is metres behind that point after the two seconds and `speed` the forward speed then.

### examples/headless_run.gd (was line 4022)

A handbrake turn: the back end steps out. Godot's raycast vehicle never locks a wheel, so before `handbrake_grip_fraction` a bus turning with Ctrl held turned LESS than without it (dot-vehicle's driving.md measured the same on a car). Measured as the heading turned and the slip angle (between where the nose points and where the bus is going) over the same second of full lock from 12 m/s, with and without the handbrake, through a person's keys.

### examples/headless_run.gd (was line 4073)

One second of D held at full lock from 12 m/s, heading +X on the south straight (D turns it towards the middle of the bowl), with or without Ctrl; then a second with neither key so the grip comes back. `yaw` is the degrees the bus turned in that second, `slip` the most its nose pointed INSIDE its direction of travel (the back end out; a gripping turn's nose points a few degrees outside it, which reads negative), `speed` what was left.

### examples/headless_run.gd (was line 4123)

A runner holding one key across open sand, [param ticks] long, facing +Z. [param jump] is 0 for no jump, 1 for jump held the whole way, 2 for jump pressed afresh on every tick the runner is on the ground, which is what a person mashing the key does. Returns the ground covered in the last second, the speed at the end, the time on the ground, and how many jumps were taken.

### examples/headless_run.gd (was line 4171)

The straight [method _drive_straight] measures: west to east along z = 32, south of the stacks and the scaffold and nowhere near the farm. [b]Not the centreline[/b], which looks open and is not: the hook's pillars stand on it at z = 15 and 22, and the first version of this wedged a bus on one at 11.5 m and read it as a speed.

### examples/headless_run.gd (was line 4227)

What a bot on foot and a bot in a bus actually travel at, beside the numbers the configuration says they should.

[b]The family's `[bot-drive-1]`, asked of this game.[/b] Every bot in the family was driven with forward and jump held, and in the games with auto-hop that is a player who leaves the ground on the tick they land, never gets a ground tick to accelerate in, and bleeds to the air cap: 1 m/s of a 7 in one of them, behind checks that passed for as long as they existed. This game has auto-hop OFF (docs/design.md, "No bunny hopping"), so the question is different and the answer has to be measured rather than assumed: a held jump here is ONE jump, and the route bot only presses it at a face. What is asserted is what the design says — a runner holding a key runs at `runner_speed`, and jumping does not make them faster — and every number is printed, because a detail line shows only on failure and a number only asserted is a number nobody reads once it passes.

### examples/headless_run.gd (was line 4290)

--- A bus, across the bowl, by the bot and by a person

The same straight both times, along the south of the bowl: a person holding the throttle, then the autopilot chasing a runner held at the far end. The autopilot's `target_speed` is `bus_top_speed` and it aims eight metres past the runner so that it never eases off for arriving — so the two runs should be the same run, and if the bot's is slower the bot is holding back.

### examples/headless_run.gd (was line 4326)

Where a runner who has been run down looks, decided by the authority.

[b]Until 2026-09-25 they looked at the sand they were run over on, for the rest of the round.[/b] Out is out here, so that is not the two seconds before a respawn; it is most of a round. What is asserted is the policy as much as the camera: the living do not watch, the bus is watchable and is watched FROM ITS CAB rather than from where its driver sat down, nobody watches themselves or the dead, a leaver hands the camera on, and a new round ends it.

### examples/headless_run.gd (was line 4370)

[b]At the bus's CAB, which is what the death camera looks at[/b] (`pose_of` the killer, 3.8 m up), not at the body's origin under it. Measured against the origin this read 0.87 on two seeds out of six: the runner is wherever the round scattered them, and a runner who fell a few metres from the bus looks up at a cab the origin is well below.

### examples/headless_run.gd (was line 4536)

The catalogue, the stand-ins, and every noise reaching a client's ears.

[b]The two directions that fail silently, first.[/b] An id with no recipe is a sound that stays silent for ever on a deployment with no audio files — every deployment, today — and a recipe for an id the catalogue lacks is a decision that reaches nothing. Then the world: every noise it is supposed to make, made, and heard by `BfhAudio` through the null sink a headless run gets (dot-audio's own honest device check). What no assertion here can reach is whether a speaker moves; see docs/client.md.

### examples/headless_run.gd (was line 4706)

The engine, from the bus as drawn. Still, it idles; moved at 18 m/s it pulses faster and the client hears the speed it is being drawn at.

Every pulse is finished as soon as it starts: the null sink never ends a sound on its own, and a pulse is 75 ms, so without this the engine's concurrency cap would be what this counted.

### examples/headless_run.gd (was line 4754)

The five numbers, counted from what happened, and what they earn.

[b]Every reading is a world signal[/b], so this section drives the real paths — a hammer, a bus's impact rule, the round clock — and reads the tracker. The two documents are checked against each other in both directions first: an achievement over a stat nothing records never unlocks, and a stat no achievement reads is counted for nobody.

### examples/headless_run.gd (was line 4930)

The document, what reads it, and the screen that changes it.

[b]A value loaded from disk has not CHANGED, and that is the family's repeated bug.[/b] So the check that matters saves a document with one launch and reads it back with the next, and asserts that the loaded values reached the sampler, the camera and the mixer with nobody touching anything. It uses a memory store, because a suite that wrote to `user://` would pass differently the second time it ran (docs/testing.md).

### examples/headless_run.gd (was line 5051)

Every bare `"res://…"` string in a SHIPPED script that names one of this game's own directories, as `file:line`. See the form-three check that calls it.

The same rule `dot-server-deploy/tools/check.sh` counts, asked here because that tool is not what somebody adding a file runs: comments are prose and skipped, a literal already inside `<Game>Paths.rebase("…")` is the fixed form and skipped, and a path whose first segment this game does not ship — `res://addons/…`, `res://audio/…` in a game with no audio — names the HOST's file and is right as it stands.

### examples/headless_workshop.gd (was line 8)

What a subscribed map pack does to this game's lists, against a fixture [DotContentIndex] and never the process's shared one: a solo map is listed (ballot and map menu) as Name [Pack], an online session lists none, a map kind the game does not accept is left out, and the game's own ids win. A pack's bowl is a JSON document {radius} named in `scene`; a pack entry whose document is missing is not listed at all.

[codeblock] godot --headless --path . res://examples/headless_workshop.tscn [/codeblock]

### fx/bfh_blast.gd (was line 3)

A barrel going off, as a client draws it: a fireball, a shock ring on the sand out to exactly the blast's reach, a flash of light and a few puffs of smoke.

[b]Drawn, never decided.[/b] Where it went off and how far it reached arrive from the server in a BLAST (or from the offline world's own `barrel_exploded`); this reads the two numbers and moves nothing. dot-fx may refuse to spawn it at all — a low tier, a budget, a client whose pack is still arriving — and the round is the same round.

[b]The ring is the part a runner reads, so it is sized to the radius and not to taste.[/b] What a runner needs from a barrel they did not see is "was I inside it", and the ring ends where the blast's reach ends: [method drawn_reach] measures the drawn mesh, and `headless_net` holds it to the radius the server sent.

Built in code rather than authored in the scene, like the bowl and the beacon: this game ships no particle art, and a mesh made here needs no texture a mounted pack could lose.

### game/bfh_arena.gd (was line 10)

The bowl: a round sand floor, a wall around it, and a ledge the drivers look from.

[b]Built in code and dev-textured, like every other map in this family.[/b] There is no art here and there does not need to be: the whole of this game's geometry is a disc, a ring of wall and a shelf, and what a player has to read off it is distance and closing speed rather than detail. A repeating grid at a known size is better at that than a texture would be.

[b]The floor is a single disc collider and not a heightmap.[/b] A bus at 22 m/s crossing a seam between two triangles is the concave-shape problem dot-props documents from the other direction — a sliding body catches on interior edges — and the fix at this scale is not to have seams. A cylinder is one convex shape.

### game/bfh_arena.gd (was line 44)

How far the ramp's top end runs in under the deck.

[b]A third of a metre, and it was a metre.[/b] The ramp meets the deck's height only where it ends, so however far that is under the deck, the ramp is that far times tan(18) short of the deck at its front edge: 0.32 m at a metre. That is inside a runner's step height and a runner still could not get over it — the slide against the deck's face leaves them moving upward, the motor calls that airborne, and a step is only tried from the ground. They walked all 25 m of the ramp and bounced at the top. At 0.3 the lip is 0.1 and the overlap that keeps it from being a seam is still there.

### game/bfh_arena.gd (was line 55)

THE STACKS: the permanent half of the bowl.

[b]Everything else in this arena is either scenery a bus cannot reach or cover a bus can remove.[/b] The crates are the game and they are also consumable — by the last thirty seconds the drivers have flattened what they could, and the concrete blocks are the floor under that, which is a handful of things to stand behind rather than anywhere to go. So the bowl has one idea in it and the idea runs out.

A pillar is the other thing a person on foot has against a vehicle, and this map did not have one: [b]a turning circle[/b]. A bus is nine metres long and a runner turns on the spot, so a cylinder a runner can orbit is cover that does not have to survive anything — the driver has to come round it, and coming round is the gap the round is played in. It is also the only obstacle shape a raycast vehicle handles honestly: a crate passes under a wheel and lifts the corner (see [BfhGame]'s `_unstick`), where a pillar is taller than the hull and simply stops it.

[b]Laid out as a lane between two rows, not scattered.[/b] Scattered pillars are more cover and less map: every gap is the same gap and a driver has no reason to prefer one line through them to another. Two staggered rows leave a lane a bus can take at full speed, which makes the stacks a place a runner is safe only as long as they stay out of the middle of it — and the lane does not run clean through, because a pillar sits across the far end of it. A driver who commits to the fast line has to get out of it at the other end.

### game/bfh_arena.gd (was line 99)

--- The hook, past the dog-leg

[b]The lane ended in a decision and then in nothing.[/b] A driver who took the fast line had to get out of it at the dog-leg, and what was on the other side of the dog-leg was open floor -- so the whole feature was one move long, and the move was always the same one. Past the last pillar the map went back to being a bowl with a lane in the corner of it.

Three pillars in a triangle, entered through three gaps rather than one. It is the tightest cluster on the map: a runner inside it has three things to orbit within six metres of each other, which is the only place here where losing a bus does not mean crossing open ground to the next pillar. A driver gets the opposite problem -- whichever gap they come in by is not the one their quarry will leave by, and coming round one pillar puts the next between them.

[b]Every gap is wide enough for a bus, and that is a rule rather than a happy accident.[/b] Two pillars closer than 2 * PILLAR_CLEARANCE leave a gap a bus cannot take, which would make the space behind them somewhere a runner is safe by standing still -- and a game whose runners win by standing still is not this game. `narrowest_pillar_gap` is the measurement and `headless_run` asks it of the whole layout, not of the hook.

These three are [constant HOOK_LAYOUTS]' "tight" hook, the default; see there for the "wide" one an operator can choose instead, and why it is not the default.

### game/bfh_arena.gd (was line 127)

--- The second lane, south of the first (2026-09-29)

[b]The stacks were one lane, so the fast line through them was always the same line.[/b] A driver coming at the west end knew where the runner had to be, and a runner who was in the lane had two moves: out through a row, onto open floor, or on to the dog-leg. A third row makes the rows between it and the old south row a second lane, and turns the west end into a fork: the old lane ends at the dog-leg and the hook; this one ends at the hook's south pillar, offset in it the way the dog-leg is offset in the first, and past it is the open floor to the scaffold's west end. [b]A covered way from the stacks to the height, which the back yard made from the farm.[/b] Two features with a way to the one height in the bowl, and a runner on it can see which one the bus is coming out of.

[b]Wider than the first lane, on purpose: 7.6 m of clear floor against 6.8.[/b] `steer_around` keeps radius + PILLAR_CLEARANCE (4.8 m) off every axis, so a lane whose rows stand 4.6 m either side of its centre line is threaded by nudges, and only one of 7.2 m or more (LANE_THROUGH) gives the autopilot a straight line down it. The first lane is the bus's hard line; this one leads to the scaffold, and a lane a bus cannot chase down on the way to the height would make the height a refuge. Staggered against the row it faces and two long, starting 4 m further east than it, so the west end is a funnel of two mouths rather than a wall, and the east end opens south onto the floor to the scaffold rather than a third pillar standing on it (one at x = 12.5 stood where a bus coming at the scaffold's low end from the west has its tail).

### game/bfh_arena.gd (was line 158)

The hook's three pillars, stack-local, by name: what [code]BfhConfig.hook_layout[/code] chooses between. Each replaces [constant PILLAR_LAYOUT]'s [code]HOOK_FIRST[/code] to [code]HOOK_FIRST + 2[/code] in that order (north, middle, south).

[b]"tight" is the hook as built, and still the default: gaps of 5.59 m (south-middle) and 5.56 m (middle-north),[/b] past [constant BUS_GAP], so a bus fits, and under [constant LANE_THROUGH], so the autopilot does not go -- a runner standing still in either is never reached by a bot bus (`runner-standing-1`, pinned in `headless_run`).

[b]"wide" is the 2026-10-06 decision for that item, kept selectable and not the default, because it breaks the gap rule it was meant to keep (measured 2026-10-07).[/b] The middle pillar at x = 30.3 opens the gaps to 7.44 m (south-middle) and 7.56 m (middle-north), and a bot then runs down a runner standing in either from 8 and 14 m out -- but from 11 m out at the middle-north gap it is still sent home (the back yard's west drum turns that approach 17.5 degrees off square, and 7.56 m at that angle is inside the steering's corridor), and the middle pillar stands 3.48 m from the scaffold on the shipped 46 m bowl (2.63 m at 45) and 4.31 m from the back yard's west drum at 40: gaps under BUS_GAP, which the build logs as a WARN when this is chosen. [b]No other three-pillar hook was found that does better,[/b] by a search over every pillar position within about 3 m of the old ones: the middle pillar cannot move out (the scaffold and that drum), the north one is boxed by the end of the stacks' south row and the dog-leg (opening it leaves a 5.75 m door to the row's end, where the bot wedged), and the south one stands 0.9 m off the line a bus takes at the scaffold's low end (every move that opens it puts it across that line, and the scaffold section's bus no longer brought the runner down). The way through is a change to the steering or to the hook's neighbours: Christian's call.

### game/bfh_arena.gd (was line 218)

Below this the lanes would not fit inside the floor and the stacks are left out.

[b]36, and it was 34.[/b] The second lane's west pillar is the stacks' furthest from the bowl's middle, and at 34 it stood 0.9 m outside the floor a runner may be on (`runner_area_radius`): cover nobody can use, and 5.1 m of floor between it and the wall. `headless_run` asks every pillar of it at this radius as well as at 46.

### game/bfh_arena.gd (was line 226)

THE TANK FARM: the east half, and a different question from the stacks.

[b]The stacks are a map you can see through.[/b] Eleven columns 1.2 m across, and a runner behind one watches the bus decide which way to come round: everything in that half of the bowl is visible between them from thirty metres, so the game there is reacting to a vehicle you can see the whole time. That is one idea, it is a good one, and it was the only permanent one on the floor -- the rest of the bowl is sand and crates the drivers flatten.

[b]A tank is the same cover with the sightline taken away.[/b] Four storage tanks of 2.6 to 4.4 m radius hide a nine-metre bus completely, so a runner standing at one does not know which side it is coming round, and the driver does not know which way the runner will break. The west half is a game of reaction and the east half is a game of guessing, which is two things for a round to be about instead of one.

[b]Arranged around a courtyard, not as a cluster.[/b] Four tanks in a loose diamond leave open floor about a dozen metres across in the middle with four lanes into it, so the courtyard is the most dangerous ground in the east exactly as the middle of the lane is in the west: cover on every side and no way to know which gap the bus is in. Every one of those lanes is wide enough for a bus, which is the rule the stacks already live under -- see [method narrowest_gap]. A courtyard a bus could not enter would be a place a runner wins the round by standing still in, and this game has two drivers against everybody on foot.

[b]No yaw, where the stacks have one.[/b] The stacks are a lane, and a lane square to the ramp is a corridor a driver lines up on from the moment they land. A ring of drums has no axis to hide: it reads the same from every approach, which is the point of it.

### game/bfh_arena.gd (was line 255)

Tank-local metres and the radius of each, as [code]x, z, radius[/code].

Sized apart deliberately. Four drums of one radius are one obstacle drawn four times, and what a runner is actually choosing between at this end of the bowl is how much floor a piece of cover hides -- a 4.4 m tank is somewhere to lose a bus entirely and a 2.6 m one is somewhere to make it commit.

### game/bfh_arena.gd (was line 267)

--- The back yard, south of the courtyard (2026-09-27)

[b]The farm was one room, and the scaffold stood alone in the open.[/b] A runner who lost the bus in the courtyard had nowhere to take the chase except back out onto sand, and the scaffold -- the only height in the bowl -- stood 23 m from the nearest drum, so reaching it meant crossing open floor with a bus behind you and being knocked off it meant landing on open floor again. Two more drums close a second courtyard between the first and the scaffold: two rooms joined by the courtyard's widest lane, and a covered way from the middle of the farm to the foot of the height. It is the hook's argument made in the east: a feature one move long is a feature whose move is always the same one.

The yard is the two south tanks above and these two, in that order round it ([constant TANK_YARDS]). Its lanes are 5.5, 8.4 and 5.9 m of clear floor plus the 9.5 m it shares with the courtyard -- every one a bus's gap, because a room a bus cannot enter is a place a runner wins by standing in. [b]And the two that face each other, north and south, are wide on purpose:[/b] `steer_around` keeps radius + PILLAR_CLEARANCE off every axis, so only a lane of about 7.2 m or more gives the autopilot a straight line through its middle. The first layout had every lane past BUS_GAP and the bus, sent at a runner in the yard, wedged in the south lane and went home. Sizes 2.6 and 2.2: small, because the yard is where a runner goes to be moving, not to hide.

### game/bfh_arena.gd (was line 293)

The courtyard's west lane, as the clear floor between its two drums (the 4.4 m tank 0 and the 2.6 m tank 3), by default.

[b]7.6 m since 2026-10-07, and it was 6.60.[/b] Under [constant LANE_THROUGH] a lane is somewhere the bot bus stops against a drum, and at 6.60 a runner standing in its mouth was sent home from every start 7-12 m out: a refuge from the bots for as long as they stood there (`courtyard-west-lane-1`). Widened to the stacks' second lane's 7.6, so no lane into the courtyard is somewhere to win by standing still. Tank 0 is what moves, straight out along the line from tank 3 through its [constant TANK_LAYOUT] position, because tank 3 is a side of the back yard too and tank 0 is in nothing else; the north lane it also bounds goes from 8.23 to about 8.4 m.

### game/bfh_arena.gd (was line 339)

The farm's open floors, each as the tanks round it in order, so that neighbours in the list are the two sides of a lane. Indices into [constant TANK_LAYOUT].

[b]Declared, because which drums make a room is the one thing the positions do not say.[/b] Every lane width, the middle a camera or a check looks at, and the drives into each room come out of this and the layout together.

### game/bfh_arena.gd (was line 355)

Below this the farm is left out, and [b]it is not the same number as the stacks' nor about fitting inside the wall.[/b] Both clusters are placed as a fraction of the radius, so a smaller bowl brings them TOWARDS each other while the gap a bus needs stays an absolute width. The limit that matters here is where the floor between the two features closes, not where the farm runs out of sand.

### game/bfh_arena.gd (was line 362)

THE COLONNADE: the north-west rim, beside the drivers' start (2026-10-03).

[b]The quarter of the bowl the buses come out into had nothing in it.[/b] The stacks hold the west, the farm the east, the scaffold the south-east, and the north-west -- thirty metres of sand between the stacks' west mouths, the wall and the deck's west end -- was where a runner scattered at the top of a round spent its opening seconds in the open beside the west bus's start. It is the largest empty floor in the bowl.

[b]Along the rim, not in the middle of it, and that was measured.[/b] The open floor in that quarter is where a bus starting west turns out into the bowl: from its start the bot bus comes round in a wide arc, and on 2026-10-03 it already missed a runner standing still anywhere 26 to 38 m out along that quarter's middle and ended against the wall. A drum and three posts in the middle of it (the first design tried) made that worse -- the bus wedged on the post nearest its start. So the floor is left to the drivers, and the cover goes where a bus does not turn: four pillars on an arc a fixed [constant COLONNADE_WALK] off the wall, from the stacks' west end to the deck's west corner.

[b]A covered way along the rim.[/b] Behind the pillars is a walk the width of the stacks' second lane: a runner on it has a column every ten metres to keep between them and a bus out on the floor, and a driver who wants them has to commit to the walk -- a lane against the wall with only the gaps for a way out -- or shadow them from the floor. It joins the stacks' west mouths to the foot of the deck's west side, so the west half's cover now reaches the height at the north end of the bowl as both features already reach the scaffold in the south.

[b]No door in it.[/b] The walk and every gap between pillars are past [constant LANE_THROUGH], so the autopilot has a straight line through any of them and nobody standing still in one is safe; the courtyard's and the hook's narrow doors (nightly items `courtyard-west-lane-1`, `runner-standing-1`) are not repeated.

### game/bfh_arena.gd (was line 407)

Below this it is left out. The pillars keep their distance from the wall and their spacing, so on a smaller bowl the arc swings in towards the deck's corner and the stacks' west end; measured by [method colonnade_clearance], which `headless_run` asks at this radius. The tightest gap is 6.996 m at 44, 7.264 at 44.5, 7.558 at 45 and 8.216 on the shipped 46 (2026-10-04): it passes [constant LANE_THROUGH] from 44.5, and `arena_radius` is set in whole metres, so 45. It was 44 in the first draft, which `headless_run` refused -- a pillar 7.00 m from the deck's corner, a door.

### game/bfh_arena.gd (was line 438)

Every round obstacle on the floor, and how wide each one is. [b]One description, and everything else is derived from it[/b] -- the meshes, the colliders, the scatter that must not drop a crate inside one, the steering that must not drive a bus into one, and the rule that no two of them may be closer than a bus can pass. This family has shipped the same list twice and watched the copies drift before.

[b]The stacks come first and the tanks after it[/b], which is what lets [method pillars] and [method tanks] be views onto this array rather than two more copies of it. Everything that has to reason about "something solid standing on the sand" -- and that is all of the above -- asks for [method obstacles] and never for either view.

### game/bfh_arena.gd (was line 465)

[b]Cleared first, because building is also REBUILDING.[/b] A client is told the server's radius in the HELLO and rebuilds its bowl to match — the map here is one number, run through this function on both ends — and a second call that only added would leave a 46 m wall standing inside a 30 m one. The player then walks through the wall they can see into the wall they cannot.

### game/bfh_arena.gd (was line 512)

[b]The layout is an operator's to choose now, so the gap rule is said where it is broken.[/b] `headless_run` holds the shipped layout to BUS_GAP; a hook or a west lane set from a JSON file or the environment is not run through the suite, and a pair of drums closer than a bus is a pocket a runner wins by standing in.

### game/bfh_arena.gd (was line 528)

Everything a previous [method build] put here.

`free`, not `queue_free`: the next line builds the replacement, and a deferred free would leave both in the tree for the rest of the frame — two floors, two walls and two sets of colliders, which a body spawned in that frame can land on.

### game/bfh_arena.gd (was line 549)

Where a runner may be put: anywhere on the floor, inside a margin.

[b]The margin is not decoration.[/b] A spawn flush against the wall is a spawn a bus can pin somebody against on the first second of the round, before they have looked around — and a spawn point the wall's own collider overlaps is one the player is pushed out of in a direction nothing chose.

### game/bfh_arena.gd (was line 559)

Metres above the deck surface a bus is dropped from.

[b]Measured from the WHEELS, not from the body, and the first version was not.[/b] The bus scene puts its wheel axles 0.55 m below its origin with a 0.55 m radius, so its origin has to clear the deck by 1.1 m before a wheel touches anything. Dropped at +1.0 the whole vehicle spawned inside the deck: every wheel ray started below the surface, found no contact, and the bus sat there at full throttle with the autopilot steering hard over and the speedometer reading 0.0 m/s. Nothing errored — a vehicle with no wheels on the ground is a legitimate state, it is what being airborne is — and from the floor of the bowl it is indistinguishable from a bot that has not been wired up.

### game/bfh_arena.gd (was line 582)

Where the [param index]th of [param count] buses starts, on the floor.

[b]On the sand, not on the ledge, and that is a design decision as much as a practical one.[/b] The ledge was the buses' starting line for a while and a nine-metre bus cannot get off it: the transition from a flat deck to a ramp beaches it on the lip, front wheels over the drop and chassis grounded, whatever the ramp is angled at. It could be solved with a longer ramp and more ground clearance — and the reference this game is built from does not have the problem at all, because its buses are down in the bowl with the runners from the first second. The ledge is what it looks like it is: somewhere to stand and see the whole floor. The drivers get their overview by spawning there between rounds, not by driving off it.

[b]Beside the ramp, never under it.[/b] The line used to be centred on x = 0, which is the ramp's own centreline — harmless while the ramp was built backwards and rose away from here, and a bus parked under 26 m of slab facing the wedge where it meets the floor once it was the right way round. So the buses stand in lanes either side of it, alternating, [constant BUS_LANE] apart, and the first one is off to the east.

### game/bfh_arena.gd (was line 620)

The bowl's palette: a sunny sand bowl in the family's pastels (game-arena's built-in maps), one colour per kind of thing so a runner can call a place out ("behind the blue tanks", "up the lavender ramp"). Warm sand underfoot, a peach-pink wall, a lavender ledge and ramp, sky-blue tanks with a deeper band, mint pillars with a darker cap. The crates, barrels and buses are Kenney's art and keep their own colours, which are the saturated things on screen: the cover and the threat. Each colour is the tint of the one-metre grid (`BfhTextures`), so the grid stays the same on every surface. The sand is a mid tone, not a pale one: it fills half of every frame, and at (0.98, 0.84, 0.60) the sunlit half rendered at 0.88 luminance under Compatibility, white enough that a crate's shadow was the only thing on it.

### game/bfh_arena.gd (was line 640)

The sun and the sky, as a dot-lighting document.

[b]Built here rather than left to the host scene, and the first render is why.[/b] A Godot scene with no [DirectionalLight3D] and no [WorldEnvironment] is not dark — it is *flat*: every surface comes back its own albedo with no shading at all, so a bowl, the wall around it and the crates in it are three shades of the same brown and the depth a player judges a bus's distance by is simply absent. It looked like a fog bug and is the absence of any lighting at all.

A clear afternoon: a warm sun, a blue sky, a pale cool fill, a little haze on the far wall, filmic tone map and glow. [b]The sun is lowish and from the side[/b]: high noon over a flat disc gives every surface the same light, and a lower sun is what makes the crates cast the shadows a runner reads cover off. The angles are dot-lighting's source convention (a negative pitch is a sun in the sky); the brightness is divided by the profile's reference and square-rooted. The ambient is the shade's light, a pale cool grey: a blue fill at its strength turns every shaded face navy. `sky_top` is this game's (the rig draws the zenith in the ambient colour). The fog distances are source units (metres / 0.01905): haze from 60 m, so the far wall softens and a bus coming across the bowl never hides in it (fog that lost the far wall hid the thing a player reads).

### game/bfh_arena.gd (was line 695)

What this machine draws of [constant DAYLIGHT]: dot-lighting's `painted()`.

[b]Shadows stay on in the browser[/b], unlike dot-lighting's `web()`: the bowl is a few hundred boxes and a crate's shadow is how a runner reads cover. `painted()` is the family's profile for a world of flat colours, matched to the renderer: under the hand-set numbers it replaced (the sun divided by 700, a fill of 0.62) a runner's frame was still 40 % flat white sand and the grid (the speed a runner reads off the ground) was gone. It lowers the exposure, lengthens the tone map's shoulder, grades, and adds a shadowless fill so a crate's two shaded faces are two shades.

### game/bfh_arena.gd (was line 780)

The way down. A bus drives off the ledge onto the floor, which is the only route between the two halves of the map and therefore the only place a runner can do anything about a driver at all.

[b]Derived from the deck rather than positioned by eye, and the eye version did not meet it.[/b] The first ramp was placed at a round number and its top edge came out 0.6 m below the deck's front lip — so a bus drove to the edge, got two wheels over a step it could not climb down cleanly, and balanced there with its nose in the gap for the rest of the round. It looked exactly like a bus that had been told to drive into a wall. Solving for where the top of a ramp of this length at this angle has to be is four lines and cannot come out misaligned.

### game/bfh_arena.gd (was line 802)

[b]Runner-wide, not vehicle-wide.[/b] At 0.6 of the deck it was thirteen metres across, which is a road: the bot drove up it on the way to anybody standing near the north edge, beached itself on the lip at the top, and spent the round being recovered by the stuck rule. Five metres reads as a walkway, which is what it is for — the ledge is height for a runner to dodge from, and the buses start on the sand.

### game/bfh_arena.gd (was line 811)

[b]Positive, and for the game's first nine days it was negative.[/b] A rotation about +X by -18 degrees LIFTS the +Z end, so the ramp was built rising out of the floor under the deck and ending 7.8 m up in the middle of the bowl: a ski jump pointing away from the ledge it was meant to reach. Every number that places it is right, so no check about the ramp's position could see it — a runner walked under it and stopped against its underside, and the ledge had no way up at all. It was found by driving a runner at it; see docs/history.md, "The ramp went the wrong way".

### game/bfh_arena.gd (was line 824)

How many boxes the ramp's collider is built from. The mesh stays one piece.

[b]Because one 26 m box is a floor the motor loses.[/b] Measured: a runner walking up it is grounded with velocity exactly along the slope and then, twenty ticks later, the ground probe reports nothing below them — the swept-query convergence failure dot-player-controller documents for its sweeps against a large flat convex, on a tilted one. They drop into AIR a metre above the surface and stop. Eight boxes of 3.3 m, overlapping by a few centimetres in one plane, walk to the deck; so does a trimesh. Boxes, because a seam in one plane is invisible to a sliding capsule and a trimesh's interior edges are not.

### game/bfh_arena.gd (was line 902)

The clear floor in the named hook's two narrow gaps: [code]x[/code] south-middle (the third pillar to the middle), [code]y[/code] middle-north (the middle to the first), as `headless_run` names them. The base between the outer two is not one of them: it opens onto the dog-leg, with no straight run at it.

### game/bfh_arena.gd (was line 1019)

A road, flat on the floor and never solid: a strip between two points or a disc. Painted a hair above the sand so it does not shimmer against it, and thin enough that nothing drives over a lip. Roads are the streets the buildings leave, drawn so a player can read the kind of place; the gap rule is about the buildings.

### game/bfh_arena.gd (was line 1203)

The narrowest clear floor between a colonnade pillar and anything that is not the walk or a neighbour in the row: every other cylinder, the ramp's slab and the deck. The walk (to the wall) and the gaps in the row are fixed by construction and measured by their own checks.

[b]Held to [constant LANE_THROUGH], not [constant BUS_GAP].[/b] A gap a bus fits and the autopilot cannot drive through is a door a runner can stand in, and two of those are open questions on this map already.

### game/bfh_arena.gd (was line 1268)

A band around the top and one around the waist, mesh only. A tank is a big smooth cylinder and the grid alone gives a runner nothing to judge the distance to it by; two horizontal rings at known heights do, and they read from across the bowl.

No collider on either, for the reason the pillars' capital has none: the only body that could reach one is a bus, and a lip that catches a hull three metres up is a way to stop a bus that nobody drew on the floor.

### game/bfh_arena.gd (was line 1323)

[b]A capital, and it is mesh only.[/b] A bare cylinder against a bare disc gives a player nothing to judge its height by until they are beside it, and height is the whole reason to run at one. A wider band at the top reads at distance. It carries no collider deliberately: the only body that could reach it is a bus, and a lip that catches a hull at 5 m is a way to stop a bus that nobody drew on the floor.

### game/bfh_arena.gd (was line 1400)

The clear floor a lane needs before the bot bus will drive straight through it, in metres: [constant PILLAR_CLEARANCE] each side of the line through its middle.

[b]Not [constant BUS_GAP], and the difference is the steering, not the bus.[/b] [method steer_around] treats any obstacle whose axis is within its radius plus PILLAR_CLEARANCE of the line as in the way, and a line down the middle of a lane of floor [code]g[/code] passes [code]radius + g / 2[/code] from each side's axis -- so below this width both drums are "in the way" of the straight line, the nudge sends the bus beside one of them and into the other, and it wedges (driven, `[steer-3]`, 2026-09-27). A bus would fit; the autopilot does not go. See [method yard_refuges].

### game/bfh_arena.gd (was line 1413)

The lanes round the [param index]th yard the bot bus cannot drive through, as lane indices (see [method yard_lanes]): every lane narrower than [constant LANE_THROUGH].

[b]Deliberate, and a runner's.[/b] A lane a runner can go through and a bus chasing them cannot follow is a door that shuts behind them -- the bus has to go round to a wide lane, and the bot bus that tries it anyway wedges and is sent home by the stuck rule. It is not somewhere to win by standing still: a runner standing IN one is run down from outside it, and the room behind it is open through its wide lanes, which is why every yard must keep at least one lane of LANE_THROUGH (checked). Measured and held in `headless_run`'s "the courtyard's four lanes, driven".

### game/bfh_arena.gd (was line 1432)

Everything solid standing on the sand: the stacks, then the tank farm.

[b]The steering, the scatter keep-out and the gap rule all ask for this and none of them asks which feature an obstacle belongs to[/b], because a bus wedged nose-on does not care whether the thing in front of it is concrete or steel. The two named views above exist for the map's own checks and for a camera that wants to look at one feature; anything about the physics of the floor belongs here.

### game/bfh_arena.gd (was line 1448)

The least clear floor between any two obstacles on the built map, in metres. INF when there are fewer than two.

[b]Face to face, not axis to axis, and that is the whole reason this exists next to [method narrowest_pillar_gap].[/b] That one is static, is measured in stack-local metres, and compares centre distances -- which is exactly right for eleven columns of one radius and says nothing at all about a 4.4 m tank standing 8 m from a 3.0 m one. The rule was never about how far apart two centres are; it is about how much floor is left between them for a bus.

[b]And it has to be asked of the BUILT map rather than of the layouts.[/b] Both clusters are placed as a fraction of the bowl radius, so the distance between a pillar and a tank is a function of the radius -- the one measurement in this map that cannot be taken off the constants somebody edits. A bowl small enough to close the floor between the two features would have a gap no bus can take and nothing in the layouts would show it.

### game/bfh_arena.gd (was line 1477)

The clear floor a bus needs between two obstacles, in metres.

Derived from [constant PILLAR_CLEARANCE] rather than written down again: that is how far off an obstacle's axis [method steer_around] puts its waypoint, so the width the steering will actually use is its clearance less the obstacle's own radius, twice over. The stacks have been held to exactly this number since they were built -- a centre distance of 2 * PILLAR_CLEARANCE between two pillars of PILLAR_RADIUS is this much floor between them -- and writing it as the gap rather than as the spacing is what lets a tank be held to the same rule.

### game/bfh_arena.gd (was line 1489)

The tightest gap between any two pillar axes, in metres. INF when there are none.

[b]The one number this map's layout has to be held to, and it is about what a bus can do rather than about what looks right.[/b] Two pillars closer together than 2 * [constant PILLAR_CLEARANCE] leave a gap [method steer_around] will not take a bus through, so the floor behind them is somewhere a runner is safe by standing still -- and this game is two drivers against everybody on foot, so a runner who cannot be reached at all has won by not moving.

[b]Measured off [constant PILLAR_LAYOUT] rather than off the built world, because the layout is the thing somebody edits[/b] and because the answer must not depend on a bowl having been built at a radius that includes the stacks at all. The spacing does not scale with the bowl -- it is sized to a bus, and a bus is the same size in every bowl -- so one answer covers every radius.

### game/bfh_arena.gd (was line 1519)

[param target], moved aside if driving straight at it would go through a pillar.

[b]The stacks would not be playable without this and the failure is not the obvious one.[/b] The bot driver aims at a point past its quarry and floors it; against a pillar that is a bus wedged nose-on, going nowhere, asking for throttle -- which is exactly the state [BfhGame]'s stuck rule reads as "caught on a crate". There is no crate, so after five seconds the bus teleports back to its start line. A runner who stood behind a pillar would make the bus chasing them vanish, which is a free escape that looks precisely like a bug.

So the driver goes round. The pillar in the way nearest the bus is the only one that matters -- the next tick asks again from wherever it got to -- and it is passed on the side the bus is already leaning towards, because the alternative is a bus that changes its mind about which way round every time the quarry moves.

This is a nudge and not a path. It cannot solve the stacks as a maze and is not meant to: a bus that comes round a pillar and finds another one is a bus that has to come round again, which is the whole reason there is a lane through the middle for a driver who would rather not.

### game/bfh_arena.gd (was line 1540)

[b]The nudge's point is a target too, and the ramp is asked about it again.[/b] A bus beside the ramp (where every bus starts) whose line meets a building is handed the point beside it on whichever side has more room, and that is as often the far side of the slab: the bus then drove into the ramp's flank at full throttle until the stuck rule sent it home (measured 2026-10-15, every map, from the start lane). Only when the nudge moved the aim: the line to an untouched target was already checked.

### game/bfh_arena.gd (was line 1584)

The ramp, which is not a cylinder and is the one thing in the bowl a bus cannot come round on either side: its top end is the deck, so the only way past is round its foot.

[b]New on 2026-09-23, with the ramp the right way up.[/b] Built backwards it rose away from the floor and a bus drove UNDER most of it; the right way round, it is a wedge of solid slab 5 m wide and 25 m long between the ledge and the bowl, and a bus aimed across it drove into its side and held the throttle there — the state the stuck rule answers by teleporting the bus home. So a line that crosses the footprint is sent to the corner of the foot on the bus's own side first, and a quarry standing ON the ramp or the deck is chased up it from the bottom, which is the only way there is.

### game/bfh_arena.gd (was line 1620)

Against the slab itself, not the slab widened by a bus. A bus that is BESIDE the ramp and driving away from it passes through the widened box without ever touching the ramp, and sending it round the foot then drove it into the hook: the first version did exactly that, and a drive that had passed for a week stopped against a pillar. Getting from one side to the other means going through the slab, so the slab is the test; the margin is in where the waypoint goes.

### game/bfh_arena.gd (was line 1668)

The way up to a quarry on the ramp or the deck, from [param from] on the floor or the ramp: the ramp's centreline [constant RAMP_LOOKAHEAD] ahead of the bus while it is on the ramp or in front of its foot, the line-up point [constant RAMP_LINE_UP] in front of the foot otherwise, and the corner of the foot first if the line to that would go through the slab.

[b]Pursued along the centreline, because the ramp is 5 m wide and a bus is 2.5.[/b] This used to return the quarry itself once the bus was in front of the foot, and the driver's line to a point 40 m away corrects sideways slowly enough that a bus that arrived 2 m off the middle was still 1.8-2.6 m off it halfway up, with its outer wheels over the edge: measured 2026-10-01, it went over the side at 3.3 m up and wedged against the slab. Aiming at the centreline a fixed distance ahead pulls it onto the middle within a bus length or two, and only the deck itself releases it to the quarry.

[b]And round the foot first, which is the other half of the same bug.[/b] A bus beside the slab (where buses start) was sent straight at the line-up point, through the ramp's side; it held the throttle against it and the stuck rule sent it home, over and over, for as long as the runner stood on the deck.

### game/bfh_arena.gd (was line 1740)

How far the line-up strip reaches past the line-up point. A bus steering for that point arrives AT it, and with the strip ending exactly there it was 0.08 m outside, so its target stayed the point it was parked on and it sat at 0 m/s for the rest of the round (measured 2026-10-01, from the north-east, with the first reverse-only turn; the two-leg turn happens not to arrive there, so `headless_run` passes without this, and it stays because the boundary is wrong whichever turn reaches it).

### game/bfh_arena.gd (was line 1767)

Where a bus that faces away from the ramp turns round to go up it: the point on the centreline, between [constant RAMP_TURN_NEAREST] and [constant RAMP_LINE_UP] in front of the foot, with the most clear floor round it.

[b]Measured off the floor that is actually there, not a fixed distance.[/b] On the shipped bowl the slab is behind it and the stacks' pillar at (-3.3, 7.6) in front, and the point between them with the most room is 7.5 m out, with 7.1 m clear; the line-up point (11 m) has 4.1 m, which is less than a turning bus sweeps. The stacks scale with the bowl and the ramp does not, so on another bowl the best point is somewhere else, and a constant tuned on this one would turn a bus into a pillar on that one.

### game/bfh_arena.gd (was line 1841)

[b]And then the side is checked against the OTHER pillars, which it was not.[/b] This used to return the point beside the blocking pillar without asking what else was standing there, which is correct exactly as long as no pillar is within a bus-width of another pillar's shoulder. Two staggered rows are never that; the hook past the dog-leg is three pillars in a triangle, and the waypoint beside one of them is inside the next. The bus then drives at a point it cannot occupy, arrives, stops, and holds the throttle -- which `_unstick` reads as caught on a crate, so the symptom of a steering bug is a bus teleporting back to its start line.

Both sides are scored by how much room is actually there and the indicated one wins a tie, so a layout that never had the problem gets exactly the answer it got before.

### game/bfh_arena.gd (was line 1867)

How far from obstacle [param index]'s axis a bus has to pass to miss it.

Its own radius plus [constant PILLAR_CLEARANCE], which for a stack pillar is the PILLAR_RADIUS + PILLAR_CLEARANCE this used to be written as, unchanged.

### game/bfh_arena.gd (was line 1875)

How far past an obstacle's surface the steering keeps a bot bus: [constant PILLAR_CLEARANCE] unless `BfhConfig.bot_steer_clearance` says otherwise, which the world writes here before each bot steers. [b]Only the steering reads it.[/b] The map's rules -- [constant BUS_GAP], [constant LANE_THROUGH], every layout check -- are about the shipped steering and stay the constant, so an operator who widens this has bots that give everything more room and a map still measured against the default.

### game/bfh_arena.gd (was line 1884)

How much room there is at [param at], to the nearest obstacle that is not [param blocking].

The blocking one is excluded because the waypoint is deliberately placed at exactly its clearance; including it would make every candidate score the same number and the test above decide nothing.

[b]Measured to the SURFACE, not to the axis.[/b] With eleven pillars of one radius the two spellings rank the candidates identically -- they differ by a constant -- and with a 4.4 m tank and a 2.6 m one in the same list they do not: a waypoint 7 m from the big drum has 2.6 m of floor around it and one 6 m from the small one has 3.4, so the axis spelling picks the side that is actually tighter.

### game/bfh_arena.gd (was line 1945)

A point on the floor for something to be dropped at, from a seeded stream.

[b]Rejection-sampled in a square rather than picked as (angle, radius).[/b] The obvious polar spelling clusters everything in the middle — uniform radius is not uniform area — and on a round map that is a pile of crates at the centre and a bare rim, which reads as the scatter being broken.

### game/bfh_arena.gd (was line 1996)

Metres of floor around a pillar that nothing is dropped into.

The pillar's own radius plus the largest thing scattered, and then some. What this is preventing is not a near miss, it is an OVERLAP: a crate whose spawn point is inside a pillar is two solid bodies sharing a volume, and the physics resolves that by flinging the lighter one across the bowl at the first step. A runner spawned there gets the same treatment with a camera attached. It is also why the margin has to cover a person and not only a crate.

### game/bfh_arena.gd (was line 2007)

Metres of floor around ANY obstacle that nothing is dropped into, past its own radius.

[constant PILLAR_KEEP_OUT] less the pillar's radius, so a pillar keeps exactly the margin it always had and a tank keeps the same margin around a much bigger drum. The flat constant would have left a crate 1.4 m inside the biggest tank.

### game/bfh_arena.gd (was line 2017)

Where the bowl's toys stand (dot-props' loose toys: beach balls, barrels, a tyre): a ring two thirds of the way out, clear of every pillar, tank and the scaffold. Not of the bus lanes: they are the game's per round and a client never sets them, and a bus ploughing a ball is the point. A pure function of the build, so both ends place the same toys in the same order and a client pairs them by index.

### game/bfh_arena.gd (was line 2084)

THE SCAFFOLD: the only height in the bowl a runner can climb, and a bus can take away.

[b]Everything else here is a question about going round.[/b] The stacks are cover you watch a bus through and the tank farm is cover you guess behind, and both are answered on the flat: the runner's whole game is where to stand relative to a nine-metre vehicle that is faster than them. The scaffold asks the other question — UP. Crates stacked as a staircase one, two and three high, which a runner climbs in three jumps and a bus cannot climb at all. From the top the whole bowl is visible and no bus can reach you.

[b]Built of crates, and that is the whole design.[/b] Height made of anything permanent is a place a runner wins the round by standing on, which is the one thing this map is not allowed to have (see the gap rule). Crates break at a bus's cruising speed. So the top of the scaffold is the safest place in the bowl for exactly as long as the drivers leave it standing, and a driver who wants you down drives through the bottom step. It is the stacks' deal — a pillar is safe until the bus comes round — made vertical, and paid for in cover: every crate a bus spends bringing it down is one fewer anywhere else.

[b]Laid out by the world, not the arena.[/b] The arena says where each crate stands; the crates themselves are props, spawned with the round and replicated like any other, so a client builds no scaffold of its own and a server reset rebuilds it.

### game/bfh_arena.gd (was line 2107)

Crates high, per column, along the scaffold's length. Two columns per step so a runner lands with a metre to run before the next face: measured, a jump from standing against a face clears a 1 m rise by 9 cm and misses one time in three.

[b]A saddle, climbable from both ends.[/b] It was a staircase with a sheer 3 m back, so the drivers always knew which end to break and a runner who saw the bus coming at it had nowhere to go but off the top. With two ends, a bus that comes through one has left the other standing, and the runner on top has a way down that is not the one the bus took. The peak is the same two columns three high it always was.

### game/bfh_arena.gd (was line 2128)

Below this it is left out: its position scales with the bowl and its size does not.

[b]45, and it was 40 -- a number nobody had asked the gap rule of.[/b] The scaffold's clearance from every drum and pillar was checked at the shipped 46 m only (6.2 m, to a hook pillar). Both are placed as a fraction of the radius, so a smaller bowl walks them together: at 40 the scaffold stood 1.2 m from that pillar, at 44 still 4.5, and a gap no bus can take beside the one height in the bowl is a pocket the bus cannot reach. Found building the tank farm's back yard, which stands between the two. See [method scaffold_clearance]; `headless_run` asks it at this radius.

### game/bfh_arena.gd (was line 2139)

Air between neighbouring crates, and between a layer and the one it is dropped onto.

[b]Neither is zero, and both were.[/b] A crate spawned touching its neighbour is two bodies in contact on the first step, and the solver pushes them apart — the whole staircase spread half a metre before anybody touched it. And a crate spawned exactly on the floor's surface was driven INTO it: the floor is one very large convex, and contact generation against one at zero separation is the same unreliable judgement dot-player-controller documents for a swept capsule. Dropped from a few centimetres, every crate settles to within a centimetre of its cell.

### game/bfh_arena.gd (was line 2252)

The least clear floor between the scaffold's footprint and any pillar or tank, in metres. INF with no scaffold.

[b]Held to [constant BUS_GAP] like any two obstacles, and asked of the built map for the reason [method narrowest_gap] is:[/b] the scaffold and both clusters are placed as fractions of the radius, so the floor between them is a function of the bowl's size and cannot be read off the constants. Crates rather than steel, but at the top of a round a gap the bus cannot take beside it is a pocket it cannot reach, and a bus that tries is wedged on a pillar with a crate under it.

### game/bfh_arena.gd (was line 2287)

The ramp's walking surface as a height at ([param x], [param z]), from the built body.

[b]Read off the collider's transform, never off the constants that placed it.[/b] The constants were right for nine days while the ramp pointed the wrong way.

### game/bfh_arena.gd (was line 2316)

Every way up this map expects a runner to take, each measured off what it climbs.

[b]Declared, because only the map knows which two surfaces are a route; measured, because everything else about a route is already in the geometry.[/b] The three props are from their scenes' collider sizes through [BfhContent]'s constants (and the suite asserts the scenes agree), the ramp from its built transform, and the scaffold from the same cells the world spawns its crates into.

### game/bfh_audio.gd (was line 8)

What a client hears: the world's noises, the round's cues, and every bus's engine.

[codeblock] var audio := BfhAudio.new() add_child(audio) audio.setup(world, func() -> BfhPlayer: return my_player) # once a frame: audio.present(delta, camera.global_position) [/codeblock]

[b]It listens to ONE world and never learns which half it is in.[/b] Offline the world is the authority and emits its own `noise`, `round_began` and the rest; connected, the bridge re-emits the same signals on the client's world from the events the server sent (`BfhNetBridge._heard_a_swap` has the reasoning). So there is one path from "a crate broke" to a noise, and the net suite asserts it is reached from the wire.

[b]The engine is the one sound nobody sends.[/b] It is continuous, it is a function of how fast a bus is going, and every client is already drawing every bus at the speed it is going — so each client makes it from what it draws. A server that sent it would be sending, sixty times a second, a number the client has.

[b]And an engine is a PULSE here, not a loop,[/b] for a reason that is partly dot-audio's and partly the right answer anyway. dot-audio's Godot sink did not loop a stream (its `looping` flag was carried in the request and read by nothing — reported upstream, and honoured since 2026-09-25), and the synthesised stand-ins are one-shots. But a pulse whose RATE rises with speed is also what a runner needs: how fast the thuds are coming is how fast the bus is, heard through a tank.

### game/bfh_audio.gd (was line 85)

Measured toward the family's -17 LUFS (dot-audio docs/loudness.md): a 40 s stand-in round read -25.4 LUFS integrated with the wind and the steps in (-20.1 before them, on a run with a crash in it); -19.9 at +6, -18.1 and -19.1 at +8. Once the stand-in turned off walls (2026-10-12, camera over 150 m a run): -19.0 at +8, -17.5 and -17.6 at +9.

### game/bfh_audio.gd (was line 146)

Once a frame: where the listener is, and every driven bus's engine.

[param listener] is the camera's position, which is what dot-audio culls against. Not the player's: a runner who is out is watching from somebody else's eyes, and a cull measured from the patch of sand they fell on would silence the chase they are watching.

### game/bfh_audio.gd (was line 161)

A bus's engine, from the bus this client is drawing.

[b]Only a DRIVEN bus has an engine running.[/b] An empty bus is a vehicle nobody is in — a driver who left mid-round, a bus waiting for a bot — and a thud from one would be a bus telling runners to be afraid of nothing.

### game/bfh_audio.gd (was line 231)

Won or lost, by THIS client's side. See `BfhSounds.ROUND_WON`.

Nobody here yet — a client between connecting and its JOIN — hears the round end as a loss rather than as nothing, because silence is what a broken client sounds like.

### game/bfh_avatars.gd (was line 3)

What a player looks like, as a dot-user-avatar document: the schema, the stock avatar a player without one of their own wears, and which skin a document asks for.

[b]One slot, because this game's people differ in one thing.[/b] Every Blocky Character carries byte-identical geometry and UVs, so the six runners [BfhFigure] can draw are six atlases on one mesh. [b]A driver is not a choice[/b]: whoever is at the wheel wears `BfhFigure.DRIVER_ATLAS`, because the side is the first thing anybody needs to read off a body here and the two sides are not symmetrical — so a face is what somebody looks like while they are on foot. A document with a hat slot in it would be a promise this game has no art to keep.

[b]Data only, and loads nothing.[/b] A dedicated server validates a document against this schema without holding the art, which is dot-user-avatar's whole premise; which atlas a skin means is [BfhFigure]'s, on a client. [constant SKINS] and [code]BfhFigure.RUNNER_ATLASES[/code] are the same list in the same order, and `headless_net` checks that they stay so.

[b]The stock avatar is the old hash, exactly.[/b] Before this file a player's look came from `hash(player_id)` into the atlas list; [method stock_avatar] makes the same choice into a document, so nobody's character changed the day profiles arrived, and a server with no platform draws everybody precisely as it did before.

### game/bfh_avatars.gd (was line 61)

The avatar a player with none of their own wears: the skin their id hashes to.

[param player_id] is the game's own key — `u<session>` — and the hash is the one [code]BfhPlayer[/code] used before there were documents. See the class note.

### game/bfh_avatars.gd (was line 75)

Which of [constant SKINS] a document asks for, or -1 for none this game has.

[b]-1 rather than a guess.[/b] A document for another schema, or naming a skin this build does not ship, is not this game's to reinterpret; the caller falls back to the stock one, which is a real person rather than a wrong one.

### game/bfh_avatars.gd (was line 102)

The letter of the site's skin in [param slot] of its `builtin` document, or "".

The site's avatar is the Kenney kit's eighteen painted skins, `skin-a` to `skin-r`, chosen per face, top and legs — the same atlases this game draws, spelt the site's way.

### game/bfh_awards.gd (was line 5)

What a player can earn here, as a document rather than as code.

Every rule reads an id from `BfhStats` and nothing else. That is the whole integration: dot-achievements never hears about a bus or a crate — it hears that a number moved.

[b]Both sides have something to earn, and that took a decision.[/b] The obvious list is the driver's (people flattened) and it would make the runners' side the one with nothing on it — in a game where the runners are most of the server. So three of the five series are the runners': staying up, staying up for long, and the one thing a runner can do TO a bus, which is put a crate in front of it.

Every stat is read with `SUM`, because every stat in `BfhStats` is a counter; the catalogue's own validation refuses one stat read two ways, and the helper below is the only way a rule is built here, so it cannot be.

### game/bfh_bindings.gd (was line 3)

Every key this game reads, as one dot-menu [DotMenuBindings] table: the action, the setting that stores it, the words a player sees, the default, and the card it goes on.

[b]A table, because four things read it:[/b] the client matches events against the actions, the settings document stores one binding per row, the menu's Controls page draws a key per row, and the help screen (H) lists them with the key each is on now. Until 2026-10-11 the board's Tab and the spectator's Space were keycodes and the rest were nobody's, so the help screen had nothing to list and the Escape menu had no Help.

[b]One set of keys for both sides.[/b] A driver steers the bus with the runner's movement keys, so the rows say both. H is help, in every game of the family (dot-menu adds the row), so nothing here may default to it; the talk key is dot-menu's row too (V).

### game/bfh_bowls.gd (was line 5)

The bowls a round can be played in: this game's maps, for the players' vote.

[b]A bowl is a radius, not a file.[/b] The map here is [method BfhArena.build] run on both ends from one number (and the hook and the courtyard's west lane, which stay the operator's), so a bowl is a name and a radius. Every feature is placed as a fraction of the radius and spaced for a bus, so a different radius is a different map with the same rules: `headless_run` builds every bowl here and holds each to the gap rule, the same way it holds the minimum radii.

[b]`bfh_bowl` is the operator's own[/b]: whatever `arena_radius` says (46 m shipped). The other two are the sizes the arena's own minimum radii already describe from either side: a small bowl below the scaffold's and the colonnade's minimum, where only the stacks and the tank farm stand and the bowl is open floor between them, and a big one where every feature is further apart and a bus has room to build speed.

No `class_name`: this game is delivered as a pack (see docs/delivery.md).

### game/bfh_client_chat.gd (was line 6)

The client's half of chat and voice: a box to type in and a key to talk with.

[b]Everything here draws or captures, and nothing here decides.[/b] What a line may contain, who may hear it, whether somebody is gagged and whether they are talking too fast are all the server's, and this client's local copy of the rules exists only so a message that is going to be refused can be refused without a round trip. The server's answer is the one that counts, and when the two disagree the server wins — which is the right way round for a disagreement to fail.

[b]The one thing it does decide is that typing is not moving.[/b] A chat box open over a first-person game whose keys are still driving the player is a player who walks into a bus while saying so, and every game in this family has had to learn it separately.

### game/bfh_client_chat.gd (was line 45)

Builds the box, the client and the microphone over an attached bridge.

[param p_bridge] may be null, which is the offline case: the box is still drawn and still echoes what the local player types, because a chat box that does nothing at all reads as broken rather than as absent.

### game/bfh_client_chat.gd (was line 84)

[b]An outline, because this map is pale sand in bright light.[/b] Three lines in three colours over that floor are three lines nobody can read — measured in a screenshot, with every property of every line correct. `BfhHud` had already reached the same answer for its own labels; dot-ui's feed grew the option so both can say it once.

### game/bfh_client_chat.gd (was line 122)

The microphone, which is allowed to be absent.

[b]A machine with no input device is the normal case on a server and a common one on a desktop, and it must not be an error.[/b] `DotVoiceManager` reports it, listening still works, and what a player gets is a game where they can hear everybody and say nothing — which is exactly what somebody with no microphone should get.

### game/bfh_client_chat.gd (was line 129)

Typed explicitly rather than inferred. Inside a mounted pack a script whose base class lives in the HOST build cannot hand its return type to a script in the mount, and `:=` here is a client scene that fails to compile on a real server and works perfectly in the project it was written in.

### game/bfh_client_chat.gd (was line 159)

Binds V, unless the player has already bound it to something.

The same rule dot-ui's chat window follows for Y and U: an action that already exists is an action somebody configured, and overwriting it is a game taking a key back off a player who chose it.

### game/bfh_client_chat.gd (was line 175)

Push to talk, polled rather than driven by events.

[b]A key that is HELD is a state, and an event queue is sampled per frame.[/b] Reading the press and the release as events works until a frame drops one, and what that leaves is a microphone that stays open after the key is up — which is the one failure mode of voice chat that nobody forgives.

### game/bfh_client_chat.gd (was line 218)

[b]The server's own lines arrive on the shell's client link, not on the bridge.[/b] A vote between games, "Ada joined the game." and an admin's `say` are dot-server's chat manager, sent as `chat.line` on `DotClientLink`; this box read only the bridge and never showed one. Only those kinds are drawn (dot-game's `DotGameChatClient.draw_server_line`): what players say comes over the bridge, and drawing it from both would be every line twice. A method callable, so the connection goes with this node when a game switch frees it.

### game/bfh_client_chat.gd (was line 260)

Something the server said to this player alone: a refusal, a rate limit, the reply to a `!command`.

[b]Drawn in the chat log, because that is where the player was looking.[/b] A notice that arrives and is not drawn is the server explaining itself to nobody — which is exactly what "I pressed Enter and nothing happened" is, and it is the commonest thing a chat server ever has to say.

### game/bfh_client.gd (was line 14)

One local player, a camera and a HUD over a [BfhGame] — offline, or against a server.

[b]One client for both, and the offline half is not a demo mode.[/b] It is the same world class with `authoritative` true and nothing else different: the same bowl, the same bot bus, the same rules. What changes is where the answers come from, and the whole of that difference is [BfhNetBridge]. A separate "single player" build would be a second game to keep in step, and the family has watched two copies of one thing drift more than once.

[b]Which half runs is decided by whether there is a link in the registry.[/b] A dot-server client publishes a [DotClientLink] under `dot_client_link` before the game scene loads; no link means nobody connected us to anything, and the honest answer to that is a playable bowl rather than an error. `--offline` forces it.

### game/bfh_client.gd (was line 156)

[b]Here, in `_ready`, which runs INSIDE `DotClientLink._load_scene`.[/b] The link adds this scene and tells the server it has loaded on the next line, so the netcode is up before the server has been told there is anybody to send to — which is the order that leaves nothing to be missed. Measured against a real server in a second process: the join completes and the first snapshot arrives with the bowl already replicated.

### game/bfh_client.gd (was line 168)

The load gate is [member DotGameClient.gate]: covered, and the local body and the input still, until the bowl stands, the local player exists and its camera is current.

[b]Covered also means the round does not run.[/b] Offline the world ticks itself, so the bot bus, the round clock and the barrels would all act on the runner in front of a picture; [member BfhGame.hold_clock] steps only the bodies then, which settle onto the sand under the cover with their input off. Connected, the server owns the round; what is left to hold is this end's sampling and keys, which wait on [method _covered]. The vendored art is loaded exactly as before: the gate only waits for it.

### game/bfh_client.gd (was line 394)

A player arrived or changed. The one we are waiting for might be us.

[b]Connected before anything can create a player rather than only checked on HELLO.[/b] HELLO and JOIN are both reliable and ordered, so HELLO does arrive first — but "the ordering happens to save us" is exactly the reasoning that put this bug in another game here, and a check that costs nothing is cheaper than depending on it.

### game/bfh_client.gd (was line 501)

The player's settings, applied to everything that reads them. See [BfhSettings].

After the audio and the sampler, because both are bound here and a binding applies at once. The camera arrives with the player and is bound in [method _adopt].

### game/bfh_client.gd (was line 520)

Walking is off while the cover is up, a menu is open or a line is typed: the sampler polls the keyboard, and a player dragging a volume slider with the arrow keys would otherwise walk into the bus they had stopped to turn up (and a driver steer with the letters of the word they are typing).

### game/bfh_client.gd (was line 550)

M: the bowl list (dot-menu's map menu). Solo a choice changes the bowl here at once; connected the server decides, by the owner's `sv_map_menu_flag`, and anybody without it gets a vote instead (dot-vote's map menu, wired in [BfhModule]). By name, so a client shell older than the map menu still runs the game without it.

### game/bfh_client.gd (was line 570)

What this client hears, listening to its own world. See [BfhAudio].

Not fatal: a client whose audio was refused is a silent client, which is what this game was for its first eleven days, and a WARN is what says so.

### game/bfh_client.gd (was line 588)

What this client draws, listening to its own world. See [BfhFx].

Not fatal, for the reason the audio is not: a client that draws no blast still hears it and is still thrown by it, and a WARN says why the picture is missing.

### game/bfh_client.gd (was line 606)

The chat box, before the netcode and before any player exists.

[b]Built in both halves and attached to the bridge afterwards.[/b] A box that only appeared on a server would be a box nobody could test offline, and a box built after the first line arrived would miss it — the backlog a joining player is sent is the first thing the server says.

### game/bfh_client.gd (was line 668)

The sampled command, on a connected client, once per tick the clock says has passed.

[b]Offline this does nothing and the world ticks itself.[/b] The player samples inside [method BfhPlayer.simulate] there, which is the shape a single process wants; a connected client cannot use it, because its local player has to be simulated by the PREDICTOR from the same command that was sent, and a second sample would predict something different from what the server was told.

### game/bfh_client.gd (was line 698)

[b]Each pass is its own tick.[/b] `advance` has already moved the clock by all of them, so `input_tick()` is the LAST one on every pass: a frame worth two ticks sent the second twice and the first never, the server repeated a stale command for the one it never got, and the predictor's replay stopped at the hole and drew the player short of where they were -- after every hitch, and on every frame the display and the tick rate do not line up. Arithmetic here rather than a new dot-net call, because a pack has to run on whatever client shell the player already has.

### game/bfh_client.gd (was line 758)

Drawn every FRAME from the controller's own interpolated view, not once per tick. Another game in this family measured what the other way costs: a client stepping physics at one rate and drawing at another advances the camera in bursts, which is a 47% change in apparent speed several times a second and reads as "the game is jittery" with every simulated number correct.

### game/bfh_client.gd (was line 766)

[b]And the position, which the angles above never needed.[/b] The camera hangs off the player's node and the node only moves on a tick, so a camera left there advances in steps while everybody it is looking at is now interpolated every frame — a runner watching another runner alongside them sees the other one shudder, because it is the VIEW that is stepping. `render_state` blends the last two ticks by the engine's physics fraction, which the bridge makes a fraction through a tick by putting the engine on the server's rate. Written globally rather than by moving the node, because the tick writes the node and prediction reads it back. Not while riding: the controller is not simulated in a bus, and a blend between two ticks that never happened drags the view backwards.

### game/bfh_client.gd (was line 839)

Puts [param eye] where a runner who is out is looking. Returns whether it did.

[b]Static, so the net suite drives this and not a copy of it[/b] — the same reason [method present_frame] is. The answer is the world's spectator camera, which on a connected client is a mirror computing it from the view the server sent and the positions this frame is drawing; see [BfhSpectate].

### game/bfh_client.gd (was line 869)

Everything a frame draws that a tick does not, in this order: the netcode's interpolation, then every player's body, then every beacon. Returns how many bodies are shown. Static so the net suite drives exactly this and not a copy of it.

[b]The interpolation was never called in this game, and that is half of why nobody else was visible.[/b] `DotNetManager.interpolate_frame` is what blends two snapshots and hands the result to `BfhPlayerNet._net_interpolated` and `BfhPropNet._net_interpolated` — both written, documented, and reached by nothing. So every remote runner, every crate and both buses moved only when a snapshot landed, twenty times a second on a 60-tick server: the render-jitter class this family has now paid for in three games. The other half was that a remote runner had no body to move (see [BfhFigure]).

[param alpha] is the fraction through the current tick; -1 derives it from the engine, which is what a real frame wants. A suite passes it explicitly, because a suite's frames are not an engine's.

### game/bfh_client.gd (was line 893)

Your own runner is drawn at the clock's render alpha, not the engine's fraction: the clock stretches and shrinks its ticks while it settles on the server, so a physics frame now and then runs no tick or two, and drawn at the engine's fraction the eye stood still on one frame and moved double on the next. `DotFpsController.render_state` reads it from `render_clock` (dot-player-controller); by name both ways, so a shell older than either draws as before. Null offline, where every physics frame is one tick.

### game/bfh_client.gd (was line 925)

Whether the mouse button is down this frame. Read by [method _physics_process].

[b]A held state and not an event, because a hammer is held.[/b] An event queue is sampled per frame and a tick is not a frame: at 60 Hz on a 144 Hz screen, two frames in three carry no click at all, so a swing bound to the event would be dropped two times in three at exactly the moment somebody was leaning on the button.

### game/bfh_client.gd (was line 1074)

The free camera, once a frame: WASD along the view, Space and Ctrl up and down, Shift fast, Alt slow, the mouse to look. Only the camera moves; the body stays where it fell.

[b]The speed is the server's[/b] (`mp_freeroam_speed`, through the mirror's rules), so a client cannot fly faster than it was told to. The server holds only the mode.

### game/bfh_config.gd (was line 3)

Every cvar this game has, layered like every other [DotConfig] in the family.

[code]exported defaults < JSON file < environment < command line[/code], identically to dot-server, dot-cloud and the other four games. Nothing here reads [code]OS.get_cmdline_args[/code] itself.

[b]The units are metres and seconds, and that is a decision this game gets to make where game-g2gfast did not.[/b] That game speaks a twenty-year-old community's units because its operators already know what [code]sv_airaccelerate 1000[/code] means and because its records have to be comparable with theirs. Nothing here is comparable with anything, nobody is going to type these into a console from memory, and a second set of units is a second place the ratio can drift. So a bus does 22 m/s and the file says 22.

### game/bfh_config.gd (was line 31)

Rounds before the sides swap. 0 never swaps.

[b]Swapping matters more here than in a symmetric game.[/b] Driving is the fun half and there are one or two seats for it against six on foot, so a server that never swaps is a server where the same two people drive all night.

### game/bfh_config.gd (was line 40)

How many drivers the round starts with: how many buses, and (in fill mode, the default) how many bots there are when nobody has taken a seat.

[b]Four, and it was two.[/b] Two buses in a 46 m bowl is a bus for every 3300 m^2 of floor, which a runner crosses between one pass and the next; the bowls on the ballot run from 40 to 60 m (5000 to 11000 m^2), and four gives roughly one bus per 1500 to 2800 m^2, a pass every few seconds without the floor being all bus. Four is also what the start line holds: two lanes either side of the ramp. A person who takes a seat takes it from a bot, so a full table of people is the same four. The suites set their own (1) and do not read this.

### game/bfh_config.gd (was line 67)

Metres per second squared, for everything: the runners, the crates and the buses.

[b]Here rather than in `project.godot`, because a project setting does not travel with a delivered game.[/b] This game's `physics/3d/default_gravity` is 20 — high on purpose, because it is what the character movement wants and what every other 3D game in this family uses — and a pack mounted into the server tool's project runs at ITS setting, which is Godot's 9.8. Nothing reports it. What it looks like is a game that plays correctly on a developer's machine and floats everywhere it is deployed: crates that drift down, a bus whose suspension was tuned against twice this force, and jumps that hang.

Applied to the world's own physics space by [BfhGame], so two worlds in one process — a server and a client — each get it without either of them writing a global.

### game/bfh_config.gd (was line 93)

How hard a swing shoves a crate it does not break, in newton-seconds.

[b]A hammer that only deletes crates is a worse tool than one that also moves them.[/b] Shoving a crate into a bus's path is a play, and it costs one impulse.

### game/bfh_config.gd (was line 104)

Closing speed, in m/s, above which a bus kills a runner outright.

Below it a runner is knocked down and hurt in proportion. A bus idling into somebody standing still should not be a kill, or the drivers park in the spawn.

### game/bfh_config.gd (was line 168)

How far past an obstacle's surface the bot steers a bus, in metres. 3.6 is the number the map is laid out against (a lane narrower than twice it is one the bot will not drive straight through); more gives every pillar and drum a wider berth and makes more of the map a door, less shaves them closer and wedges sooner.

### game/bfh_config.gd (was line 174)

How far a bot bus's centre is kept off a building, the wall and the ramp when it is routed along a district's streets, in metres. A district's street is 7.6 m of clear floor, so the open centre line is 7.6 minus twice this: at 3.4 it is 0.8 m, and at 3.8 or more no street is open at all and the bots fall back to the nudge. Only the districts read it.

### game/bfh_config.gd (was line 184)

Seconds a bot bus may throttle against something before it backs off (`bot_unwedge_after`), and how long it reverses for (`bot_unwedge_seconds`), with the wheel over so the nose swings towards where it wants to go. The stuck rule's five seconds before a bus is put back on its start line is the slow way out of a building and the symptom a runner sees as a bus deleting itself; this is the way a driver gets out of one.

### game/bfh_config.gd (was line 192)

Seconds a bus may ask for throttle and go nowhere before whatever is under it is broken, and before it is given up on and put back on its start line. A person's bus as well as a bot's: it is the rule that frees a bus high-centred on a crate. A bot that is put back sooner gives up on a quarry behind a drum sooner, which a runner sees as the bus vanishing sooner.

### game/bfh_config.gd (was line 222)

The file that says which bowls this server ROTATES: `cfg/maps.yml` (dot-map's `DotMapRotationFile`: named rotations, `random` or `cycle`, wildcards, command names), looked for in the `--config` directory. Empty, or no such file, rotates every bowl. A bowl it leaves out stays installed (the map menu loads it); it is only never drawn, balloted or nominated. `sv_map_rotation_file`.

### game/bfh_config.gd (was line 232)

Whether the scatter keeps a lane clear in front of every bus start, and how big: a crate, barrel or block dropped there is the first thing a bus hits, and a block 13 m ahead of a start (it happened on the suite's seed) is a bus that ends its first second against it. Christian's pick is on; off lets the bowl's scatter fall anywhere, as it used to.

### game/bfh_config.gd (was line 241)

Metres of floor round the scaffold's footprint that nothing is scattered into, to the prop's centre. A prop beside the scaffold BRACES it: measured (2026-10-07), a barrel 2.44 m off its west end kept a bus at full tilt from bringing a runner off the peak (34 of 36 crates still standing), and with it gone the same bus did. A braced scaffold is a refuge from the buses, which is the opposite of what the scaffold is for. 4 m clears it and the block 3.74 m off that seed laid too. Never less than the 2.2 m every obstacle keeps (`BfhArena.OBSTACLE_MARGIN`); `bfh_scaffold_margin` is the cvar.

### game/bfh_config.gd (was line 253)

How high a barrel throws a runner standing against it, in metres of apex. Falls off with the blast, linearly, like the damage.

[b]Sized from the one route it exists for.[/b] A barrel is the only thing here that throws anybody upward, and that is what makes a stack of two crates somewhere a runner can get to at all: 2 m is past any jump. The farthest a runner can set a barrel off from is the hammer's reach to its face, 2.9 m from its centre, where the blast is at 0.55 of full — and 0.55 of 4.2 is 2.3 m, the stack plus the margin every other climb in this game is held to. `headless_run` asserts it through the map's declared climbs and then throws a runner onto one.

[b]It was 4 m/s of upward velocity, added to a runner the motor still believed was standing on the sand[/b], so the ground snap ate it on the next tick: measured, a barrel lifted a runner 7 to 8 cm at every distance. The comment above it said it was "the one way onto a crate stack".

### game/bfh_config.gd (was line 270)

Which hook the stacks end in (the three pillars past the dog-leg), by name. [code]tight[/code], the default, is the hook as built: gaps of 5.6 m that a bus fits and the bot bus never drives into, so a runner standing still in one is safe from bots. [code]wide[/code] is the 2026-10-06 decision to fix that (the middle pillar walked out to 7.4-7.6 m gaps): a bot reaches a runner in either gap from most starts, but the pillar then stands 3.5 m from the scaffold, under a bus's width, and the build logs it as a WARN. It is not the default for that reason; `BfhArena.HOOK_LAYOUTS` says what was measured. An unknown name builds the default and logs a WARN.

[b]Read when the bowl is built, and not a cvar.[/b] The map is the arena's build run on the server and on every client, and a client learns this in the HELLO when it joins; a live change would move a pillar under the people already connected. Set it in the JSON file, `BFH_HOOK_LAYOUT` or `--bfh-hook-layout` and restart.

### game/bfh_config.gd (was line 285)

The clear floor of the tank farm's courtyard's west lane, in metres: its 4.4 m drum is moved out along the lane's axis to leave this much. 7.6 (Christian's pick, 2026-10-07) is past the 7.2 m the bot bus needs, so no lane into the courtyard is a refuge from the bots; 6.6 is the farm as first built, where a runner standing in the lane's mouth was never reached. Read when the bowl is built, like [member hook_layout], for the same reason.

### game/bfh_config.gd (was line 293)

Seed for where they land.

[b]A seed rather than a fixed layout, and it is reproducible on purpose.[/b] Two servers on the same seed lay the same round out, which is what makes a bug report about "the crate by the north wall" mean anything — and what lets the suite assert a layout at all. [DotRandom] rather than [code]randi()[/code], for the family's reason: the global RNG is shared with everything else in the process.

### game/bfh_config.gd (was line 382)

Overridden to print what this game is tuned to rather than every field.

The signature carries the parent's `redact_sensitive` even though nothing here is a secret: a subclass that quietly narrows an override is a method that is silently the parent's at every call site that passes the argument.

### game/bfh_content.gd (was line 6)

The two catalogues: what can be in the bowl, and what can be driven at it.

[b]Three props and one vehicle, and the whole game is in their numbers.[/b] A crate is breakable by a hammer and by a bus and is something to stand on; a barrel is breakable by anything and takes whoever is near it with it; a block is neither and exists so there is somewhere a bus cannot follow. Every one of those is a field on [DotPropDef] rather than a script, which is what lets a server retune the game by editing JSON — and what lets the suite assert the design instead of the code.

### game/bfh_content.gd (was line 15)

Where the three bodies live, as this game was authored.

[b]Rebased where they are defined, so no use of them can forget to.[/b] A delivered pack mounts at `res://dot_cloud/<id>/<version>/`, so an absolute path to this game's OWN files resolves against the host project root — which holds another game's props, or nothing. Rebasing returns these unchanged in a build and the mounted path in a pack, which is one form that is right in both. They were `const`s rebased at every call site, which was correct and was also one new call site away from not being: `static var` is the only spelling that can hold the rebased value, because a `const` cannot call.

### game/bfh_content.gd (was line 28)

The props' collision sizes, in metres, as the scenes above build them.

[b]A deliberate copy, and `headless_run` asserts it against the scenes.[/b] The map's climbs are measured off these — what a runner can get onto is a question about the collider, not the art — and reading them out of an instanced scene every time the map is asked would make the map depend on loading a prop.

### game/bfh_content.gd (was line 59)

Three swings of a hammer at 34. Deliberately not two and not four: two is a crate nobody can shelter behind and four is a crate nobody bothers with. [b]Below the speed that kills a runner, and that ordering is the design.[/b] At the lethal speed a bus was fast enough to run somebody over and not fast enough to get through the crate they were hiding behind — so it climbed the crate instead, high-centred on it with two wheels off the ground, and sat there for the rest of the round. A bus at cruising speed has to go THROUGH the cover or the cover is a bus trap rather than cover.

### game/bfh_content.gd (was line 85)

[b]The one thing in the bowl that is not a toy.[/b] A round where every piece of cover can be removed is a round that ends the same way every time: the drivers flatten the crates and then the runners have nowhere to be. A handful of blocks that cannot be broken and cannot be pushed are what make the last thirty seconds a game rather than a countdown.

### game/bfh_content.gd (was line 122)

The bus, and nothing else.

[b]One vehicle on purpose.[/b] The reference this is built from has a school bus and a handful of cars, and the cars are the half that does not work: a car is small enough to be dodged reliably and fast enough to make dodging feel arbitrary, so a round with cars in it is decided by whoever happened to be looking the right way. A bus is slow to turn, impossible to miss, and telegraphs everything it is about to do — which is what makes running from one a decision instead of a coin toss.

### game/bfh_content.gd (was line 143)

Newtons since dot-vehicle 4f4afaf (they were an impulse per step, and the bus stopped from 15 m/s in 1.9 m on the foot brake and 4.5 m on the handbrake). 30 kN is 15 m/s², three quarters of this bowl's gravity: 7.6 m from 15 m/s. 22 kN, the old figure as a force, made the bot's three-point turn under the deck settle between legs slowly enough to give a runner up there a second and a half more (the deck chase in headless_run). The handbrake is a person's Ctrl and stops in 6.3 m in a straight line. A person's S is this foot brake until the bus has stopped and reverse after (`_drive_buses`), 7.5 m. The rear tyres' grip while Ctrl is held, so a handbrake turn slides. Measured from 12 m/s at full lock for a second (headless_run's "a handbrake turn"): at 1.0 (no change) the bus turned 14 degrees and stopped dead, the handbrake only a brake; at 0.25 and 0.2 still under the plain turn's 41; at 0.15 the back end steps out, 71 degrees with 7 m/s left; at 0.1 it spins round. The change between 0.2 and 0.15 is a threshold, not a slope. [b]Low, and it is the single most important number in the file.[/b] A bus that turns as fast as it accelerates is a homing missile and there is no counterplay to one; the whole of a runner's game is that a bus committed to a line cannot take it back. Everything else here is feel. [b]150, not the 45 a car uses, and 45 is what this shipped with.[/b] Stiffness has to carry the mass above it: at 45 the springs on a 4.2 tonne bus bottomed out on the first frame, the hull came to rest on the ground, and the body's own collider dragged on the deck — so a bus with four wheels in contact and 26 kN of engine force behind it sat perfectly still. Every number in the report read correctly except the speed. Dropped hard, because a 2.6 m tall box on a 2.5 m track rolls over on the first hard turn otherwise — and a bus lying on its roof is a driver out of the round through no decision anybody made. [b]0.4, not 1.1, and the larger number is below the wheels.[/b] Godot's raycast vehicle resolves its springs about the centre of mass; put that below the contact plane and the springs push the body the wrong way about it. A drop is meant to stop a tall box rolling over, not to move the pivot underground.

### game/bfh_districts.gd (was line 3)

The districts: bowls whose floor is a town, laid out by hand to the shape of a kind of place.

[b]Drawn by hand, from the kind of place and never from a survey.[/b] A district is a street pattern anybody would recognise (a grid downtown, a road that switches back up a hill, a suburb of roundabouts) written out as the few numbers that make it: where the roads run and how the buildings stand along them. No map data of any real town went in, which is deliberate: the open-map databases are share-alike, and nothing in this family is.

[b]A building is a cylinder, because the map has one obstacle description.[/b] Steering, the scatter, the toys and the gap rule all read [code]BfhArena._obstacles[/code], which is circles; a district adds to that list through `_add_obstacle` like every other feature and adds nothing of its own. A block is a round tower, a house a round hut, a roundabout's island a drum. The streets are the floor between them, painted flat, with no collider.

[b]Every gap is held to the gap rule at build time, by construction.[/b] [method plan] places each building only where it leaves [constant STREET] of clear floor to every other, so a street is never narrower than the 7.2 m a bot bus drives straight through, and a building is refused where it would crowd the wall, the scaffold or the buses' start lanes. Refused, not moved: a district with a hole where a house would have been is a plaza, and that is honest.

No `class_name`: this game is delivered as a pack (see docs/delivery.md).

### game/bfh_districts.gd (was line 73)

What a district puts on the floor: `buildings`, each `{at: Vector3, radius, height, kind}`, and `roads`, each `{from: Vector3, to: Vector3, width, colour_id}` for a strip or `{at: Vector3, radius, colour_id}` for a disc (a roundabout's ring). [param keep_out] is the rectangles that stay clear of every building: the buses' start lanes. [param scaffold] is the scaffold's footprint on the floor (size zero when there is none).

### game/bfh_districts.gd (was line 95)

A grid: square-ish blocks on a 21 m pitch with an 8 m street between them, an avenue running down from the buses' ramp, and a ring street round the middle four blocks, marked in a lighter paint because it is the one-way loop a driver circles to come back at a runner. The grid's last column does not fit the bowl and is left out; the scaffold's corner is a plaza.

### game/bfh_figure.gd (was line 5)

What somebody ELSE looks like: a Kenney blocky character, scaled to the runner's hull and turned to face where they are looking. Client side only; a server never builds one.

[b]This game drew no person at all until 2026-09-24.[/b] Every runner's own view is first person and every driver is inside a bus, so nobody had ever needed a body on screen — until a networked client, whose other runners were drawn as nothing. Their node moved, their beacon marked them, and the bowl had crates walking round it being shoved by nobody. See `BfhPlayer.present_body` for when one is shown.

[b]A child of the player's node, and so placed by whatever places that node.[/b] On a remote player that is the interpolator once a frame (`BfhPlayerNet._net_interpolated`, reached from `BfhClient.present_frame`), which is the whole reason a figure moves smoothly rather than at the snapshot rate. Nothing here computes a position.

[b]One of the family's animated people[/b] (dot-player-char's `DotHumanoidFigure`, the style every game's players, bots and NPCs share): which one a runner is still comes from the blocky kit's atlas their avatar names (`DotHumanoidLook.from_letter`), and a driver on foot wears the uniform's colours. It animates from how far its node moved each frame (`auto_animate`), because the interpolator moves the node and nothing here knows a speed.

### game/bfh_fx.gd (was line 5)

What a client draws that nothing simulates: today, a barrel going off.

[codeblock] var fx := BfhFx.new() add_child(fx) fx.setup(world) # once a frame: fx.present(delta, camera.global_position, -camera.global_basis.z) [/codeblock]

[b]It listens to ONE world, as [BfhAudio] does, and never learns which half it is in.[/b] Offline the world is the authority and emits its own `barrel_exploded`; connected, the bridge re-emits it on the client's world from the BLAST the server sent. So the blast is decided in one place — the server, or the offline world standing in for one — and this only draws the place and the reach it was told. Nothing here is built on a server: only [BfhClient] makes one.

[b]dot-fx, because an effect is the one thing a client may drop.[/b] A tier, a frame budget or a pack still arriving may refuse the blast, and every refusal is safe by that addon's own invariant; the sound ([BfhAudio]) and the shove (the server's) do not depend on it.

### game/bfh_game.gd (was line 16)

The simulation. Headless, authoritative, and the only thing that decides anything.

[b]One side drives and the other side runs, and every decision in this file comes from that being asymmetric.[/b] It is not a deathmatch with vehicles in it: the drivers have no way to lose except the clock, the runners have no way to win except the clock, and the only thing either side can change is the shape of the bowl between them. So the crates are the game, and everything here is about keeping enough of them standing to make the last thirty seconds interesting.

[b]What it owns and what it borrows.[/b] The round, the sides and the scoreboard are dot-match's; health and damage are dot-combat's; the crates and barrels are dot-props'; the bus is dot-vehicle's; the bowl is this file's. The joins are the part that is new, and they are the part worth reading.

### game/bfh_game.gd (was line 35)

Where this world publishes itself, so a module can find it.

[b]A registry name and not an autoload, which is the family rule and here also a requirement.[/b] A server and a client in one editor session is two of these, and the suite builds two worlds in one process on purpose -- see [method _build_random] for what the other kind of global already cost this game.

### game/bfh_game.gd (was line 43)

Snapshots a second. Twenty, against a sixty-tick simulation.

[b]Lower than the games whose whole content is a person aiming at another person.[/b] Nothing here is decided at the precision of a single frame: a bus is nine metres of telegraphed intent, and what a runner reads off it is a direction and a speed rather than a silhouette. The interpolator covers the rest, and the bandwidth goes to the thirty-odd rigid bodies instead, which is where this game's snapshot actually is.

### game/bfh_game.gd (was line 52)

How far a position may be from the origin, in metres, on the wire.

[b]The bowl is 46 m across and this is 256.[/b] Not tidiness: a quantised position is decoded against this range, so a client and a server that disagree about it do not lose precision, they land somewhere else entirely. It is written here, once, and both ends read it from here -- the arena client and the module said 256 and 128 in two other games in this family and that is the bug being avoided.

### game/bfh_game.gd (was line 87)

Something in the bowl made a noise worth hearing: one of `BfhSounds.WORLD`, where it happened.

[b]Emitted by the authority, and by a connected client's world when the server says so[/b] (`BfhEvents.Kind.SOUND`), so the thing that plays it — `BfhAudio` — listens to one signal in both halves and never learns which it is in. A sound is presentation: it is decided here because WHAT happened is decided here, and it never changes anything.

### game/bfh_game.gd (was line 117)

Whether something else drives the tick.

[b]Set by the bridge on both ends, and it has to be both.[/b] A game's tick has to happen INSIDE the netcode's -- between applying each peer's inputs and building the snapshot -- so a world still running its own `_physics_process` moves every player twice a tick, and what that looks like is a server running at double speed only while somebody is connected. A client's is worse: it would simulate the local player twice and dead-reckon every remote one from stale state.

### game/bfh_game.gd (was line 127)

Whether this world counts statistics and achievements. Authority only either way.

On by default, because a server and an offline game both want it. A suite that builds a world to test a bus does not need two trackers under it, but pays nothing much for them either, so the default is not about cost — it is here so a caller can say "no".

### game/bfh_game.gd (was line 134)

Whether this world publishes itself under [constant SERVICE].

Off on a client that shares a process with a server -- the suite, an editor session running both -- because a registry name is global and the last one to register wins.

### game/bfh_game.gd (was line 154)

dot-player-controller's `mp_forceview`: whether a player may switch to third person (0), or is held in first (1) or third (2). Bound by the module (REPLICATED) and followed by a client through its link. (No `mp_solidplayers` here: runners and buses share layer one, and a hull on it would be something every bus hits.)

### game/bfh_game.gd (was line 219)

What the server last said about the numbers a client cannot count for itself.

[b]Negative means "count it yourself", which is what a server and an offline client do.[/b] A client does not run the prop spawner — its crates are mirrored bodies with no [DotPropInstance] behind them — so `crates_left()` there would count zero and the HUD would tell every networked player that all the cover was gone. See `BfhEvents.Kind.CLOCK`.

### game/bfh_game.gd (was line 241)

Every world object this game has an id for. See [DotEntityTable].

Replaces a `_next_entity_id` counter that was correct and did two things this is not: it had no reverse index, so finding out who an attacker was walked every player on the server ([method _on_player_died]); and nothing ever closed anything, so `DotCombatManager` kept a `DotHealth` for every player who had ever joined -- nodes that were freed with their player, leaving the manager holding references to deleted objects for the life of the process. `forget()` is called now, from the one place that knows a player has gone.

### game/bfh_game.gd (was line 260)

The bowl's toys (dot-props' loose ones: beach balls, barrels, a tyre), on a ring the arena works out from its build (`BfhArena.toy_placements`), so both ends place the same toys in the same order. A bus ploughs them, a hammer whacks them, a walk pushes them; nobody stands on one or hides behind one. Rebuilt with the arena; home at every round's start.

### game/bfh_game.gd (was line 341)

Puts this world's physics space on the gravity the game was tuned for.

[b]On the SPACE, not on `ProjectSettings`.[/b] Two worlds in one process is the normal case here — a server and a client in one editor session, and every section of the suite — and a global would be one of them deciding for the other. A space is a world's own, so each gets the same answer independently.

[b]And it is done at all because a project setting does not travel in a pack.[/b] See [member BfhConfig.gravity]: delivered into the server tool's project, this game ran at Godot's default 9.8 against numbers chosen for 20, and the only symptom was that everything floated.

### game/bfh_game.gd (was line 367)

[b]Off, and the addon's own comment says why.[/b] A registry name is global to the process, so the last manager to register wins — and two worlds in one process is not exotic here: it is a server and a client in one editor session, and it is what the suite does in every section. With it on, the second world's manager displaced the first's and two worlds built from the same seed laid out different bowls, which is the one thing a seed exists to prevent.

### game/bfh_game.gd (was line 425)

The buses are put out by the world at the top of a round, not requested by players, so the limits that exist to stop somebody spamming a spawn key are the wrong shape here. The interval in particular: every bus is placed in the same instant, and at the shipped 1.0 s only the first one appears — silently, because a refused spawn is a refusal rather than an error.

### game/bfh_game.gd (was line 435)

[b]The SPAWNER'S ride, not a second one.[/b] `DotVehicleSpawner` builds one in its own `_init` and uses it for three things: evacuating a vehicle that is destroyed with people in it, answering `vehicle_of_rider`, and reporting how many riders there are. This game used to construct its own beside it, so those three read an index that was always empty — `describe()` said nobody was driving while somebody was, and a destroyed bus released nobody, which is the "stuck aboard a bus that no longer exists" failure this game already had once from the other direction.

It is a [RefCounted] rather than a Node, and dot-vehicle made it one deliberately: seating a rider means stopping their controller and reparenting their node, and neither is something that addon can do without naming dot-player-controller — which would make it fail to parse in a project that does not have it. The two callables below are that seam, and this game is the half that knows what a player is.

### game/bfh_game.gd (was line 463)

[b]Said out loud, because the inherited default says the opposite of what this game does.[/b] [DotDamageRules] defaults `friendly_fire` to false, and a reader who found that here would conclude that a runner cannot hurt another runner. A runner very much can: [method _on_prop_exploded] filters a barrel blast on dead-or-riding and on nothing else, and a blast that asked whose side you were on would not be a blast.

[b]And `team_of` stays unset deliberately.[/b] dot-combat decides friendly fire through a `team_of` [Callable] and treats a missing one as "nobody is anybody's team mate" — which is a real trap, and cost another game in this family a round where friendly fire was on in a game whose rules said it was off. It is not a trap HERE, because the one damage path that could hit your own side already does the side test itself before it calls in: a bus skips every driver by key, so a bus cannot run over a driver even after its own driver has been evacuated onto foot. Wiring `team_of` now would not fix anything; it would silently start refusing the barrel splash that is meant to be indiscriminate.

### game/bfh_game.gd (was line 510)

[b]One.[/b] dot-match defaults to two because a deathmatch with one player in it is not a match; a round here with one runner and no drivers is a legitimate, if dull, thing for a nearly-empty server to be doing, and the alternative is a server that sits in warmup for ever and looks broken to the one person on it.

### game/bfh_game.gd (was line 515)

[b]The rule asks the game who is alive, and that is the seam dot-match is built around.[/b] Being alive is a `DotHealth`, which lives in dot-combat, which dot-match deliberately does not depend on. Left unset this falls back to a score and a clock — and the tell is specific and visible in the first round played: the round runs to the full clock instead of ending on the last kill.

### game/bfh_game.gd (was line 528)

[b]Here, in both halves, and it was not.[/b] From 2026-09-26 these lines sat at the end of [method _build_progress], below its two early returns, because that function and [method _build_spectate] were inserted into the middle of this one. So a client's world kept dot-match's default pair, "Red" and "Blue" — nothing read them until the scoreboard asked for a side's name — and so would a server with `track_progress` off or whose tracker failed to attach, with dot-match's balancing and its one-ahead cap back on, which is the bug the lines below exist to prevent. Nothing ships with the tracker off, which is why no round said so.

### game/bfh_game.gd (was line 541)

[b]And re-indexed, because assigning the list does not.[/b] dot-match fills in its standard pair when it is added to the tree and indexes it on first lookup, and `teams.team(id)` goes on answering from that index: the ids agree (1 and 2), so every rule worked, and the first thing to ask for a side's NAME — the scoreboard — was told "Red" and "Blue". Found in its first render.

### game/bfh_game.gd (was line 553)

[b]And off in the second place dot-match balances, which `force_balance` does not reach.[/b] `max_difference` defaults to 1 and REFUSES any join that puts a side more than one ahead — so on a shipped server the second driver and every runner past the drivers' count plus one were on no team at all in dot-match, while `sides` had them placed correctly. The elimination rule counts survivors off dot-match's teams, so a round was handed to the drivers the moment the runners it knew about were down, with the others still standing. `sides` decides who is on which side; dot-match is told.

### game/bfh_game.gd (was line 579)

Statistics and achievements, on the authority. See [BfhProgress].

[b]Not fatal either, and deliberately loud:[/b] a server that cannot count is a server people can still play on, and a WARN is what tells the operator their players are not earning anything.

### game/bfh_game.gd (was line 608)

Puts somebody in the world. [param wanted_team] is a TEAM_* constant, or 0 to be placed.

[param bot] is here rather than set by the caller afterwards, because [signal player_added] is answered by things that need to know: `BfhProgress` does not count a bot, and a flag set on the line after this returns is a flag every listener read as false. The bridge and the offline client both used to set it that way.

### game/bfh_game.gd (was line 648)

A refusal here means this player id is already an entity, which cannot happen -- `add_player` returns early on a duplicate. Logged rather than ignored because arming them anyway would register a second health record against one body, and the symptom of that is a player taking half damage.

### game/bfh_game.gd (was line 684)

[b]Somebody arriving in the middle of a round is placed NOW, not at the next one.[/b] `_place_players` only runs when a round is laid out, so a runner who joined a live server stood where a `CharacterBody3D` starts — the centre of the bowl, on the ramp's line — until the round ended, which on a real server is most of their first two minutes. It was found by a second client DRAWING them there: every suite asserts the joiner exists and moves, and a player at the origin does both. mg-smash-copter shipped the same line, where the origin was inside the floor that kills you.

### game/bfh_game.gd (was line 710)

Puts a driver who arrived after the buses were placed into one nobody is driving.

[b]Seating used to happen only at the top of a round, and the bots made that a real gap.[/b] A person driving disconnects, their bus stays where it stopped, and the module fills the seat with a bot inside two seconds -- in `sides`, and nowhere else. The bot then stood on the sand as a pedestrian nothing can run over while its bus sat still for the rest of the round. With no empty bus this does nothing and the next round seats them, which is what always happened.

### game/bfh_game.gd (was line 731)

Which side somebody new goes on.

[b]Drivers are capped and runners are not, which is the opposite of a balancer.[/b] There are `driver_count` buses and a driver without one is a person standing on a ledge watching, so the cap is the number of seats rather than a fraction of the server.

[b]Except that somebody has to be on foot, and only a person can be.[/b] A round needs a runner ([method sides_are_playable]) and a bot only ever drives, so the first person on a server took a seat, the module put a bot in the other one, and the match sat in warmup for ever with two drivers and nobody to run over. The offline client always put its player on foot; a dedicated server's first joiner now gets the same.

### game/bfh_game.gd (was line 767)

Before the node goes. dot-combat keyed a `DotHealth` on this entity and NOTHING in this game had ever told it to let go -- so every player who had ever joined left a health record behind, pointing at a node freed with them. The manager's own documentation says what that costs; what made it invisible is that a stale entity is never asked about, because nothing traces against a player who left.

### game/bfh_game.gd (was line 797)

Hands a runner their hammer and listens to it.

[b]The hammer is a plain object that swings and emits, and this is where its two signals become the world's.[/b] A swing is a sound and a number: `noise` for whoever is listening to the bowl, `swung` for [BfhProgress]. Both are decided on the authority, because the authority is the only place a hammer is ever swung.

### game/bfh_game.gd (was line 840)

A driver's horn. The swing button, for somebody whose only weapon is the bus.

[b]Rate-limited here, on the authority,[/b] because a horn is heard by everybody and a modified client holding the button down would otherwise be a server-wide siren. A bot sounds it far less often than a person may, and only when it has somebody lined up — see [method _autopilot]. Returns whether it sounded.

### game/bfh_game.gd (was line 939)

[b]The bowl is laid out here and not only on `round_started`, and that is the difference between an empty server and a broken-looking one.[/b] dot-match runs a warmup before the first round, so a world that only furnished itself when a round began sat for the whole warmup as a bare disc with nothing in it — which is what somebody joining an empty server would see, and is indistinguishable from the props having failed to spawn. A round re-lays it; this puts it there.

### game/bfh_game.gd (was line 991)

Swaps every player's side.

[b]Driving is the fun half and there are two seats for it.[/b] A server that never swaps is a server where the same two people drive all night, which is the failure this game has that a symmetric one does not.

### game/bfh_game.gd (was line 997)

[b]Not when nobody driving is a person.[/b] Bots only drive, and the module removes a bot that finds itself on foot, so swapping a server whose seats are all bots put every person in a bus and left nobody to run: the next round never started. The people keep running until one of them is driving.

### game/bfh_game.gd (was line 1016)

[b]dot-match as well, because its elimination rule is what decides the round and it reads teams off its own scoreboard.[/b] Flipping `sides` alone left the rule on the old sides for the rest of the server's life: the drivers ran the new runners down and every such round was announced as the runners' win.

### game/bfh_game.gd (was line 1045)

[b]Riders out before the bus goes, and nothing else does this for us.[/b] `DotVehicleRide` is a RefCounted holding its own rider index and it does not watch the spawner — so a bus removed underneath somebody leaves the ride still believing they are aboard, and every later `enter` is refused with "You are already in a vehicle." Permanently: there is no bus left to get out of. The symptom is a driver who is put on the ledge at the top of round two and never gets into anything again, which reads as the seating being broken rather than as a round having cleaned up in the wrong order. `occupants` is keyed by SEAT id and valued by rider id, which is the direction `seat_of()` reads it in. Iterating the keys hands `exit` a seat name where it wants a rider, and it answers "You are not in that vehicle" — truthfully, about a rider called "driver" who does not exist — so the real rider is never released and is stuck aboard a bus that no longer exists.

### game/bfh_game.gd (was line 1227)

Every bowl this server plays, as the map menu (M) lists them: `{id, name, detail, current}`, its size under the name. Solo the client's list, online the server's (the module hands it to dot-vote's map menu), so both say the same.

[param index] is the Workshop's: a subscribed map of an accepted kind whose bowl document loads is listed after the bowls as "Name [Pack]", for the index's current session only (so never online). Null lists the game's own.

### game/bfh_game.gd (was line 1247)

The bowls a subscribed pack adds, each `{id, name, radius}`. A pack's `map` entry of an accepted `map_kind` names, in `scene`, a bowl document: JSON `{"radius": metres}`, clamped to what the arena's gap rule has been built and checked for. One that does not load is left out (nothing broken is listed), and the game's own ids win.

### game/bfh_game.gd (was line 1379)

Where one person stands at the top of a round, or on arriving during one.

A late joiner draws from its own stream ([method add_player]), so somebody connecting does not move where everybody ELSE is scattered next round — the layout a seed promises is the same whoever came and went.

### game/bfh_game.gd (was line 1400)

[b]Turned to face the bowl, and the default is 180 degrees wrong.[/b] `spawn` orients with `Basis.IDENTITY` unless told otherwise, and identity faces -Z — which from a ledge at the north edge is straight into the wall seven metres behind it. The bus then drove forward, at full throttle, into that wall, for the whole round: four wheels on the ground, correct engine force, correct steering, and a speedometer reading 0.0 m/s. Every number was right and the only wrong one was which way it was pointing.

### game/bfh_game.gd (was line 1469)

One simulated tick, numbered by the netcode. What the bridge uses.

[b]The tick number comes from outside and the step does not.[/b] A snapshot is stamped with the netcode's tick and a client reconciles against that number, so a world counting its own would be replying about a different tick than the one it was asked about. The STEP stays a fixed `1 / tick_rate` either way: a simulation stepped by a frame's delta is a simulation that runs differently on a server having a bad second, and this family has paid for that twice.

### game/bfh_game.gd (was line 1505)

[b]A round with one side empty is not a round, and letting the clock run on one is an infinite loop with a scoreboard.[/b] The elimination rule ends a round the moment a side has nobody alive, and a side with nobody *at all* satisfies that on the first tick — so a server holding five runners and no drivers starts a round, ends it, swaps the sides, starts another and ends that, several times a second, for as long as nobody joins. Nothing errors: every round is decided correctly and the decision is correct. The suite found it as crates vanishing out from under a test that had just spawned them.

### game/bfh_game.gd (was line 1519)

How long a round lasts, from now on: the config AND dot-match's rule.

[b]The rule is the clock that ends a round[/b]; `config.round_seconds` is only what it was built from and what the HUD counts down. `bfh_round_seconds` used to write the config alone, so an owner's 50 s was shown on the HUD while every round ran the built-in 180. Read live by dot-match, so it applies to the round in progress too.

### game/bfh_game.gd (was line 1582)

Adopts a tick rate, on a client being told what the server runs at.

[b]Every player's controller as well as this world, and that is the whole reason it is a method.[/b] `tick_rate` is a plain property on a [BfhPlayer] with a setter that forwards to the controller, so a world that changed only its own left every player integrating at the old rate -- which is a client that walks at 60/128 of the speed the server moves it at and is corrected on every snapshot for doing so.

### game/bfh_game.gd (was line 1626)

Turns each driver's movement keys into throttle and steering.

[b]The sample is the same one the walking controller takes, deliberately.[/b] A driver's forward key is the throttle and their strafe keys are the wheel, so nobody has to learn a second set of controls for the half of the game they only play every third round.

### game/bfh_game.gd (was line 1647)

`current_command` is what `apply_command` stored and what the next tick would have moved them with. Read rather than re-sampled: sampling a second time here would consume a frame's mouse motion twice and make the driver's view turn at double rate, which reads as the bus having drifty steering.

### game/bfh_game.gd (was line 1672)

S brakes while the bus is still rolling forward and reverses once it has (nearly) stopped, as the key list says; W while rolling back brakes too. Reverse thrust stopped a bus from 15 m/s in 21 m against the foot brake's 7.6. A person's keys only: the autopilot's reverse legs mean reverse.

### game/bfh_game.gd (was line 1684)

Drives a bot's bus at whoever is nearest.

[b]`set_target` each tick rather than a route, and that is what makes a bot bus readable.[/b] [DotVehicleDriver] will follow a waypoint list, which is the right shape for traffic and the wrong one here: a runner's entire game is reading where a bus has committed to and stepping out of it, and a bus on rails is not committing to anything about them. Re-aimed every tick it behaves like a person who has picked a target — it overshoots, it has to come round again, and the gap while it does is the opening the round is played in.

### game/bfh_game.gd (was line 1697)

Wider than the default, because a bus is nine metres long: a waypoint radius tighter than the vehicle means it can never be "at" its target and it circles the spot for ever. [b]Tiny, because arriving is the one thing this driver must never do.[/b] `DotVehicleDriver` slows down inside `arrive_radius` and stops at the waypoint, which is right for traffic and exactly wrong for a chase: at 6 m the bus coasted to a halt beside the runner and sat there with the throttle at zero. A bus is not trying to reach a person, it is trying to be where they are at speed.

### game/bfh_game.gd (was line 1708)

[b]No corner-cutting toward the next waypoint.[/b] The point beside a pillar is placed at exactly the clearance `steer_around` measured; blending it 4 m toward the quarry (the driver's default) drove the bus inside that clearance, and the colonnade's drive along the walk from its deck end wedged on a pillar and was sent home.

### game/bfh_game.gd (was line 1722)

Aimed PAST them, not at them. The driver decides its speed from the distance to its target, so a target sitting on the runner is a target that is always nearly reached — the bus arrives gently. A point eight metres beyond them, along the line the bus is already on, keeps the throttle down through the moment that matters and is what makes a near miss look like one. [b]How well it drives is dot-bot's `bot_difficulty`[/b] (the module binds the cvars, the offline client the console variables). Two of its settings mean something at a wheel: `bot_prediction` is how far ahead of a running target it aims, and `bot_aggression` how close to top speed it drives. Both are taken relative to medium, so medium is exactly the bus this game always had: a nightmare bus cuts a runner off, an easy one trails where they were and comes in slower.

### game/bfh_game.gd (was line 1753)

And round the stacks, because the driver has no idea they are there. A bus aimed through a pillar wedges nose-on and the stuck rule then teleports it back to its start line, which from the runner's side reads as hiding behind a pillar deleting the bus. See [method BfhArena.steer_around]. Slower while bound up the ramp: 5 m of slab for 2.5 m of bus leaves 1.25 m either side, and at full speed the line-up overshoots the middle. See [method BfhArena._up_the_ramp]. [b]In a district the ramp's own rules begin at the foot.[/b] Further out the street route carries the bus there: the open-floor turn and line-up, planned with `steer_around`, drove a bus into a street's buildings 45 m from the ramp and stood it braking there for 26 s.

### game/bfh_game.gd (was line 1778)

[b]A district is a maze and is driven by a route.[/b] Through the streets with [method BfhArena.street_route]; the first waypoints are passed at speed like any detour and the point past the quarry is last. No nudge on top of it: the route already keeps a bus off every building, and the nudge's wider berth is what wedged it in a 7.6 m street. Not up the ramp, whose line-up is its own rule.

### game/bfh_game.gd (was line 1793)

[b]And never the point the bus is already standing on.[/b] `steer_around` hands a bus the point beside a pillar across its line; a bus that stops there with the pillar still (just) across it -- level with it, centimetres ahead -- is handed the same point again, which `DotVehicleDriver` calls arrived: it brakes with the throttle at zero, and `_unstick` only answers a bus asking to go, so it was parked for the rest of the round with the runner in plain view (measured 2026-10-01 from the spawn lane, chasing a runner on the deck). Level with a pillar is past it, so a bus at a standstill on its waypoint drives on along its line to the quarry. Only at a standstill: done at speed, inside `steer_around`, it threw the stacks' pillar drive off its line onto the next pillar in the row. `headless_run`'s "no bot bus ... is ever parked" holds it.

### game/bfh_game.gd (was line 1822)

[b]A point beside an obstacle is passed THROUGH, not arrived at.[/b] As the only waypoint it was the last one, and `DotVehicleDriver` slows into its last waypoint and brakes hard once inside `arrive_radius`: a bus coming round a stacks pillar at 15 m/s stood on the brake for two ticks beside it, lost its line, and put its front corner into the next pillar of the row, every time (measured 2026-10-07, round pillar 5: 4.6 s for a 27 m line, against 3.0 s as a route). So the detour is the first of two waypoints and the point past the quarry the second, which the driver passes at `waypoint_radius` with no slowing. Not up the ramp, whose line-up points are meant to be arrived at slowly and are tuned for it.

### game/bfh_game.gd (was line 1842)

A bot bus that has been throttling against something, backing out of it: reverse with the wheel over (in reverse it swings the nose towards the side [param toward] is on) for `bot_unwedge_seconds`, then null so the ordinary drive takes over from where it got to.

[b]Because the driver only ever goes forward.[/b] A bus whose nose is in a building, or whose aim is behind it with a wall of towers either side, held the throttle until `_unstick` put it back on its start line five seconds later (measured 2026-10-15: every map, two to five times in 45 s). Triggered by the same clock the stuck rule reads, so nothing here decides what "wedged" is; only sooner, and by a driver's remedy instead of a teleport.

### game/bfh_game.gd (was line 1928)

A bot bus that has to face the other way to get up the ramp turns round in legs, or null to drive on. The bowl has no room for a circle (about 22 m, boxed by stacks, hook and farm), so past [constant RAMP_BACK_FROM] degrees off it reverses with the wheel over, then goes forward the other way, each leg for at most [constant RAMP_BACK_LONGEST] / [constant RAMP_FORWARD_LONGEST] seconds, until the nose is within [constant RAMP_BACK_TO]. Both legs: reversing alone dithered at the foot.

### game/bfh_game.gd (was line 1977)

A bot bus bound up the ramp that cannot simply drive at it (back to it, or climbing off the middle) turns or backs down and lines up again. Null when neither applies and the ordinary line-up drives. Planned against the floor that is there, where [method _turn_for_the_ramp] is planned against the clock: it drives to [method BfhArena.ramp_turn_point], ends each leg when the end it moves towards is about to run out of floor ([method _end_blocked]) or off the centreline ([constant RAMP_TURN_ACROSS]), turns to the ramp's fixed axis, and hands over only when it will arrive ON the centreline ([constant RAMP_LINE_RADIUS], [constant RAMP_LINED_X]). A bus on the ramp heading for its edge backs down it. Done here, not in `DotVehicleDriver`, and only for the ramp. See docs/bots.md.

### game/bfh_game.gd (was line 2124)

Onto the centreline the way a lane-keeping controller does it: the heading it wants is the ramp's axis turned towards the centreline by an angle that grows with how far off it is, so the offset and the heading are taken out together and the bus arrives on the line pointing along it. The angle is the one from which a full-lock straightening lands on the line. A pursuit point 6 m up the line (what the ordinary line-up uses) does not converge in the room there is: from 4 m off and 12.5 m out it was still 1.7 m off and 18 degrees across 4.8 m from the foot, measured.

### game/bfh_game.gd (was line 2163)

[b]A leg that has not moved is not ended by the floor.[/b] A bus within the margin of something at both ends found each new leg blocked on its first tick, flipped and braked again, and stood braking for 27 s with no throttle for the stuck rule to see (small bowl, in front of the foot). It pushes instead, and the stall ends it.

### game/bfh_game.gd (was line 2192)

Whether the end of [param bus] it is moving towards ([param reverse] for the tail) is about to run out of floor: any of its two corners and its middle, a margin ahead along the way that point is moving, inside [constant RAMP_TURN_MARGIN] of an obstacle, the slab or the deck, or, with a [param centre], further than [constant RAMP_TURN_REACH] from it and still going out.

### game/bfh_game.gd (was line 2263)

The speed a leg is held under (m/s); how still the bus has to be, and for how long the wheel has to swing, between legs; how long a leg can push without moving before it counts as stopped; how long a leg runs before the turning point's bounds apply; and the longest a leg lasts whatever the floor says (s).

### game/bfh_game.gd (was line 2351)

A bus that touched somebody, and what that costs them.

[b]Closing speed, not the bus's speed.[/b] A runner sprinting into the side of a parked bus is not being run over, and a bus reversing at 3 m/s into somebody who is running away from it at 6 is not either. Taking the bus's own speed makes both of those kills, which reads as the game being unfair in a way nobody can point at.

### game/bfh_game.gd (was line 2387)

[b]And nothing above the roof, which the sphere cannot tell.[/b] A sphere round a box that is wider than it is tall reaches over the top of it: a runner standing three crates up, with a bus driving past the foot of the stack, was 3.2 m from its centre and killed — by a vehicle whose hull ends at 2.5 m. Found by the scaffold's own check, whose runner died on the top step with one crate out of place. Height is the scaffold's whole point, so it has to be the one thing this bound gets right.

### game/bfh_game.gd (was line 2397)

[b]Along the offset, not against it.[/b] `offset` runs from the bus to the player, so a bus moving toward them has a POSITIVE component along it. The first version negated this, which made every genuine run-over read as a closing speed below the threshold and every impact was silently skipped — a bus that drove through people and left them standing. Nothing errored; the arithmetic was simply backwards.

### game/bfh_game.gd (was line 2417)

The top of a bus's hull in world height, from its own collider.

Read off the scene rather than written down, because the art is a truck twice the hull's height and the number anybody would guess from a picture is the wrong one.

### game/bfh_game.gd (was line 2472)

Crates and barrels a moving bus has driven into.

[b]The bus's own box, not a sphere around it, and the sphere was wrong in both directions.[/b] A nine-metre bus has a centre five metres from its nose, so a radius generous enough to catch what it is about to hit also catches everything beside and behind it — a bus flattened a line of crates it merely drove past. Testing the prop in the bus's local frame is the same arithmetic and answers the question actually being asked: is this thing under the bus.

### game/bfh_game.gd (was line 2522)

A bus that is throttling and going nowhere, and what to do about it.

[b]A crate stops a bus, and it should not, and no amount of tuning fixes it.[/b] A raycast vehicle has no wheel collider: each wheel is a ray, so a crate does not hit a wheel, it passes under one and lifts the corner of the bus off the ground. The bus ends up high-centred with two wheels in the air and a crate wedged under the chassis, going nowhere — and the speed-gated impact rule cannot save it, because by then it has no speed. Lowering the hull so it rams crates instead was tried and is worse: the hull then drags on the ground and the bus barely moves at all.

So the rule is about intent rather than geometry. A bus asking for throttle and not moving is caught on something; after a second, whatever is under it stops existing, and after five it goes back to its start line. That second rule is not a fallback for the first — it is what recovers a bus that drove up the ramp and beached itself on the ledge, where there is no prop to blame.

### game/bfh_game.gd (was line 2541)

[b]Rocking in place is not moving.[/b] The back-off reverses and goes forward again, and each lurch passes 1 m/s and restarts the clock below, so a bus wedged among crates in a street shuffled within three metres for 20 s without ever being caught (hill town). Asking for throttle and not having left the `bus_pinned_radius` circle for `bus_pinned_seconds` counts as stuck whatever the speed.

### game/bfh_game.gd (was line 2585)

[b]Before the start line, a short hop back the way it came.[/b] A bus sitting on a concrete block (it cannot be broken or pushed, so the rule above has nothing to remove) is high-centred in both directions, and the back-off rocking cannot lift it. Measured 2026-10-18 with four bot buses: three of four maps held a bus on a block or crate for the full five seconds and then sent it across the bowl. A hop of a few metres along its own axis puts it where it was driving a moment ago, still in the chase.

### game/bfh_game.gd (was line 2631)

A bus that has rolled over, and why it is not left there.

[b]A bus on its roof is a driver out of the round through no decision anybody made.[/b] dot-vehicle's own tunables comment says it about the centre of mass; this is the other half, because no amount of lowering the centre of mass makes a 2.6 m box on a 2.5 m track impossible to flip — a ramp, a crate under one wheel and a hard turn will do it. The round is three minutes long and there are two buses, so a driver spending one of those minutes upside down is a quarter of the game's threat gone for reasons the runners cannot see and did not cause.

[b]Rolled over where it lies rather than put back on its start line.[/b] `_unstick` has the start line for the case where the bus is somewhere it cannot get out of; this is for the case where it is somewhere perfectly good and merely inverted, and teleporting it across the bowl would take it away from the chase it was in the middle of. Its heading is kept and its velocity is not: a bus that lands upright still carrying the roll's momentum immediately flips again.

### game/bfh_game.gd (was line 2683)

Who is driving the bus with this instance id, or an empty name.

Public because a bridge, a console command and a suite all ask it, and the alternative is three copies of a loop over the ride's index.

### game/bfh_game.gd (was line 2696)

A barrel went off. dot-props described the blast; this is what it does to people.

[b]The blast reaches players through dot-combat and props through dot-props, and that split is the addon boundary rather than an accident.[/b] dot-props knows what a prop is and nothing else — a player, an NPC and a vehicle each need somebody else's id space and authority rules — so it shoves the other crates itself and hands the rest over here.

### game/bfh_game.gd (was line 2733)

Thrown, and a barrel is the only thing in the game that throws a runner UPWARD — two metres from the hammer's reach, past any jump, which is why a barrel is worth standing near as well as away from. NOT onto a loose stack of crates beside it, which this comment used to promise: the same blast shoves the stack further than it throws the runner. See docs/map.md, "What a runner can climb".

### game/bfh_game.gd (was line 2746)

[b]And off the ground, or none of that survives the tick.[/b] A velocity added to a runner the motor still has as GROUND is snapped back onto the sand before it moves them — which is what this did for nine days, and a barrel lifted people 7 cm. The motor's own launch path does exactly these two lines; see `DotFpsMotor.add_modifier`.

### game/bfh_game.gd (was line 2760)

The fall a death gets: dot-player-char's reaction rule over the server's weights, seeded from the player and the tick. [b]A bus or a barrel always throws the body[/b] (the power launch, unless the server turned it off): being run over by a bus from hell is the one death this game is named for, and a body that just slumped in front of the grille would undersell it.

### game/bfh_game.gd (was line 2775)

One dictionary read. This walked every player on the server comparing ints, which is the reverse index [DotEntityTable] keeps so nobody has to -- and it ran on every death, which on this game is a lot of them.

An attacker of 0 is dot-combat's "the world" -- a bus that nobody was driving, a fall -- and the table returns an empty key for it, which is the same answer the scan gave and means the same thing.

### game/bfh_game.gd (was line 2812)

Rounds [param team] has won this match, which is what dot-match scores here.

[b]A SIDE's tally, not a group of people's.[/b] Everybody changes sides every `rounds_before_swap` rounds, and dot-match's `rounds_won` is keyed by team id, so this is "rounds the buses have won" and "rounds the runners have won" whoever was in them. On a client it is what the last CLOCK said; dot-match is not ticked there.

### game/bfh_game.gd (was line 2865)

Where each bus is and how fast, for a console dump and a bug report.

[b]Position and speed, because "the bus does nothing" has three causes and they look identical from the floor.[/b] It can be stuck on the ledge, upside down, or driving perfectly well somewhere the player is not — and only one of those is a bug.

### game/bfh_hammer.gd (was line 5)

The only weapon in the game, and it does not hurt people.

[b]A hammer that cannot kill is the whole balance of the runners' side.[/b] The obvious version of this game gives the runners something to shoot the drivers with, and that version is a deathmatch in a bowl: the buses stop mattering, the crates stop mattering, and the round is decided by aim. What the hammer does instead is change the map — break a crate somebody else is hiding behind, shove one into a bus's line, open a path, close one. Every use of it is about geometry, which is the only thing a person on foot has against a vehicle.

[b]It is not a [DotWeapon] and there is no dot-loadout here.[/b] Both addons exist and both are about choosing between things; there is exactly one thing. A catalogue of one is a catalogue that will be wrong the moment somebody adds a second entry and forgets the rules that went with it, so this is a plain object that swings.

### game/bfh_hammer.gd (was line 59)

Swing from [param origin] along [param direction].

[b]Given an origin and a direction rather than a camera.[/b] The same rule dot-props' own tools follow: a tool that owned a camera could not be swung by a bot, by a replay, or by a headless test, and all three are things this game's suite does.

Returns whether the swing happened at all — false means it was still on cooldown, which is different from a swing that missed. A swing's weight against a toy, as a shot's damage (dot-props' `DotPropToyBox.shot`): a beach ball goes off at its nine metres a second, a barrel rolls.

### game/bfh_hud.gd (was line 8)

Health, the clock, and how much cover is left. Four numbers and a crosshair.

[b]How much cover is left is the one number that is not obvious, and it is the most important of the four.[/b] Health tells a runner how many mistakes they have left and the clock tells them how long they have to survive; neither tells them whether surviving is still possible. The crate count does: a bowl down to its last few blocks is a bowl where standing still stops working, and a player who can see that number drop starts moving before it is too late rather than after.

### game/bfh_hud.gd (was line 17)

No `const CHANNEL`. This draws four numbers from state somebody else owns and has nothing an operator would act on; the round, the deaths and the bowl are logged by [BfhGame], which is where the decisions are. A channel declared and never used is a file that meant to say something and does not.

### game/bfh_hud.gd (was line 34)

An administrator's `blind`, over the world and under the four numbers.

[b]Under the numbers, on purpose.[/b] A blind takes the bowl away, not the player's bearings: the clock, their health and the cover count still say that the round is going on and that they are in it, which is what makes it read as "an admin did this" rather than as a client that stopped drawing. The chat box is its own layer above this one.

Black rather than white. A white screen at full brightness is a thing a player can be hurt by in a dark room, and taking the picture away is the whole of the point.

### game/bfh_hud.gd (was line 67)

The Escape menu, whose theme this HUD follows (dot-menu's `follow_hud`): the menu sets the theme on the HUD's root now and at every theme change, and applies the player's HUD size. Christian's first play test (2026-10-11) asked for a darker HUD a player can restyle in the menu. Duck-typed and called by name, for a client shell older than dot-menu 7.

### game/bfh_hud.gd (was line 91)

[b]A full-rect Control between the CanvasLayer and the labels, and the first render is why.[/b] A CanvasLayer is not a Control and does not lay its children out, so anchors on a Label parented straight to one resolve against nothing: every label landed in the top-left corner stacked on top of the others, and the only one visible was the clock, clipped in half by the edge of the screen. It reads as the HUD being half-written rather than as four labels in one place.

### game/bfh_hud.gd (was line 199)

Fades [member blind_overlay] toward whether this HUD's player is blinded.

Read off [member player] rather than pushed by anybody, because the flag arrives in a snapshot on a connected client and is set directly offline, and a HUD that had to be told would need telling from two places. Public so a check can step it.

[b]Sized to the viewport every frame it shows, not trusted to its anchors.[/b] The root it sits in is full-rect under a [CanvasLayer], which today IS the viewport — but a blind that left a strip of the bowl showing would be a blind a player can still play through, and one line here costs less than finding that out from a picture.

### game/bfh_hud.gd (was line 247)

What a runner who is out is told about the camera they are looking through.

[b]Who, and how to change it, on one line.[/b] A camera that moved to somebody else's eyes with nothing on screen saying whose reads as the client having lost track of the player, and the three controls are the kind nobody finds by pressing keys at random. Static and public so the suite reads the words a player would.

### game/bfh_killcam.gd (was line 5)

The killcam at a round's end. Client side: every frame drawn goes into dot-replay's [DotKillcamBuffer], every decisive moment (a runner going under a bus) is noted, and when the round ends [DotKillcam] replays the last one from the eyes of whoever caused it. The length is `mp_killcam_time`; 0 skips straight to [signal over].

### game/bfh_module.gd (was line 17)

Where the services keep punishments. Empty is [DotGameServices]'s own default, `user://buses_punishments.json` — the store a real server enforces.

[b]Static, because nothing holds this module before it exists[/b]: dot-server constructs it from a path inside `load_module`, so there is no instance for a host to set a field on first. `examples/dedicated.tscn` points it at a directory of its own; before it could, every run appended the live tools' audit warnings to the real store, 134 of them by the time anybody counted.

### game/bfh_module.gd (was line 33)

This game, as a module a dedicated server loads.

[b]The first game to subclass [DotGameModule].[/b] The netcode, the bridge, the seal, the identity layer, the roster, the tick and the teardown are the base's; this file is only what is this game's.

[b]No `class_name`, and that is a requirement rather than a style.[/b] [method DotModuleHost.load_module] takes a PATH and constructs the module itself — it must, because that is the shape that lets an operator name one in a config file — and a module delivered inside a dot-cloud pack cannot have a `class_name` at all: a mounted pack's globals are not registered in the host.

[codeblock] server.modules.load_module("res://game/bfh_module.gd") [/codeblock]

### game/bfh_module.gd (was line 48)

[b]No `const CHANNEL` here, and its absence is the point.[/b] [DotGameModule] already declares one and GDScript refuses to let a subclass redeclare it — which is the right refusal: a module logs through [method DotModule.log_info], which stamps the module's own name, so a second channel would split one module's records across two places an operator has to know to turn up separately.

### game/bfh_module.gd (was line 71)

The netcode's numbers, which are the game's and not the addon's.

Tick rate from the world, so `sv_tickrate` reaches it: the server sets the engine's physics rate from that cvar at boot, the world is built after the server and reads it, and this reads the world. A number written here instead would be a netcode running at a rate the operator did not choose, silently.

### game/bfh_module.gd (was line 83)

[b]Off, and this is the one game in the family where that is obviously right.[/b] Lag compensation exists to resolve one player's shot against where they saw somebody. Nothing here is resolved that way: the hammer has a reach of 2.4 m and hits scenery, and a bus hits people by being where they are. There is no shot to rewind for.

### game/bfh_module.gd (was line 99)

Chat, voice and moderation, over [DotGameServices].

[b]The bridge is handed over as the link, and that is the whole of the wiring.[/b] A chat line goes out through `send_chat` and a voice frame through `send_voice`, both on this game's own wire — see [BfhNetLink]. [DotGameModule] does the rest: it assigns the bridge's `voice_relay_fn`, checks `check_admission` before seating anybody, and tells the roster to follow this layer so a leaver is forgotten by the rate limiter and the voice router together.

### game/bfh_module.gd (was line 114)

Profiles, avatars and admission: dot-platform's [DotPlatformIdentity] over this game's one-slot schema. [DotGameModule] builds it before the services and loads dot-platform's own module beside it.

[b]Authentication is not here and was never this game's.[/b] Whether a player is proven to be somebody is the host's `dot_auth_server`, the same for every game it runs; what this layer does is everything after — a scoped profile, the name on it, a face, and a key their numbers outlive the connection under.

### game/bfh_module.gd (was line 204)

[b]How many is dot-server's [DotBotQuota], so `bot_quota` and `bot_quota_mode` mean the same thing on every server in the family[/b] — counted in DRIVING SEATS here, because a bot only ever drives. The people it is given are the people driving, not everybody on the server: counting runners would stand a bus down for a person who joined on foot, and two people joining inside one check would leave both on foot with no bus at all, which is a round that never starts. The default is the seat count in fill mode, the rule this game ran before the policy was shared: every seat nobody is driving has a bot in it, and a person who takes a seat (the sides swap every few rounds) takes it from a bot. `bfh_drivers` is still how many seats there are and caps whatever the quota says.

### game/bfh_module.gd (was line 224)

[b]Started here and not in the world's own `_ready`.[/b] `start()` lays the bowl out and puts the buses on it, and a world that did that before the bridge existed would have spawned every crate with nothing listening to `props.spawned` — thirty-four bodies the server knows about and no client is ever told about. They would be invisible cover: a runner shelters behind a crate a bus cannot see, and the bus drives through it.

### game/bfh_module.gd (was line 245)

The numbers an operator is actually going to want to change, as cvars.

[b]Live, and each one writes through to the config the world already reads.[/b] The alternative is what most of this family's games still do — a JSON file and a restart — and the reason to do better here is the shape of this particular game: the whole thing is a balance between a bus's top speed, how much cover there is and how long a round lasts, and an operator finds their server's numbers by moving one of them between rounds with people watching.

[b]What is NOT here is anything the world has already built.[/b] `bfh_crates` changes how many crates the NEXT round is laid out with; it does not put crates in the bowl now. A cvar that pretended otherwise would be one an admin sets in the middle of a round and then reports as broken. The cvars dot-spectate's rules were bound to, kept for the suite.

### game/bfh_module.gd (was line 286)

The bots' knobs, live from the next tick: the autopilot and the stuck rule run on the authority only and read these every tick, so no client has anything to agree with. The hook and the courtyard's west lane are NOT here (`hook_layout`, `courtyard_west_lane`): they are the map, which every client builds from the HELLO it joined with, so they are set in the JSON file or the environment and need a restart.

### game/bfh_module.gd (was line 407)

A number as an operator would type it: `34`, not `34.000000`.

[b]Not `%g`, which GDScript's format strings do not have.[/b] It is accepted by the parser and fails at RUNTIME with "unsupported format character" — inside `_game_load`, which is the one place in the module sequence that unwinds everything above it. The symptom was a server whose netcode came up, logged that it was ready, and then reported that the game would not load.

### game/bfh_module.gd (was line 467)

One cvar, its default taken from the configuration rather than written twice.

[b]The default is the value the world was built with, and that is the whole point.[/b] A cvar declared with a literal default is a second copy of a number that `defaults < JSON < environment < argv` has already decided — so an operator who set `BFH_ROUND_SECONDS=300` would see `bfh_round_seconds` report 180 and, worse, would reset their own setting the moment anything wrote the value back.

### game/bfh_module.gd (was line 489)

[b]Nothing to undo.[/b] The commands are the module's own and [DotModule] removes them; the netcode, the bridge and the roster are [DotGameModule]'s and it tears them down in the reverse order it built them. The world is NOT this module's to free: it was in the tree before the module loaded and a server can unload and reload a game module without the bowl going away, which is what `module reload` is for.

### game/bfh_module.gd (was line 531)

[b]A server with nobody in the buses is a server with no game in it, and that is specific to this game rather than a general nicety.[/b] Every other game in this family degrades gracefully when it is empty: a deathmatch with one person in it is a person walking around a map, a sandbox with one person in it is the whole sandbox. This one is ASYMMETRIC — a runner with no bus to run from has nothing at all to do, and `sides_are_playable` correctly refuses to start a round, so the first visitor to an empty server would stand in a bowl watching a clock that never moves.

So the seats are kept full. A bot is removed the moment a person wants to drive, which is the other half: the bots are there to make the game exist, not to take the fun half from the people who came to play it.

### game/bfh_module.gd (was line 561)

Bots are told apart by the flag rather than by a list of the ones this module added, as they always were here: a bot an admin or a test put in a seat is a bot in that seat, and it stands down for a person like any other. A leaver is gone from the world the moment the bridge removes them, so nobody half-disconnected is counted.

### game/bfh_module.gd (was line 574)

[b]A bot that is no longer a driver is removed rather than left to walk.[/b] Sides swap every few rounds and take the bots with them, and a bot RUNNER is a person shaped obstacle that never moves: free points for the drivers and nothing for anybody else. There is no walking AI here and there should not be one — the bots exist to fill a bus, and a bus is the only thing this game can drive itself.

### game/bfh_module.gd (was line 624)

Joins the bridge's two chat seams to the services layer's router.

[b]Here rather than in either of them, because this is the only object that holds both.[/b] The bridge knows what arrived on the wire and nothing about what a line means; the services layer knows the rules and nothing about the wire. That separation is the reason a client cannot send a line with somebody else's name on it: what crosses is a channel id and a string, and everything else is decided on this side. The players' vote for the next bowl, over dot-vote: `!vote`, `!rtv`, `!nominate`.

[b]Opened [member BfhVote.open_after_sec] into every round and applied when it ends[/b], because the bowl is rebuilt only between rounds; see [code]game/bfh_vote.gd[/code] and [code]game/bfh_bowls.gd[/code]. A server owner turns it off or reshapes it in `user://cfg/buses_vote.json` or `game.yml`'s `metadata: bowl_vote:`, keyed as dot-vote's [DotVoteRules]. A vote that cannot be built is a WARN and the server's own bowl, never a server that will not start.

### game/bfh_module.gd (was line 772)

A `!command` typed into chat. Run through the console as the person who typed it.

[b]As THEM, not as the server.[/b] `run_command_as_uid` builds a context with that player's own flags, so `!kick` from somebody without the flag is refused by the same file that refuses it at the console — rather than by this function having an opinion.

### game/bfh_module.gd (was line 813)

Who somebody is reaches the world: a face as they are seated, the real name and face once dot-platform has them, and the key what they keep is filed under.

[b]Three events and one path.[/b] Admission finishes AFTER a player is seated whenever the profile store is slower than the join — dot-server has no stage to hold them in — so `player_admitted` is the moment the real name and face exist; a wardrobe change and an operator's `platform_name` are the same thing later. All three end in [method BfhNetBridge.refresh_player], a JOIN everybody already knows how to apply.

### game/bfh_module.gd (was line 836)

dot-platform's state for a session, through its module, or null.

[b]Through the module's `player_for`, never the hub by a key made here.[/b] The hub keys a player by their scoped profile key, which only admission knows; a lookup by `u<session>` finds nobody, every time, and reads as "no avatar" rather than a wrong key. Duck-typed, because a server without dot-platform is a configuration.

### game/bfh_module.gd (was line 878)

One player's session: the five numbers and what they have earned. With no argument, everybody counted, one line each.

[b]By userid, as the player list prints it, not by the storage key.[/b] The key is an implementation detail (`bfh-u<userid>`) and an operator types what `status` shows.

### game/bfh_paths.gd (was line 3)

Where this game's own files are, wherever this copy of it happens to live.

[b]A delivered pack does not mount at the path its content was authored at.[/b] It mounts at [code]res://dot_cloud/<id>/<version>/[/code], so every absolute `res://` reference a game makes to its OWN files resolves against the HOST project root instead — which holds another game's file, or nothing. The pack mounts, the scene loads, and the first thing that tries to use the reference finds something else.

A script knows where it is: `resource_path` is the mounted path, not the authored one. So this game's root is this script's directory with the `game/` segment taken off, and every other path hangs off that.

[codeblock] load(BfhPaths.rebase("res://props/bfh_crate.tscn")) [/codeblock]

Built in, [method rebase] returns exactly what it was passed, so nothing about today's behaviour changes. That is the point: one form that is right in both.

### game/bfh_paths.gd (was line 30)

Moves one `res://` path onto [method root].

Anything that is not a `res://` path comes back untouched, so this is safe to wrap around a value that may already be absolute or may be a `user://` path.

Format specifiers survive: only the prefix is replaced, so `rebase("res://maps/%s.json") % name` works exactly as it read before.

### game/bfh_paths.gd (was line 41)

[method rebase], against a root given rather than discovered.

[b]This split exists so the mounted case can be TESTED from a build.[/b] Built in, [method root] is [code]res://[/code] and every [code]res://[/code] path is already under it — so every property of [method rebase] that only matters inside a pack is a tautology here, and a suite asserting one passes whatever the body says. That is measured rather than argued: in another game the idempotence below was asserted, the guard was removed, and the suite reported 101 passed and 0 failed with the bug back in place.

### game/bfh_paths.gd (was line 53)

[b]Idempotent, and the seventh form of this family's one delivery bug.[/b] The publisher REWRITES every [code]res://[/code] string inside a [code].tscn[/code], a [code].tres[/code] and a [code].import[/code] onto the mount prefix before it signs the pack — it has to, because a scene's [code]ext_resource[/code] paths would otherwise point at the host — and it does NOT rewrite the ones inside a [code].gd[/code], because a script is not a resource file it can parse. So a delivered game holds both kinds: a [code]const[/code] in a script that still says [code]res://props/x.tscn[/code] and needs rebasing, and an exported property on a node that arrives already absolute and must not be. Rebasing the second produces [code]res://dot_cloud/<id>/<version>/dot_cloud/<id>/<version>/…[/code], which fails to load with a path long enough that the doubling reads as noise.

Built in, [param here] is [code]res://[/code] and every [code]res://[/code] path is already under it, so this returns its argument unchanged — which is what it did before.

### game/bfh_player.gd (was line 31)

One person in the bowl: their movement, their view, their health, and their hammer.

[b]This file is a bridge, and the family's own history says bridges are where the bugs are.[/b] Every addon it touches is complete and tested on its own; what has never run is the joins. The three this game adds to the family's usual set are all here, and all three are orderings:

- a player standing on a crate has to be carried by it [i]after[/i] the motor has   moved them, because the motor writes an absolute position and anything applied   before it is overwritten; - the weight they press into that crate is applied on the same tick they were   standing on it, not the next one, or a crate reacts to where somebody was; - a driver's movement is turned OFF rather than ignored while they are in a bus,   for the reason game-playground records: two authorities over one transform reads   as the vehicle shaking itself apart at speed.

### game/bfh_player.gd (was line 47)

No `const CHANNEL`. A player is a body and a controller: what an operator wants to know about one — joined, died, was run over — is decided in [BfhGame] and logged there, and a second channel for the same events would split one story across two places somebody has to know to turn up separately.

### game/bfh_player.gd (was line 52)

Metres above a player's feet that their eyes are.

[b]Here rather than on the client, because it is not a camera height — it is where the hammer is swung from.[/b] The client puts its camera at it and the server resolves every swing from it, and the two being one number is what stops a player hitting what they are not looking at. It was on the client alone for exactly as long as the hammer was swung only on the client.

### game/bfh_player.gd (was line 71)

What this player looks like on foot, as a dot-user-avatar document; null is the stock person. Set on a server from the platform — see `bfh_module._avatar_for` — and carried to every client in JOIN. Null falls back to the same hash [BfhAvatars] calls stock, so a server with no identity layer draws everybody exactly as it always did.

### game/bfh_player.gd (was line 77)

Whether a command is sampled from the input devices each tick.

True for the person at the keyboard, false for a bot and every remote player. A property of the PLAYER rather than of the build, because one client holds both.

### game/bfh_player.gd (was line 83)

Whether this player is driven by the game rather than by a person.

[b]Separate from [member samples_input], and conflating the two is a bug waiting for netcode.[/b] Every remote player also samples nothing; what makes a bot a bot is that something here decides for them. A game that drove "everybody who is not sampling" would drive every other human on the server the moment a bridge arrived.

### game/bfh_player.gd (was line 116)

The bus this player is driving, as the node that is DRAWN, or null on foot.

[b]Kept because nothing else says where a driver is.[/b] The ride does not carry rider nodes and a riding controller is not simulated, so a driver's own position stays where they got in for the whole round. Anything that has to be drawn AT a driver — a beacon — is drawn at this. Set by the world on the authority and from `BfhPlayerNet.net_bus` on a client; cleared by [method set_riding] when they get out.

### game/bfh_player.gd (was line 125)

An administrator's `blind`: this player's own screen is blacked out.

[b]Set on the server and replicated to the OWNER ONLY[/b] (`BfhPlayerNet.net_blind`). Nobody else's screen changes, so nobody else needs to know — and in a game of two drivers hunting everybody else, a driver who could read it would know exactly which runner cannot see the bus coming. `BfhHud` draws it.

### game/bfh_player.gd (was line 133)

An administrator's `beacon`: a pulsing ring and a column over this player that every client draws, and a ping every client hears, until it is turned off.

Set on the server and replicated to everybody (`BfhPlayerNet.net_beacon`), who each draw it in [method present_beacon].

### game/bfh_player.gd (was line 177)

EXTERNAL rather than LOCAL even offline: the game owns the tick, so the order "sample, move, then ride what you are standing on" is explicit here rather than happening inside somebody else's loop. It is also the shape a dedicated server and a net bridge need, so nothing has to be rearranged when one arrives.

### game/bfh_player.gd (was line 196)

How a runner moves.

[b]Static, and it takes the config, and neither was true to begin with.[/b] Static because a connected client has to build a sampler before it has a player — the local player arrives in a JOIN, several frames after the keyboard does — and a sampler built from different tunables than the controller it feeds is a client whose own input is clamped differently from the simulation that consumes it.

And it takes the config because it used to ignore it: `runner_speed` and `runner_jump_height` were exported, documented, layered through JSON, environment and argv, validated — and then this function wrote 6.5 and 1.15 in literally. They happened to be the same two numbers as the defaults, so nothing looked wrong; an operator who set `BFH_RUNNER_SPEED=9` got a server that accepted the value, reported it in `describe()`, and moved at 6.5. The family's own "produced correctly and consumed by nothing", in the shape where the consumer exists and reads a literal.

### game/bfh_player.gd (was line 214)

[b]No bunny hopping, and that is a design decision rather than an omission.[/b] Every other 3D game in this family turns auto-hop on because their genres are about carrying speed. This one is about a top speed a bus beats comfortably: the entire tension is that you cannot outrun the thing chasing you, so you have to put something between you and it. A runner who could chain hops to 15 m/s would simply drive around the bowl faster than the bus and the game would be over.

### game/bfh_player.gd (was line 278)

[b]`ground_id` is the whole mechanism, and it is deliberately not simulation state.[/b] `DotFpsState` documents it as a local physics handle whose value differs between machines — which is exactly right for this: riding is resolved per frame from a handle each machine has, rather than becoming another predicted field two machines would have to agree about. They could not agree about it; rigid bodies do not simulate the same way twice, which is why props are not predicted at all.

### game/bfh_player.gd (was line 292)

Written back into the state as well as onto the node. The controller starts the next tick from `state.position`, so a displacement applied only to the node is undone by the very next move — the player would ride the crate for exactly one frame each tick and stand still overall, which looks like the crate sliding out from under them rather than like anything being wrong.

### game/bfh_player.gd (was line 305)

Where this player's eyes are, in the world.

[b]From the simulated state and not from the node.[/b] The node is where the last frame drew them, which on an interpolating client is between two ticks; the state is where the tick that is being resolved put them. A swing aimed from the node would be aimed from a position no tick ever had.

### game/bfh_player.gd (was line 315)

Which way they are looking, as a unit vector.

Built from yaw and pitch rather than read off a camera, for the reason [method BfhHammer.swing] documents from the other end: a server has no camera, a bot has no camera, and a headless test has no camera, and all three have to be able to aim.

### game/bfh_player.gd (was line 327)

Gets in or out of a bus.

Both halves matter and the second is the one that is easy to leave out: a driver put back on their feet still carrying the bus's velocity is launched across the bowl on their first step.

### game/bfh_player.gd (was line 352)

Draws [member beacon], and says when it pings. Client side, once a frame, from `BfhClient`; a server never builds a marker.

[b]Only while alive.[/b] The flag outlives a death — dot-moderation re-applies it at the next round, which is this game's respawn — but a runner who is out is out until then, and a column over where they fell points everybody at an empty patch of sand.

[param own_view] is whether this is the player the camera belongs to; see [DotFxBeacon].

### game/bfh_player.gd (was line 400)

Draws this player's body for one frame. Client side, once a frame, from `BfhClient.present_frame`. Returns whether it is shown.

[b]Shown for everybody except three people[/b], and each is a rule of this game rather than a performance saving:

- [b]the one the camera belongs to[/b] ([param own_view]), whose view is first person —   a body drawn round a camera is the inside of somebody's head; - [b]a driver[/b], who is drawn AS their bus (not sat in it: the cab is solid, its windows   painted on, so a seated person inside is never seen and one tall enough to be seen sits   through the roof). Nothing moves a rider (see [member ridden]),   so a body left standing would be a person frozen on the spot where they got in for the   rest of the round, while the thing they are actually steering chases people. That is   the same reason [method drawn_position] answers with the bus; - [b]somebody who is out.[/b] A runner who was run over is out until the next round and a   body standing there would be a runner nobody can hit, which reads as a bug in the bus.

[param driver_side] dresses them: a driver on foot wears the uniform.

### game/bfh_progress.gd (was line 8)

What a player's round was worth: dot-stats counts it, dot-achievements decides what the counting earns.

[codeblock] var progress := BfhProgress.new() world.add_child(progress) progress.attach(world)       # listens to the world; nothing calls in progress.session_values(&"u7").get_value(BfhStats.CRATES_BROKEN) [/codeblock]

[b]A child of the authoritative world, and only of that.[/b] The server decides every number here — a client counting its own crates is a client that awards itself achievements — and an offline client IS an authoritative world, so the same node counts a game played alone. A connected client's world never builds one.

[b]It listens and nothing calls it.[/b] Every reading is a world signal: `run_over`, `swung`, `bus_struck`, dot-props' `broken`, the round's own two. A counter fed from call sites inside the simulation is a counter that misses the one call site somebody added later.

[b]The link between the two trackers is [DotAchievementStatsLink], not a `connect`.[/b] dot-stats' `recorded` carries a SESSION total and an achievement is about a lifetime; wiring one straight into the other adds the running total to itself on every reading. The link differences them, and that is its whole job.

[b]A signed-in player is filed under their scoped profile key[/b] (2026-10-03), which [member durable_key_fn] supplies from dot-platform and which can never carry a site account id. Everybody else — a guest, or anybody on a server with no platform — is still `bfh-u<session>`, and THAT is why this stays in memory and unreported: a session id is handed out again by the next boot, so a file store would give one guest's lifetime to whoever next got their number, and a report would file it under a name that means nobody. Turning either on is one line each the day guests are not counted at all.

[b]A key is fixed the first time it is asked for, for the rest of the session.[/b] Counting begins as a player is added, which is after admission whenever the profile store is quicker than the join; one seated first keeps the session key until they reconnect, because moving half a session's numbers mid-flight would file the second half against a total the first half never reached.

### game/bfh_progress.gd (was line 152)

The key a player's numbers are kept under, or empty for somebody who is not counted.

[b]A bot is not counted.[/b] Bots are what keep the buses full on an empty server, so on a dedicated server they do most of the flattening; a bot earning "Rush Hour" is a board of who the server was, and a runner flattened by a bot credits nobody.

### game/bfh_progress.gd (was line 214)

Not awaited: a join does not wait on a store. Readings that arrive during a slow load are still counted — dot-stats records them regardless, and the link neither files them nor moves its baseline while the tracker has no such player, so the first delta after the load carries everything that happened during it.

### game/bfh_progress.gd (was line 283)

The round is over. Every runner still standing survived it.

[b]Before the sides swap, and the world's order guarantees it:[/b] `round_over` is emitted before `_swap_sides` runs, so "a runner" here is somebody who spent this round running rather than somebody about to spend the next one driving.

### game/bfh_reach.gd (was line 3)

What a runner can get onto, as arithmetic over the movement they actually have.

[b]Asked of the controller's own tunables, not of a copy.[/b] The two games that answered this question first carry the three movement numbers as constants in their map classes, because a map there is content that must load with no player in the tree, and a check that the copies agree. The bowl here is built by the world that owns the configuration, so every function below takes the [DotFpsTunables] that [code]BfhPlayer.tunables_for(config)[/code] builds for a real runner. There is nothing to drift.

[b]`jump_height` is the APEX of a standing jump, not the height of something you can climb onto.[/b] Measured at this game's numbers and 60 ticks a second, a runner's feet rise 1.094 m of a nominal 1.15; landing ON something at exactly the apex needs the tick to fall right. So a climb is held to [constant CLIMB_MARGIN] of the apex, which is the same margin the family's other two answers use.

[b]The arithmetic is the controller's.[/b] [method climb_limit] and [method jump_reach] delegate to [DotFpsTunables]; this file keeps the names, the declared climbs and the refusals, which are this game's.

[codeblock] var t := BfhPlayer.tunables_for(config) BfhReach.climb_limit(t)       # 1.035 m: the highest top face a runner jumps onto BfhReach.jump_reach(t, 1.0)   # clear air crossed while landing a metre higher [/codeblock]

### game/bfh_reach.gd (was line 48)

One way up the bowl expects a runner to take, measured off the geometry.

[b]Built from two boxes, never from two numbers.[/b] A climb written as a rise and a gap is one more description of geometry that is already described by the colliders, and it goes stale the first time somebody moves a crate. What is declared is only WHICH two surfaces are a route — the one thing the geometry does not say.

### game/bfh_reach.gd (was line 110)

The clear air a runner at full ground speed crosses in one jump, landing [param rise] metres higher than they left. [method DotFpsTunables.jump_reach] at `max_speed`.

[b]The landing height is the point.[/b] The airtime people write down is the time to fall back to where you jumped FROM, and it is the wrong number for anything that climbs: one sized a jump course in this family 30% long and nobody could finish it. Returns 0 for a rise no jump reaches.

### game/bfh_route.gd (was line 3)

A route for a bot bus through a town: the streets between the buildings, found on a grid laid over the one obstacle description and pulled straight.

[b]Why the nudge is not enough here.[/b] `BfhArena.steer_around` moves the aim beside the nearest obstacle in the bus's corridor, and it keeps `radius + PILLAR_CLEARANCE` off each axis. A district's streets are laid out at `BfhDistricts.STREET`, 7.6 m of clear floor, which is 0.4 m more than two clearances: a line down the middle of one is clear by centimetres, a bus a metre off it has a building in its corridor, and the nudge sends it to the point beside that building, which is the next building's ring. Head-on at a roundabout's island it hands a bus 7 m away a point 8 m to one side, which a nine-metre bus cannot turn for, and it stands on the island with the throttle down until the stuck rule sends it home. A grid of towers is a maze, and the doc's rule is that a maze is a route, not a nudge ([docs/bots.md](bots.md)).

[b]Still one obstacle description.[/b] The grid is built from the arena's own obstacle circles, the wall and the ramp's slab; a building a district adds is in it because it is in `_obstacles`, with nothing declared twice.

[b]Cells are solid when a bus's centre may not be there[/b]: within an obstacle's radius plus the route clearance, outside the wall by the same, or on the ramp's slab or the deck widened by it. The clearance is `BfhConfig.bot_route_clearance` (3.4 m: a bus's half width, and the swing of its nose and tail through the turns), a little under the nudge's 3.6 because a street is only 0.4 m wider than twice that. A bus start is usually inside the slab's margin, so the route starts from the nearest open cell.

No `class_name`: this game is delivered as a pack (see docs/delivery.md).

### game/bfh_scoreboard.gd (was line 8)

The score, and who is on which side: held on Tab, and up on its own between rounds.

[b]Two sides, not two teams of the same thing.[/b] A symmetric game's scoreboard is one ranked list with a team colour per row; here two people drive and everybody else runs, and "who is still up" is a question about the runners only. So the board is two blocks side by side, each under its side's tally, and the per-player column is the one thing a player looks for: in a bus or on foot, up or out.

[b]What dot-match scores in this game is rounds, per side.[/b] Its per-player records — kills, deaths, score — are never reported to (a runner cannot kill and a driver cannot die, so they would be one number and a column of zeros; see "What a player's numbers are" in docs/services.md). The tallies are [method BfhGame.rounds_won], which is dot-match's `rounds_won` on the authority and what the last CLOCK said on a client.

[b]Drawn by dot-menu's `DotMenuScoreboard` since 2026-10-09[/b]; this file is what is this game's: the sides, the statuses, the tallies, the line about the round, and being up on its own after one. It drew its own two `DotTableView`s before, and had to give each an explicit size because a table in a container is drawn zero pixels tall; the menu's board is containers all the way down. Online the rows are the server's roster — names, pings and time connected, which no client knew for anybody else — with the side and the status joined in by id.

### game/bfh_scoreboard.gd (was line 201)

One side's rows. Static so a check reads the same rows the board draws.

Drivers by name. Runners who are up first, then by name: the living are the part of the list a runner reads, and the table is capped at [constant RUNNER_ROWS].

### game/bfh_server.gd (was line 6)

What a [DotServer] loads as its game scene. Never a client.

[b]Small on purpose.[/b] Everything a dedicated server does is in `bfh_module.gd`; this exists because dot-server loads a SCENE and the game needs one, and because the world has to be in the tree — registered under [constant BfhGame.SERVICE] — before the module looks for it. dot-server loads the scene and then the module, in that order, for exactly this reason.

[b]It lives in `game/`, not beside its own scene in `scenes/`.[/b] That is a deployment constraint rather than a preference: a game is vendored by copying its `game/` wholesale and its `scenes/*.tscn` — only the `.tscn` — so a script under `scenes/` is a script that never reaches the build. The scene then fails to load with "referenced non-existent resource", the module refuses to load because no game registered itself, and the server reports that the game loaded but its module did not. Every other game in this family keeps its server scene's script in `game/`, having learned it the same way.

### game/bfh_server.gd (was line 31)

The family's `defaults < JSON < environment < argv` chain, on the server too. It is how an operator sets `BFH_ROUND_SECONDS` or `--bfh-arena-radius` without editing anything, and the cvars the module adds are the live half of the same numbers. Plus the cfg/ yml layers; strict (a typo or bad value stops the boot) on a dedicated server.

### game/bfh_server.gd (was line 46)

[b]The engine's rate, which the server has already set from `sv_tickrate`.[/b] Read rather than chosen: this scene is loaded after the server has booted and executed its config, so the number is already decided — and a game that picked its own would be a simulation running at one rate inside a process ticking at another.

### game/bfh_server.gd (was line 58)

[b]Not started here.[/b] `start()` lays the bowl out and puts the buses on it, and nothing is listening yet: the module builds the bridge that answers `props.spawned`, so a bowl laid out now is thirty-four crates no client is ever told about. The module starts it, on the last line of its own load.

### game/bfh_services.gd (was line 7)

Chat, voice and moderation — and the moderator's live tools — wired to this game's two sides.

[b]Sixty lines, because [DotGameServices] holds the other five hundred.[/b] The five games written before this one each carry their own copy — 557 to 718 lines, differing in the channels, the rules and a voice range — and this is the first game to take the base instead. What is left here is what is genuinely this game's: who can hear whom, and where a player is standing.

[b]The sides are the whole design, so the sides are the channels.[/b] Two drivers against everybody else is a game about two conversations that must not overhear each other: the drivers arranging who takes which half of the bowl, and the runners saying which way one is coming. `team` is therefore the channel that matters here — in a deathmatch it is a convenience and here it is the game — and it is what VOICE defaults to, which no other game in this family does.

[b]There is no proximity channel, and that is a decision about the map.[/b] The bowl is 46 m across and a proximity range worth having would be most of it; a channel that reaches nearly everybody is a channel that lies about who can hear you. game-playground has one because a sandbox is a place with corners.

### game/bfh_services.gd (was line 44)

What a line may be.

[b]Short and slow, because a runner types while being chased.[/b] 140 characters and 20 a minute is a game whose chat is called out rather than written out: "north ramp", "he's turning". A sandbox's 200 at 30 is for people standing still, and this game has nobody standing still in it.

### game/bfh_services.gd (was line 54)

The same rules, as a static a CLIENT can ask for without building a services layer.

[b]Static because the other end needs them and must not instantiate this.[/b] `BfhServices` is a [Node] with a moderation store and a router under it; a client that called `new()` on one to read two numbers off it would build all of that, leak it, and — inside a delivered pack — fail to compile, because a script whose base class comes from the HOST cannot have its return type inferred by a script in the mount. Both were measured: seven leaked objects in a suite, and a client scene that would not load at all on a real server.

### game/bfh_services.gd (was line 130)

The voice format, which both ends must agree on exactly.

Static, because the CLIENT builds one too and a sample rate that differs between two peers is a stream of packets the router refuses for being the wrong length, counted and said to nobody. [method DotVoiceConfig.format_fingerprint] exists for that reason.

### game/bfh_services.gd (was line 140)

[b]Push to talk, in the one game in this family where it is not a preference.[/b] A runner is being chased by a bus and is breathing into a microphone; open-mic voice on a side of six people is six sets of breathing over the one thing anybody needs to hear, which is somebody saying which way it is coming.

### game/bfh_services.gd (was line 158)

TEAM, and this is the only game here that says so.

Everywhere else voice is the whole server, because everywhere else the sides are teams in a game rather than the game itself. Two drivers coordinating which half of the bowl each takes is a conversation the runners must not hear, and the runners calling a bus's line is one the drivers must not.

### game/bfh_services.gd (was line 168)

Which side somebody is on, for the team channel and for team voice.

[b]Read off the game rather than off dot-team, because the sides swap.[/b] `BfhGame` owns `sides` and rewrites the whole table every few rounds; anything caching a team id would put a player in the conversation they were in two rounds ago.

### game/bfh_services.gd (was line 201)

What the admin set means here, one callable per ability. See `DotGameServices`.

[b]What is refused is refused for a reason about THIS game, and says so.[/b] Respawn is the one worth reading: a runner who is out stays out until the next round, and an admin who put one back mid-round would be deciding who won. Give and strip are refused because there is one thing anybody holds here and it is not a weapon. Anything that moves a body is refused for a driver while they drive, because the bus is what is moving and the body is a passenger in it.

### game/bfh_services.gd (was line 247)

[b]The screen and nothing else, for either side.[/b] A blinded runner still moves and can still be run over; a blinded driver still drives, which is the point. An admin who wants a runner stopped as well has freeze, and a verb that did both would be a verb nobody could use for only the first.

### game/bfh_services.gd (was line 283)

Toggles that outlive a new body here, beyond dot-moderation's own god and buddha.

[b]Blind and beacon are about the person, not the body.[/b] Noclip and freeze end with the round because arriving in a new round frozen is the round broken; a player an admin blinded, or wanted the bowl to watch, is still that player after a round — and a round ending is exactly what a player being punished would otherwise wait out.

### game/bfh_services.gd (was line 397)

The team seam dot-chat and dot-voice both ask for, which the base cannot wire.

[DotGameServices] knows nothing about teams — a lobby has none — so the two `team_fn` hooks are set here, after the base has built each router.

### game/bfh_services.gd (was line 413)

Read, appended and written back. Measured on 4.7.2, the append alone already reaches the tools' own [PackedStringArray] — a packed array fetched through `get` shares its buffer — but this family has also shipped the opposite case (an append to a packed array inside a Dictionary landed on a copy), and the `set` is what stops this line depending on which of the two the engine does. `dedicated` fails without the append.

### game/bfh_settings.gd (was line 5)

A player's own settings and the menu that changes them: how fast the view turns, how wide it is, how loud things are, the window, and the look of the menu itself.

[codeblock] var settings := BfhSettings.new() add_child(settings) settings.setup()                    # loads, and pushes every value at what reads it settings.bind_look(sampler.tunables) settings.bind_camera(camera) settings.bind_audio(audio.manager) settings.open()                     # Escape does this in the client [/codeblock]

[b]dot-menu's `DotMenuSettings` with this game's schema[/b] (2026-10-09). This was the original of a 250-line file — a manager, a `match` over four keys and a bare settings screen — that five other games copied. What is left here is what is this game's: where the document lives, and the stock keys it has nothing to apply to.

[b]The scopes are the family's, not this game's.[/b] `sensitivity` is ACCOUNT under the shared `tmc_account` namespace — a person's hand, the same number in every game here. `field_of_view` is SERVER_CLAMPED: a wide view is an advantage a server may cap, and dot-settings gives a server no way to READ it. The volumes are this machine's.

### game/bfh_sounds.gd (was line 5)

What this game makes a noise about, as a document, and which stand-in voice says it.

[b]Until 2026-09-25 this game made one sound: an administrator's beacon.[/b] A bus doing 22 m/s at somebody made no noise at all, which in the one game in this family whose whole threat is a vehicle nobody can outrun is the one sound that matters most — a runner behind a 4.4 m tank judges which side the bus is coming round by EAR, because that is the only sense the tank does not block. So the engine and the horn are the first two entries, and both are positional.

[b]The ids are the contract, twice.[/b] [method catalogue] says what each one is worth — positional or flat, how far away it stops mattering, how many may overlap and what loses to what — and [method sound_recipes] says which of dot-audio's synthesised voices stands in for it until a real file is dropped at the path. `headless_run` asserts the two directions that fail silently: an id with no recipe is a sound that stays silent for ever, and a recipe naming an id the catalogue does not have is a decision that reaches nothing.

[b]The world's noises are ALSO a wire format.[/b] [constant WORLD] is the list a server sends by index (`BfhEvents.Kind.SOUND`), so the order is part of the protocol: append, never reorder.

### game/bfh_sounds.gd (was line 101)

Where the sound files would be, under this game's own root.

[b]Through the root, because a delivered pack is not at `res://`.[/b] A path written as `res://audio/…` inside a mounted pack resolves against the HOST project, where it names nothing — or, worse, another game's file of the same name, which `DotAudioSinkGodot` would load and play in preference to the stand-in. [param root] is for a check: built in, [method BfhPaths.root] is `res://` and every path is trivially under it, so the suite asks with a mount prefix instead. See [method BfhPaths.rebase_onto] for why.

### game/bfh_sounds.gd (was line 122)

The engine is the most important sound in the game and the most frequent, so it is capped harder than anything else: two buses, and a pulse each that overlaps its neighbour at speed. Far-reaching, because a bus you can hear coming from across the bowl is the whole point — and positional, because WHICH side of a tank it is on is the only question a runner is asking.

### game/bfh_sounds.gd (was line 234)

Which synthesised voice stands in for each id until a real file exists at its path.

[b]A table rather than a guess inside dot-audio.[/b] Which noise belongs to which id is this game's decision, the same way the distances are. Several ids share a voice and are told apart by the pitch their catalogue entry gives them — thirteen voices and fifteen sounds — which is a placeholder's honest limit rather than a design.

### game/bfh_spectate.gd (was line 5)

Where a runner who has been run down looks until the next round.

[b]Until 2026-09-25 a runner who was out looked at the patch of sand they were run over on, for up to three minutes.[/b] Out means out here — there is no respawn until the next round, by design — so the part of the game a runner spends dead is not two seconds before a respawn, it is most of a round on a bad one. A first-person game whose dead players stare at the floor for that long is a game people alt-tab out of.

[codeblock] spectate.setup(world, authoritative, tick_rate) spectate.on_death(&"u7", where, &"u900000", tick)   # the world does this spectate.request(&"u7", BfhSpectate.ASK_NEXT)       # the player's click camera.global_transform = spectate.camera_for(&"u7") [/codeblock]

[b]The server decides and the client draws, and they are two instances of this.[/b] The authority's [DotSpectatorManager] runs the chain — a death camera on the bus that did it, a freeze on its cab, then somebody to follow — and answers every click. A connected client's copy is a MIRROR: told its own view as per-player state (`BfhPlayerNet.net_watch`, owner-only), it computes the camera from the positions it is already drawing, and it decides nothing. An offline client is an authority, so it is the same code as a server.

[b]The policy, and why it is the loosest one in the family.[/b] - [b]Anybody may be watched, a bus included[/b] (`force_camera` 0). The obvious worry —   a dead runner calling out where the bus is — is not one this game can defend against   with a camera: every player and every bus is ALWAYS relevant here (`BfhNetBridge`   replicates everything to everybody, because the bowl is a disc with nothing tall in   it), so any client already has every position the camera could show it. A policy that   forbade the bus would protect nothing from a modified client and deny an honest one the   most watchable thing on the server. And "own side only" would mean a runner may watch   runners — the half of the round that is not being chased by anything. - [b]No delay[/b], for the same reason: a delay that only a client enforces, over data   the client already has, is theatre. (A mirror records its own history since   2026-09-25, so it would draw — but only what this client already has.) - [b]Roaming is on, as everywhere in the family[/b] (decided 2026-10-21; `mp_freeroam 0`   or `mp_forcecamera` 1 or 2 switches it off). The worry that kept it off, a map of the   bowl above the tanks, is the same one as the positions above: this server replicates   everything to everybody, so a modified client has the map whatever the camera shows,   and an honest runner who is out is owed something better than three minutes of one bus.   The camera is the client's ([code]DotSpectatorFreeCam[/code]); the server holds only the   mode. - [b]The living do not watch.[/b] A runner who is up is playing; a driver cannot be out.

[b]A bus's "eyes" are its cab.[/b] A driver's own position is where they sat down — nothing moves a rider (see [member BfhPlayer.ridden]) — so a camera on a driver's body would sit on the sand watching an empty patch while the bus they are steering chases somebody else. [method pose_of] answers with the bus.

### game/bfh_spectate.gd (was line 63)

Where a driver's view is, in their bus's own frame: over the cab roof, behind the container its forks carry out front.

[b]Higher than a driver's head, on purpose, and the first render is why.[/b] At seat height (2.9 m, just forward of the seat) the Kenney truck's container filled the bottom third of the frame and the road the bus was about to take was behind it. Up here the container is a strip along the bottom edge that says "you are the bus", and the runners it is chasing are in the middle of the picture.

### game/bfh_spectate.gd (was line 166)

Where somebody's eyes are: a runner's, or a driver's bus's cab.

Read from what this machine is drawing — the controller's state on a runner, which a client's interpolation writes every frame, and the bus's body, which it moves — so a mirror's camera is exactly as smooth as the picture it is looking at.

### game/bfh_spectate.gd (was line 230)

A click, on the authority. [param ask] is one of the ASK_* constants.

[b]Every answer is the manager's.[/b] A living runner asking to watch is refused by the same rule that decides everything else, rather than by this function having an opinion.

### game/bfh_spectate.gd (was line 303)

A mirror is told its own view. [param target] is who [method target_of] would answer.

[b]The place they fell is taken from where THIS machine last drew them[/b], on the transition into watching, because it is not in the state that is replicated (`net_watch` is a mode and a target). dot-spectate's own wire carries it since 2026-09-25, but this game does not send that wire. A mirror left at the default would draw every death camera from the world origin.

### game/bfh_stats.gd (was line 3)

Every per-player number this game counts, declared once.

[b]The ids are the contract three ways.[/b] The same strings name a stat in the [DotStatsSchema] below, a requirement in `BfhAwards`' achievement rules, and what `BfhProgress` records. Three places that never import each other agree because they all read these constants, which is the only reason a rename cannot leave two of them counting different things under one name.

[b]Five numbers, and each is one side's half of the game.[/b] A driver's is people flattened. A runner's are rounds survived and seconds survived, which are the clock the runners win on, and the two things they do to the bowl: crates broken, and crates put where a bus then drove into them. What is deliberately NOT here is a kill count and a death count. A runner cannot kill anybody, and a driver cannot die: a symmetric game's two most-read numbers would be one number and a column of zeros.

### game/bfh_stats.gd (was line 30)

Crates a runner's hammer moved that a bus then drove into.

[b]Measured by what happened next, not by where the crate was pointed.[/b] "Shoved into a bus's path" judged at the moment of the swing is a guess about where a bus is going, and the autopilot changes its mind every tick; a crate a bus actually ran into inside `BfhProgress.SHOVE_CREDIT_SEC` of the shove is a crate that was in its path.

### game/bfh_stats.gd (was line 51)

The schema a [DotStatsTracker] is given.

[b]All five are counters.[/b] A delta is "add 3", never "now has 40", and every one of these is a thing that happened some number of times. `publish` is on for all five because every one is a number a player page would show — but nothing here reports anywhere yet (see `BfhProgress`), so the flag is the answer for the day it does.

### game/bfh_textures.gd (was line 3)

A generated grid, because a flat colour has no speed in it.

[b]This game is judged almost entirely on closing speed, and a flat surface carries none.[/b] What a runner decides by is how fast a bus is getting bigger and how fast the ground is going past, and both of those are read off a repeating pattern of a known size. The first render of this game had `uv1_triplanar` set on every material and no texture under it — so the flag did nothing, the bowl was one unbroken tone, and the comment beside it claiming a readable scale was describing something that was not there. That is this family's own "a value produced correctly and consumed by nothing", in the shape where the value is a rendering flag.

[b]Lines and a checker, not lines alone.[/b] game-g2gfast measured this and wrote it down: a pure grid seen at a glancing angle — which is every angle that matters when you are running away from something — collapses to nothing between its lines, because a mipmap keeps a tile's average and a tile that is 97% one colour *is* that colour a few metres out. Alternating squares survive the mipmap. The lines are what you read standing still; the checker is what you read at speed.

### game/bfh_vote.gd (was line 3)

The players choose the next bowl.

[DotVoteDirector] over a [DotVoteListSource] of this server's bowls, and the only thing this file decides is WHEN: a ballot opens [member open_after_sec] into every bowl and is applied when the round ends, because the bowl is rebuilt only between rounds — the next round starts in whatever was chosen. The bowls are [code]BfhBowls[/code]: this game has no map files, its map is a radius, and a bowl is a name for one. Everything about the ballot itself (how many options, the counting method, the tie-break, rock the vote, nominations, cooldowns) is dot-vote's settings and none of it is restated here; [method _rules] only says which of them a one-bowl-per-round game wants by default.

[b]`trigger` is MANUAL, not ROUND_END, and that is the point of this file.[/b] dot-vote's ROUND_END opens a ballot at a round's end and applies it at the NEXT round's end, which is right for a game that plays several rounds on a map and one round late here. Opening it during the round and applying it at the end (`apply: END_OF_ROUND`) puts the choice on the very next round.

[b]Server side only.[/b] A client draws the ballot from the notice [member ballot_fn] sends (the client shell's [DotBallotPanel]), and never holds a director: a client that applied a result would be deciding what it plays.

### game/bfh_vote.gd (was line 43)

The file a server owner configures the vote in, keyed exactly as [DotVoteRules]. Layered: [code]_rules() < game.yml metadata bowl_vote: < this file < DOT_VOTE_* < --vote-*[/code]. Empty skips the file. [code]{"enabled": false}[/code] turns the vote off and the rotation the server's own bowl stays.

### game/bfh_vote.gd (was line 134)

[b]Set by name, and only where it exists.[/b] A delivered pack runs on the shell's dot-vote, and one older than API 3 has no `round_in_progress_fn`: naming it would fail the pack's parse. There, a finish_round limit in warmup waits out finish_round_max_sec, which is what it did before. Read through this node's own field, so the order the host sets it in does not matter.

### game/bfh_vote.gd (was line 154)

[b]Rock the vote opens its own ballot under MANUAL from dot-vote API level 2.[/b] Before that the director handed every opening to its host, a rocked vote included: the clock expired with reason rtv, the director did nothing, and `!rtv` answered "Rocked. 1 of 1." and nothing happened. A pack runs on the client shell's dot-vote, which may be older than the one this repository links, so below level 2 this handler stays as the fallback. From level 2 it is gone, because two openers is one too many: a second ballot is only prevented by start_vote refusing while one is open.

### game/bfh_vote.gd (was line 273)

The server woke from hibernation: the bowl ballot is owed again, from the top.

The director restarts itself ([member DotVoteRules.wake_restart]); this is the half that is this game's — the seconds into the bowl at which the ballot opens.

### game/bfh_vote.gd (was line 306)

The ballot's own timer waits with the director's clock while the server hibernates (DotGameModule hands the director the server's hibernation). Counted on, it ran past open_after_sec over an empty room, the ballot was refused for want of voters, and the first player in never got one on this bowl.

### game/net/bfh_bus_net.gd (was line 3)

What a bus replicates, through [DotVehicleNetSync].

[b]It extends the prop behaviour rather than sitting beside it.[/b] A bus is another body the server moves and the client draws, so the bridge keeps ONE table of replicated bodies and one `pull` loop over it; a second parallel table is a second thing that can disagree about which of them exists. What is overridden is the three halves that differ: what is declared, what is copied out of the authority, and what is drawn on the mirror.

[b]Nothing here is predicted, and that is dot-vehicle's decision rather than this game's shortcut.[/b] A raycast vehicle is a rigid body with a contact solver under it, so two machines diverge within a second or two; a predicted bus is a CORRECTED bus, and a correction on the thing a player is steering reads far worse than latency does. The driver's own throttle therefore goes round trip.

### game/net/bfh_bus_net.gd (was line 36)

Declared from the addon's own table.

[b]The type is resolved from a STRING, and that is why the table is written the way it is.[/b] [DotVehicleNetSync] never mentions a dot-net `class_name`, because a script naming a class the project does not have fails to parse and takes every script that references it down with it — so a game without dot-net can still use dot-vehicle. Resolving `DotNetVar.Type[spec.type]` is the game's half of that bargain and can only be done here.

### game/net/bfh_bus_net.gd (was line 76)

The wheels, which cannot be derived from anything else replicated: a client watching a bus come round a corner knows the body is turning and not which way the front wheels are pointed, and a bus that has just been put on the spot has them on opposite lock to the one that is coasting. Without this every mirrored bus drives with its wheels straight ahead and its tyres not turning, which is the single most noticeable thing wrong with a networked vehicle.

### game/net/bfh_event.gd (was line 18)

[b]Built with [code]new(kind, body)[/code], and this file does not preload itself.[/b] It used to, for a typed [code]static func of() -> BfhEvent[/code] factory, and that one line leaked the whole script graph at exit — 111 scripts, the grid textures in [code]bfh_textures.gd[/code]'s static cache and eight texture RIDs — whenever the file was first loaded from a module a [DotServer] loads at runtime, which is how every deployed server loads it. Measured on 4.7.2 with a two-line reproduction: a script that [code]extends DotNetMessage[/code] and preloads ITSELF is enough, whether the base is named or given by path; a self-preload over [code]RefCounted[/code], [DotResult] or [DotNetBehaviour] is not, nor is a two-script cycle through [DotNetMessage]. The registry decodes with a bare [code]new()[/code], which is why both arguments default. See docs/history.md, "The leak that was one line of a message".

### game/net/bfh_events.gd (was line 6)

The wire format for everything that is not a snapshot or an input.

Encoders and decoders in pairs, and nothing checks that they are inverses for you — `headless_net` round-trips every one of them, because this family has already shipped a serialisation whose two ends never met: dot-moderation wrote `"voice muted"` and read back a warning, and the one thing that addon existed for silently did nothing.

[b]Everything in the bowl is ANNOUNCED and then moved by snapshot, and it needs both.[/b] A snapshot carries a position and a rotation; it cannot carry what a thing IS. So a crate, a barrel, a block and a bus each arrive as an event naming the catalogue id and the net id the snapshot will move, and the client builds the same body from the same catalogue. A factory keyed on a script would be the alternative, and a script cannot be named: a `class_name` inside a mounted dot-cloud pack is not registered in the host, which is the whole reason this game's content is addressed by path in [BfhContent].

### game/net/bfh_events.gd (was line 48)

Something in the bowl made a noise: which one of `BfhSounds.WORLD`, and where.

[b]Appended, never inserted.[/b] A kind is its index on the wire, and the ones above are what every deployed client already decodes.

### game/net/bfh_events.gd (was line 70)

Every decoder returns an `ok` beside its fields, and every caller checks it.

[b]A reader past its end returns plausible zeros rather than failing.[/b] dot-net shipped with exhaustion that was not sticky, so a decoder that skipped this check got a believable value for the field AFTER the overrun — and a truncated packet decodes as a valid message about nothing.

### game/net/bfh_events.gd (was line 85)

Where a body may be, in metres, on the wire.

[b]Read from [BfhGame], not written here.[/b] A quantised position is decoded against this range, so two files holding two numbers do not lose precision — they put the crate somewhere else. game-arena had exactly this, 256 against 128, in two files that each looked right on its own.

### game/net/bfh_events.gd (was line 116)

What a client needs before it can build anything.

[b]The arena radius is in here, and a client that guessed it would build a different bowl.[/b] This game's map is not a file, it is `BfhArena.build(radius)` run on both ends — which is what makes it free to deliver and free to change — so the radius is the whole map as far as the wire is concerned. A client on 46 against a server on 30 has a wall seven metres past where the server says the wall is.

[b]And the two layout choices an operator can make (2026-10-07), appended:[/b] where the hook is which and how wide the courtyard's west lane is. A client on the default hook against a server on the tight one would walk through a pillar it cannot see and stop at one that is not there. The hook by name, the lane to the millimetre.

### game/net/bfh_events.gd (was line 227)

A join, or a change to who somebody is: their name, their side, their avatar.

[b]The avatar is the document, not the skin it picks[/b] — as JSON, capped at [constant AVATAR_BYTES], and empty for the stock person — so a slot this game adds later needs no new wire. [b]Appended, never inserted[/b]: a field before it would move the side for every reader of the old layout.

### game/net/bfh_events.gd (was line 302)

Something the world has put out: a crate, a barrel, a block or a bus.

[param vehicle] says which catalogue [param kind_id] is in. It is a bit rather than a second message kind because everything else about the two is identical — a net id, a scene, a place to put it — and two near-identical messages is two decoders to keep in step.

### game/net/bfh_events.gd (was line 346)

Who is driving what.

[b]The client is told the answer rather than running the ride.[/b] It has no vehicle spawner, no seats and no exit sweep — the server owns all three — and what it does with this is stop predicting a player who is no longer walking. Without it a predicted controller fights the snapshots that are carrying the bus, every tick, at a metre a time.

### game/net/bfh_events.gd (was line 370)

The clock and the two numbers a client cannot count for itself.

[b]`cover` is why this message exists.[/b] A client does not run the prop spawner — its crates are mirrored bodies — so `crates_left()` on a client counts nothing, and that number is the most important one on this game's HUD: it is what tells a runner whether standing still is still an option. Health and the clock a client can see for itself; this it has to be told.

### game/net/bfh_events.gd (was line 452)

Where a barrel went off and how far it reached.

[b]An event and not a replicated property, because a blast is an instant.[/b] A client that learned about it from a snapshot would learn about it once the barrel had already been removed, at whatever the interpolation delay is — which is a bang with nothing under it. Reliable, for the same reason: a missed one is a player wondering why they are suddenly in the air.

### game/net/bfh_events.gd (was line 488)

One routed line, in [DotChatMessage]'s own wire shape.

[b]Field by field rather than `var_to_bytes`, like every other message here.[/b] A dictionary serialised whole is a dictionary whose contents are whatever the sender put in it — including keys a client will happily read — and the widths below are the validation. `x.p` is the one meta field this game carries: the speaker's session id, so a client can colour a line by whose it is.

### game/net/bfh_events.gd (was line 545)

What a client sends when somebody presses Enter: a channel and a line, and nothing else.

[b]No speaker, no time, no colour.[/b] Everything about what a line MEANS is decided on the server — who said it, whether they are gagged, whether they are talking too fast, which of the four channels they may use and who can hear it. A client that sent any of that would be a client that could claim it.

### game/net/bfh_events.gd (was line 569)

A noise the server decided, by its index in `BfhSounds.WORLD`, and where it was.

[b]An index and not the id's string.[/b] A hammer swing is the commonest thing in this game after a snapshot — two a second per runner — and five bits is what it costs to say which sound. The list is append-only for that reason; see `BfhSounds`.

[b]Reliable, like every event here, and that is a trade rather than an oversight.[/b] A lost swing is a lost sound, which is harmless, but a lost `runner_down` is a runner who was flattened in silence, and splitting the kinds across two deliveries would be a second message type to keep in step for a handful of bytes a second.

### game/net/bfh_events.gd (was line 592)

What a spectator asked for: `BfhSpectate.ASK_NEXT`, `ASK_PREVIOUS`, `ASK_VIEW` or `ASK_ROAM`.

[b]Only the ask.[/b] Not who to watch: the server picks the next target from its own list, under its own rules, so a client cannot name somebody the policy would refuse.

### game/net/bfh_net_bridge.gd (was line 18)

Joins a [BfhGame] to a [DotNetManager]. The netcode seam, and the only file in this project that names both.

[codeblock] # server bridge.attach(game, net)          # dot-game's DotGameNetcode does this bridge.open_link(server)          # and this bridge.add_player(peer_id, userid, "Ada") bridge.server_tick(tick)          # instead of the game's own loop

# client bridge.attach(game, net) bridge.open_link(client_link) bridge.ask_ready() bridge.client_tick(tick, command) [/codeblock]

[b]Only a runner's own movement is predicted.[/b] Crates, barrels, blocks and buses are server-authoritative, because Godot's rigid-body solver is not reproducible across machines. A driver's keys go round trip: a bus takes a second to respond to anything, so the trip lands inside the time it would have ignored the input, which would be intolerable on a runner.

[b]The ordering is the other half of the file.[/b] dot-net drives simulation per entity; this game's tick is a whole-world property — every player moves, then the buses are driven, then what a bus hit is decided. [method ensure_game_ticked] reconciles the two: the first behaviour through on a tick runs the whole world and the rest find it done.

### game/net/bfh_net_bridge.gd (was line 51)

Commands in every input packet: this tick's and the four before it, so a lost packet costs the server no tick unless the next four are lost too. Over WebSocket nothing is ever lost; over ENet (the desktop client, since servers went dual-stack) one command a packet was a tick the server ran on the previous command for every packet dropped. game-arena measured it first: 80% of ticks with the right command at 20% loss with one copy, 99-100% with three, and five closed the rest (2026-10-09).

### game/net/bfh_net_bridge.gd (was line 59)

How often the round clock and the cover count go out, in ticks.

[b]Twice a second, not per tick and not per snapshot.[/b] What it carries changes when a crate breaks or a second passes, and a client that was told sixty times a second would be paying for fifty-eight copies of the same three numbers. The clock itself is interpolated on the client from its own frame time between messages — see [method _apply_clock].

### game/net/bfh_net_bridge.gd (was line 88)

Somebody pressed Enter. Server side, and the only thing this bridge does with chat.

[b]The bridge carries chat and decides nothing about it.[/b] Who may say what, on which channel, how often and who hears it are [DotChatRouter]'s, and the router is the services layer's.

### game/net/bfh_net_bridge.gd (was line 110)

Where the clock learns how long the link is, in milliseconds.

dot-net never touches a transport and cannot measure it; dot-server's heartbeat already does ([method DotClientLink.ping_ms]). A client that feeds nothing has a clock that assumes an instant connection and stamps every command for a tick the server has already simulated — and the symptom is every command being discarded as late. Two games in this family shipped without a sample and read a median of an empty set.

### game/net/bfh_net_bridge.gd (was line 133)

The next session id handed to somebody the world made itself.

[b]Well above anything dot-server will issue, and a bot needs one at all because of how a player id is written.[/b] Every id on the wire is `u<session>`, and a player called `bot` parses back to session ZERO — so two bots are one entry in [member _behaviours], and their JOIN carries a player id that is also dot-net's broadcast address. Bots are the whole deployment this game is for: a server with two empty buses is a server with no game in it.

### game/net/bfh_net_bridge.gd (was line 145)

net id -> the behaviour replicating that body, on BOTH ends.

[b]Keyed by net id rather than by instance id, and that is what makes the tick loop the same on both ends.[/b] A prop instance id and a vehicle instance id are two counters in two addons that both start at 1, so a table keyed on either holds two different things under the same key the moment a bus and a crate exist together.

### game/net/bfh_net_bridge.gd (was line 161)

Server: peers whose READY came before their seat ([method add_player]). A client sends READY when its link says PLAYING, which the link decides itself after sending `loaded` on another channel; over ENet with loss the READY can overtake `loaded`, and a READY dropped here left that client waiting for a world for ever. Admitted when seated.

### game/net/bfh_net_bridge.gd (was line 258)

Opens the link under [param parent], whose NAME is half the RPC routing.

A [DotServer] on one end and a [DotClientLink] on the other, both called `Server`, with this node under each: Godot routes an RPC by the receiver's node path, so a link opened anywhere else is addressed by a path the other end does not have and every message lands nowhere, with no error on either side.

### game/net/bfh_net_bridge.gd (was line 274)

How every dot-net message reaches a peer.

[b]Routed by DELIVERY, not by kind.[/b] Snapshots are unreliable and go on the snapshot call; everything else is reliable, and which reliable call it is depends on which end is sending — the server has events, the client has requests. Sending them all as events works on a server and silently drops every client request, which is a client that connects, draws, and can never ask for anything.

### game/net/bfh_net_bridge.gd (was line 338)

Somebody the world drives itself: a bot driver, or a test's stand-in for one.

[b]The same entity a peer gets, with a peer id of zero.[/b] A bot is replicated, scored and run over exactly like a person — what it does not have is a socket — and that is the whole of the difference. The session id is synthetic; see [constant FIRST_BOT_SESSION] for why it cannot simply be a name.

### game/net/bfh_net_bridge.gd (was line 380)

Released BEFORE the game is told: `game.remove_player` emits `player_removed`, which `_on_player_removed` answers by releasing the entity and broadcasting the LEAVE. Releasing first empties `_behaviours`, so that handler finds nothing and this stays the one place a leaving player is announced.

### game/net/bfh_net_bridge.gd (was line 397)

A player the game made itself — a bot, a test — gets an entity exactly like one a peer asked for. Its peer id is zero, and that is not the broadcast address by accident: [method _tell] refuses zero, because `send(msg, 0)` IS a broadcast and another game in this family once sent every player's private message to everybody through that hole.

### game/net/bfh_net_bridge.gd (was line 410)

[b]Every id on the wire is `u<session>`, and anything else parses back to zero.[/b] A world that added a player called `bot` would replicate it under session 0 — which is also dot-net's broadcast address — and a second one would silently replace the first in this table. Refused with a line rather than accepted quietly: the symptom otherwise is one bot driving and the other standing still for ever.

### game/net/bfh_net_bridge.gd (was line 491)

Every crate, barrel and block the world puts out becomes a replicated entity.

[b]Announced reliably AND replicated by snapshot, and it needs both.[/b] The snapshot moves it; the event says what it IS, because a client cannot build a barrel from a position. A spawner factory would have to name a script, and this game's content is named by PATH in [BfhContent] precisely so a dot-cloud pack can deliver it — a mounted pack's `class_name` globals are not registered in the host.

### game/net/bfh_net_bridge.gd (was line 655)

The CLOCK first, carrying the tally dot-match has just counted this round into, so a client's world has the new score by the time its `round_over` fires — which is when a scoreboard shows itself. Behind the ROUND it would show last round's score for up to half a second, on the one screen whose whole job is saying who won.

### game/net/bfh_net_bridge.gd (was line 676)

Every player's side, one message each.

[b]After the swap, and every player rather than only the ones that changed.[/b] A swap turns everybody round, so "the ones that changed" is everybody — and sending the whole roster's sides is also what makes a client that missed an earlier TEAM correct itself.

### game/net/bfh_net_bridge.gd (was line 735)

The other end of [method watch_state]: a client is told its own view. Client side.

[b]Only for the player this client is, by session id — not by `DotNetIdentity.is_owner`.[/b] Every other entity's pair is the zero it was declared with, and adopting that would build a spectator view per remote player that says nothing.

The session id is the better key: the server keys the view by it, and it is right from the moment HELLO lands, where `is_owner` is right only once the entity is claimed.

### game/net/bfh_net_bridge.gd (was line 770)

Belt and braces: `net.server_tick` drives the entities, and the first player behaviour through calls `ensure_game_ticked`. A server with nobody on it has no behaviours at all, and a world that only ticked when somebody was connected is a server whose round clock stops between players — which looks like the server having hung.

### game/net/bfh_net_bridge.gd (was line 816)

One player's hammer, from the buttons their command carried.

[b]A button and not a request, and the difference is what a swing is aimed with.[/b] Swinging is per-tick and continuous — you hold the button and it swings at its own interval — so it rides in [member DotFpsCommand.buttons] beside jump and crouch, and it is resolved against the position and view the same command produced. Sent as a reliable request it would arrive a round trip later, be resolved against a different position, and break the crate the player was no longer looking at.

[b]And the SERVER swings it, not the client that asked.[/b] A client's own crates are frozen mirrors; it could not break one if it tried. The hammer's cooldown is enforced here too, so a modified client holding the button down gets the same rate as everybody else.

### game/net/bfh_net_bridge.gd (was line 965)

Text for one player: a refusal, a rate limit, a command's reply.

[b]To the one person who asked, and that is the whole reason this is a method.[/b] "You are talking too fast" and "you are gagged" are the two commonest things a server says, and both are nobody else's business — a broadcast refusal is a punishment announced to everybody. Public because the module answers chat refusals with it; it used to reach in and call `_tell`, which is a private method being used as an interface.

### game/net/bfh_net_bridge.gd (was line 981)

A voice frame off [method BfhNetLink.send_voice], in whichever direction.

[b]Not a [BfhEvent].[/b] Voice is fifty packets a second and every event here is reliable, so a talk spurt would put a hundred retransmittable messages in front of a crate breaking. It also does not go through [DotNetManager]: the message registry seals a message set and hashes it, and adding a fifty-hertz opaque blob buys nothing — the packet has its own header, sequence and validation in [DotVoicePacket].

### game/net/bfh_net_bridge.gd (was line 1001)

[b]One path or the other, never both.[/b] [DotGameModule] assigns `voice_relay_fn` to the services layer's `relay_voice`; a game that ALSO connected `voice_requested` to the same router would relay every frame twice — which is a doubled talk spurt, a doubled rate limit, and a sequence number the jitter buffer sees go backwards. The signal is the seam for a game with no services layer, so it fires only when nothing else is listening.

### game/net/bfh_net_bridge.gd (was line 1077)

Everything in the bowl, to one peer, once its world exists.

[b]On READY and not on connect, and the difference is a whole join's worth of messages.[/b] dot-server's signon finishes and THEN the client builds its scene; a server that started talking at connect is one whose JOIN, PROP and CLOCK land on a node that does not exist yet and are lost, one "Node not found" per call. --- Both ends: the bowl's toys

### game/net/bfh_net_bridge.gd (was line 1175)

Client, on TOYS: a mirror for every id at once, under the holder, whether this end's toys for the bowl exist yet or not. [b]A client must know every entity a snapshot carries[/b]: dot-net stops reading a snapshot at the first one it does not know (a body cannot be skipped without its declarations), so a toy mirror missing while the client loads the map, or ever, on a client left on another map, was every player after it frozen. Paired with its toy by index as soon as both are here.

### game/net/bfh_net_bridge.gd (was line 1279)

Which catalogue entry a replicated body came from.

Read off the spawners rather than remembered beside the table: a second copy of "what this is" is a second thing that can disagree with the first, and this one is only asked for on a join.

### game/net/bfh_net_bridge.gd (was line 1308)

Tells everybody who somebody is now: a profile that arrived after they were seated, a wardrobe change, an operator's rename. Server only.

[b]Through JOIN, which a client already applies to a player it has.[/b] A second message for "this person changed" would be a second thing a joiner has to be told and a second order two of them can arrive in. An empty [param display_name] keeps the one they have.

### game/net/bfh_net_bridge.gd (was line 1331)

To every peer that has said it is ready, and to nobody else.

[b]An empty body is dropped rather than sent.[/b] It means an encoder was handed something that had already gone — a player whose entity was released before the LEAVE was written — and a zero-length event decodes on the far end as a valid message about nothing, which is the truncation bug this family has already paid for once.

### game/net/bfh_net_bridge.gd (was line 1345)

One peer, and never zero.

`net.send(msg, 0)` is a BROADCAST in dot-net, so a helper that passed a missing peer id straight through would send one player's private message to everybody. game-hungario shipped exactly that.

### game/net/bfh_net_bridge.gd (was line 1482)

A TEAM arrived: on a client, the world says its sides swapped, once per swap.

[b]A client world emits the same signals a server's does, from the events it is sent[/b] — `round_began`, `round_over`, `sides_swapped`, `player_died`, `barrel_exploded`, `noise` — so what draws and plays the game listens to ONE world in both halves and never learns which it is in. Without this an offline game made a noise at the end of a round and a connected one did not, and nothing could have said so: every check reads one half.

A swap arrives as one TEAM per player, because that is also what corrects a client that missed one, so the world's signal is emitted for the first of them and not the rest. TEAM is sent on a swap and on nothing else.

### game/net/bfh_net_bridge.gd (was line 1501)

The server's bowl, built here if it is not the one this client has: from the HELLO on joining, and from a BOWL when the players' vote changed it between rounds.

And the two layout choices, which are as much the map as the radius is: a client on its own default hook against a server on the tight one has a pillar where the server has floor.

### game/net/bfh_net_bridge.gd (was line 1526)

[b]The server's tick rate, before anything is derived from it.[/b] Another game in this family shipped with HELLO carrying this and nothing reading it: a browser client counted at the 60 its export declared against a server on 128, so the correction rate was 0.96 and every replicated time was out by 128/60. Produced correctly and consumed by nothing, and invisible to a one-process suite because one process has one engine rate and both ends agree whatever the wire says.

Before `sync_from_server`, because the clock converts its error and its lead through `tick_rate` and would otherwise do that arithmetic at the old rate.

### game/net/bfh_net_bridge.gd (was line 1540)

[b]The map, which in this game is one number.[/b] The bowl is not a file, it is `BfhArena.build(radius)` run on both ends — so a client that kept its own default against a server running a smaller bowl would have its wall, its ledge and its stacks all in the wrong place, and would walk through the visible wall into the server's real one.

### game/net/bfh_net_bridge.gd (was line 1555)

Puts the whole client — the world, every player's controller and the ENGINE — on the server's tick rate.

That last one is not cosmetic. Measured in another game in this family at 60 against 128: the simulation stayed correct, because the clock is asked how many ticks a frame is worth — it just ran them in bursts of two and three, and the camera advanced 74 mm on six frames out of seven and 112 mm on the seventh. A 47% change in apparent speed, eight times a second.

A server never calls this: its rate is `sv_tickrate`, and adopting a peer's would be a client telling the server how fast to run.

### game/net/bfh_net_bridge.gd (was line 1607)

[b]This client's own player is owned by this client, and nobody else's is.[/b] Until 2026-09-25 every mirror was built with owner 0, this client's own included, so `is_owner` was false for the local runner, `registry.predicted()` was empty, and `client_tick` simulated nobody: the runner moved only when a snapshot came back, a round trip behind the keys. Every check passed anyway, because a client adopting the server's answer also agrees with the server.

By session and not by a peer id on the wire: JOIN does not carry one, and what `is_owner` compares is the owner against THIS registry's local peer — so the local peer id is the only right value whatever the server calls the connection. HELLO (which sets `local_player_id`) is sent before every JOIN in `_admit`, on the same reliable channel; [method _apply_hello] still claims a player that got here first, because an order is a property of the server, not of this file.

### game/net/bfh_net_bridge.gd (was line 1638)

Who owns a mirrored player on this client: this client, if it is this client's own player, and the server's 0 otherwise.

[b]Never the local peer for anybody else[/b], or this client would predict a person whose keys it never had. And a client whose local peer is 0 claims nothing: 0 is the server's owner id, and on such a registry dot-net's `is_owner` (owner == local peer) is already true of every owner-0 mirror — which this function cannot undo, and which no client here runs into, because `BfhClient` takes its id from the multiplayer API and that never answers 0.

### game/net/bfh_net_bridge.gd (was line 1657)

The local player's mirror, claimed if it arrived before HELLO said whose it was.

Not the order `_admit` sends in, and that is why it is belt and braces rather than a path this game takes: a JOIN broadcast that reached this peer before its HELLO would otherwise leave the local runner unpredicted for the rest of the session, with every check still passing — which is the bug [method _apply_join] documents.

### game/net/bfh_net_bridge.gd (was line 1745)

Where a client finds the scene for something the server named.

[b]Both catalogues, because the client has both and neither is the wire format.[/b] The event carries a catalogue id; this build turns it into a path, and a build with a different catalogue turns the same id into its own path. That is the whole point of not sending a script name.

### game/net/bfh_net_bridge.gd (was line 1780)

A client's copy of "that player is driving".

[b]The client does not run the ride at all.[/b] It has no vehicle spawner, no seats and no exit sweep — the server owns every one of those — so what arrives is the answer rather than the question. What the client does with it is stop predicting somebody who is no longer walking.

### game/net/bfh_net_command.gd (was line 3)

One tick of a player's intent, on the wire: a [DotFpsCommand] and nothing else.

[b]The same command drives a runner and a bus, and that is this game's design rather than a saving.[/b] A driver's forward key is the throttle and their strafe keys are the wheel — nobody has to learn a second set of controls for the half of the game they play every third round — so there is one thing to send either way and the server decides which of the two it means. A client that sent "throttle" would be telling the server it was in a bus.

The hammer rides in [member DotFpsCommand.buttons] for the same reason a jump does: it is per-tick, it is held rather than pressed once, and it has to be ordered against the movement it was aimed with. Sending it as a request would put every swing a round trip behind the mouse and reorder it against the step the player took while swinging.

### game/net/bfh_net_link.gd (was line 3)

The four remote calls this game needs, on one node that exists on both ends.

A copy of the other games' links in shape — deliberately, per the family rule that a game copies what it needs rather than growing a shared dependency — because it encodes the one thing that cost this family a day: Godot refuses an RPC unless both ends declare the same set of `@rpc` methods, and routes it by the receiver's NODE PATH. Using the same script on both ends makes the checksum identical by construction; naming the node the same on both ends and parenting it to a node that is itself named the same ([DotServer] on one side and [DotClientLink] on the other, both called `Server`) is the whole of the routing.

[codeblock] Server            <- DotServer, or DotClientLink named to match   Buses           <- this, on both [/codeblock]

### game/net/bfh_net_link.gd (was line 29)

Voice, and only voice.

[constant DotTransport.Channel.EVENT] is what dot-server reserves for chat and events, and this game's chat rides `event` on the state channel with everything else — so this one is free. Voice gets it to itself for the reason the state channel exists at all: a burst of snapshots must not sit behind a talk spurt, and a talk spurt must not sit behind a snapshot.

### game/net/bfh_net_link.gd (was line 44)

Where calls go instead of onto the network.

Signature: `func(method: StringName, peer_id: int, payload: PackedByteArray)`, with `method` one of `snapshot`, `event`, `input` or `request`.

[b]A test seam, and the only way this netcode can be checked at all.[/b] A real socket does not reproduce the same latency, reordering and loss twice, so `headless_net` puts a server and a client in one process with a lossy loopback between them. Unset — which is every real deployment — every send goes out as an RPC.

### game/net/bfh_net_link.gd (was line 79)

Whether anything this end sends can actually go anywhere.

[b]Reported on its EDGES, not per call.[/b] A link that is not live drops everything silently — which is correct, because the alternative is an error per snapshot at sixty a second — and a link that goes quiet is indistinguishable from a game with nothing to say. So the transition is logged once each way, at DEBUG, and the counters in [method describe] are what answer "how much got through".

### game/net/bfh_net_link.gd (was line 104)

One routed chat line, to one peer.

[b]A chat line is an EVENT on this game's own wire, not dot-server's chat manager.[/b] [DotChatRouter] has the rules — the channels, the gag, the rate limit, who may hear whom — and a second path through the server's own chat would be a second set of rules to keep in step, with the one that skipped the filter being the one that leaked admin chat.

### game/net/bfh_net_link.gd (was line 156)

One encoded voice packet, in whichever direction this end is.

[b]One call for both transports.[/b] On ENet `unreliable` is a UDP datagram that is never retransmitted, which is what voice wants — a frame that arrives late is one the jitter buffer has already concealed. On a WebSocket every transfer mode is TCP underneath and it is delivered reliably whether or not that was asked for. That is a property of the transport rather than a gap here.

[param peer_id] is the recipient on a server and is ignored on a client. **Zero is not "everybody"** — the router names its listeners one at a time.

### game/net/bfh_net_link.gd (was line 236)

A voice frame, either way.

`any_peer`, so on the server the sender is a claim until the transport is asked. [method DotVoiceRouter.relay] is handed the id the TRANSPORT reported and stamps it over whatever the packet's own speaker field said — without that any client can put words in any other player's mouth.

### game/net/bfh_net_link.gd (was line 250)

Hands a payload to this end as though it had arrived over the wire.

What the other end's [member loopback] calls. It goes through the same counters and the same bridge entry points the RPCs do, so a test exercises the real path minus the socket.

### game/net/bfh_player_net.gd (was line 7)

What a networked player replicates: the movement state, their health, their side, and whether they are driving.

[b]The movement half is dot-player-controller's own table and is not written here.[/b] [DotFpsNetSync.state_specs] is what the controller says its state is, in the quantisation it says it wants; a game that listed the fields itself would be a second copy to drift, and the type names in that table are STRINGS precisely so the addon can describe a dot-net layout without naming dot-net.

[b]The two game fields are not derivable from the movement.[/b] Health decides whether a body is drawn at all, and riding decides whether the client predicts them; a client that worked either out for itself would be running a second copy of the rules.

[b]Which side somebody is on is deliberately NOT here.[/b] It changes twice an hour, on a swap, and a per-tick field for it would be sending the same two bits sixty times a second for ever to carry a fact that arrives reliably in a JOIN and a TEAM. The general rule this game follows: a per-tick property for what changes per tick, an event for what changes on a decision.

### game/net/bfh_player_net.gd (was line 37)

Hit points, and the one field with a hard cap on the wire.

[b]Sent against 0..1000 rather than against the player's own maximum.[/b] A server that raised `runner_health` mid-round would otherwise change what every previously sent number MEANT, which is the quantisation version of the arena-radius bug: the value does not get less precise, it becomes a different value.

### game/net/bfh_player_net.gd (was line 56)

The net id of the bus they are driving, or 0 on foot.

[b]State and not only the SEAT event, because a beacon on a driver is drawn at their bus.[/b] A driver's own position is where they got in — nothing moves a rider — so a client that knows only `net_riding` knows somebody is driving and not WHAT; a client that joined after the seat was taken was never sent the SEAT at all. One varint that changes twice a round, and nothing on a tick where it did not.

### game/net/bfh_player_net.gd (was line 67)

`DotSpectatorView.Mode` of the view the server has them in; 0 when they are playing.

[b]Owner-only, and state rather than an event, like the blind.[/b] Nobody else's screen is drawn from it, so nobody else is sent it. And the death camera is three timed modes handing over to each other on the SERVER's clock: a client told each hand-over by an event it might miss would be left on a freeze camera until the round ended, where a client told the state gets the next snapshot's answer.

### game/net/bfh_player_net.gd (was line 99)

[b]Per-player state rather than an event, and that is what makes both of these survive what an event does not.[/b] A client that joins after the admin typed `beacon`, a snapshot lost on the way, a round re-laying the bowl: each is a baseline the next snapshot corrects, where an event sent once is simply missed.

The blind goes to its owner alone. Nobody else's screen changes, and a driver who received it would know which runner cannot see the bus coming.

### game/net/bfh_player_net.gd (was line 121)

On the authority the whole game ticks as one — every player moves, then the buses are driven, then what a bus hit is decided — so the first behaviour through drives the whole world and the rest find it done. On a predicting client there is one predicted player and simulating it directly is the whole of what a client may compute: the crates and the buses are rigid bodies and a client cannot reproduce them.

### game/net/bfh_player_net.gd (was line 134)

[b]A rider is not predicted, because a rider is not walking.[/b] The controller is the thing that would be predicting and while its owner is in a bus it has no answer to predict: the bus's position comes from the server, it is not reproducible across machines, and a controller simulating on top of it fights every snapshot at a metre a time. The command is still applied, because those same keys ARE the throttle and the wheel and they have to reach the server.

### game/net/bfh_player_net.gd (was line 174)

No relevance decision for the beacon, unlike a game with an interest set: every player here is already always relevant (see `BfhNetBridge._build_entity`), because a 46 m disc with nothing tall in it is a map where everybody can see everybody. A beaconed player therefore reaches every client with nothing further to do.

### game/net/bfh_player_net.gd (was line 190)

NOT the node, on a predicted entity: `receive_snapshot` calls this BEFORE the predictor reconciles, and reconcile's first act is to read the node as "what the client is showing". Moving it here makes the measured error the whole replay distance, and the correction rate then reads as if every snapshot snapped. Two games in this family shipped that line.

...unless they are riding, when there is nothing predicted to spoil: the server's answer IS what the client should be showing. Without this exception the local player's node — and the camera under it — stays where they got in, and the driver watches the bus drive away from inside their own head.

### game/net/bfh_player_net.gd (was line 214)

The game half of a snapshot, on a mirror.

[b]`set_riding` and not the flag, because getting out of a bus is two things.[/b] The controller's velocity has to be cleared and its mode put back to AIR, or a driver put back on their feet is launched across the bowl carrying the bus's speed on their first step. That is [method BfhPlayer.set_riding]'s whole job and a client has the same reason to want it as a server.

### game/net/bfh_prop_net.gd (was line 3)

What a crate, a barrel or a block replicates: where it is and how it is turned.

[b]Server-authoritative and never predicted, and that is a decision rather than an omission.[/b] Godot's rigid-body solver is not reproducible across machines — island ordering, sleep thresholds and contact caching all differ — so a client predicting a bowl full of crates would disagree with the server within a second and be corrected continuously. In this game that matters more than in most: a crate is COVER, and cover that is a few centimetres out on the client is a runner who is shot at through a wall they believe they are behind.

The consequence a player feels is that a crate they hit with the hammer starts moving one round trip later, and it is the correct trade: a wrong-but-immediate crate that snaps back is worse than a right one that starts a moment after.

### game/net/bfh_prop_net.gd (was line 40)

Where this body is, for anything that does not care what kind of body it is.

[b]A method and not a property read, because a bus does not use [member net_position].[/b] [BfhBusNet] replicates through [DotVehicleNetSync], whose layout is three separate floats — so code that read `net_position` off a mirrored bus got the zero it was constructed with, and a joining player was told every bus in the bowl was at the origin. It was the announcement to a late joiner that had it, which is the one path a suite that joins first never takes.

### game/net/bfh_request.gd (was line 5)

Anything a client asks the authority for. Reliable, rare, to the server only.

[b]There is exactly one of these and it is still a message type rather than a flag on something else.[/b] What a client asks for here is not a per-tick intent — swinging the hammer is a BUTTON, because it is a thing you hold down and it has to be ordered against the movement it is aimed with. This is for the other kind: "my world exists, start telling me about yours", which happens once and must not be lost.

### game/net/bfh_request.gd (was line 21)

[b]Built with [code]new(kind, body)[/code], and this file does not preload itself.[/b] It used to, for a typed [code]static func of() -> BfhRequest[/code] factory, and that one line leaked the whole script graph at exit — 111 scripts, the grid textures in [code]bfh_textures.gd[/code]'s static cache and eight texture RIDs — whenever the file was first loaded from a module a [DotServer] loads at runtime, which is how every deployed server loads it. Measured on 4.7.2 with a two-line reproduction: a script that [code]extends DotNetMessage[/code] and preloads ITSELF is enough, whether the base is named or given by path; a self-preload over [code]RefCounted[/code], [DotResult] or [DotNetBehaviour] is not, nor is a two-script cycle through [DotNetMessage]. The registry decodes with a bare [code]new()[/code], which is why both arguments default. See docs/history.md, "The leak that was one line of a message".

### game/net/bfh_toy_net.gd (was line 3)

One of the map's toys on the wire (dot-props' [DotPropToy]): where its moving part is and how it is turned, whether it is on, and how often it has been used.

[b]The server's physics, never predicted[/b], for the reason game-arena's ArenaProps gives: Godot's rigid-body solver is not the same on two machines. The client's toy is frozen and posed from these ([method DotPropToy.show_state]), so a see-saw a person stands on there is the plank the server tipped, an interpolation behind, and a roundabout's spin is measured from the poses.

[b]Paired by index[/b]: both ends build the same toys in the same order from the map, so the TOYS event carries only the net ids, in toy order, and nothing here says which toy it is.

[b]A use count, not a use event[/b]: a honk, a switch and a bounce each move [member net_count] by one, and a client plays the sound when it sees it move, so a joiner and a lost packet cost nothing but a late sound. Eight bits; it wraps. game-hide-n-seek's HsToyNet, game-playground's PlaygroundToyNet and game-arena's arena_toy_net.gd are the same file.

### props/bfh_art.gd (was line 5)

Puts a Kenney model's atlas back on it when the engine could not find it.

[b]A GLB references its texture by URI, and an imported one references it by UID and an ABSOLUTE PATH — which is the one thing a delivered pack cannot have.[/b] Godot imports `crate.glb` into a binary scene whose external dependency on `Textures/colormap.png` is recorded as a UID plus the path the file had when it was imported. Inside a mounted pack the UID is not registered, so the loader falls back to the path — and the path is `res://assets/…`, which in the host project is another game's directory or nothing:

[codeblock] invalid UID: 'uid://reboanwombd2' - using text path instead:     'res://assets/kenney/survival/Textures/colormap.png' Resource file not found: res://assets/kenney/survival/Textures/colormap.png [/codeblock]

The mesh still loads. The texture does not, so every crate in a delivered round is plain white — a game that works perfectly and looks like the art failed to ship. This is the sixth form of the family's one delivery bug (script → class_name, scene → ext_resource, script → `res://` string, `extends "res://…"`, an asset the engine has to import, and now an IMPORTED asset's own external dependency; the table is in dot-server-deploy's docs/delivery-constraint.md), and it is the only one nothing rewrites: the publisher rewrites text resources and a binary `.scn` is not one.

[b]Surgical, not an override.[/b] It sets the atlas only on a material that has none, so in a build — where the import worked — this does exactly nothing, and the picture a developer sees is the picture a player gets. An unconditional `material_override` would be a second definition of how these models look, drifting from the one in the file.

### props/bfh_art.gd (was line 35)

The two kits' atlases, rebased where they are defined. [method paint] rebases again, which is a no-op on these and is what makes an [code]atlas_path[/code] set in a scene safe too — the publisher has already rewritten that one onto the mount.

[b]Two files with the same name, and they are different files.[/b] Flattening the kits into one folder paints the bus in the survival kit's palette, which is a plausible-looking wrong answer.

### props/bfh_art.gd (was line 46)

Gives every untextured material under [param root] the atlas at [param atlas_path].

Returns how many materials it had to repair, which is zero in a build and the whole model in a pack — a number worth having in a log line, because "the art is white" is otherwise indistinguishable from an art mistake.

### props/bfh_art.gd (was line 76)

On a DUPLICATE, and this is the line that stops one repair painting the whole game: an imported scene's materials are shared between every instance of it, so writing into one is writing into all of them — which is what is wanted here — but the surface override below is per-instance and the two must not be the same object, or a later crate with a different atlas would repaint the earlier ones.

### props/bfh_bus.gd (was line 3)

The bus's own body: the art, and the four wheels that have to be seen turning.

[b]A raycast vehicle's wheels are rays, and rays are invisible.[/b] [VehicleWheel3D] is a suspension ray with a contact point and a steering angle; it draws nothing. The wheels a player sees are four meshes inside the Kenney model, and by default they are welded to the hull — so a bus doing 22 m/s round a corner slides on four static cylinders pointed straight ahead. Every number about it is right and it reads as the whole vehicle skating.

Three things are drawn from the simulation and each is separately noticeable:

- the front wheels STEER, which is how a runner reads where the bus is about to go   before it goes there — the whole of their game; - all four ROLL, which is the only thing that says a bus is moving rather than being   slid along; - and they do both on a MIRROR as well, from what the server replicated, because a   client cannot derive either from a position.

[b]The art is turned round, and that is not a preference.[/b] The Kenney garbage truck faces +Z — its loader arms and forks are at the +Z end — and forward in this family is -Z, which is what [method Basis.looking_at] produces and what dot-vehicle's wheel layout assumes. Unturned, the bus chased people backwards: it drove cab-last with its forks in front, which looks exactly like a bus reversing at 22 m/s and is invisible to every assertion in this repository, because every number in it is correct.

### props/bfh_bus.gd (was line 43)

Radius of the wheel a player can SEE, in metres, which is not the simulated one.

Measured off the mesh rather than written down: the art is scaled to fit a hull whose size comes from the catalogue, and a hard-coded radius here would be a number that silently stops matching the picture the first time anybody rescales the model. What it is for is the roll rate — a wheel of the wrong radius spins at the wrong speed, which reads as the bus slipping.

### props/bfh_bus.gd (was line 52)

+1 when the art faces the way the vehicle drives, -1 when it is turned round.

Derived from the art's own transform, so this keeps telling the truth if the model is ever replaced by one that faces the other way and the scene's 180° goes with it.

### props/bfh_bus.gd (was line 126)

Drawn per FRAME and not per tick, like every other visual in this family.

A wheel advanced once per physics tick and drawn three times is a wheel that turns in bursts, which is exactly the jitter game-g2gfast measured on its camera: every simulated number correct and the picture wrong several times a second.

### props/bfh_bus.gd (was line 154)

The steering angle the simulation is actually using, in radians.

Read off the wheel rather than off the last command: the chassis ramps steering towards what was asked for at [member DotVehicleTunables.steering_rate_deg] and falls it off with speed, so the command is what the driver wants and this is what the bus is doing. Drawing the command would show full lock on a bus that has barely begun to turn.

### props/bfh_bus.gd (was line 173)

What a client is told, by [code]bfh_bus_net.gd[/code], once a snapshot has arrived.

[b]Set together and latched, because a mirror must never read its own body.[/b] A mirrored bus is frozen and its transform is written from the packet, so `linear_velocity` on it is whatever it was when it was frozen — usually zero. A client that fell back to reading the body would draw every other bus in the game with its wheels stopped.

### props/bfh_prop_body.gd (was line 5)

A crate or a barrel: a rigid body with a Kenney model under it.

[b]The only thing this script does is repair the art, and only in a delivered pack.[/b] See [BfhArt] for the whole reason it exists — an imported GLB's texture is an external dependency recorded by UID and absolute path, and neither survives being mounted somewhere else. Everything about how a crate BEHAVES is in the catalogue ([BfhContent]) rather than here, which is what lets a server retune the game by editing a document.

### tools/camera_check.gd (was line 3)

The third-person camera and the spectator's chase camera flown round the bowl in the real offline game (dot-core's DotCameraCheck: never inside, armed by the unprotected camera being in or behind the level on some frames), `mp_forceview` through the view key's path, and with `--render` both views and another player at the lens before and after the fade. No body check: runners and buses share layer one here, so this game binds no `mp_solidplayers` (see bfh_game.gd's `view_rules`).

  tools/camera_check.sh            # headless; exit 1 on a failure   tools/camera_check.sh --render   # and the frames, in screenshots/cameras/

### tools/cover_server.gd (was line 6)

A headless dedicated bowl for tools/render_cover.gd to join: the boot examples/dedicated.gd does (DotServer, the world, the module), left running.

[codeblock] godot --headless --path . res://tools/cover_server.tscn -- --port 27399 [/codeblock]

### tools/drive_shot.gd (was line 7)

Renders a person driving a bus, from straight above, as a contact sheet of frames a quarter of a second apart. What headless_run's "a bus's brakes" and "a handbrake turn" measure, drawn, because a number cannot say whether a slide looks like one.

[codeblock] tools/drive_shot.sh stop        # S from 15 m/s: the brake, a standstill, then reverse tools/drive_shot.sh handbrake   # D and Ctrl from 12 m/s: the back end steps out tools/drive_shot.sh turn        # D alone from 12 m/s, to compare [/codeblock]

The world is stepped by hand, as the suites step it, so the frames fall on the same ticks every run. Frames read left to right, top to bottom; the first is the moment the keys go down.

### tools/load_probe.gd (was line 5)

Boots the solo client and prints, per rendered frame, what a player would see: whether the map, the player and the camera exist, where the body is, and whether the load gate (if any) still covers the screen. A body that moves while uncovered, or a frame with no player, is the glitch. Needs xvfb-run, never --headless:   xvfb-run -a godot --path . --script tools/load_probe.gd -- [--frames=90] [--shot=N]

### tools/net_shot.gd (was line 9)

Renders a CONNECTED client looking at another runner, and measures how smoothly that runner moves on screen. The check no assertion makes, from the side `tools/shot.gd` cannot reach: offline there is nobody else on foot to look at.

[codeblock] tools/shot.sh 6 net.png --net              # four consecutive frames, net_0..net_3.png tools/shot.sh 6 net.png --net --no-interp  # the same, with the client's interpolation off tools/shot.sh 6 near.png --net --close      # four metres off, to judge the body itself tools/shot.sh 8 walk.png --net --walk       # THIS client runs, and is it predicted? [/codeblock]

A server and a client in one process, joined by the same loopback `headless_net` uses: the server's world is in a SubViewport with its own physics space that is never drawn, and the client's is the one on screen. Every frame calls `BfhClient.present_frame`, the function the real client's `_process` calls, so what is rendered is what a player sees.

[b]The probe.[/b] Once a rendered frame, the other runner's drawn position is sampled and divided by that frame's own delta: the apparent speed. A runner running in a straight line at a constant speed should have the same apparent speed every frame, and the spread of it is the judder. `--no-interp` is there to show what the spread looks like when it is wrong, because a number with nothing to compare it to proves nothing.

[b]`--walk` is the other probe: this client's OWN runner.[/b] It stands for half a second, runs nine metres east, stands, runs back, through the same `client_tick` the real client calls, and reports three numbers a player feels: how many ticks after a key is pressed the runner is drawn moving (the prediction latency: 0 is the tick it was pressed in), the predictor's corrections per second, and the eye's apparent speed per frame while the server has them at full speed. Until 2026-09-25 the client predicted nothing, and this is where that shows as a number rather than as a feeling.

xvfb-run, never --headless: headless gives a null renderer and saves a frame of nothing.

### tools/net_shot.gd (was line 167)

This harness stamps every command itself (`_tick + INPUT_LEAD`), not from the client's clock, so the client must not ask for dot-net's input-lead report: steered by reports about commands it never stamped, the clock runs away from them (only dot-net's cap holds it). By the constant map, so this parses against a dot-net from before the report.

### tools/net_shot.gd (was line 336)

The open north-west of the bowl: south of the ledge, north of the stacks, west of the ramp. The client's runner stands looking north and Bea runs across in front of them, ten metres off, so the pillars are behind her rather than in her way. Put back whenever a round starts and scatters everybody, which is what moved them the first time. With `--walk` this client moves its own runner, so it is placed once and then left alone.

### tools/render_cover.gd (was line 5)

Frames of a real client on a real server, to look at: the loading cover while the server still holds the seat as loading, and the first frames after the cover lifts. A dedicated bowl (tools/cover_server) runs in a second process.

[codeblock] xvfb-run -a godot --path . --resolution 1280x720 res://tools/render_cover.tscn [/codeblock] Writes screenshots/cover_up.png, cover_lifted.png and cover_after_1s.png.

### tools/shot.gd (was line 8)

Renders the game from the local player's eyes and exits. The check no assertion makes.

xvfb-run, never --headless: headless gives a null renderer and saves a frame of nothing, which is worse than no screenshot because it looks like one.

### tools/shot.gd (was line 195)

An administrator's marks, set the way the handlers set them and then given a few frames to draw. `--beacon` beacons everybody — the bot driver's is round the bus, which `--bus` looks at; alone it stands off behind the local runner so their own ring and the column over the bus are both in the frame. `--blind` blacks the local player's screen out and looks through it, HUD and all.

### tools/shot.gd (was line 236)

Run down, and then where the camera goes: `--watch=death` is the death camera, `cab` the freeze on the bus's cab, `follow` the first person it hands over to and `chase` the view behind them. A second runner is put in the bowl first, because the local player going down alone would end the round and the camera with it.

### tools/shot.gd (was line 424)

A barrel going off twelve metres in front of the local runner, drawn by the client's own effects from the world's `barrel_exploded` — the path a connected client takes from a BLAST. Rendered a fifth of a second in, when the ring has reached the blast's edge and the fireball has not burned out.

### tools/shot.gd (was line 545)

A real ballot from this game's vote: every bowl this server offers there is, four voters, three of whom have voted, drawn the way the client shell's notice overlay draws a `map_ballot` — a [DotBallotPanel] down the right-hand side. Waits a second for the voters' discs to slide to the row they chose; a frame too soon catches one between rows.

### tools/soak.gd (was line 7)

Bot soak on the real game: N bot-driven buses chase idle runners in one bowl for M simulated minutes through dot-bot's DotBotSoak, fed by dot-spawn's DotSpawnWatch. A "map" here is a bowl id.

[codeblock] ./game.sh soak [bowl] [minutes] godot --headless --path . res://tools/soak.tscn -- --map bfh_bowl --bots 4 --minutes 2 [/codeblock]

Takes the harness's own flags too (--soak-max-stuck-sec and the rest of DotBotSoakConfig). Writes .godot/test-logs/soak-<bowl>.json, prints the SOAK line, exits 1 when the run fails. The movers are the bot-driven buses; runners are idle people (there is no runner bot in play), so rounds end when the buses have run them down. Kills are off.

### examples/dedicated.gd (was line 522)

The players' vote decides the next bowl, end to end through what a player types: a nomination, the ballot opening on its own clock with the nomination on it, a vote by number, the round's end handing the winner to the world, and the next round REBUILDING the bowl to it; then rock-the- vote.

### examples/headless_run.gd (was line 1240)

[b]`is_bot`, and nothing else in this file sets it.[/b] `add_player` leaves it false, so every other section's driver is a person who never presses anything -- which is why the bus in them only ever moves when a check drives it by hand, and why `_autopilot` had no coverage at all until.

### examples/headless_run.gd (was line 1688)

[b]No stack beside them, and that is a finding.[/b] The same blast shoves every loose prop in its radius: measured, a stack of two 4 m from the barrel came apart before the runner came down — the bottom crate 2.5 m along, the top one 6.4 m — while the runner's arc passed over exactly where it.

### examples/headless_run.gd (was line 2912)

[b]And nothing REFUSES them either, which `force_balance` alone does not say.[/b] dot-match's team manager has a second rule, `max_difference`, that refuses a join putting one side more than one ahead — so the fifth person here was left on no team in dot-match while `sides` called them a.

### examples/headless_run.gd (was line 3391)

[b]And the round AFTER the swap is decided by the sides as they are now.[/b] The elimination rule reads teams off dot-match's scoreboard, not off `sides`, so a swap that only flipped `sides` left the rule scoring the old ones: the drivers ran the new runner down and the round was announced as.

### game/bfh_arena.gd (was line 62)

A third row makes the rows between it and the old south row a second lane, and turns the west end into a fork: the old lane ends at the dog-leg and the hook; this one ends at the hook's south pillar, offset in it the way the dog-leg is offset in the first, and past it is the open floor to.

### game/bfh_arena.gd (was line 182)

[b]The quarter of the bowl the buses come out into had nothing in it.[/b] The stacks hold the west, the farm the east, the scaffold the south-east, and the north-west -- thirty metres of sand between the stacks' west mouths, the wall and the deck's west end -- was where a runner scattered.

### game/bfh_arena.gd (was line 245)

[b]Cleared first, because building is also REBUILDING.[/b] A client is told the server's radius in the HELLO and rebuilds its bowl to match — the map here is one number, run through this function on both ends — and a second call that only added would leave a 46 m wall standing inside.

### game/bfh_arena.gd (was line 291)

[b]The layout is an operator's to choose now, so the gap rule is said where it is broken.[/b] `headless_run` holds the shipped layout to BUS_GAP; a hook or a west lane set from a JSON file or the environment is not run through the suite, and a pair of drums closer than a bus is a pocket a.

### game/bfh_game.gd (was line 406)

[b]One.[/b] dot-match defaults to two because a deathmatch with one player in it is not a match; a round here with one runner and no drivers is a legitimate, if dull, thing for a nearly-empty server to be doing, and the alternative is a server that sits in warmup for ever and looks broken.

### game/bfh_game.gd (was line 844)

[b]dot-match as well, because its elimination rule is what decides the round and it reads teams off its own scoreboard.[/b] Flipping `sides` alone left the rule on the old sides for the rest of the server's life: the drivers ran the new runners down and every such round was announced as.

### game/bfh_game.gd (was line 1960)

The speed a leg is held under (m/s); how still the bus has to be, and for how long the wheel has to swing, between legs; how long a leg can push without moving before it counts as stopped; how long a leg runs before the turning point's bounds apply; and the longest a leg lasts whatever the.

### game/bfh_hud.gd (was line 74)

[b]A full-rect Control between the CanvasLayer and the labels, and the first render is why.[/b] A CanvasLayer is not a Control and does not lay its children out, so anchors on a Label parented straight to one resolve against nothing: every label landed in the top-left corner stacked on top.

### game/bfh_module.gd (was line 29)

[b]No `const CHANNEL` here, and its absence is the point.[/b] [DotGameModule] already declares one and GDScript refuses to let a subclass redeclare it — which is the right refusal: a module logs through [method DotModule.log_info], which stamps the module's own name, so a second channel would.

### game/bfh_services.gd (was line 105)

[b]Push to talk, in the one game in this family where it is not a preference.[/b] A runner is being chased by a bus and is breathing into a microphone; open-mic voice on a side of six people is six sets of breathing over the one thing anybody needs to hear, which is somebody saying which.

### props/bfh_art.gd (was line 42)

On a DUPLICATE, and this is the line that stops one repair painting the whole game: an imported scene's materials are shared between every instance of it, so writing into one is writing into all of them — which is what is wanted here — but the surface override below is per-instance and.

