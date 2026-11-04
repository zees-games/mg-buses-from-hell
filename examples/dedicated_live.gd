extends "dedicated_boot.gd"
## Rounds, bots, services and live tools, unloading and reloading.


## [b]`time_up: finish_round` waits for a round being played, never for warmup.[/b] The game hands
## dot-vote its match's answer (`round_in_progress_fn`); without it a limit that ran out in warmup
## held the change for `finish_round_max_sec` over a round that had not started.
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

	# [b]A person who takes a seat takes it from a bot, and leaving gives it back[/b]: DotBotQuota's
	# fill mode, counted in driving seats.
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


## dot-moderation's live tools, built by dot-game's services layer BY PATH, with this game's verbs
## in them — the first game to get them from the shared layer rather than writing its own.
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

	# Each body is looked at the moment the command returns, not after a frame. A lone runner makes the
	# sides playable, so a round can start under this section — and a round start is a new body here,
	# which is exactly when the tools switch a noclip off and the game stands a slain runner back up.
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


## A module reload must leave ONE link under the server, still named for the client's route, and a
## real client must still be sent to over it.
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
