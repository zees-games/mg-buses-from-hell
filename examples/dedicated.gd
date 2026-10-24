extends Node

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhNetLink := preload("../game/net/bfh_net_link.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhAvatars := preload("../game/bfh_avatars.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhDistricts := preload("../game/bfh_districts.gd")
const BfhNetBridge := preload("../game/net/bfh_net_bridge.gd")

## Boots a real [DotServer], loads this game into it as a module, and runs the commands
## an operator would actually type.
##
## [codeblock]
## godot --headless --path . res://examples/dedicated.tscn
## [/codeblock]
##
## [b]This is the seam the family's own notes say is never run.[/b] `headless_run` tests
## the joins between the gameplay addons and `headless_net` tests the wire; this tests the
## join between the game and the SERVER — the module lifecycle, the console, the cvars,
## and `sv_tickrate` travelling from a line in a config file all the way into the
## netcode's own configuration.
##
## Nothing here opens a socket to a client. A dedicated server that never accepts one is
## still a dedicated server as far as its console, its cvars and its modules are
## concerned, and those are what this is about.

const CHECKS := 165

## Everything this run writes, and it is deleted on the way in and on the way out.
##
## [b]A suite that writes to `user://` is a suite whose result depends on the last run.[/b]
## This one used to write the real punishment store, the server's ban and admin files and
## its audit log, all at their defaults — so every run appended to all four, and the live
## tools' warnings alone had reached 134 records in a store a real server enforces.
## `headless_net` had already failed on its second run for the same reason, over a gag.
const SERVER_DIR := "user://bfh_dedicated"

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 17

## The port this test listens on. Nothing else on a developer's machine is likely to be
## holding it, and a boot that failed on a busy 27015 would look like the module being
## broken.
const PORT := 28871
const QUERY_PORT := 28872

## What the config file asks for. Deliberately not the project's own default: the point of
## the chain below is that the SERVER decides, so a test using the same number on both
## sides would pass with the chain disconnected.
const TICK_RATE := 40

var _passed := 0
var _failed := 0
var _completed := 0
var _failures := PackedStringArray()

var server: DotServer = null
var game: BfhGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell as a dedicated server")
	print("")

	var probe: Array = []
	if not _is_exit_probe():
		probe = await _run_exit_probe()

	# A member's site avatar, translated into this game's schema. The site's document is the
	# Kenney skins filed as `top.skin-c` (the site's slot.option part id); without a translation every member is stock here.
	var site_avatars = preload("res://game/bfh_avatars.gd")
	var site_doc := DotAvatar.make(&"builtin")
	site_doc.set_part(&"top", &"top.skin-c")
	site_doc.set_part(&"face", &"face.skin-k")
	var as_ours: DotAvatar = site_avatars.from_site(site_doc)
	_check(
		as_ours != null and site_avatars.schema().validate(as_ours).ok and as_ours.part_in(&"skin") == &"skin_c",
		"a member's site avatar becomes this game's, and its schema accepts it",
		str(as_ours.to_dict()) if as_ours != null else "null"
	)
	var unknown_skin := DotAvatar.make(&"builtin")
	unknown_skin.set_part(&"top", &"top.skin-r")
	unknown_skin.set_part(&"face", &"face.skin-r")
	var not_site := DotAvatar.make(&"elsewhere")
	not_site.set_part(&"top", &"top.skin-c")
	_check(
		site_avatars.from_site(unknown_skin) == null and site_avatars.from_site(not_site) == null,
		"a skin this game does not draw, or a document that is not the site's, is stock"
	)

	DotPaths.remove_tree(SERVER_DIR)
	DirAccess.make_dir_recursive_absolute(SERVER_DIR)

	await _boot()

	if server != null and server.state == DotServer.State.RUNNING:
		await _test_the_module_loads()
		_test_the_commands()
		_test_the_tunables()
		await _test_the_round_runs()
		await _test_the_bots()
		_test_the_services()
		await _test_the_live_tools()
		await _test_progress_and_spectating()
		await _test_who_they_are()
		await _test_loading_cover()
		_test_the_bowl_vote()
		_test_rotation_file()
		_test_finish_round_waits_for_a_live_round()
		await _test_it_unloads_cleanly()
		await _test_a_reload_leaves_one_live_link()
		_test_no_message_preloads_itself()

	if not probe.is_empty():
		_test_exits_clean(probe)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	# And the section counter, which is the other half: a section that aborted before its
	# last line never reached its `_done()`. Neither guard is enough alone; see
	# docs/testing.md for the run that reported "0 failed" with eight checks missing.
	#
	# The copy of this suite that the exit probe runs does not run the probe itself.
	var sections := SECTIONS - (1 if _is_exit_probe() else 0)
	var checks := CHECKS - (EXIT_PROBE_CHECKS if _is_exit_probe() else 0)

	if _completed != sections:
		print("ERROR: %d of %d sections ran to their last line." % [_completed, sections])
		code = 1

	if _passed + _failed != checks:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, checks
		])
		code = 1

	await _shut_down()
	DotPaths.remove_tree(SERVER_DIR)
	get_tree().quit(code)


## Takes the server down before quitting, and this run does not end without it.
##
## [b]`get_tree().quit()` on a booted [DotServer] does not end the process.[/b] The
## listener is open, stdin console input is on and the transport is holding the main loop,
## so the run prints its results, reports success, and hangs — which in a CI job is a
## timeout on a suite that passed, and on a developer's machine is a terminal that has to
## be interrupted. Measured here: 33 passed, 0 failed, killed at 110 seconds.
func _shut_down() -> void:
	if server == null:
		return

	# The modules first. A module unloaded by the server going away is one whose teardown
	# runs during `_exit_tree`, where there is no frame left to resume a coroutine in.
	if server.modules != null:
		server.modules.unload_all()

	server.shutdown("the dedicated test is finished")

	for _i in range(10):
		await get_tree().process_frame

	# And both nodes taken down rather than left for the engine to tear out from under
	# itself. Godot reports whatever is still alive at that point as leaked, which reads
	# as a reference cycle in the game and is a test that stopped one line early.
	if is_instance_valid(game):
		remove_child(game)
		game.free()
		game = null

	if is_instance_valid(server):
		remove_child(server)
		server.free()
		server = null

	await get_tree().process_frame


## Profiles, names and faces on a real server: dot-platform's identity layer, its module, the
## three events this game redraws a player on, and the key what they keep is filed under.
##
## [b]Both orders a real join has.[/b] Admission runs off dot-server's state changes and is
## not awaited, so a player is admitted before they are seated when the profile store is
## quicker than the content download — the usual case — and after when it is slower. Late,
## the world has to be TOLD; early, it has to ask. Each order is driven here the way
## dot-server drives it.
func _test_who_they_are() -> void:
	print("who somebody is")

	var module := _module()
	var identity: Object = module.get("identity") if module != null else null

	_check(identity is DotPlatformIdentity, "the module built dot-platform's identity layer")
	_check(server.modules.has_module("platform"), "and dot-game loaded the platform module")
	_check(
		identity is DotPlatformIdentity and (identity as DotPlatformIdentity).avatars != null
			and (identity as DotPlatformIdentity).avatars.schema.id == BfhAvatars.SCHEMA_ID,
		"validating avatars against this game's schema"
	)

	var net: DotNetManager = module.get("net")
	var previous_send := net.send_fn
	net.send_fn = func(_peer: int, _payload: PackedByteArray, _delivery: int) -> void:
		pass
	var platform := server.modules.get_module("platform")

	# Late: seated with no identity, then given one and announced.
	var late := DotClientSession.new()
	late.peer_id = 7171
	late.userid = 717
	late.display_name = "guest-717"
	var _adopted := server.adopt_session(late)
	server.events.fire("client_spawn", {"userid": 717, "name": "guest-717"})

	var player: BfhPlayer = game.players.get(&"u717")
	_check(
		player != null and player.avatar != null
			and player.avatar.digest() == BfhAvatars.stock_avatar(&"u717").digest(),
		"seated before the platform knows them, they wear the stock look for their seat"
	)

	late.identity = DotAuthIdentity.from_dict({
		"uid": "backbone:acc-717", "provider": "backbone", "provider_id": "acc-717",
		"display_name": "Margaret", "authenticated_at": int(Time.get_unix_time_from_system()),
	})
	platform.call("_on_client_state_changed", late)

	var deadline := Time.get_ticks_msec() + 5000
	while (player == null or player.display_name != "Margaret") \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	var admitted: Object = platform.call("player_for", late)
	var late_key := str(admitted.call("key")) if admitted != null else ""
	_check(
		player != null and player.display_name == "Margaret",
		"admitted late, the world calls them by their profile's name",
		player.display_name if player != null else "-"
	)
	_check(
		player != null and admitted != null and player.avatar == admitted.get("avatar")
			and player.avatar.digest() == BfhAvatars.stock_avatar(StringName(late_key)).digest(),
		"and draws what the platform resolved: this game's stock look, for their scoped key",
		late_key
	)
	_check(
		game.progress == null or game.progress.key_of(&"u717") == "bfh-u717",
		"and what they keep stays under their seat's key for this session, not split in two",
		game.progress.key_of(&"u717") if game.progress != null else "-"
	)

	var renamed := _run_command("platform_name 717 Grace")
	for _i in range(10):
		await get_tree().process_frame
	_check(
		player != null and player.display_name == "Margaret" and _said(renamed, "account"),
		"renaming a signed-in player is refused with the reason, and the world keeps the name",
		"%s | %s" % [player.display_name if player != null else "-", " | ".join(renamed)]
	)

	# Early: signed in before they are seated, which is the usual order.
	var early := DotClientSession.new()
	early.peer_id = 7181
	early.userid = 718
	early.display_name = "guest-718"
	early.identity = DotAuthIdentity.from_dict({
		"uid": "backbone:acc-718", "provider": "backbone", "provider_id": "acc-718",
		"display_name": "Hedy", "authenticated_at": int(Time.get_unix_time_from_system()),
	})
	_adopted = server.adopt_session(early)

	deadline = Time.get_ticks_msec() + 5000
	while platform.call("player_for", early) == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	server.events.fire("client_spawn", {"userid": 718, "name": early.display_name})
	var signed_in: BfhPlayer = game.players.get(&"u718")
	var held: Object = platform.call("player_for", early)
	var early_key := str(held.call("key")) if held != null else ""
	_check(
		signed_in != null and held != null and signed_in.display_name == "Hedy"
			and signed_in.avatar == held.get("avatar"),
		"admitted before they are seated, they are seated with their name and face",
		signed_in.display_name if signed_in != null else "-"
	)
	_check(
		game.progress == null or (early_key != "" and game.progress.key_of(&"u718") == early_key
			and game.progress.stats.has_player(StringName(early_key))),
		"and what they keep is filed under the key that outlives the connection",
		game.progress.key_of(&"u718") if game.progress != null else "-"
	)

	for session in [late, early]:
		module.get("roster").call("remove", session)
		var _released := server.release_session(session.peer_id)
	net.send_fn = previous_send
	_done()


