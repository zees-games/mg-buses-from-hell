extends "headless_net_drawn.gd"
## A runner who is out, a barrel, splinters and the scoreboard.


var _out_ears: BfhAudio
var _out_sink: DotAudioSinkNull
var _out_eye: Camera3D


## Run down on the server, the client's camera goes where the server says, and every noise and cue
## on the way reaches the client's world as the same signal an offline one emits.
func _test_a_runner_who_is_out() -> void:
	_section("a runner who is out: where the server says to look, and what the client hears")

	var mine_on_server := _server_player()
	var bot_key := BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	var bot: BfhPlayer = _server_game.players.get(bot_key)

	# A second runner, so this client going down does not end the round under the test.
	var other := _server_bridge.add_bot("Cy", BfhGame.TEAM_RUNNERS)
	await _steps(6)

	var server_net := mine_on_server.get_node("Net") as DotNetBehaviour
	_check(
		server_net.find_var(&"net_watch").audience == DotNetVar.Audience.OWNER
		and server_net.find_var(&"net_watch_target").audience == DotNetVar.Audience.OWNER,
		"where a runner who is out looks is sent to them and to nobody else"
	)

	if bot == null or not bot.riding or other == null:
		for _i in range(9):
			_check(false, "(no bot in a bus to be run over by, or no second runner)")
		_done()
		return

	await _out_death_camera(mine_on_server, bot, bot_key)
	await _out_then_through_eyes()
	await _out_free_roam()
	await _out_achievement(mine_on_server)
	await _out_round_turns_over(other)
	_done()


## The client's ears, the flattening it hears, and the camera on the bus that did it.
func _out_death_camera(mine_on_server: BfhPlayer, bot: BfhPlayer, bot_key: StringName) -> void:
	# The client's ears, on the client's world, with the null sink a headless run gets.
	var ears := BfhAudio.new()
	add_child(ears)
	var _built := ears.setup(_client_game, func() -> BfhPlayer: return _client_player())
	_out_ears = ears
	_out_sink = ears.audio.sink as DotAudioSinkNull
	var heard: Array = []
	_client_game.noise.connect(func(id: StringName, at: Vector3) -> void:
		heard.append({"id": id, "at": at}))
	var deaths: Array[StringName] = []
	_client_game.player_died.connect(func(id: StringName, _by: StringName) -> void:
		deaths.append(id))

	var fell_at := mine_on_server.global_position
	_server_game._bus_hit(mine_on_server, bot_key, 30.0, Vector3(0.0, 0.0, 1.0))
	await _steps(4)

	var mine := _client_player()
	var spectate := _client_game.spectate
	_check(
		spectate != null and not spectate.manager.authoritative
		and spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.DEATH_CAM
		and spectate.target_of(mine.player_id) == bot_key,
		"the client's mirror is put on the death camera, looking at the bus that did it",
		spectate.describe_view(mine.player_id) if spectate != null else "no spectate"
	)

	var down: Array = heard.filter(func(h: Dictionary) -> bool: return h["id"] == BfhSounds.RUNNER_DOWN)
	_check(
		down.size() == 1 and (down[0]["at"] as Vector3).distance_to(fell_at) < 0.5
		and deaths.has(mine.player_id),
		"a flattening on the server is a noise on the client's world, where it happened, "
		+ "and a death its world says it saw",
		"%d noises, deaths %s" % [down.size(), str(deaths)]
	)

	var eye := Camera3D.new()
	_out_eye = eye
	var client_side := _client_game.get_parent()
	client_side.add_child(eye)
	var client_bus := _client_bridge.body_of_net_id(_server_bridge.net_id_of_node(bot.ridden))
	var drew := BfhClient.present_spectator_camera(_client_game, mine, eye)
	# At the client's copy's CAB, which is where `BfhSpectate.pose_of` puts a bus's eyes and so what a
	# death camera looks at — not at the hull's centre.
	var toward := (
		((client_bus.global_transform * BfhSpectate.CAB_EYE) - eye.global_position).normalized()
		if client_bus != null else Vector3.ZERO
	)
	_check(
		drew and client_bus != null and (-eye.global_basis.z).dot(toward) > 0.9,
		"and the client's camera looks at its OWN copy of that bus",
		"facing %.2f of the way to its cab, %.1f m from the bus" % [
			(-eye.global_basis.z).dot(toward),
			eye.global_position.distance_to(client_bus.global_position) if client_bus != null
				else -1.0,
		]
	)



