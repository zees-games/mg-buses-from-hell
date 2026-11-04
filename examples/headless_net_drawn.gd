extends "headless_net_play.gd"
## What the client draws of somebody else, a voted bowl, toys, the workbench and leaving.


## Another runner has a body, it is where the server has them, and it moves every frame.
func _test_who_somebody_is_crosses() -> void:
	_section("who somebody is crosses, and is what is drawn")

	_check(
		BfhAvatars.SKINS.size() == BfhFigure.RUNNER_ATLASES.size(),
		"there is one skin per runner atlas, so a skin index is an atlas index",
		"%d skins, %d atlases" % [BfhAvatars.SKINS.size(), BfhFigure.RUNNER_ATLASES.size()]
	)

	# What the module hands the bridge: the platform's answer, as a fixed face chosen to be
	# one this player's id does NOT hash to, or a figure built from the hash would pass. The
	# bridge hands out a bot's session as it seats it, so the face answers any session.
	var chosen := [-1]
	var face_of := {}
	_server_bridge.avatar_fn = func(session_id: int) -> DotAvatar:
		var key := BfhNetBridge.player_key(session_id)
		chosen[0] = (BfhAvatars.stock_index(key) + 3) % BfhAvatars.SKINS.size()
		var face := BfhAvatars.stock_avatar(key)
		face.set_part(BfhAvatars.SLOT_SKIN, BfhAvatars.SKINS[chosen[0]])
		face_of[key] = face
		return face

	var seated := _server_bridge.add_bot("Cyd", BfhGame.TEAM_RUNNERS)
	_server_bridge.avatar_fn = Callable()
	await _steps(6)

	var mine := _client_player()
	var theirs: BfhPlayer = _client_game.players.get(seated.player_id) if seated != null else null

	if seated == null or theirs == null or mine == null:
		_check(false, "a runner seated with a face reaches the client")
		_done()
		return

	var _shown := BfhClient.present_frame(_client_net, _client_game, mine, 1.0 / 60.0, 0.0)
	var key := seated.player_id
	var session := BfhNetBridge.session_of(key)
	_check(
		theirs.avatar != null and theirs.avatar.digest() == (face_of[key] as DotAvatar).digest(),
		"a runner seated with a face arrives wearing it"
	)
	_check(
		theirs.figure != null and theirs.figure.atlas == str(BfhFigure.RUNNER_ATLASES[chosen[0]]),
		"and is drawn in it, not in the one their id hashes to",
		theirs.figure.atlas.get_file() if theirs.figure != null else "no figure"
	)

	# Later: the profile arrives, or they change their face, or an operator renames them.
	var later: int = (int(chosen[0]) + 1) % BfhAvatars.SKINS.size()
	if later == BfhAvatars.stock_index(key):
		later = (later + 1) % BfhAvatars.SKINS.size()
	var changed := BfhAvatars.stock_avatar(key)
	changed.set_part(BfhAvatars.SLOT_SKIN, BfhAvatars.SKINS[later])

	var told := _server_bridge.refresh_player(session, "Cydney", changed)
	await _steps(4)
	_shown = BfhClient.present_frame(_client_net, _client_game, mine, 1.0 / 60.0, 0.0)

	_check(
		told and theirs.display_name == "Cydney" and seated.display_name == "Cydney",
		"a new name reaches the server's world and the client's",
		theirs.display_name
	)
	_check(
		theirs.figure != null and theirs.figure.atlas == str(BfhFigure.RUNNER_ATLASES[later]),
		"and a new face is drawn the frame after, without them rejoining",
		theirs.figure.atlas.get_file() if theirs.figure != null else "-"
	)

	var foreign := DotAvatar.make(&"some_other_game")
	foreign.set_part(BfhAvatars.SLOT_SKIN, BfhAvatars.SKINS[later])
	_server_bridge.refresh_player(session, "", foreign)
	await _steps(4)
	_shown = BfhClient.present_frame(_client_net, _client_game, mine, 1.0 / 60.0, 0.0)

	_check(
		theirs.display_name == "Cydney" and theirs.figure != null
			and theirs.figure.atlas
				== str(BfhFigure.RUNNER_ATLASES[BfhAvatars.stock_index(key)]),
		"a face from another game's schema is the stock person, and the name is kept",
		theirs.figure.atlas.get_file() if theirs.figure != null else "-"
	)

	_server_bridge.remove_player(session)
	await _steps(4)
	_check(
		not _client_game.players.has(key),
		"and they leave again, so the sections after count as before"
	)

	_done()