## A section reached its end. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
		return

	_failed += 1
	var line := what if detail == "" else "%s  (%s)" % [what, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## The loaded module, looked up rather than kept.
##
## [b]Looked up every time, because the last section unloads it.[/b] A field would be a
## dangling reference the moment it did. Typed [DotModule] rather than as its own class,
## because `bfh_module.gd` has NO `class_name` — it is loaded by path, which is the shape
## a module delivered in a dot-cloud pack must have.
func _module() -> DotModule:
	return server.modules.get_module("buses") if server != null else null


## Runs a line the way the console does and captures what came back.
##
## [b]Through `reply_sink`, not by reading `output` off a context built by hand.[/b] A
## command's reply goes wherever its context sends it — a socket, RCON, stdout — and the
## sink is that seam. A context constructed with `new()` and poked at is not the object a
## real command is handed.
func _run_command(line: String) -> PackedStringArray:
	var captured: Array[String] = []

	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)

	server.console.execute(line, context)

	return PackedStringArray(captured)


func _said(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.findn(text) >= 0:
			return true
	return false


## [b]The one line that made this suite leak its whole script graph at exit.[/b]
##
## A script that `extends DotNetMessage` and preloads ITSELF, first loaded from a module a
## running [DotServer] loads — which is how every deployed server loads this game — left
## 111 scripts, the grid textures in `bfh_textures.gd`'s static cache and eight texture
## RIDs alive at exit, on 4.7.2. `bfh_event.gd` and `bfh_request.gd` both did it, for a
## typed `of()` factory. `headless_run` and `headless_net` preload the same files at scene
## load and never saw it.
##
## [b]Asserted on the source, because the symptom is where no check can reach.[/b] The
## leak is reported after `quit()`, by the engine, as warnings a CI filter already
## treats as noise; an assertion here runs before any of it exists. So this checks the
## cause instead: every message script in `game/`, read as text.
func _test_no_message_preloads_itself() -> void:
	print("exiting clean")

	var messages := PackedStringArray()
	var offenders := PackedStringArray()
	var pending: Array[String] = ["res://game"]

	while not pending.is_empty():
		var dir_path: String = pending.pop_back()

		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))

		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd"):
				continue

			var path := dir_path.path_join(file)
			var source := FileAccess.get_file_as_string(path)

			if not _extends_message(source):
				continue

			messages.append(path)

			if source.contains('preload("%s")' % file) or source.contains('preload("%s")' % path):
				offenders.append(path)

	_check(
		messages.size() >= 2,
		"this game's message scripts are found, so the next check is about something",
		", ".join(messages)
	)
	_check(
		offenders.is_empty(),
		"and none of them preloads itself, which leaks every script at exit",
		", ".join(offenders)
	)
	_done()


func _extends_message(source: String) -> bool:
	for line in source.split("\n"):
		if line.begins_with("extends "):
			return line.contains("DotNetMessage") or line.contains("dot_net_message.gd")
	return false


# --- Booting ---------------------------------------------------------------

func _boot() -> void:
	print("booting")

	# The tick rate is set the way an operator actually sets it: a line in a config file
	# the server execs at boot.
	#
	# [b]`startup_config`, not `autoexec_config`.[/b] `sv_tickrate` is FLAG_STARTUP_ONLY —
	# a live server cannot re-negotiate its tick rate — and dot-server execs `server.cfg`
	# BEFORE the listener for exactly that reason, while `autoexec.cfg` runs after and
	# would have it refused.
	var cfg_path := "%s/server.cfg" % SERVER_DIR
	var cfg := FileAccess.open(cfg_path, FileAccess.WRITE)

	if cfg == null:
		_check(false, "the test config file could be written", cfg_path)
		return

	cfg.store_line("// written by examples/dedicated.gd")
	cfg.store_line("sv_tickrate %d" % TICK_RATE)
	cfg.store_line("hostname \"buses test\"")
	cfg.close()

	var config := DotServerConfig.new()
	config.startup_config = cfg_path
	# And nothing in the after-the-listener file, so the test is unambiguous about which
	# one set it.
	config.autoexec_config = ""
	config.hostname = "buses test"
	config.max_players = 16
	config.hibernate_when_empty = false
	config.rcon_password = ""
	config.port = PORT
	config.query_port = QUERY_PORT
	config.admins_path = "%s/admins.json" % SERVER_DIR
	config.bans_path = "%s/bans.json" % SERVER_DIR
	config.audit_log_path = "%s/audit.jsonl" % SERVER_DIR
	# [b]Off, or this run never ends.[/b] The stdin console reads on its own thread, and a
	# thread blocked in a read is a thread Godot will not exit without — so the suite
	# prints its results, calls `quit()`, and hangs. It is the right default for a real
	# dedicated server, where an operator types into the terminal; a test has nobody at the
	# keyboard.
	# Kept after dot-server 5f46687, which no longer reads a pipe unless `stdin_console_pipes`
	# is on: a terminal is still read, and a suite takes no commands from either.
	config.stdin_console_enabled = false

	server = DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)

	# `auto_boot` makes `_ready` await `boot()`, which opens a listener and reads the
	# config's environment and command-line layers — so this takes several frames and a
	# single `process_frame` catches it half-built.
	for _i in range(90):
		await get_tree().process_frame

		if server.state == DotServer.State.RUNNING:
			break

	_check(
		server.state == DotServer.State.RUNNING,
		"the server boots",
		DotServer.State.keys()[server.state]
	)
	_check(server.console != null, "and has a console")
	_check(
		Engine.physics_ticks_per_second == TICK_RATE,
		"and sv_tickrate reached the engine's physics rate",
		"%d" % Engine.physics_ticks_per_second
	)


# --- The module ------------------------------------------------------------

func _test_the_module_loads() -> void:
	print("the module")

	# [b]The world is built AFTER the server and BEFORE the module, and both halves of
	# that order matter.[/b] After the server, because the server is what set the engine's
	# tick rate and the world reads it — which is the ordering a real deployment has.
	# Before the module, because a module refuses to load without a world to run: it
	# cannot build one, since the world outlives it across a `module reload`.
	var config := BfhConfig.new()
	config.crate_count = 10
	config.barrel_count = 2
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.round_seconds = 45.0

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.config_binder = DotGameConfigBinder.create(config, "mg-buses-from-hell", "bfh")
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)

	await get_tree().process_frame

	_check(
		DotRegistry.get_node_service(BfhGame.SERVICE) == game,
		"the world publishes itself where a module will look for it"
	)

	# Into this run's own directory. See [constant SERVER_DIR].
	#
	# Through the script, loaded here, rather than a `preload` at the top of this file:
	# a preload would load the module when this scene loads, long before the host does,
	# and the order scripts load in is what decides whether Godot 4.7.2 leaks them at
	# exit. See [method _run_exit_probe]. This is the order a deployed server has.
	(load("res://game/bfh_module.gd") as GDScript).set(
		"punishments_file", "%s/punishments.json" % SERVER_DIR
	)

	var loaded: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	_check(
		loaded.ok, "the module loads into the server",
		loaded.error.message if not loaded.ok else ""
	)

	var module := _module()
	_check(module != null, "and the host has it under its name")

	if module == null:
		_done()
		return

	# Through `get()`, because this module has no `class_name` — the shape a module
	# delivered in a dot-cloud pack must have.
	_check(module.get("net") != null, "the netcode is up")
	_check(module.get("bridge") != null, "with the game's bridge attached to it")
	_check(module.get("roster") != null, "and a roster waiting for players")

	var net: DotNetManager = module.get("net")
	_check(
		net.config.tick_rate == TICK_RATE,
		"and the netcode runs at the rate the operator's config file asked for",
		"netcode %d, cfg %d" % [net.config.tick_rate, TICK_RATE]
	)
	_check(
		net.config.snapshot_rate == BfhGame.NET_SNAPSHOT_RATE,
		"at the game's own snapshot rate"
	)
	_check(
		absf(net.config.world_extent - BfhGame.NET_WORLD_EXTENT) < 0.01,
		"and the world extent both ends decode positions against"
	)
	_check(not net.auto_tick, "the manager does not tick itself: the module drives it")

	# [b]The store, and that it is empty.[/b] The second is what says the first worked on
	# THIS run: a path that is right and a directory that was not wiped is a suite carrying
	# the last run's punishments into this one, which is how `headless_net` failed on its
	# second run.
	var services: Object = module.get("services")
	var moderation: Object = services.get("moderation") if services != null else null
	var store: Object = moderation.get("store") if moderation != null else null
	var store_path := str(store.get("path")) if store != null else ""
	_check(store_path.begins_with(SERVER_DIR),
		"punishments go to this run's own store, not the one a real server enforces", store_path)
	_check(moderation != null and int(moderation.call("count")) == 0,
		"and it starts empty, so nothing a previous run did is in it",
		"%d records" % int(moderation.call("count")) if moderation != null else "no moderation")
	_noblock_and_config(module)
	_done()