## Past the death camera and the freeze, through somebody's eyes, then the next and the chase view.
func _out_then_through_eyes() -> void:
	var eye := _out_eye
	var mine := _client_player()
	var spectate := _client_game.spectate
	# Past the death camera and the freeze on the cab, on the server's clock.
	await _steps(int((BfhSpectate.DEATH_CAM_SEC + BfhSpectate.FREEZE_CAM_SEC) * 60.0) + 10)
	var following := spectate.target_of(mine.player_id)
	var watched: BfhPlayer = _client_game.players.get(following)
	var _drew := BfhClient.present_spectator_camera(_client_game, mine, eye)
	_check(
		spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.FIRST_PERSON
		and watched != null
		and eye.global_position.distance_to(spectate.pose_of(String(following)).origin) < 0.01,
		"then through somebody's eyes, as this client draws them",
		"%s" % spectate.describe_view(mine.player_id)
	)

	_client_bridge.ask_watch(BfhSpectate.ASK_NEXT)
	_exchange()
	await _steps(4)
	var next := spectate.target_of(mine.player_id)
	_check(
		next != following and next == _server_game.spectate.target_of(mine.player_id),
		"a click is asked of the server, and the client is moved to the server's next",
		"%s -> %s, server says %s" % [following, next, _server_game.spectate.target_of(mine.player_id)]
	)

	_client_bridge.ask_watch(BfhSpectate.ASK_VIEW)
	_exchange()
	await _steps(4)
	_check(
		spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.CHASE,
		"and space asks for the view behind them",
		spectate.describe_view(mine.player_id)
	)



## Free roam is decided by the server, and a refused ask comes back as a notice.
func _out_free_roam() -> void:
	var mine := _client_player()
	var spectate := _client_game.spectate
	# Free roam: the ask goes to the server, which decides (toggle_roam), and ROAMING comes
	# back with no target. An empty target must not read as "stop watching".
	var server_rules := _server_game.spectate.manager.rules
	_client_bridge.ask_watch(BfhSpectate.ASK_ROAM)
	_exchange()
	await _steps(4)
	_check(
		_server_game.spectate.is_roaming(mine.player_id) and spectate.is_roaming(mine.player_id)
		and spectate.is_spectating(mine.player_id),
		"the free-camera ask is decided by the server, and ROAMING comes back to the client",
		"server %s, client %s" % [
			_server_game.spectate.describe_view(mine.player_id), spectate.describe_view(mine.player_id)
		]
	)

	var roam_notices: Array[String] = []
	_client_bridge.notice_received.connect(func(text: String) -> void: roam_notices.append(text))
	var _roam_off := server_rules.set_cvar("mp_freeroam", "0")
	await _steps(4)
	_check(
		not _server_game.spectate.is_roaming(mine.player_id) and not spectate.is_roaming(mine.player_id)
		and spectate.is_spectating(mine.player_id),
		"mp_freeroam 0 mid-roam returns the roamer to a player, on the client too",
		spectate.describe_view(mine.player_id)
	)

	_client_bridge.ask_watch(BfhSpectate.ASK_ROAM)
	_exchange()
	await _steps(4)
	_check(
		not _server_game.spectate.is_roaming(mine.player_id)
		and roam_notices.any(func(t: String) -> bool: return t.to_lower().contains("roam")),
		"a refused free-camera ask comes back as a notice, and the roamer stays on a player",
		str(roam_notices)
	)
	var _roam_on := server_rules.set_cvar("mp_freeroam", "1")



## An achievement told to the one player who earned it.
func _out_achievement(mine_on_server: BfhPlayer) -> void:
	var mine := _client_player()
	# An achievement, from the server's tracker to the one person who earned it. Unlocked
	# by hand rather than earned — earning is `headless_run`'s — so what is under test is
	# everything after the tracker: the world's signal, the bridge, a notice, the client.
	var notices: Array[String] = []
	_client_bridge.notice_received.connect(func(text: String) -> void: notices.append(text))
	var awarded := _server_game.progress.achievements.unlock(
		_server_game.progress.key_of(mine_on_server.player_id), &"bfh.demolition"
	)
	_exchange()
	await _steps(2)
	_check(
		awarded.ok and notices.any(func(t: String) -> bool: return t.contains("Demolition")),
		"an achievement the server awards is told to the one player who earned it",
		"%s, notices %s" % [str(awarded.value) if awarded.ok else str(awarded.error), str(notices)]
	)



