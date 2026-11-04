extends "dedicated_live.gd"
## Ambient cvars, a clean exit, the loading cover, stats and progress.


## [b]`bfh_ambient*` on a client.[/b] The server's ambience intent rides the replicated cvars over a real socket, and a director that follows the game's rules (as [BfhClient] wires it) has it in its layer's config; the Ambience bus follows Effects.
func _test_ambient_cvars_reach_the_client() -> void:
	print("")
	print("the server's bfh_ambient* reaches a client's ambience director, live")
	var side := Node.new()
	side.name = "AmbientClient"
	add_child(side)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), side.get_path())
	var mirror := Node.new()
	mirror.name = name
	side.add_child(mirror)
	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Ambient"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % server.config.port
	mirror.add_child(link)
	var attach := func(_a: Variant = null, _b: Variant = null) -> void:
		if link.get_node_or_null(NodePath(String(BfhNetLink.NODE_NAME))) == null:
			link.add_child(BfhNetLink.attached_to(link, null, false))
	attach.call()
	link.phase_changed.connect(attach)
	link.connect_to_server("127.0.0.1:%d" % server.config.port)
	var rules := BfhAmbience.make_rules()
	var _followed := rules.follow_cvars(link)
	var director := DotAmbienceDirector.new()
	director.ambient = DotAmbience.new()
	director.follow_settings(null, rules)
	var joined := await _until(func() -> bool: return link.replicated_cvar("bfh_ambient_volume", "") != "", 30.0)
	_check(joined and link.replicated_cvar("bfh_ambient_dir", "x") == "x",
		"the join carried bfh_ambient_volume, and the machine-local bfh_ambient_dir stayed home", str(link.replicated_cvars))
	var _vol := server.console.set_cvar("bfh_ambient_volume", "0.8")
	var _mood := server.console.set_cvar("bfh_ambient_mood", "swamp")
	var _off := server.console.set_cvar("bfh_ambient", "0")
	var arrived := await _until(func() -> bool:
		return is_equal_approx(director.ambient.config.volume, 0.8) and director.ambient.config.mood == "swamp" \
			and not director.ambient.config.enabled, 15.0)
	_check(arrived, "a change of volume, mood and the switch reaches the director live", str(rules.describe()))
	var _back_vol := server.console.set_cvar("bfh_ambient_volume", "0.3")
	var _back_mood := server.console.set_cvar("bfh_ambient_mood", "")
	var _back_on := server.console.set_cvar("bfh_ambient", "1")
	var back := await _until(func() -> bool: return rules.is_on() and rules.mood == "", 15.0)
	_check(back, "and back", str(rules.describe()))

	var world := BfhGame.new()
	world.config = BfhConfig.new()
	add_child(world)
	var audio := BfhAudio.new()
	add_child(audio)
	var made := audio.setup(world)
	_check(made.ok and audio.ambient != null and audio.ambient.manager == audio.audio,
		"the client's audio builds a director on its manager", str(made.error.message if not made.ok else ""))
	var mixer := audio.audio.mixer
	mixer.sfx = 0.5
	mixer.ambience = 0.8
	var _applied := mixer.apply_to_buses()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience")), linear_to_db(0.4)),
		"the Effects slider reaches the Ambience bus the director plays on")
	audio.ambient.on_map(&"bfh_small_bowl")
	_check(audio.ambience != null and is_equal_approx(audio.ambience._gain(), audio.ambience.level * 0.8),
		"on_map(id) alone gives the small bowl's catalogue ambient level through the lookup", str(audio.ambience._gain()))
	audio.ambient.on_map(&"bfh_big_bowl")
	_check(is_equal_approx(audio.ambience._gain(), audio.ambience.level * 1.2),
		"and the big bowl's", str(audio.ambience._gain()))

	audio.queue_free()
	world.queue_free()
	director.ambient.free()
	director.free()
	link.disconnect_from_server("done")
	await get_tree().create_timer(2.0).timeout
	side.queue_free()
	_done()


func _until(condition: Callable, seconds: float) -> bool:
	var left := seconds
	while left > 0.0 and not bool(condition.call()):
		await get_tree().create_timer(0.1).timeout
		left -= 0.1
	return bool(condition.call())



func _is_exit_probe() -> bool:
	return EXIT_PROBE_FLAG in OS.get_cmdline_user_args()


func _exit_probe_seconds() -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--exit-probe-seconds")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		return maxi(1, args[at + 1].to_int())
	return EXIT_PROBE_SECONDS


## Runs this same suite in a fresh process: `[exit code, its stdout, its stderr, whether it had to
## be killed, the seconds it was allowed]`.
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
	# Every leak line is the engine's, and the engine writes them to stderr; both are searched so that
	# stays a fact about the engine rather than an assumption here.
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
## [DotClientLink] joins over the server's ENet socket and says nothing, as a client still loading
## its level does.
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
	# The server's snapshots are RPCs to Server/Buses; without that node the client rejects each packet.
	var attach := func(_a: Variant = null, _b: Variant = null) -> void:
		if link.get_node_or_null(NodePath(String(BfhNetLink.NODE_NAME))) == null:
			link.add_child(BfhNetLink.attached_to(link, null, false))
	attach.call()
	link.phase_changed.connect(attach)
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


## A module-built world has stats, achievements and the death camera, and the operator can read them.
func _test_stats_report() -> void:
	print("stats_report")
	var cv: DotConVar = server.console.find_cvar("stats_report")
	var progress: Object = game.progress
	_check(cv != null and cv.get_string() == "0", "stats_report is registered and off by default")
	_check(progress != null and progress.stats != null and not progress.stats.report_to_backbone,
		"and the tracker does not report at boot")
	if cv == null or progress == null:
		return
	var _off := cv.set_value("1")
	_check(not progress.stats.report_to_backbone, "on with no backbone client stays off, not a crash")

	var client := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc post_integration(_a = null, _b = null, _c = null): return null\n"
	var _reloaded := script.reload()
	client.set_script(script)
	DotRegistry.register(&"dot_backbone_client", client)
	var _r0 := cv.set_value("0")
	var _r1 := cv.set_value("1")
	_check(progress.stats.report_to_backbone, "on with a backbone client makes the tracker report")
	_check(progress.stats.get_node_or_null(DotGameStatsReport.TIMER_NAME) != null, "and adds the flush timer")
	var _r2 := cv.set_value("0")
	_check(not progress.stats.report_to_backbone, "off stops it again")
	DotRegistry.unregister_instance(&"dot_backbone_client", client)
	client.free()


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