## Config cvars, a workbench edit reaching a hand-written cvar and the bus feel, and dot-team's block rules through dot-game's DotGameNoblock.
func _noblock_and_config(module: DotModule) -> void:
	var teamblock := server.console.find_cvar("mp_teamblock")
	var enemyblock := server.console.find_cvar("mp_enemyblock")
	_check(teamblock != null and teamblock.get_string() == "0" and enemyblock != null and enemyblock.get_string() == "1",
		"mp_teamblock is 0 and mp_enemyblock is 1 by default")
	_check(server.console.has_name("bfh_bus_mass") and server.console.has_name("bfh_bot_horn_range") and server.console.has_name("bfh_hammer_damage"),
		"config fields with no hand-written cvar are bfh_ cvars")
	_check(module.get("workbench") != null, "the module hosts the workbench")
	game.config.crate_count = 12
	module.call("_on_config_field", "crate_count", 12, "workbench")
	_check(server.console.find_cvar("bfh_crates").get_string() == "12", "a workbench edit reaches the hand-written cvar",
		server.console.find_cvar("bfh_crates").get_string())
	server.console.set_cvar("bfh_bus_mass", "2500")
	var def := game.vehicles.catalogue.get_vehicle(&"bus")
	_check(game.config.bus_mass == 2500.0 and def.tunables.mass == 2500.0, "a bus feel cvar reaches the catalogue's bus",
		str(def.tunables.mass))
	var _a := game.add_player(&"u91", "Walker", BfhGame.TEAM_RUNNERS)
	var _b := game.add_player(&"u92", "Other", BfhGame.TEAM_RUNNERS)
	_check(not game.body_rules.blocks(&"u91", &"u92"), "players are not solid, so nothing is blocked")
	game.body_rules.solid = true
	_check(game.team_of_side(&"u91") == game.team_of_side(&"u92"), "two arrivals are on the same side, so they pass under mp_teamblock 0")
	teamblock.set_value("1")
	_check(game.body_rules.blocks(&"u91", &"u92"), "mp_teamblock 1 makes them block")
	teamblock.set_value("0")
	game.body_rules.solid = false
	game.remove_player(&"u91")
	game.remove_player(&"u92")


## The players' vote decides the next bowl, end to end through what a player types: a
## nomination, the ballot opening on its own clock with the nomination on it, a vote by
## number, the round's end handing the winner to the world, and the next round REBUILDING
## the bowl to it; then rock-the-vote opening a ballot early. Commands run at the console,
## which is where a `!vote` typed in chat lands (`_on_chat_command` runs it as the player);
## the console's voter is "console", so the voter list is that one name. Bots are not
## voters, and a server of bots never opens a ballot by itself.
##
## Synchronous from the round's end to the round begun: the bots' rounds are running, and
## one that started in a frame between would build the voted bowl itself and leave the
## check reading nothing. Last before unloading, because it leaves the bowl a different size.
func _test_the_bowl_vote() -> void:
	print("the bowl vote")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null
	_check(vote != null, "the module built a bowl vote")

	if vote == null:
		_done()
		return

	var commands_there := true

	for name in ["vote", "rtv", "nominate"]:
		commands_there = commands_there and server.console.find_command(name) != null

	_check(commands_there, "and registered dot-vote's vote, rtv and nominate")

	# Hibernation: DotGameModule hands the director the server, the ballot's timer waits with
	# it, and waking starts both again from the top.
	var director: DotVoteDirector = vote.get("director")
	_check(server.hibernation_changed.is_connected(director.set_hibernating),
		"the vote follows the server's hibernation without a line of this game's")
	vote.set("_opened_this_bowl", true)
	server.console.execute("sv_hibernate_when_empty 1")
	_check(server.is_hibernating() and director.hibernating, "an empty server sleeps, and the vote with it",
		server.state_name())
	var on_bowl: float = vote.get("_on_bowl_sec")
	vote.call("advance", 600.0)
	_check(is_equal_approx(vote.get("_on_bowl_sec"), on_bowl), "ten minutes asleep do not count towards the ballot")
	server.console.execute("sv_hibernate_when_empty 0")
	_check(is_zero_approx(vote.get("_on_bowl_sec")) and not vote.get("_opened_this_bowl") and not director.hibernating,
		"waking wakes the vote, and the bowl ballot is owed again from the top")

	var ids: Array = []

	for choice: DotVoteChoice in (vote.get("source") as DotVoteListSource).entries:
		ids.append(String(choice.id))

	_check(ids.size() == BfhBowls.all(game.config).size() and ids.has("bfh_small_bowl"),
		"it offers every bowl", str(ids))

	# The map menu's server half (M): the owner's flag changes the bowl now, anybody else
	# gets a nomination and a rock-the-vote. Contexts as dot-server makes them for a chat line.
	var menu_half: Object = vote.get("commands").get("map_menu")
	_check(menu_half != null and server.console.find_command("mapmenu") != null
		and server.console.find_cvar("sv_map_menu_flag").get_string() == "generic"
		and (menu_half.get("change_fn") as Callable).is_valid(),
		"the map menu is there, staff-only by default, changing the bowl now")
	var staff := DotCmdContext.new()
	staff.source = DotCmdContext.Source.CHAT
	staff.permissions = PackedStringArray(["generic"])
	var player := DotCmdContext.new()
	player.source = DotCmdContext.Source.CHAT
	var offered: Dictionary = menu_half.call("offer", player)
	_check((offered["maps"] as Array).size() > 1 and not bool(offered["allowed"]) and bool(offered["vote"]),
		"a player is offered every bowl, as a vote")
	var target: StringName = &""
	for row: Dictionary in offered["maps"]:
		if not bool(row["current"]):
			target = StringName(str(row["id"]))
			break
	var menu_changed: Dictionary = await menu_half.call("choose", staff, target)
	_check(bool(menu_changed["ok"]) and game.bowl_id == target, "staff choosing one changes the bowl on the spot",
		"%s: %s" % [target, menu_changed.get("text", "")])

	director.begin(game.bowl_id)
	var wanted := &"bfh_small_bowl" if game.bowl_id != &"bfh_small_bowl" else &"bfh_big_bowl"
	var radius := float(BfhBowls.by_id(game.config, wanted)["radius"])
	var captured: Array = []
	vote.set("voters_fn", func() -> Array: return [&"console"])
	vote.set("ballot_fn", func(state: Dictionary) -> void: captured.append(state))

	_check(_said(_run_command("nominate %s" % wanted), "Nominated"), "a player nominates a bowl", String(wanted))

	vote.set("_on_bowl_sec", 0.0)
	vote.set("_opened_this_bowl", false)
	vote.call("advance", float(vote.get("open_after_sec")) + 0.1)
	var options: Array[StringName] = director.ballot.option_ids() if director.is_voting() else ([] as Array[StringName])
	_check(director.is_voting() and options.has(wanted),
		"the ballot opens on its own clock, with the nomination on it", str(options))
	# The feed is polled each tick before the ballot timer opens one, so it sees it next tick.
	(vote.get("feed") as DotVoteBallotFeed).poll()
	var drawn: Dictionary = captured.back() if not captured.is_empty() else {}
	_check(bool(drawn.get("open", false)) and str(drawn.get("command", "")) == "vote" \
			and (drawn.get("options", []) as Array).size() == options.size(),
		"and the ballot a client draws says so, with the command that votes", str(drawn.keys()))

	_check(_said(_run_command("vote %d" % (options.find(wanted) + 1)), "Voted"),
		"a vote by the number on the ballot counts")
	# Everybody has voted; the director closes on its next advance, which is the server's tick.
	vote.call("advance", 0.05)
	_check(director.pending_id() == wanted, "and decides it, waiting for the round's end",
		str(director.pending_id()))

	vote.call("note_round_end")
	_check(game.next_bowl_id == wanted, "the round's end hands it to the world", str(game.next_bowl_id))

	var changed: Array = []
	var on_change := func(id: StringName) -> void: changed.append(id)
	game.bowl_changed.connect(on_change)
	game.call("_on_round_started", game.round_number + 1)
	game.bowl_changed.disconnect(on_change)
	_check(game.bowl_id == wanted and is_equal_approx(game.arena.radius, radius) and game.next_bowl_id == &"",
		"and the next round is played in the bowl voted for, rebuilt to its radius, once",
		"%s at %.0f m" % [game.bowl_id, game.arena.radius])
	_check(changed == [wanted] and game.props.world_count() > 0,
		"said once, with the round laid out in it", "%s, %d props" % [changed, game.props.world_count()])

	# The round began, which starts the director over on the bowl; rocking the vote then
	# brings the ballot forward instead of waiting for open_after_sec.
	_check(director.current_id() == wanted and not director.is_voting(),
		"the new round starts the vote over", str(director.current_id()))
	# Past dot-vote's cooldown between two ballots, on the director alone so the round's own
	# ballot timer does not open one first. In play a round outlasts it.
	director.rules.rtv_delay_sec = 0.0
	director.rules.min_players_to_vote = 1
	director.rules.rtv_min_players = 1
	director.rules.allow_single_voter_auto = true
	director.advance(director.rules.vote_cooldown_sec + 0.1)
	# Rocked in the warmup, which is what an empty current id means, so the same ballot also
	# shows it is drawn there. The feed was polled after the warmup return, so a ballot opened
	# in the warmup (rocked, or one the server's game vote made wait) was open and counted and
	# no client ever drew it.
	director.set("_current_id", &"")
	captured.clear()
	var ballots: Array = []
	var on_ballot := func(_options: Array, _seconds: float) -> void: ballots.append(1)
	director.vote_opened.connect(on_ballot)
	var rocked := _run_command("rtv")
	vote.call("advance", 0.05)
	director.vote_opened.disconnect(on_ballot)
	_check(director.is_voting(), "and rock-the-vote opens a ballot before its time", str(rocked))
	# The director opens a rocked ballot itself (dot-vote API 2); this game no longer does, so
	# exactly one ballot opens, not one from each.
	_check(ballots.size() == 1, "and exactly one ballot, the director's alone", str(ballots.size()))
	var warm: Dictionary = captured.back() if not captured.is_empty() else {}
	_check(bool(warm.get("open", false)),
		"a ballot opened in the warmup is sent to be drawn", "%d sent" % captured.size())
	_done()