## The last runner goes: the round turns over and the client hears it.
func _out_round_turns_over(other: BfhPlayer) -> void:
	var eye := _out_eye
	var ears := _out_ears
	var sink := _out_sink
	var mine := _client_player()
	var spectate := _client_game.spectate
	var bot_key := BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	# The last runner goes; the round turns over on the server, and the client's world says
	# so with the signals an offline world emits, and hears it.
	var rounds: Array = []
	_client_game.round_over.connect(func(n: int, winner: int) -> void: rounds.append([n, winner]))
	_server_game._bus_hit(other, bot_key, 30.0, Vector3(0.0, 0.0, 1.0))
	await _steps(12)
	_check(
		not spectate.is_spectating(mine.player_id),
		"a new round ends the client's spectating, because the server's did",
		spectate.describe_view(mine.player_id)
	)
	_check(
		not rounds.is_empty() and int(rounds[0][1]) == BfhGame.TEAM_DRIVERS
		and sink.played_ids().has(String(BfhSounds.RUNNER_DOWN))
		and sink.played_ids().has(String(BfhSounds.ROUND_LOST))
		and sink.played_ids().has(String(BfhSounds.ROUND_START)),
		"and the connected client HEARS it: the flattening, the round lost, the next one",
		"rounds %s, played %s" % [str(rounds), str(sink.played_ids())]
	)

	eye.queue_free()
	remove_child(ears)
	ears.free()
	_server_bridge.remove_player(BfhNetBridge.session_of(other.player_id))
	_exchange()
	await _steps(2)


## The server sets a barrel off; the client draws it, where it went off and as far as it reached,
## from the BLAST alone.
func _test_a_barrel_is_drawn() -> void:
	_section("a barrel the server sets off is drawn on the client, where and as far as it went off")

	var client_side := _client_game.get_parent()
	var fx := BfhFx.new()
	client_side.add_child(fx)
	var built := fx.setup(_client_game)
	_check(
		built.ok and fx.fx.catalogue.missing_scenes().is_empty(),
		"the client's effects are built, and the blast's scene is in this build",
		str(built.error) if not built.ok else ", ".join(fx.fx.catalogue.missing_scenes())
	)

	# The truth is the server's: what its own world says went off, and where.
	var decided: Array = []
	_server_game.barrel_exploded.connect(func(at: Vector3, radius: float) -> void:
		decided.append([at, radius]))

	var spot := Vector3(-11.0, 0.0, 17.0)
	var barrel := _server_game.props.spawn(BfhContent.BARREL, &"world",
		spot + Vector3(0.0, BfhContent.BARREL_HEIGHT * 0.5 + 0.05, 0.0))
	await _steps(4)
	_check(fx.heard == 0 and fx.drawn == 0, "nothing is drawn before the server decides")

	_server_game.prop_damage.break_now(barrel.instance_id, &"")
	_exchange()
	await _steps(3)

	var truth_at: Vector3 = decided[0][0] if not decided.is_empty() else Vector3.INF
	var truth_radius: float = float(decided[0][1]) if not decided.is_empty() else -1.0
	var blast := fx.last_blast
	_check(
		decided.size() == 1 and fx.heard == 1 and fx.drawn == 1 and blast != null,
		"one blast on the server is one effect on the client",
		"server %d, client heard %d, drew %d" % [decided.size(), fx.heard, fx.drawn]
	)

	if blast == null:
		for _i in range(4):
			_check(false, "(no blast drawn)")
		client_side.remove_child(fx)
		fx.free()
		_done()
		return

	_check(
		blast.global_position.distance_to(truth_at) < 0.05,
		"drawn where the server says it went off",
		"%s against %s" % [str(blast.global_position), str(truth_at)]
	)
	_check(
		blast.get_world_3d() == _client_game.get_world_3d()
		and blast.get_world_3d() != _server_game.get_world_3d(),
		"in the client's world, and not the server's"
	)

	# Past the moment the ring reaches the edge, stepped rather than waited for.
	blast.call("advance", 0.35)
	var reach := float(blast.call("drawn_reach"))
	_check(
		absf(float(blast.get("radius")) - truth_radius) < 0.05
		and absf(reach - truth_radius) < truth_radius * 0.03,
		"sized from the radius the server sent: the ring is drawn to the blast's reach",
		"radius %.2f, ring %.2f m, server %.2f" % [float(blast.get("radius")), reach, truth_radius]
	)

	# dot-fx retires it on its own lifetime, which is wall-clock milliseconds.
	await get_tree().create_timer(float(BfhFx.BLAST_MS) / 1000.0 + 0.2).timeout
	fx.present(0.016, Vector3.ZERO)
	await get_tree().process_frame
	_check(
		fx.fx.live_count() == 0 and not is_instance_valid(blast),
		"and gone once its lifetime is up, rather than kept for the round",
		"live %d" % fx.fx.live_count()
	)

	client_side.remove_child(fx)
	fx.free()
	_done()