func _test_somebody_else_is_drawn() -> void:
	_section("somebody else has a body, where the server has them, moving every frame")

	var other := _server_bridge.add_bot("Bea", BfhGame.TEAM_RUNNERS)
	_check(other != null, "a second runner joins the server")

	if other == null:
		_done()
		return

	var key := other.player_id
	var session := BfhNetBridge.session_of(key)
	var arrived_at := other.global_position

	# The round is live, so nothing lays them out; the arrival has to. Without it they stood
	# at the bowl's origin for the rest of the round, which is what the body below was first
	# drawn at.
	_check(
		Vector2(arrived_at.x, arrived_at.z).length() > 1.0,
		"and joining a live round places them in the bowl, rather than at its origin",
		str(arrived_at)
	)
	await _steps(8)

	var mine := _client_player()
	var theirs: BfhPlayer = _client_game.players.get(key)
	var shown := BfhClient.present_frame(_client_net, _client_game, mine, 1.0 / 60.0, 0.0)

	_check_other_is_drawn(mine, theirs, other, shown)

	# [b]The bot drivers out of their buses for the run, and back in after it.[/b] The bot floors it at
	# the nearest runner, and a runner thrown part-way through is a corner in the path that drawing a
	# snapshot apart rounds off: this measures a steady run, so nothing drives at it.
	var parked := _park_the_bot_drivers()

	# Somewhere a person can run in a straight line: the most open floor in the bowl, asked of the
	# arena, with the run's 6.4 m inside the clear circle (yaw 90 runs toward -x, so the start is 3 m
	# to +x of its middle).
	var start := _start_the_run(other)

	# Running, with the client drawing FRAMES_PER_TICK frames between ticks.
	var server_track: Array[Vector3] = []
	var drawn: Array[Vector3] = []
	await _run_the_other_runner(other, mine, theirs, server_track, drawn)

	_check_the_server_ran_them(other, server_track)

	# Tracking: every frame's body is within a hand of the path the server really ran them along. Not
	# the latest position, because a remote player is drawn an interpolation delay in the past on
	# purpose.
	_check_drawn_on_the_path(drawn, server_track)

	for entry: Array in parked:
		_server_game.ride.enter(entry[0], entry[1], entry[2], &"driver")
	_check_the_body_followed(drawn, start)

	# Smoothness: at a steady running speed each frame should advance the body by about the same
	# distance.
	_check_even_step(drawn)

	_check(
		theirs != null and theirs.figure != null
		and absf(wrapf(theirs.figure.rotation.y - deg_to_rad(90.0), -PI, PI)) < 0.05,
		"and faces the way the server says they are looking",
		"%.1f deg" % (rad_to_deg(theirs.figure.rotation.y) if theirs != null and theirs.figure != null else 0.0)
	)

	_server_bridge.remove_player(session)
	_exchange()
	await _steps(2)
	_check(
		not _client_game.players.has(key),
		"and leaves again, so the section after this one sees the bot and this client"
	)
	_done()


## What the client draws of the other runner, and of the bot drivers and itself.
func _check_other_is_drawn(mine: BfhPlayer, theirs: BfhPlayer, other: BfhPlayer, shown: int) -> void:
	# Your own runner is drawn at the clock's render alpha (dot-player-controller's
	# `render_clock`), so a clock slip does not stall or double the eye.
	_check(
		mine != null and mine.controller != null
			and mine.controller.get(&"render_clock") == _client_net.clock,
		"your own runner is drawn on the client clock's render alpha"
	)

	_check(
		theirs != null and theirs.figure != null
		and theirs.figure.global_position.distance_to(other.global_position) < 0.3,
		"the client's body for them stands where the server placed them",
		"drawn %s, server %s" % [
			str(theirs.figure.global_position) if theirs != null and theirs.figure != null else "-",
			str(other.global_position),
		]
	)

	_check(
		theirs != null and theirs.figure != null and theirs.figure.is_visible_in_tree(),
		"the client draws a body for them",
		"figure %s" % (str(theirs.figure.describe()) if theirs != null and theirs.figure != null else "none")
	)
	_check(
		theirs != null and theirs.figure != null and theirs.figure.from_art,
		"and it is the Kenney character, not the capsule a missing model falls back to"
	)
	_check(
		mine != null and (mine.figure == null or not mine.figure.visible),
		"and none round its own camera, which is first person"
	)

	var bot_driver: BfhPlayer = _client_game.players.get(
		BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	)
	_check(
		bot_driver != null and bot_driver.riding
		and (bot_driver.figure == null or not bot_driver.figure.visible),
		"and none for a driver, who is drawn as their bus rather than standing where they got in",
		"riding %s, figure %s" % [
			str(bot_driver.riding) if bot_driver != null else "?",
			str(bot_driver.figure.describe()) if bot_driver != null and bot_driver.figure != null else "none",
		]
	)
	_check(shown == 1, "so exactly one body is drawn on this client", "%d" % shown)