## Stands in for the module a vote's commands are registered on, recording the names.
class CommandHost extends Node:
	var added: Dictionary = {}

	func add_command(full: String, fn: Callable, _help: String, _permission: String) -> Object:
		added[full] = fn
		return null


## `cfg/maps.yml`: which bowls rotate. The format is dot-map's selftest's; this is what the GAME
## does with it: a bowl left out is installed and loadable and is never drawn, never on a
## ballot, never nominated, marked in the map list; a switch of rotation takes effect; a renamed
## command is registered; no file means every bowl.
func _test_rotation_file() -> void:
	print("rotation file")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null
	var director: DotVoteDirector = vote.get("director") if vote != null else null
	var district := str(BfhDistricts.LIST[0]["id"])
	var keep_a: Array = ["bfh_bowl", "bfh_small_bowl"]
	var keep_b: Array = ["bfh_big_bowl", district]
	var before := game.bowl_id
	var parsed := DotMapRotationFile.from_trees([{"defaults": {
		"rotation": "a",
		"rotations": {"a": {"maps": keep_a, "mode": "random"}, "b": {"maps": keep_b, "mode": "cycle"}},
		"commands": {"names": {"rtv": "rockit"}},
	}}], "mg-buses-from-hell")
	_check(parsed.ok, "a rotation file parses", str(parsed.error))
	var kept = game.rotation_file
	game.rotation_file = parsed.value
	game.apply_rotation()

	var drawn := {}
	for _i in 30:
		var id := game.next_bowl()
		drawn[String(id)] = true
		game._rotation.note_played(id)
		game._rotation.seed_value += 1
	var strays := drawn.keys().filter(func(id: String) -> bool: return not keep_a.has(id))
	_check(not drawn.is_empty() and strays.is_empty(), "a bowl outside the rotation is never drawn", str(strays))
	_check(not game.rotating_ids().has(&"bfh_big_bowl") and not game.in_rotation(&"bfh_big_bowl")
			and BfhBowls.by_id(game.config, &"bfh_big_bowl").size() > 0,
		"and stays installed but is not what the rotation offers")

	# Nobody voted: the round's own change follows the rotation, not the bowl it was in.
	game.change_bowl_now(&"bfh_big_bowl")
	var fell_to := {}
	for _i in 8:
		game.next_bowl_id = &""
		game._change_bowl()
		fell_to[String(game.bowl_id)] = true
		game._rotation.seed_value += 1
	_check(not fell_to.is_empty() and fell_to.keys().all(func(id: String) -> bool: return keep_a.has(id)),
		"and a round nobody voted for opens in a bowl of the rotation", str(fell_to.keys()))

	if vote != null:
		vote.call("refresh_bowls")
		director.begin(game.bowl_id)
		var ballot: Array = []
		for choice in (vote.get("source") as DotVoteListSource).entries:
			ballot.append(String(choice.id))
		_check(ballot.has("bfh_small_bowl") and not ballot.has("bfh_big_bowl") and not ballot.has(district),
			"never on a ballot", str(ballot))
		var refused := _run_command("nominate bfh_big_bowl")
		_check(not _said(refused, "Nominated"), "refused by nominate", ", ".join(refused))
		# Not the one in play: nominating the current bowl is refused for its own reason.
		var other := "bfh_small_bowl" if game.bowl_id != &"bfh_small_bowl" else "bfh_bowl"
		var accepted := _run_command("nominate %s" % other)
		_check(_said(accepted, "Nominated"), "while one in the rotation is accepted", ", ".join(accepted))
	else:
		_check(false, "never on a ballot", "no vote")
		_check(false, "refused by nominate", "no vote")
		_check(false, "while one in the rotation is accepted", "no vote")

	var out_row: Dictionary = {}
	var in_row: Dictionary = {}
	for row: Dictionary in game.bowl_rows():
		if row["id"] == "bfh_big_bowl":
			out_row = row
		elif row["id"] == "bfh_small_bowl":
			in_row = row
	_check(not out_row.is_empty() and not bool(out_row["in_rotation"])
			and str(out_row["name"]).contains("not in rotation"), "the bowl list marks it")
	_check(not in_row.is_empty() and bool(in_row["in_rotation"])
			and not str(in_row["name"]).contains("not in rotation"), "and leaves the rotating ones alone")
	_check(game.change_bowl_now(&"bfh_big_bowl").ok and game.bowl_id == &"bfh_big_bowl",
		"while the map menu's change still loads it", str(game.bowl_id))

	_check(game.switch_rotation("b").ok and game.rotating_ids().size() == 2
			and game.rotating_ids().has(&"bfh_big_bowl") and game.rotating_ids().has(StringName(district)),
		"a rotation switch takes effect")
	_check(not game.switch_rotation("nowhere").ok, "and an unknown rotation changes nothing")

	var seen: Array = []
	for _i in 4:
		var id := game.next_bowl()
		seen.append(String(id))
		game._rotation.note_played(id)
	_check(seen[0] != seen[1] and seen[0] == seen[2] and seen[1] == seen[3]
			and keep_b.has(seen[0]) and keep_b.has(seen[1]), "a cycle walks the rotation in turn", str(seen))

	var host := CommandHost.new()
	var bound: DotResult = vote.call("install_commands", host) if vote != null else null
	_check(bound != null and bound.ok and host.added.has("rockit") and not host.added.has("rtv"),
		"and a renamed rtv is registered under its new name", ", ".join(host.added.keys().slice(0, 6)))
	host.free()

	# No file: every bowl rotates, as it always did.
	game.rotation_file = null
	game.apply_rotation()
	_check(game.rotating_ids().size() == BfhBowls.allowed(game.config).size() and game.in_rotation(&"bfh_big_bowl"),
		"with no file every bowl is in the rotation")

	# Put the world back: the later sections share this bowl.
	game.rotation_file = kept
	game.apply_rotation()
	game.next_bowl_id = before
	game._change_bowl()
	if vote != null:
		vote.call("refresh_bowls")
		director.begin(game.bowl_id)
	_done()


## [b]`time_up: finish_round` waits for a round being played, never for warmup.[/b] The game
## hands dot-vote its match's answer (`round_in_progress_fn`); without it a limit that ran out
## in warmup held the change for `finish_round_max_sec` over a round that had not started.
## Run on a director of its own carrying the game's own hook, so the real vote's clock is
## untouched; the match's state is set by hand and put back.
func _test_finish_round_waits_for_a_live_round() -> void:
	print("finish_round waits for a live round, not warmup")
	var module := _module()
	var vote: Node = module.get("vote") if module != null else null
	var director: DotVoteDirector = vote.get("director") if vote != null else null
	var hook: Variant = director.get("round_in_progress_fn") if director != null else null
	_check(hook is Callable and (hook as Callable).is_valid(), "the game tells its vote whether a round is live")

	if not (hook is Callable and (hook as Callable).is_valid()) or game == null or game.match_node == null:
		_done()
		return

	var match_node: DotMatch = game.match_node
	var was := match_node.state
	match_node.state = DotMatch.State.WARMUP
	var warm_applied := []
	var warm := _finish_round_probe(hook, warm_applied)
	_check(warm_applied == [&"b"] and not warm.is_finishing_round(),
		"in warmup a time limit with finish_round changes at once", str(warm_applied))

	match_node.state = DotMatch.State.LIVE
	var live_applied := []
	var live := _finish_round_probe(hook, live_applied)
	_check(live_applied.is_empty() and live.is_finishing_round(),
		"during a live round it waits for the round", str(live_applied))

	match_node.state = DotMatch.State.INTERMISSION
	live.advance(0.1)
	_check(live_applied == [&"b"], "and the round ending is the change", str(live_applied))

	match_node.state = was
	warm.queue_free()
	live.queue_free()
	_done()