## A crate the server breaks throws splinters on the client (its crack stays BfhAudio's), and nothing
## when effects are off.
func _test_a_crate_breaks_in_splinters() -> void:
	_section("a crate the server breaks throws splinters on the client, none with effects off")

	var client_side := _client_game.get_parent()
	var fx := BfhFx.new()
	client_side.add_child(fx)
	var built := fx.setup(_client_game)
	_check(built.ok and fx.break_fx != null, "the client's effects include the break effect")
	fx.break_fx.config.headless = true
	var spot := Vector3(-9.0, 0.0, 15.0)
	var crate := _server_game.props.spawn(BfhContent.CRATE, &"world", spot + Vector3(0.0, 0.6, 0.0))
	await _steps(4)
	_server_game.prop_damage.break_now(crate.instance_id, &"")
	_exchange()
	await _steps(3)
	_check(fx.break_fx.spawned == 1, "one broken crate is one burst of splinters", "spawned %d" % fx.break_fx.spawned)
	var root := fx.break_fx.get_child(fx.break_fx.get_child_count() - 1) as Node3D
	_check(root != null and root.name.begins_with("Break_wood") and root.get_node_or_null("Pieces") != null,
		"wood pieces are drawn")
	_check(root != null and root.global_position.distance_to(spot) < 2.0, "where the crate was")
	_check(root != null and not _has_audio(root),
		"no second crack: the crate's own sound is BfhAudio's")

	fx.break_fx.config.enabled = false
	var crate2 := _server_game.props.spawn(BfhContent.CRATE, &"world", spot + Vector3(2.0, 0.6, 0.0))
	await _steps(4)
	_server_game.prop_damage.break_now(crate2.instance_id, &"")
	_exchange()
	await _steps(3)
	_check(fx.break_fx.spawned == 1 and fx.break_fx.last_refusal == "disabled",
		"with effects off nothing is drawn", "spawned %d, %s" % [fx.break_fx.spawned, fx.break_fx.last_refusal])
	client_side.remove_child(fx)
	fx.free()
	_done()


func _has_audio(n: Node) -> bool:
	for c in n.get_children():
		if c is AudioStreamPlayer3D or c is AudioStreamPlayer:
			return true
	return false