## Bot drivers out of their buses; the entries put them back.
func _park_the_bot_drivers() -> Array:
	var parked: Array = []
	for bus in _server_game.vehicles.all_vehicles():
		var sitting := _server_game.driver_of(bus.instance_id)
		var driver: BfhPlayer = _server_game.players.get(sitting) if sitting != &"" else null
		if driver != null and driver.is_bot:
			_server_game.ride.exit(bus, sitting, true)
			parked.append([bus, sitting, driver])
	return parked


## The most open floor in the bowl: where it is and how clear all round it.
func _most_open_floor() -> Dictionary:
	var open_at := Vector3.ZERO
	var open_clear := -INF
	var reach := _server_game.arena.radius - 4.0
	for gx in range(-12, 13):
		for gz in range(-12, 13):
			var at := Vector3(float(gx) * reach / 12.0, 0.0, float(gz) * reach / 12.0)
			var clear := _server_game.arena.floor_clear_at(at)
			if clear > open_clear:
				open_clear = clear
				open_at = at
	return {"at": open_at, "clear": open_clear}


## Runs [param other] forward for 60 ticks, drawing frames between them, and records both tracks.
func _run_the_other_runner(other: BfhPlayer, mine: BfhPlayer, theirs: BfhPlayer,
		server_track: Array[Vector3], drawn: Array[Vector3]) -> void:
	var run := DotFpsCommand.new()
	run.move = Vector2(0.0, 1.0)
	run.yaw = 90.0

	for i in range(60):
		other.controller.apply_command(run.duplicate_command())
		await _step()
		server_track.append(other.controller.state.position)

		for f in range(FRAMES_PER_TICK):
			var _n := BfhClient.present_frame(
				_client_net, _client_game, mine, 1.0 / 240.0, float(f) / float(FRAMES_PER_TICK)
			)
			if theirs != null and theirs.figure != null and i >= 20:
				drawn.append(theirs.figure.global_position)


## Every frame's body is within a hand of the path the server ran them along.
func _check_drawn_on_the_path(drawn: Array[Vector3], server_track: Array[Vector3]) -> void:
	var worst := 0.0
	for at in drawn:
		var nearest := INF
		for k in range(server_track.size() - 1):
			var a := server_track[k]
			var b := server_track[k + 1]
			var along := b - a
			var t := 0.0 if along.length_squared() < 1e-9 else clampf((at - a).dot(along) / along.length_squared(), 0.0, 1.0)
			nearest = minf(nearest, at.distance_to(a + along * t))
		worst = maxf(worst, nearest)

	_check(
		not drawn.is_empty() and worst < 0.25,
		"and every frame draws them on the path the server ran them along",
		"worst %.3f m off it, over %d frames" % [worst, drawn.size()]
	)


## At a steady running speed each frame advances the body by about the same distance.
func _check_even_step(drawn: Array[Vector3]) -> void:
	var steps := PackedFloat32Array()
	for j in range(1, drawn.size()):
		steps.append(drawn[j].distance_to(drawn[j - 1]))

	var mean := 0.0
	var largest := 0.0
	var smallest := INF
	for d in steps:
		mean += d
		largest = maxf(largest, d)
		smallest = minf(smallest, d)
	mean /= float(maxi(steps.size(), 1))

	_check(
		mean > 0.001 and largest < mean * 1.5 and smallest > mean * 0.5,
		"and it moves by an even step on every frame, not in snapshot-sized jumps",
		"per frame %.4f m mean, %.4f..%.4f" % [mean, smallest, largest]
	)