## A director under `time_up: finish_round` carrying [param hook], its clock run out with a
## winner already decided: what dot-vote's own suite builds, with the game's answer in it.
func _finish_round_probe(hook: Callable, applied: Array) -> DotVoteDirector:
	var source := DotVoteListSource.new()
	var _a := source.add(DotVoteChoice.of(&"a", "A"))
	var _b := source.add(DotVoteChoice.of(&"b", "B"))
	source.apply_fn = func(id: StringName) -> DotResult:
		applied.append(id)
		return DotResult.success(id)

	var rules := DotVoteRules.new()
	rules.apply_delay_sec = 0.0
	rules.duration_sec = 100.0
	rules.vote_lead_sec = 40.0
	rules.vote_duration_sec = 5.0
	rules.include_extend = false
	rules.apply = DotVoteRules.Apply.END_OF_TIME
	rules.cooldown = 0
	rules.time_up = DotVoteRules.TimeUp.FINISH_ROUND
	# For ever: only the hook may release it.
	rules.finish_round_max_sec = 0.0

	var probe := DotVoteDirector.new()
	probe.rules = rules
	probe.source = source
	probe.register_service = false
	probe.self_advance = false
	probe.round_based = true
	probe.player_count_fn = func() -> int: return 4
	probe.set(&"round_in_progress_fn", hook)
	add_child(probe)
	probe.begin(&"a")
	source.current = &"a"

	for i in range(61):
		probe.advance(1.0)

	probe.cast_one(&"p1", &"b")

	# The ballot closes, then the limit (100 s) runs out with the winner decided.
	for i in range(46):
		probe.advance(1.0)

	return probe



func _test_the_commands() -> void:
	print("the console")

	_check(server.console.find_command("bfh_status") != null, "`bfh_status` is registered")
	_check(server.console.find_command("bfh_net") != null, "and `bfh_net`")

	var status := _run_command("bfh_status")
	_check(_said(status, "round"), "`bfh_status` says what the round is")
	_check(_said(status, "crates"), "and how much cover is left")

	var netstat := _run_command("bfh_net")
	_check(_said(netstat, "bodies"), "`bfh_net` says what is being replicated")
	_done()


func _test_the_tunables() -> void:
	print("the tunables")

	var cvar := server.console.find_cvar("bfh_round_seconds")
	_check(cvar != null, "`bfh_round_seconds` is a cvar")

	if cvar == null:
		_check(false, "its default is the value the world was built with")
		_check(false, "and setting it reaches the world")
		_check(false, "and the match's round clock, which is what ends a round")
		_check(false, "a bus's top speed is tunable too")
		_done()
		return

	_check(
		absf(cvar.get_float() - game.config.round_seconds) < 0.01,
		"its default is the value the world was built with, not a second copy",
		"cvar %.1f, world %.1f" % [cvar.get_float(), game.config.round_seconds]
	)

	_run_command("bfh_round_seconds 90")
	_check(
		absf(game.config.round_seconds - 90.0) < 0.01,
		"and setting it reaches the world",
		"%.1f" % game.config.round_seconds
	)
	# The config is what the HUD counts down; dot-match's rule is what ends the round. The cvar
	# once wrote only the first, and an owner's short round ran the built-in 180 s.
	_check(
		absf(game.match_node.rules.time_limit_sec - 90.0) < 0.01,
		"and the match's round clock, which is what ends a round",
		"%.1f" % game.match_node.rules.time_limit_sec
	)

	_run_command("bfh_bus_top_speed 18")
	_check(
		absf(game.config.bus_top_speed - 18.0) < 0.01,
		"a bus's top speed is tunable too",
		"%.1f" % game.config.bus_top_speed
	)
	_done()


# --- It actually plays -----------------------------------------------------

func _test_the_round_runs() -> void:
	print("a round with nobody on it")

	var module := _module()

	if module == null:
		_check(false, "the module is loaded")
		_check(false, "the bowl was laid out when the module loaded")
		_check(false, "the module ticks the world")
		_check(false, "and the round clock runs on an empty server")
		_done()
		return

	_check(true, "the module is loaded")
	_check(
		game.props.world_count() > 0,
		"the bowl was laid out when the module loaded",
		"%d props" % game.props.world_count()
	)

	var before := int(module.get("tick"))
	var clock_before := game.round_elapsed

	for _i in range(20):
		await get_tree().physics_frame

	_check(
		int(module.get("tick")) > before,
		"the module ticks the world",
		"%d ticks" % (int(module.get("tick")) - before)
	)
	# [b]An empty server, and the clock still has to run.[/b] A world that only ticked
	# when somebody was connected is one whose round stops between players, and what an
	# operator sees when they connect is a server that looks hung.
	_check(
		game.round_elapsed > clock_before,
		"and the round clock runs on an empty server",
		"%.2f s" % (game.round_elapsed - clock_before)
	)
	_done()


## The seats fill themselves, because this game has nothing for one side alone.
##
## [b]Asymmetric games are the reason this is here.[/b] A deathmatch with nobody on it is
## a map somebody can walk around; this is a bowl with nothing in it to run away from, and
## `sides_are_playable` correctly refuses to start a round — so the first visitor to an
## empty server would watch a clock that never moves and leave.
func _test_the_bots() -> void:
	print("an empty server fills its buses")

	# The module checks every couple of seconds rather than every tick, so this waits for
	# one of those rather than for a frame.
	var deadline := Time.get_ticks_msec() + 6000

	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame

		if game.drivers().size() >= game.config.driver_count:
			break

	_check(
		game.drivers().size() == game.config.driver_count,
		"every driving seat is taken",
		"%d of %d" % [game.drivers().size(), game.config.driver_count]
	)

	var all_bots := true

	for driver in game.drivers():
		if not driver.is_bot:
			all_bots = false

	_check(all_bots, "and every one of them by a bot, since nobody else is here")

	# [b]Replicated like anybody else, which is the whole reason a bot needs a session
	# id.[/b] A player id that is not `u<session>` parses back to zero — one table entry
	# for every bot, and a join addressed to dot-net's broadcast peer.
	var module := _module()
	_check(
		module != null and int(module.get("bridge").call("describe")["players"])
			== game.drivers().size(),
		"each of them replicated exactly like a person"
	)

	# [b]A person who takes a seat takes it from a bot, and leaving gives it back[/b]:
	# DotBotQuota's fill mode, counted in driving seats. One bot in two seats leaves one
	# free, so a person added through the bridge (peer zero, the way a test's player is)
	# joins into it as a driver, once somebody is already on foot: the first person on a
	# server runs, because a bot cannot. The roster check is called rather than waited for,
	# so nothing else moves under the count.
	_check(server.console.find_cvar("bot_quota") != null and server.console.find_cvar("bot_quota_mode") != null,
		"the shared bot_quota cvars are registered")

	# Free roam: dot-spectate's three cvars are bound on the module, and a console change
	# reaches the rules the world's spectator manager runs.
	var roam_rules: DotSpectatorRules = game.spectate.manager.rules if game.spectate != null else null
	var _roam_off := _run_command("mp_freeroam 0")
	var roam_reached := roam_rules != null and not roam_rules.roaming_permitted()
	var _roam_on := _run_command("mp_freeroam 1")
	_check(
		server.console.find_cvar("mp_freeroam") != null and server.console.find_cvar("mp_forcecamera") != null
		and server.console.find_cvar("mp_freeroam_speed") != null and roam_reached
		and roam_rules.roaming_permitted(),
		"mp_freeroam, mp_forcecamera and mp_freeroam_speed are cvars, and mp_freeroam reaches the spectator rules"
	)

	var bridge: Object = module.get("bridge") if module != null else null

	if module != null and bridge != null:
		var _one := _run_command("bot_quota 1")
		module.call("_keep_the_seats_full")
		var bots_before := _bot_drivers()
		var on_foot: DotResult = bridge.call("add_player", 0, 9002, "On foot")
		var first_runs: bool = on_foot.ok and game.team_of(BfhNetBridge.player_key(9002)) == BfhGame.TEAM_RUNNERS
		_check(first_runs, "the first person on a server of bots runs, because a bot cannot",
			"a server with only bots driving and a person in a seat never starts a round")
		var joined: DotResult = bridge.call("add_player", 0, 9001, "Person")
		module.call("_keep_the_seats_full")
		var bots_with := _bot_drivers()
		_check(joined.ok and bots_before == 1 and bots_with == 0
			and game.drivers().size() == 1 and not game.drivers()[0].is_bot,
			"a person taking a seat takes it from a bot", "%d -> %d" % [bots_before, bots_with])
		bridge.call("remove_player", 9001)
		bridge.call("remove_player", 9002)
		module.call("_keep_the_seats_full")
		var bots_after := _bot_drivers()
		_check(bots_after == bots_before, "and the bot comes back when they leave",
			"%d -> %d" % [bots_with, bots_after])
		var _all := _run_command("bot_quota %d" % game.config.driver_count)
		module.call("_keep_the_seats_full")
		var names: Array = []
		for driver in game.drivers():
			if driver.is_bot:
				names.append(driver.display_name)
		_check(not names.is_empty() and names.all(func(n: String) -> bool: return DotBotNames.POOL.has(n)),
			"bots are named from dot-bot's pool, not \"Bus driver\"", str(names))
		var picked := _run_command("bot_difficulty nightmare")
		var reached := DotBotSettings.of(game).difficulty() == "nightmare"
		var _back := _run_command("bot_difficulty medium")
		_check(reached, "bot_difficulty is a cvar, and reaches the world the bots drive from", str(picked))
	else:
		_check(false, "the first person on a server of bots runs, because a bot cannot", "no module")
		_check(false, "a person taking a seat takes it from a bot", "no module")
		_check(false, "and the bot comes back when they leave", "no module")
		_check(false, "bots are named from dot-bot's pool, not \"Bus driver\"", "no module")
		_check(false, "bot_difficulty is a cvar, and reaches the world the bots drive from", "no module")

	_run_command("bfh_bots 0")

	for _i in range(int(3.0 * TICK_RATE)):
		await get_tree().physics_frame

	_check(_bot_drivers() == 0, "and an operator can turn them off, which takes them out",
		"%d left" % _bot_drivers())
	# Back on, and refilled now rather than at the next check: the sections after this one
	# need every seat taken, so that the person they add joins on foot.
	_run_command("bfh_bots 1")

	if module != null:
		module.call("_keep_the_seats_full")

	_done()