## The client's scoreboard over the real match: both sides from the roster the server sent, the
## tallies dot-match kept on the server, up on its own at a round's end with that round already
## counted, and on Tab.
func _test_the_scoreboard() -> void:
	_section("the scoreboard: both sides, and the score dot-match kept on the server")

	var client_names := {}
	var mine := _client_player()
	var board := BfhScoreboard.new()
	add_child(board)
	board.bind(_client_game, func() -> BfhPlayer: return _client_player())

	var client_match := _client_game.match_node
	var drivers_side: DotTeam = client_match.teams.team(BfhGame.TEAM_DRIVERS)
	var runners_side: DotTeam = client_match.teams.team(BfhGame.TEAM_RUNNERS)
	_check(
		drivers_side != null and drivers_side.display_name == "Drivers"
		and runners_side != null and runners_side.display_name == "Runners",
		"the client's dot-match knows the two sides by this game's names",
		"%s, %s" % [str(drivers_side), str(runners_side)]
	)

	# Every player the server has, on the side the server has them, in the client's rows.
	var drivers := BfhScoreboard.rows_for(_client_game, BfhGame.TEAM_DRIVERS, mine.player_id)
	var runners := BfhScoreboard.rows_for(_client_game, BfhGame.TEAM_RUNNERS, mine.player_id)
	for row in drivers + runners:
		client_names[String(row[&"id"])] = row
	var misplaced := PackedStringArray()
	for id: StringName in _server_game.players:
		var row: Dictionary = client_names.get(String(id), {})
		var want_rows := drivers if _server_game.team_of(id) == BfhGame.TEAM_DRIVERS else runners
		if row.is_empty() or not want_rows.has(row):
			misplaced.append(String(id))
	_check(
		misplaced.is_empty() and drivers.size() + runners.size() == _server_game.players.size()
		and not drivers.is_empty() and not runners.is_empty(),
		"every player the server has is on the side the server has them",
		"%d drivers, %d runners, misplaced %s" % [drivers.size(), runners.size(), str(misplaced)]
	)
	var own_rows := runners.filter(func(r: Dictionary) -> bool: return bool(r["highlight"]))
	_check(
		drivers.all(func(r: Dictionary) -> bool: return r[&"status"] == "driving")
		and own_rows.size() == 1 and String(own_rows[0][&"id"]) == String(mine.player_id)
		and own_rows[0][&"status"] == "up",
		"the bot driver reads as driving, and this client is the one highlighted runner, up",
		str(drivers) + " " + str(own_rows)
	)

	await _steps(int(BfhNetBridge.CLOCK_EVERY) + 2)
	var server_drivers := int(_server_game.match_node.rounds_won.get(BfhGame.TEAM_DRIVERS, 0))
	var server_runners := int(_server_game.match_node.rounds_won.get(BfhGame.TEAM_RUNNERS, 0))
	_check(
		server_drivers > 0
		and _client_game.rounds_won(BfhGame.TEAM_DRIVERS) == server_drivers
		and _client_game.rounds_won(BfhGame.TEAM_RUNNERS) == server_runners,
		"the client's tally is the rounds dot-match counted on the server",
		"server %d-%d, client %d-%d" % [server_drivers, server_runners,
			_client_game.rounds_won(BfhGame.TEAM_DRIVERS), _client_game.rounds_won(BfhGame.TEAM_RUNNERS)]
	)
	_check(not board.shown(), "not on screen mid-round unless asked for")

	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	var took := board.handle_key(tab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(took and board.shown() and board.board.is_open(), "Tab held puts it up")

	# Laid out with a size: the zero-size trap the old tables had, checked on the new board.
	var sized := true
	var detail := PackedStringArray()
	for team in [BfhGame.TEAM_DRIVERS, BfhGame.TEAM_RUNNERS]:
		var block := board.board.find_child("Team_%d" % team, true, false) as Control
		if block == null or block.size.x < 100.0 or block.size.y < 40.0:
			sized = false
			detail.append("side %d: %s" % [team, str(block.size) if block != null else "missing"])
	_check(sized and board.describe()["drivers"] >= 1 and board.describe()["runners"] >= 1,
		"both sides are drawn, side by side, with a size and their players in them", ", ".join(detail))

	tab.pressed = false
	var _took_release := board.handle_key(tab)
	_check(not board.shown(), "and letting go takes it down")

	# The last runner goes: the round ends on the server, and the client's scoreboard comes
	# up on its own at that moment with the round just played already in the tally.
	var at_end: Array = []
	_client_game.round_over.connect(func(_n: int, winner: int) -> void:
		at_end.append({
			"shown": board.shown(),
			"drivers": _client_game.rounds_won(BfhGame.TEAM_DRIVERS),
			"header": board.header_text(BfhGame.TEAM_DRIVERS),
			"footer": board.footer_text(),
			"winner": winner,
		}), CONNECT_ONE_SHOT)
	var bot_key := BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	_server_game._bus_hit(_server_player(), bot_key, 30.0, Vector3(0.0, 0.0, 1.0))
	await _steps(3)
	var want := server_drivers + 1
	_check(
		at_end.size() == 1 and bool(at_end[0]["shown"]) and int(at_end[0]["drivers"]) == want
		and str(at_end[0]["header"]).contains("%d round" % want)
		and str(at_end[0]["footer"]).contains("buses"),
		"at the round's end it comes up by itself, with that round already counted",
		"%s, server says %d" % [str(at_end), int(_server_game.match_node.rounds_won.get(BfhGame.TEAM_DRIVERS, 0))]
	)

	await _steps(4)
	_check(
		not board.after_round and not board.shown(),
		"and goes when the next round begins",
		str(board.describe())
	)

	remove_child(board)
	board.free()
	_done()