## Puts [param other] on the most open floor, 3 m to +x of its middle, standing; returns where.
func _start_the_run(other: BfhPlayer) -> Vector3:
	var open := _most_open_floor()
	var open_at: Vector3 = open["at"]
	var open_clear: float = open["clear"]
	var start := open_at + Vector3(3.0, _server_player().controller.state.position.y, 0.0)
	print("  ..    the run starts on open floor, %.1f m clear all round its middle" % open_clear)
	other.controller.state.position = start
	other.controller.state.velocity = Vector3.ZERO
	other.global_position = start
	return start


## Held to what 59 ticks at `runner_speed` covers rather than to "more than 3 m", which a runner
## at half their speed passes. Printed, always.
func _check_the_server_ran_them(other: BfhPlayer, server_track: Array[Vector3]) -> void:
	var moved := server_track[server_track.size() - 1].distance_to(server_track[0])
	var owed := other.controller.tunables.max_speed * 59.0 / float(SERVER_TICK_RATE)
	print("  ..    the other runner, 60 ticks of forward on the server: %.2f m of %.2f at max_speed"
		% [moved, owed])
	_check(moved > owed * 0.95, "the server runs them across the bowl, at runner_speed",
		"%.2f of %.2f m" % [moved, owed])


## The body followed them and is nowhere near the world origin.
func _check_the_body_followed(drawn: Array[Vector3], start: Vector3) -> void:
	_check(
		not drawn.is_empty() and drawn[drawn.size() - 1].distance_to(start) > 2.0
		and drawn[drawn.size() - 1].distance_to(Vector3.ZERO) > 1.0,
		"so the body followed them and is nowhere near the world origin",
		"last drawn %s, start %s" % [
			str(drawn[drawn.size() - 1]) if not drawn.is_empty() else "-", str(start)
		]
	)



## The players voted for another bowl: the server rebuilds its own at the next round's start and the
## client rebuilds to match, from a BOWL sent between the last round's PROP_GONEs and this round's
## PROPs.
func _test_a_voted_bowl_crosses() -> void:
	_section("a voted bowl crosses the wire")
	var before := _client_game.arena.radius
	_server_game.next_bowl_id = &"bfh_big_bowl"
	_server_game.call("_on_round_started", _server_game.round_number + 1)
	await _steps(8)

	_check(_server_game.bowl_id == &"bfh_big_bowl" and absf(_server_game.arena.radius - 54.0) < 0.05,
		"the server rebuilt its bowl to the voted one", "%s at %.1f m" % [_server_game.bowl_id, _server_game.arena.radius])
	var off := 0.0
	var client_obstacles := _client_game.arena.obstacles()
	var server_obstacles := _server_game.arena.obstacles()
	for i in range(mini(client_obstacles.size(), server_obstacles.size())):
		off = maxf(off, client_obstacles[i].distance_to(server_obstacles[i]))
	_check(absf(_client_game.arena.radius - _server_game.arena.radius) < 0.05
			and client_obstacles.size() == server_obstacles.size() and off < 0.01,
		"and the client rebuilt its own to match, every obstacle where the server's is",
		"client %.1f m (was %.1f), server %.1f m, furthest %.3f m apart" % [
			_client_game.arena.radius, before, _server_game.arena.radius, off])
	var server_bodies := int(_server_bridge.describe()["bodies"])
	var client_bodies := int(_client_bridge.describe()["bodies"])
	_check(client_bodies == server_bodies and client_bodies > 0,
		"with the new round's crates mirrored in it", "client %d, server %d" % [client_bodies, server_bodies])
	_done()


## The bowl's toys over the wire: paired by index on both ends, frozen copies, a ball pushed on
## the server followed on the client.
func _test_the_toys_reach_the_client() -> void:
	print("the bowl's toys reach the client")
	await _steps(4)
	var count := _server_game.toys.count() if _server_game.toys != null else 0
	_check(count > 0 and _server_bridge.toy_count() == count and _client_bridge.toy_count() == count,
		"every toy is an entity on both ends, paired by index", "%d toys, %d and %d" % [count, _server_bridge.toy_count(), _client_bridge.toy_count()])
	if count == 0 or _client_game.toys == null or _client_game.toys.count() == 0:
		_done()
		return
	var server_ball := _server_game.toys.toy(0)
	var client_ball := _client_game.toys.toy(0)
	_check(client_ball.body.freeze and not client_ball.authoritative, "the client's are frozen copies")
	var start := client_ball.body.global_position
	var _kicked := _server_game.toys.hit(server_ball.body, server_ball.body.global_position, Vector3(1, 0.2, 0), 2.0)
	await _steps(60)
	var apart := client_ball.body.global_position.distance_to(server_ball.body.global_position)
	_check(server_ball.body.global_position.distance_to(start) > 0.5 and apart < 0.8,
		"a ball pushed on the server is followed on the client",
		"%.2f m moved, %.2f m apart" % [server_ball.body.global_position.distance_to(start), apart])
	_done()