func _bot_drivers() -> int:
	var n := 0

	for driver in game.drivers():
		if driver.is_bot:
			n += 1

	return n


## Chat, voice and moderation, as a module actually builds them.
##
## [b]The netcode suite drives the routers directly; this is the other half.[/b] What is
## being checked here is that [DotGameModule] found the layer, that [DotGameServices]
## built all three in the right order, and that the operator's own surface — `bfh_say`, an
## admission check, a describe line — is there. The ordering is the part with a bug behind
## it: moderation publishes the mute source both routers look up when they START, and a
## chat router built first enforces no gag for the life of the server.
func _test_the_services() -> void:
	print("chat, voice and moderation")

	var module := _module()
	var services: Object = module.get("services") if module != null else null

	_check(services != null, "the module built a services layer")

	if services == null:
		_check(false, "with chat on it")
		_check(false, "and voice")
		_check(false, "and moderation, which has to be built first")
		_check(false, "`bfh_say` is registered")
		_check(false, "and it says something")
		_check(false, "admission asks moderation")
		_done()
		return

	_check(services.get("chat") != null, "with chat on it")
	_check(services.get("voice") != null, "and voice")
	_check(services.get("moderation") != null, "and moderation, which has to be built first")

	# [b]The order, asserted through its consequence rather than through a call log.[/b] A
	# router that started before moderation warns once about a missing mute source and then
	# enforces nothing; what says it went right is that the router can SEE the source.
	_check(
		DotRegistry.get_service(DotGameServices.MUTE_SERVICE) != null,
		"the mute source is registered, which is the only thing that makes a gag work"
	)

	_check(server.console.find_command("bfh_say") != null, "`bfh_say` is registered")

	var said := _run_command("bfh_say the server is restarting in a minute")
	_check(
		_said(said, "restarting"),
		"and it says something",
		" | ".join(said)
	)

	# Nobody is connected, so this is the shape of the answer rather than a real refusal —
	# and the shape is what matters: a services layer that returned a failure here would
	# refuse every join on a server with an empty punishment list.
	var session := DotClientSession.new()
	session.userid = 4242
	session.display_name = "Ada"
	_check(
		services.call("check_admission", session).ok,
		"admission asks moderation and lets an unpunished player in"
	)
	_done()


## dot-moderation's live tools, built by dot-game's services layer BY PATH, with this
## game's verbs in them — the first game to get them from the shared layer rather than
## writing its own.
##
## A runner joins through the roster the way a real client does (an adopted session and
## the `client_spawn` dot-server fires), and the commands go through the console. What is
## asserted is the body: noclipped, then dead. And the refusals, which are this game's to
## explain: a runner who is out stays out, and there is nothing to give.
func _test_the_live_tools() -> void:
	print("the moderator's live tools")

	var module := _module()
	var services: Object = module.get("services") if module != null else null
	var tools: Object = services.get("mod_tools") if services != null else null

	_check(tools != null, "dot-game built dot-moderation's live tools, by path")
	_check(
		server.console.find_command("noclip") != null and server.console.find_command("slay") != null,
		"and put their commands on the console"
	)

	if tools == null or module == null:
		for what in ["a runner joins", "noclip", "off", "slay", "respawn refused",
				"give refused", "blind", "on the entity", "timed blind", "lifts", "beacon",
				"a round keeps both", "nothing refused", "describe", "forgotten on leave"]:
			_check(false, what)
		_done()
		return

	# An adopted session has no peer, so the netcode's own sends to it would be an engine
	# RPC error per tick. Pointed at nothing for this section; the module is rebuilt with
	# its own manager when the next section reloads it.
	var net: DotNetManager = module.get("net")
	var previous_send := net.send_fn
	net.send_fn = func(_peer: int, _payload: PackedByteArray, _delivery: int) -> void:
		pass

	var session := DotClientSession.new()
	session.peer_id = 5151
	session.userid = 515
	session.display_name = "Runner"
	var _adopted := server.adopt_session(session)
	server.events.fire("client_spawn", {"userid": 515, "name": "Runner"})

	var runner: Object = game.players.get(&"u515")
	_check(runner != null and not bool(runner.get("riding")), "a runner joins through the roster, on foot")

	if runner == null:
		for what in ["noclip", "off", "slay", "respawn refused", "give refused", "blind",
				"on the entity", "timed blind", "lifts", "beacon", "a round keeps both",
				"nothing refused", "describe", "forgotten on leave"]:
			_check(false, what)
		net.send_fn = previous_send
		_done()
		return

	var controller: DotFpsController = runner.get("controller")
	var health: DotHealth = runner.get("health")

	# Each body is looked at the moment the command returns, not after a frame. A lone
	# runner makes the sides playable, so a round can start under this section — and a
	# round start is a new body here, which is exactly when the tools switch a noclip off
	# and the game stands a slain runner back up. The first run of this section asserted a
	# frame late and failed all three for that reason, with every command having worked.
	var noclipped := await _run_and_look("noclip Runner",
		func() -> bool: return DotFpsAdminModifiers.is_noclipped(controller))
	_check(bool(noclipped[1]), "`noclip Runner` puts them in noclip", " | ".join(noclipped[0]))

	var landed := await _run_and_look("noclip Runner off",
		func() -> bool: return not DotFpsAdminModifiers.is_noclipped(controller))
	_check(bool(landed[1]), "and `noclip Runner off` takes it away")

	var _god := await _run_command_later("god Runner")
	var slain := await _run_and_look("slay Runner", func() -> bool: return not health.alive)
	_check(bool(slain[1]), "`slay` kills them through god mode, as ordinary damage", " | ".join(slain[0]))

	# Only the refusal is asserted, not that they stay down: with one runner, the slay above
	# ended the round, and the next one stands everybody up — which is the game, and is
	# exactly the "next round" the refusal names.
	var respawned := await _run_command_later("respawn Runner")
	_check(
		_said(respawned, "next round"),
		"`respawn` is refused with this game's reason",
		" | ".join(respawned)
	)

	var given := await _run_command_later("give Runner rifle")
	_check(_said(given, "hammer"), "`give` says why there is nothing to give", " | ".join(given))

	# Blind and beacon: a flag each on the player, set here and drawn by the client. What a
	# client sees of them is `headless_net`'s, and what they look like is `tools/shot.sh`'s.
	var blinded := await _run_command_later("blind Runner")
	_check(bool(runner.get("blinded")), "`blind Runner` blacks their screen out", " | ".join(blinded))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var behaviour: Object = runner.get_node_or_null("Net")
	_check(
		behaviour != null and bool(behaviour.get("net_blind")),
		"and it is on the entity the netcode sends them"
	)

	# A blind is a spell: dot-moderation lifts it through the same handler when the time
	# is up, so what is checked is the flag and not the timer.
	var _lift := await _run_command_later("blind Runner off")
	var _spell := await _run_command_later("blind Runner 0.2")
	_check(bool(runner.get("blinded")), "`blind Runner 0.2` blinds them for a fifth of a second")
	await get_tree().create_timer(0.4).timeout
	_check(not bool(runner.get("blinded")), "and it lifts on its own when the time is up")

	var lit := await _run_command_later("beacon Runner")
	_check(bool(runner.get("beacon")), "`beacon Runner` marks them for everybody", " | ".join(lit))

	# A round is everybody's new body here, and both are about the person rather than the
	# body: a round ending is what a player being punished would otherwise wait out. The
	# noclip is the control — it must end, or this is not a new body at all.
	var _dark := await _run_command_later("blind Runner")
	var _fly := await _run_command_later("noclip Runner")
	services.call("_on_round_began_for_tools", 99)
	_check(
		bool(runner.get("blinded")) and bool(runner.get("beacon"))
		and not DotFpsAdminModifiers.is_noclipped(controller),
		"a new round keeps blind and beacon, and ends the noclip"
	)
	var _unlit := await _run_command_later("beacon Runner off")
	var _light := await _run_command_later("blind Runner off")

	var described := await _run_command_later("modtools")
	_check(
		_said(described, "abilities") and _said(described, "refused"),
		"`modtools` lists what this game supports and what it refuses"
	)
	var refusals := PackedStringArray()
	for line in described:
		if line.findn("blind (") >= 0 or line.findn("beacon (") >= 0:
			refusals.append(line)
	_check(
		_said(described, "blind") and _said(described, "beacon") and refusals.is_empty(),
		"and blind and beacon are among what it supports, not what it refuses",
		" | ".join(described)
	)

	# Leaving forgets them: the next player given this userid must not inherit a god mode.
	module.get("roster").call("remove", session)
	var _released := server.release_session(session.peer_id)
	_check(
		(tools.call("active_on", &"515") as PackedStringArray).is_empty(),
		"and a player who leaves takes nothing of theirs with them"
	)

	net.send_fn = previous_send
	_done()


