extends DotGameCheckSuite
const BfhTestPorts := preload("test_ports.gd")
## The dedicated server's boot, its module, the bowl vote and the rotation file.


const BfhAmbience := preload("../game/bfh_ambience.gd")
const BfhAudio := preload("../game/bfh_audio.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhNetLink := preload("../game/net/bfh_net_link.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhAvatars := preload("../game/bfh_avatars.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhDistricts := preload("../game/bfh_districts.gd")
const BfhNetBridge := preload("../game/net/bfh_net_bridge.gd")

## Boots a real [DotServer], loads this game into it as a module, and runs the commands an operator
## would actually type.

const CHECKS := 180

## Everything this run writes, and it is deleted on the way in and on the way out.
const SERVER_DIR := "user://bfh_dedicated"

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 18

## The ports this run listens on, probed free so two suites never collide.
var PORT := BfhTestPorts.free_port(2)
var QUERY_PORT := PORT + 1

## What the config file asks for. Deliberately not the project's own default: the point of
## the chain below is that the SERVER decides, so a test using the same number on both
## sides would pass with the chain disconnected.
const TICK_RATE := 40

var _completed := 0

var server: DotServer = null
var game: BfhGame = null


## Stands in for the module a vote's commands are registered on, recording the names.
class CommandHost extends Node:
	var added: Dictionary = {}

	func add_command(full: String, fn: Callable, _help: String, _permission: String) -> Object:
		added[full] = fn
		return null


## The flag this suite hands the copy of itself it runs. See [method _run_exit_probe].
const EXIT_PROBE_FLAG := "--exit-probe"

## What the exit probe adds to a run — one section, these checks — and the copy does not.
const EXIT_PROBE_CHECKS := 3


## How long the copy may run before it is killed and this probe fails. A copy that is still running
## this long after it started is hung, and the likeliest reason is the one that says nothing at all:
## a scene whose script failed to parse never reaches `quit()` and prints nothing.
const EXIT_PROBE_SECONDS := 300



## Takes the server down before quitting, and this run does not end without it.
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


## Profiles, names and faces on a real server: dot-platform's identity layer, its module, the three
## events this game redraws a player on, and the key what they keep is filed under.
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
		game.progress == null or game.progress.key_of(&"u717") == String(module.stats_feed.key_for(late)),
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
		game.progress == null or (early_key != ""
			and game.progress.key_of(&"u718") == String(module.stats_feed.key_for(early))
			and game.progress.stats.has_player(StringName(game.progress.key_of(&"u718")))),
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


## The loaded module, looked up rather than kept.
func _module() -> DotModule:
	return server.modules.get_module("buses") if server != null else null


## Runs a line the way the console does and captures what came back.
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



func _boot() -> void:
	print("booting")

	# The tick rate is set the way an operator actually sets it: a line in a config file the server
	# execs at boot.
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
	# [b]Off, or this run never ends.[/b] The stdin console reads on its own thread, and a thread
	# blocked in a read is a thread Godot will not exit without — so the suite prints its results,
	# calls `quit()`, and hangs.
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



func _test_the_module_loads() -> void:
	print("the module")

	# [b]The world is built AFTER the server and BEFORE the module, and both halves of that order
	# matter.[/b] After the server, because the server is what set the engine's tick rate and the world
	# reads it — which is the ordering a real deployment has.
	var config := BfhConfig.new()
	config.crate_count = 10
	config.barrel_count = 2
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.round_seconds = 45.0

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.config_binder = BfhConfig.make_binder(config)
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)

	await get_tree().process_frame

	_check(
		DotRegistry.get_node_service(BfhGame.SERVICE) == game,
		"the world publishes itself where a module will look for it"
	)

	# Into this run's own directory. See [constant SERVER_DIR].
	(load("res://game/bfh_module.gd") as GDScript).set(
		"punishments_file", "%s/punishments.json" % SERVER_DIR
	)

	var loaded: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	_check(
		loaded.ok, "the module loads into the server",
		loaded.error.message if not loaded.ok else ""
	)

	var module := _module()
	_check(game != null and game.progress != null and game.progress.durable_key_fn.is_valid(),
		"progress is filed under dot-game's stable stats key")
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

	# [b]The store, and that it is empty.[/b] The second is what says the first worked on THIS run: a
	# path that is right and a directory that was not wiped is a suite carrying the last run's
	# punishments into this one, which is how `headless_net` failed on its second run.
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
	var wb: DotGameWorkbench = module.get("workbench")
	var amb: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "ambience", "id": DotGameWorkbench.CVAR_SET_ID, "key": "bfh_ambient_volume", "value": 0.2})
	_check(amb.ok and is_equal_approx(server.console.get_float("bfh_ambient_volume"), 0.2), "the bfh_ambient* cvars are a workbench set and an edit moves the cvar", "" if amb.ok else amb.error.message)
	var _restore := server.console.set_cvar("bfh_ambient_volume", "0.3")
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


## The players' vote decides the next bowl, end to end through what a player types: a nomination,
## the ballot opening on its own clock with the nomination on it, a vote by number, the round's end
## handing the winner to the world, and the next round REBUILDING the bowl to it; then rock.
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
	vote.set("_opened_this_map", true)
	server.console.execute("sv_hibernate_when_empty 1")
	_check(server.is_hibernating() and director.hibernating, "an empty server sleeps, and the vote with it",
		server.state_name())
	var on_bowl: float = vote.get("_on_map_sec")
	vote.call("advance", 600.0)
	_check(is_equal_approx(vote.get("_on_map_sec"), on_bowl), "ten minutes asleep do not count towards the ballot")
	server.console.execute("sv_hibernate_when_empty 0")
	_check(is_zero_approx(vote.get("_on_map_sec")) and not vote.get("_opened_this_map") and not director.hibernating,
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

	vote.set("_on_map_sec", 0.0)
	vote.set("_opened_this_map", false)
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
	# Rocked in the warmup, which is what an empty current id means, so the same ballot also shows it
	# is drawn there.
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

## `cfg/maps.yml`: which bowls rotate.
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
		vote.call("refresh_maps")
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
		vote.call("refresh_maps")
		director.begin(game.bowl_id)
	_done()