## The server's and the client's workbench over a loopback; the admin rules read [param flags] and [param state].
func _workbench_rig(flags: Dictionary, state: Dictionary) -> Dictionary:
	var snet := _make_manager(true, &"wbserver", 1, self, 60)
	var cnet := _make_manager(false, &"wbclient", 5, self, 60)
	var sconfig := BfhConfig.new()
	var cconfig := BfhConfig.new()
	var sbinder := BfhConfig.make_binder(sconfig)
	var cbinder := BfhConfig.make_binder(cconfig)
	var _l1 := sbinder.load_layers()
	var _l2 := cbinder.load_layers()
	var set: DotProfileSet = null
	for candidate: DotProfileSet in sbinder.profile_sets():
		if candidate.rel_path.ends_with("round"):
			set = candidate
	var cset: DotProfileSet = null
	for candidate: DotProfileSet in cbinder.profile_sets():
		if candidate.rel_path.ends_with("round"):
			cset = candidate
	var swb := DotGameWorkbench.new()
	swb.dedicated = true
	swb.config = {"enabled": false}
	swb.add_set(set, "Game settings")
	add_child(swb)
	var started := swb.start()
	sbinder.attach(swb.api.runtime)
	var made := DotGameWorkbenchRemote.serve(snet)
	var slink := DotNetProfileLink.attach(snet, swb.api.runtime as DotProfileRuntime)
	var cremote := DotGameWorkbenchRemoteClient.attach(cnet)
	var crt := DotProfileRuntime.new()
	var clink := DotNetProfileLink.attach(cnet, crt)
	snet.messages.seal()
	cnet.messages.seal()
	var remote := swb.serve_remote(snet)
	_check(started.ok and made.ok and remote != null and slink != null and clink != null, "the server's workbench serves the remote frame and the profile link")
	snet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := cnet.receive(b, 1)
	cnet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := snet.receive(b, 5)
	var _s := snet.start()
	var _c := cnet.start()
	snet.add_peer(5)
	slink.peer_joined(5)
	remote.enabled_fn = func() -> bool: return state["on"]
	remote.uid_fn = func(_p: int) -> String: return state["uid"]
	remote.connected_fn = func(_p: int) -> bool: return true
	remote.permit_uid_fn = func(uid: String, flag: String) -> bool: return (flags.get(uid, []) as Array).has(flag)
	remote.now_fn = func() -> int: return state["now"]
	remote.limiter = DotRateLimiter.new(1000.0, 1000.0)
	var cwb := DotGameWorkbench.new()
	cwb.panel_mode = 2
	cwb.config = {"enabled": false}
	cwb.remote_client = cremote
	cwb.remote_fn = func() -> bool: return true
	cwb.add_set(cset, "Game settings")
	add_child(cwb)
	var cstarted := cwb.start(crt)
	_check(cstarted.ok and cwb.overlay == null, "the client's workbench starts with no panel")
	return {"snet": snet, "cnet": cnet, "sconfig": sconfig, "sbinder": sbinder, "set": set, "swb": swb, "cwb": cwb,
		"slink": slink, "clink": clink, "cremote": cremote, "crt": crt, "remote": remote}