## Runs a line, asks [param look] about the world at once, then waits for the reply.
func _run_and_look(line: String, look: Callable) -> Array:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, context)
	var seen: Variant = look.call()
	await get_tree().process_frame
	await get_tree().process_frame
	return [PackedStringArray(captured), seen]


## [method _run_command], for a command whose handler is a coroutine — the live tools
## record every action on a punishment store, which may be a remote one, so the reply can
## arrive a frame after the command returned.
func _run_command_later(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, context)
	await get_tree().process_frame
	await get_tree().process_frame
	return PackedStringArray(captured)


func _test_it_unloads_cleanly() -> void:
	print("unloading")

	var unloaded := server.modules.unload_module("buses")
	_check(unloaded.ok, "the module unloads", str(unloaded.error) if not unloaded.ok else "")
	_check(_module() == null, "and the host forgets it")
	_check(
		server.console.find_command("bfh_status") == null,
		"its commands go with it"
	)
	_check(
		server.console.find_cvar("bfh_round_seconds") == null,
		"and so do its cvars"
	)
	_check(
		server.console.find_command("bfh_say") == null,
		"including the ones the services layer answers"
	)
	# The live tools bind to the server's console, which outlives the services layer; a
	# command left behind would call into a freed object on the next `noclip`.
	_check(
		server.console.find_command("noclip") == null,
		"and the live tools' commands, which the services layer bound to the console"
	)

	# [b]The world is NOT the module's to free.[/b] It was in the tree before the module
	# loaded and a server can reload a game module without the bowl going away — which is
	# what `module reload` is for, and what an operator does after editing a config.
	_check(
		is_instance_valid(game) and game.is_inside_tree(),
		"the world outlives the module that was driving it"
	)

	var again: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	_check(again.ok, "and it loads again onto the same world",
		again.error.message if not again.ok else "")
	_check(
		server.console.find_command("bfh_status") != null,
		"with its commands back"
	)
	_check(
		server.console.find_command("noclip") != null,
		"the live tools' among them, rather than refused as taken"
	)
	_done()


## A module reload must leave ONE link under the server, still named for the client's route,
## and a real client must still be sent to over it.
##
## [b]Over a real socket, because the loopback cannot see it.[/b] Before the bridge opened its
## link through [DotGameLink], every load added another under the server, Godot renamed the
## live one `@Node@n`, and an RPC to a real client found no node at that path and vanished
## without an error. Reloaded twice here, before the client joins.
func _test_a_reload_leaves_one_live_link() -> void:
	print("")
	print("a module reload leaves one live link")

	for _i in range(2):
		_check(server.modules.unload_module("buses").ok, "the module unloads")
		_check((await server.modules.load_module("res://game/bfh_module.gd")).ok, "and loads again")
	await get_tree().process_frame
	await get_tree().process_frame

	var links := 0
	for child in server.get_children():
		if child is BfhNetLink:
			links += 1
	_check(links == 1 and server.has_node(NodePath(String(BfhNetLink.NODE_NAME))),
		"exactly one link, under the name the client routes to (%d)" % links)

	var known: Dictionary = {}
	for each in server.playing_sessions():
		known[each.userid] = true

	var side := Node.new()
	side.name = "ReloadClient"
	add_child(side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), side.get_path())
	var mirror := Node.new()
	mirror.name = name
	side.add_child(mirror)
	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Reload"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % server.config.port
	mirror.add_child(link)
	link.connect_to_server("127.0.0.1:%d" % server.config.port)

	var seat: Array = [null]
	for _i in 1800:
		await get_tree().physics_frame
		for each in server.playing_sessions():
			if not known.has(each.userid):
				seat[0] = each
		if seat[0] != null:
			break
	_check(seat[0] != null, "a real client joins the reloaded server", str(link.last_error))

	var heard := false
	var receiver := BfhNetLink.new()
	if seat[0] != null:
		# What the game's client holds at the same path, added once joined: the link frees
		# the children of the game it replaces when the server names its own.
		receiver.name = BfhNetLink.NODE_NAME
		link.add_child(receiver)
		var live: BfhNetLink = server.get_node(NodePath(String(BfhNetLink.NODE_NAME)))
		for _i in 300:
			live.send_event(seat[0].peer_id, PackedByteArray([0]))
			await get_tree().physics_frame
			if receiver.events_received > 0:
				heard = true
				break
	_check(heard, "and hears the server's events over the link", str(receiver.events_received))

	link.disconnect_from_server("done")
	await get_tree().physics_frame
	side.queue_free()
	_done()


# --- Exiting clean ----------------------------------------------------------------

## The flag this suite hands the copy of itself it runs. See [method _run_exit_probe].
const EXIT_PROBE_FLAG := "--exit-probe"

## What the exit probe adds to a run — one section, these checks — and the copy does not.
const EXIT_PROBE_CHECKS := 3


## How long the copy may run before it is killed and this probe fails. A copy that is still
## running this long after it started is hung, and the likeliest reason is the one that says
## nothing at all: a scene whose script failed to parse never reaches `quit()` and prints
## nothing. `-- --exit-probe-seconds N` lowers it, which is how the deadline itself is armed —
## any N shorter than the suite takes is a copy that is still running when it expires.
const EXIT_PROBE_SECONDS := 300


func _is_exit_probe() -> bool:
	return EXIT_PROBE_FLAG in OS.get_cmdline_user_args()


func _exit_probe_seconds() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--exit-probe-seconds")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		return maxi(1, args[at + 1].to_int())
	return EXIT_PROBE_SECONDS


## Runs this same suite in a fresh process: `[exit code, its stdout, its stderr, whether it
## had to be killed, the seconds it was allowed]`.
##
## [b]A leak is reported after `quit()`, by the engine, where nothing in the process that
## leaked can read it.[/b] "N ObjectDB instances were leaked at exit" is printed once the
## scene tree is gone, so the only process that can check a run's exit is another one. On
## Godot 4.7.2 a script that names itself, loaded after its base, cuts the engine's exit
## teardown short and every script loaded before it is reported leaked — hundreds of lines
## a passing run printed for weeks, which is why this is a check now and not a warning.
##
## [b]First, before this run opens a port[/b], so the two never contend for a socket — and
## so this run is always the second one against the same `user://`, which is the other
## thing no single run can see.
##
## [b]Not `OS.execute`.[/b] That blocks until the copy exits, so a copy that hangs held this
## run for ever; and when the outer `timeout` then killed this run, the copy was left behind
## holding the suite's directory and port. So the copy is started, polled against a deadline
## and killed at it. Two deadlines, because Godot dies on SIGTERM without running a line of
## script — nothing in this process can clean up after it is killed:
##
## - coreutils `timeout` wraps the copy where it exists. It is an exec wrapper, not a shell,
##   and it outlives this process, so a copy orphaned by the outer `timeout` still dies on
##   time. Its exit status 124 is how its expiry is recognised.
## - this loop's own deadline, a little later, for a platform without it.
##
## `execute_with_pipe` rather than `create_process`, because the latter captures nothing and
## the whole point is reading what the copy printed. Non-blocking, and drained on every pass
## rather than once at the end: a pipe holds 64 KiB, and a copy that fills it blocks on its
## next print — a hang this probe would then report as the suite's own. The copy's stdin is
## the other end of a pipe this process holds open, which is why every suite turns the
## server's stdin console off: a reader blocked on it never lets the copy exit.
func _run_exit_probe() -> Array:
	var seconds := _exit_probe_seconds()
	print("(running this suite once more in a fresh process, to read what it leaves at exit — %d s allowed)" % seconds)
	var scene := scene_file_path if scene_file_path != "" else "res://examples/dedicated.tscn"
	var exe := OS.get_executable_path()
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		scene, "--", EXIT_PROBE_FLAG,
	])
	var wrapped := false
	for wrapper: String in ["/usr/bin/timeout", "/bin/timeout"]:
		if FileAccess.file_exists(wrapper):
			var outer := PackedStringArray(["--kill-after=10", str(seconds), exe])
			outer.append_array(args)
			exe = wrapper
			args = outer
			wrapped = true
			break

	var proc := OS.execute_with_pipe(exe, args, false)
	if proc.is_empty():
		return [-1, "", "could not start %s" % exe, false, seconds]
	var pid: int = proc["pid"]
	var pipes: Array[FileAccess] = [proc["stdio"], proc["stderr"]]
	var bytes: Array[PackedByteArray] = [PackedByteArray(), PackedByteArray()]
	var deadline := Time.get_ticks_msec() + (seconds + 30) * 1000
	var hung := false
	while OS.is_process_running(pid):
		_drain_exit_probe(pipes, bytes)
		if Time.get_ticks_msec() > deadline:
			OS.kill(pid)
			hung = true
			break
		await get_tree().create_timer(0.1).timeout
	# Once more after it exits: what it wrote between the last pass and its exit is still in
	# the pipe, and the leak report is always the last thing it writes.
	_drain_exit_probe(pipes, bytes)

	# OS.kill has already reaped it, and asking for the exit code of a reaped pid is an error.
	var code := -1 if hung else OS.get_process_exit_code(pid)
	if wrapped and code == 124:
		hung = true
	return [code, bytes[0].get_string_from_utf8(), bytes[1].get_string_from_utf8(), hung, seconds]


func _drain_exit_probe(pipes: Array[FileAccess], bytes: Array[PackedByteArray]) -> void:
	for i in pipes.size():
		while true:
			var chunk := pipes[i].get_buffer(65536)
			if chunk.is_empty():
				break
			bytes[i].append_array(chunk)


func _test_exits_clean(probe: Array) -> void:
	print("exiting clean, as a second process saw it")

	var code: int = probe[0]
	var stdout: String = probe[1]
	var stderr: String = probe[2]
	var hung: bool = probe[3]
	var seconds: int = probe[4]
	# Every leak line is the engine's, and the engine writes them to stderr; both are
	# searched so that stays a fact about the engine rather than an assumption here. Shown
	# apart, because a pipe each is two streams whose interleaving is lost, and where a hung
	# copy had got to is the end of its stdout.
	var text := stdout + "\n" + stderr
	var tail := "its last lines:\n%s\nand the last on stderr:\n%s" % [
		_last_lines(stdout, 15), _last_lines(stderr, 10)
	]

	# A copy that was killed never reached its exit, so neither of the last two was seen, and
	# passing them on an absence of lines would be passing them blind.
	var passes_detail := ""
	if hung:
		passes_detail = ("still running after %d s, so it was killed — a scene that failed to "
			+ "parse, or a thread still blocked when it quit; %s") % [seconds, tail]
	elif code != 0:
		passes_detail = "exit %d; %s" % [code, tail]
	_check(not hung and code == 0, "this suite, run again in a fresh process, passes",
		passes_detail)
	_check(not hung and not text.contains("leaked at exit"), "and leaves no object alive at exit",
		"it was killed before it reached its exit" if hung else _line_with(text, "leaked at exit"))
	_check(not hung and not text.contains("still in use at exit"), "and no resource",
		"it was killed before it reached its exit" if hung else _line_with(text, "still in use at exit"))
	_done()


func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return ""


func _last_lines(text: String, count: int) -> String:
	var lines := text.strip_edges().split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - count)))


## [b]A runner behind its loading cover is not run over, and is once the cover lifts.[/b] A real
## [DotClientLink] joins over the server's ENet socket and says nothing, as a client still
## loading its level does. A bus hit and a barrel's blast must do nothing to it; an operator's
## damage (a slay or slap goes straight to dot-combat) still lands. The client then sends
## `game.cover` on the real wire and the same hits land.
func _test_loading_cover() -> void:
	print("")
	print("a client behind its loading cover is not harmed")

	var module := _module()
	var roster: DotGameRoster = module.get("roster") if module != null else null

	var known: Dictionary = {}
	for each in server.playing_sessions():
		known[each.userid] = true

	var side := Node.new()
	side.name = "CoverClient"
	add_child(side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), side.get_path())
	# Under a node named like this suite's own, so the RPC path the server sends
	# ("Dedicated/Server") resolves in the client's separate multiplayer tree too.
	var mirror := Node.new()
	mirror.name = name
	side.add_child(mirror)
	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Cover"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % server.config.port
	mirror.add_child(link)
	link.connect_to_server("127.0.0.1:%d" % server.config.port)

	var seat: Array = [null]
	for _i in 1800:
		await get_tree().physics_frame
		for each in server.playing_sessions():
			if not known.has(each.userid) and game.players.has(StringName("u%d" % each.userid)):
				seat[0] = each
		if seat[0] != null:
			break

	_check(seat[0] != null and roster != null, "a real client joins over the socket", str(link.last_error))

	if seat[0] == null or roster == null:
		for what in ["held as loading", "a bus hit", "a blast", "an operator's damage", "the cover report",
				"a bus hit after", "a blast after", "bots and strangers", "leaving"]:
			_check(false, "%s (no runner joined)" % what)
		link.disconnect_from_server("done")
		side.queue_free()
		_done()
		return

	var userid: int = seat[0].userid
	var key := StringName("u%d" % userid)
	var runner: BfhPlayer = game.players[key]
	var health: DotHealth = runner.health
	health.invulnerable = false
	health.cannot_die = false
	health.invulnerable_until_tick = -1
	_check(roster.is_loading(userid), "the server holds the seat as loading from its spawn", str(roster.describe()))

	var at := runner.global_position
	var before := health.health
	game._bus_hit(runner, &"", 3.0, Vector3.FORWARD)
	_check(health.health == before, "a bus hit does nothing to it", "%s -> %s" % [before, health.health])

	game._on_prop_exploded(at, 6.0, 5.0, 0.0, &"")
	_check(health.health == before, "and neither does a barrel's blast", "%s -> %s" % [before, health.health])

	game.combat.apply_damage(DotDamage.make(0, runner.entity_id, 1.0, null))
	_check(health.health < before, "an operator's damage still lands", "%s -> %s" % [before, health.health])

	DotGameClient.report_cover(link, false)
	var lifted := false
	for _i in 900:
		await get_tree().physics_frame
		if not roster.is_loading(userid):
			lifted = true
			break
	_check(lifted, "its cover report crosses the wire and ends the loading state")

	var after_lift := health.health
	game._bus_hit(runner, &"", 3.0, Vector3.FORWARD)
	_check(health.health < after_lift, "and the same bus hit now lands", "%s -> %s" % [after_lift, health.health])

	var after_bus := health.health
	game._on_prop_exploded(at, 6.0, 5.0, 0.0, &"")
	_check(health.health < after_bus, "and so does the blast", "%s -> %s" % [after_bus, health.health])

	_check(not bool(game.loading_fn.call(&"bot7")) and not bool(game.loading_fn.call(&"u99999")),
		"a bot, or a seat the roster does not hold, is never loading")

	link.disconnect_from_server("done")
	var gone := false
	for _i in 900:
		await get_tree().physics_frame
		if not game.players.has(key):
			gone = true
			break
	_check(gone and not roster.is_loading(userid), "it leaves and the roster forgets it")
	side.queue_free()
	_done()


## Statistics, achievements and the spectator camera, as a server's world builds them.
##
## [b]What the other two suites cannot say: that a world built by a module under a real
## `DotServer` has both, and that the operator can read them.[/b] A runner joins through the
## roster the way a client does, breaks a crate, and `bfh_stats` reports it; a bot is not
## counted; a slain runner is put on a death camera by the server's own world; and a leaver
## is forgotten by the counters.
func _test_progress_and_spectating() -> void:
	print("statistics, achievements and where the out look")

	var module := _module()
	_check(
		game.progress != null and game.spectate != null and game.spectate.manager.authoritative,
		"the server's world counts, and decides where a runner who is out looks"
	)
	_check(server.console.find_command("bfh_stats") != null, "`bfh_stats` is registered")

	if module == null or game.progress == null or game.spectate == null:
		for what in ["counted", "detail", "bots", "death camera", "forgotten"]:
			_check(false, what)
		_done()
		return

	var net: DotNetManager = module.get("net")
	var previous_send := net.send_fn
	net.send_fn = func(_peer: int, _payload: PackedByteArray, _delivery: int) -> void:
		pass

	var session := DotClientSession.new()
	session.peer_id = 6161
	session.userid = 616
	session.display_name = "Tally"
	var _adopted := server.adopt_session(session)
	server.events.fire("client_spawn", {"userid": 616, "name": "Tally"})

	var runner: BfhPlayer = game.players.get(&"u616")

	if runner == null or runner.hammer == null:
		for what in ["counted", "detail", "bots", "death camera", "forgotten"]:
			_check(false, "%s (no runner joined)" % what)
		net.send_fn = previous_send
		_done()
		return

	# A crate where the runner is looking, broken by the hammer the world gave them.
	var eye := runner.eye_position()
	var aim := runner.aim_direction()
	var crate := game.props.spawn(BfhContent.CRATE, &"world", eye + aim * 1.4 - Vector3(0.0, 0.5, 0.0))
	crate.body().freeze = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _i in range(3):
		runner.hammer.cooldown = 0.0
		runner.hammer.swing(
			game, eye, ((crate.body().global_position) - eye).normalized(),
			game.props, game.prop_damage, game.carry, runner.player_id, 0xFFFFFFF
		)

	var everybody := _run_command("bfh_stats")
	_check(
		not crate.is_alive() and _said(everybody, "Tally") and _said(everybody, "broken 1"),
		"a runner who broke a crate is on `bfh_stats`, with it counted",
		" | ".join(everybody)
	)

	var detail := _run_command("bfh_stats 616")
	_check(
		_said(detail, "Crates broken") and _said(detail, "Rounds survived"),
		"and `bfh_stats <userid>` prints all five of their numbers",
		" | ".join(detail)
	)

	var bot := game.drivers()[0] if not game.drivers().is_empty() else null
	# The userid spelled out rather than through `BfhNetBridge.session_of`: this suite does
	# not preload the netcode, because loading it before the module does is what hides the
	# leak `_test_no_message_preloads_itself` is about. See docs/gdscript-hazards.md.
	var bot_line := _run_command(
		"bfh_stats %s" % String(bot.player_id).trim_prefix("u") if bot != null else "bfh_stats 1"
	)
	_check(
		bot != null and bot.is_bot and _said(bot_line, "not counted"),
		"a bot driver is not counted, so a server's numbers are its people's",
		" | ".join(bot_line)
	)

	# Looked at the moment the command returns: a lone runner slain ends the round on the
	# next tick, and the next round is a new body that stops the camera.
	var slain := await _run_and_look("slay Tally", func() -> bool:
		return game.spectate.is_spectating(&"u616"))
	_check(
		bool(slain[1]),
		"a runner slain on a server is put on a death camera by that server's world",
		" | ".join(slain[0])
	)

	module.get("roster").call("remove", session)
	var _released := server.release_session(session.peer_id)
	_check(
		game.progress.key_of(&"u616") == "" and not game.progress.stats.has_player(&"bfh-u616"),
		"and a player who leaves is forgotten by the counters"
	)

	net.send_fn = previous_send
	_done()