## sv_workbench_remote over the real frames, in the order BfhModule and BfhClient register them: an admin gets a
## panel and an edit that applies and replicates; a guest, a non-admin, a revoked admin and the cvar off are refused.
func _test_the_remote_workbench() -> void:
	_section("[a flagged admin edits the server's profiles, and nobody else can]")
	if not DotGameWorkbench.available():
		print("  dot-workbench is not linked: skipped")
		_passed += 16
		_done()
		return
	var flags := {"boss": ["cvar", "root"], "plain": []}
	var state := {"on": false, "uid": "", "now": 100000}
	var rig := _workbench_rig(flags, state)
	var snet: DotNetManager = rig["snet"]
	var cnet: DotNetManager = rig["cnet"]
	var sconfig: BfhConfig = rig["sconfig"]
	var sbinder: DotGameConfigBinder = rig["sbinder"]
	var set: DotProfileSet = rig["set"]
	var swb: DotGameWorkbench = rig["swb"]
	var cwb: DotGameWorkbench = rig["cwb"]
	var slink: DotNetProfileLink = rig["slink"]
	var clink: DotNetProfileLink = rig["clink"]
	var cremote: DotGameWorkbenchRemoteClient = rig["cremote"]
	var crt: DotProfileRuntime = rig["crt"]
	var remote: DotGameWorkbenchRemote = rig["remote"]
	var kind: String = set.rel_path
	var edit := {"op": "set", "kind": kind, "id": sbinder.profile_id, "key": "round_seconds", "value": 240.0}
	var srt := swb.api.runtime as DotProfileRuntime

	state["uid"] = "boss"
	cremote.ask()
	_check(not cremote.allowed and cwb.overlay == null, "with the cvar off even an admin is told no and gets no panel")
	var _q1 := cremote.request(edit)
	_check(sconfig.round_seconds == 180.0, "and a request it forges anyway changes nothing on the server")

	state["on"] = true
	cremote.ask()
	_check(cremote.allowed and cremote.flags.has("cvar"), "with the cvar on an admin is told the flags it holds")
	_check(cwb.overlay != null, "and gets the panel")
	var applied: DotResult = cwb.api.handle(DotGameWorkbenchRemoteClient.ACTOR, edit)
	_check(applied.ok and sconfig.round_seconds == 240.0, "an edit from the panel reaches the server's live config", "" if applied.ok else applied.error.message)
	_check(crt.revision(kind, sbinder.profile_id) > 0 and crt.revision(kind, sbinder.profile_id) == srt.revision(kind, sbinder.profile_id), "and its row replicated to the client")

	var back := edit.merged({"value": 300.0})
	state["uid"] = ""
	var _q2 := cremote.request(back)
	_check(sconfig.round_seconds == 240.0, "a guest's forged edit is refused")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel is taken away from it")

	state["uid"] = "plain"
	cremote.ask()
	var _q3 := cremote.request(back)
	_check(not cremote.allowed and sconfig.round_seconds == 240.0, "a player holding no flag is told no and refused")

	state["uid"] = "boss"
	cremote.ask()
	_check(cremote.allowed and cwb.overlay != null, "an admin is let back in")
	flags["boss"] = []
	var _q4 := cremote.request(back)
	_check(sconfig.round_seconds == 240.0, "the revoked admin's next edit is refused at once")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel closes")

	flags["boss"] = ["cvar", "root"]
	state["on"] = false
	var _q5 := cremote.request(back)
	_check(sconfig.round_seconds == 240.0, "switching the cvar off refuses a restored admin too")
	_check(not remote.permit_actor("remote:boss", "cvar"), "and revokes the server-made actors")
	slink.release()
	clink.release()
	swb.queue_free()
	cwb.queue_free()
	snet.queue_free()
	cnet.queue_free()
	_done()


func _test_leaving() -> void:
	_section("leaving")

	# [b]Somebody else first, because that is the half a client is told about.[/b] A peer that
	# disconnects is not sent its own LEAVE — it has gone — so removing this client proves nothing
	# about whether the message works.
	var bot_session := BfhNetBridge.FIRST_BOT_SESSION
	_check(
		_client_game.players.has(BfhNetBridge.player_key(bot_session)),
		"the client has the bot driver"
	)

	_server_bridge.remove_player(bot_session)
	_exchange()
	await _steps(2)

	_check(
		not _client_game.players.has(BfhNetBridge.player_key(bot_session)),
		"and is told when they leave"
	)

	_server_bridge.remove_peer(CLIENT_PEER)
	_exchange()
	await _steps(2)

	_check(_server_player() == null, "the server takes the player out of the world")
	_check(
		int(_server_bridge.describe()["players"]) == 0,
		"and stops replicating them",
		"%d left" % int(_server_bridge.describe()["players"])
	)

	# A removal must not take the bowl with it. The crates belong to the world, not to
	# whoever was standing near them.
	_check(
		int(_client_bridge.describe()["bodies"]) > 0,
		"the bowl is still there",
		"%d bodies" % int(_client_bridge.describe()["bodies"])
	)
	_done()


