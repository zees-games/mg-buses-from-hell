extends "headless_net_harness.gd"
## The wire: the join, the bowl arriving, the bus, and the local runner's prediction.

const BfhKillcam := preload("../game/bfh_killcam.gd")

const CHECKS := 233

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 27


## Frames drawn per tick in [method _test_somebody_else_is_drawn], each at its own fraction
## through the tick, which is what a screen faster than the tick rate does.
const FRAMES_PER_TICK := 4


## Counts the engine's own errors while installed (mg-smash-copter's dedicated suite has the
## same class): they go to stderr and change no exit code, so only this makes one fail a run.
class EngineErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_seen.append("%s (%s)" % [code, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out

## Every encoder against its decoder, because nothing else checks that they are inverses.
func _test_the_wire() -> void:
	_section("the wire format")

	var hello := BfhEvents.read_hello(DotNetReader.new(
		BfhEvents.write_hello(SESSION, 128, 9001, 44.0, 180.0, "wide", 6.6)
	))
	_check(bool(hello["ok"]), "hello round-trips")
	_check(int(hello["player_id"]) == SESSION, "hello: who you are")
	_check(int(hello["tick_rate"]) == 128, "hello: at what rate")
	_check(int(hello["server_tick"]) == 9001, "hello: and from which tick")
	_check(
		absf(float(hello["arena_radius"]) - 44.0) < 0.05,
		"hello: how big the bowl is, which in this game IS the map",
		"%.3f" % float(hello["arena_radius"])
	)
	_check(
		absf(float(hello["round_seconds"]) - 180.0) < 0.1,
		"hello: and how long a round is"
	)
	_check(
		str(hello["hook_layout"]) == "wide"
			and absf(float(hello["courtyard_west_lane"]) - 6.6) < 0.005,
		"hello: and the layout an operator chose, the hook and the courtyard's west lane",
		"%s, %.3f" % [str(hello["hook_layout"]), float(hello["courtyard_west_lane"])]
	)

	var bowl := BfhEvents.read_bowl(DotNetReader.new(BfhEvents.write_bowl(54.0, "tight", 7.6)))
	_check(bool(bowl["ok"]) and absf(float(bowl["arena_radius"]) - 54.0) < 0.05
			and str(bowl["hook_layout"]) == "tight" and absf(float(bowl["courtyard_west_lane"]) - 7.6) < 0.005,
		"bowl round-trips: the map a vote changed between rounds", str(bowl))

	_check(str(hello["district"]) == "" and str(bowl["district"]) == "",
		"neither names a district unless the map is one")
	var town_hello := BfhEvents.read_hello(DotNetReader.new(
		BfhEvents.write_hello(SESSION, 128, 9001, 52.0, 180.0, "tight", 7.6, "bfh_hill_town")))
	var town_bowl := BfhEvents.read_bowl(DotNetReader.new(
		BfhEvents.write_bowl(56.0, "tight", 7.6, "bfh_suburb")))
	_check(bool(town_hello["ok"]) and str(town_hello["district"]) == "bfh_hill_town"
			and bool(town_bowl["ok"]) and str(town_bowl["district"]) == "bfh_suburb",
		"hello and bowl carry the district a client must build", "%s, %s" % [town_hello["district"], town_bowl["district"]])

	_wire_join_and_team()
	_wire_props_and_seat()
	_wire_clock_and_events()
	_wire_truncated_and_asks()
	_done()


## Join, with and without a face, and a side change.
func _wire_join_and_team() -> void:
	var join := BfhEvents.read_join(DotNetReader.new(
		BfhEvents.write_join(SESSION, 31, "Ada", BfhGame.TEAM_DRIVERS)
	))
	_check(bool(join["ok"]) and int(join["net_id"]) == 31, "join round-trips")
	_check(str(join["name"]) == "Ada", "join: with a name")
	_check(int(join["team"]) == BfhGame.TEAM_DRIVERS, "join: and a side")
	_check(join["avatar"] == null, "join: and no face is the stock person, not a refused join")

	var face := BfhAvatars.stock_avatar(&"u1")
	face.set_part(BfhAvatars.SLOT_SKIN, &"skin_k")
	var faced := BfhEvents.read_join(DotNetReader.new(
		BfhEvents.write_join(SESSION, 31, "Ada", BfhGame.TEAM_RUNNERS, face)
	))
	_check(
		bool(faced["ok"]) and faced["avatar"] is DotAvatar
			and (faced["avatar"] as DotAvatar).digest() == face.digest()
			and int(faced["team"]) == BfhGame.TEAM_RUNNERS,
		"join: and a face, after the side rather than in front of it"
	)

	var team := BfhEvents.read_team(DotNetReader.new(
		BfhEvents.write_team(SESSION, BfhGame.TEAM_RUNNERS)
	))
	_check(
		bool(team["ok"]) and int(team["team"]) == BfhGame.TEAM_RUNNERS,
		"a side change round-trips"
	)



## Props, a bus, a removal and a seat.
func _wire_props_and_seat() -> void:
	var at := Vector3(12.5, 1.25, -30.75)
	var prop := BfhEvents.read_prop(DotNetReader.new(
		BfhEvents.write_prop(17, BfhContent.BARREL, at, false)
	))
	_check(bool(prop["ok"]) and int(prop["net_id"]) == 17, "a prop round-trips")
	_check(
		(prop["kind_id"] as StringName) == BfhContent.BARREL,
		"prop: by catalogue id, which is what lets a client build it"
	)
	_check(
		(prop["position"] as Vector3).distance_to(at) < 0.01,
		"prop: at the quantised position",
		str(prop["position"])
	)
	_check(not bool(prop["vehicle"]), "prop: and it is not a vehicle")

	var bus := BfhEvents.read_prop(DotNetReader.new(
		BfhEvents.write_prop(18, BfhContent.BUS, at, true)
	))
	_check(
		bool(bus["ok"]) and bool(bus["vehicle"]),
		"and a bus round-trips as one, which is which catalogue to look in"
	)

	var gone := BfhEvents.read_prop_gone(DotNetReader.new(
		BfhEvents.write_prop_gone(17, DotPropSpawner.REASON_CLEANUP)
	))
	_check(
		bool(gone["ok"]) and (gone["reason"] as StringName) == DotPropSpawner.REASON_CLEANUP,
		"a removal round-trips, with the reason"
	)

	var seat := BfhEvents.read_seat(DotNetReader.new(BfhEvents.write_seat(SESSION, 18, true)))
	_check(
		bool(seat["ok"]) and bool(seat["seated"]) and int(seat["net_id"]) == 18,
		"a seat round-trips"
	)



## The clock, a round result, a blast and a death.
func _wire_clock_and_events() -> void:
	var at := Vector3(12.5, 1.25, -30.75)
	var clock := BfhEvents.read_clock(DotNetReader.new(
		BfhEvents.write_clock(3, 42.5, 27, 4, true, 5, 2)
	))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3, "the clock round-trips")
	_check(
		absf(float(clock["elapsed"]) - 42.5) < 0.1,
		"clock: the seconds", "%.3f" % float(clock["elapsed"])
	)
	_check(
		int(clock["cover"]) == 27 and int(clock["alive"]) == 4,
		"clock: and the two numbers a client cannot count for itself"
	)
	_check(
		int(clock["drivers_won"]) == 5 and int(clock["runners_won"]) == 2,
		"clock: and the rounds each side has won, which is what dot-match scores here"
	)

	var round_over := BfhEvents.read_round(DotNetReader.new(
		BfhEvents.write_round(2, false, BfhGame.TEAM_RUNNERS)
	))
	_check(
		bool(round_over["ok"]) and int(round_over["winner"]) == BfhGame.TEAM_RUNNERS,
		"a round result round-trips"
	)

	var blast := BfhEvents.read_blast(DotNetReader.new(BfhEvents.write_blast(at, 6.5)))
	_check(
		bool(blast["ok"]) and absf(float(blast["radius"]) - 6.5) < 0.05,
		"a blast round-trips"
	)

	var death := BfhEvents.read_death(DotNetReader.new(BfhEvents.write_death(SESSION, 9)))
	_check(
		bool(death["ok"]) and int(death["by"]) == 9, "a death round-trips, with who did it"
	)



## Truncated packets, noises, the spectator's asks, and the kind fields.
func _wire_truncated_and_asks() -> void:
	var at := Vector3(12.5, 1.25, -30.75)
	# [b]A truncated packet must NOT decode as a valid message about nothing.[/b] dot-net
	# shipped with reader exhaustion that was not sticky, so a decoder that skipped the
	# check got a believable value for the field after the overrun.
	var short := BfhEvents.read_join(DotNetReader.new(
		BfhEvents.write_join(SESSION, 31, "Ada", 1).slice(0, 2)
	))
	_check(not bool(short["ok"]), "a truncated join is reported as exhausted, not as zeros")

	var short_clock := BfhEvents.read_clock(DotNetReader.new(
		BfhEvents.write_clock(3, 42.5, 27, 4, true, 5, 2).slice(0, 2)
	))
	_check(not bool(short_clock["ok"]), "and so is a truncated clock")

	var sound := BfhEvents.read_sound(DotNetReader.new(
		BfhEvents.write_sound(BfhSounds.world_index(BfhSounds.RUNNER_DOWN), at)
	))
	_check(
		bool(sound["ok"]) and BfhSounds.world_id(int(sound["index"])) == BfhSounds.RUNNER_DOWN
		and (sound["position"] as Vector3).distance_to(at) < 0.01,
		"a noise round-trips, as an index into the world's list and a place"
	)
	_check(
		BfhSounds.world_id(BfhSounds.WORLD.size()) == &""
		and BfhSounds.world_index(BfhSounds.BUS_ENGINE) < 0,
		"an index this build does not know is silence, and the engine is never sent"
	)

	var watch := BfhEvents.read_watch(DotNetReader.new(
		BfhEvents.write_watch(BfhSpectate.ASK_VIEW)
	))
	_check(
		bool(watch["ok"]) and int(watch["ask"]) == BfhSpectate.ASK_VIEW,
		"a spectator's click round-trips, and it is only the ask — never who to watch"
	)

	var roam_ask := BfhEvents.read_watch(DotNetReader.new(
		BfhEvents.write_watch(BfhSpectate.ASK_ROAM)
	))
	_check(
		bool(roam_ask["ok"]) and int(roam_ask["ask"]) == BfhSpectate.ASK_ROAM,
		"and so does the free-camera ask, the fourth value of the same two bits"
	)

	# The writer masks a value to its field, so a kind past the field goes out as a smaller
	# one and nothing errors: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(BfhEvent.fits(), "every event kind fits the event's kind field",
		"%d kinds in %d bits" % [BfhEvents.Kind.size(), BfhEvent.KIND_BITS])
	_check(BfhRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [BfhEvents.Ask.size(), BfhRequest.KIND_BITS])
	_check(BfhEvents.chat_kinds_fit(), "every chat kind fits the chat line's kind field",
		"%d kinds in %d bits" % [DotChatMessage.KIND_NAMES.size(), BfhEvents.CHAT_KIND_BITS])


func _test_a_client_joins() -> void:
	_section("a client joins")

	# The READY first, as over ENet with loss: a client is PLAYING by its own reckoning once it has
	# sent `loaded`, on another channel, so its READY can reach the server before its seat. Kept,
	# and answered by the seat; a bridge that drops it never tells this client who it is.
	_client_bridge.ask_ready()
	_exchange()
	_check(_client_bridge.local_player_id != SESSION, "a READY before the seat is told nothing yet")

	var added := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_check(added.ok, "the server adds the player", str(added.error) if not added.ok else "")
	_check(_server_player() != null, "and the world has them")
	_check(
		int(_server_bridge.describe()["players"]) == 2,
		"with an entity replicating them, beside the bot's",
		"%d entities" % int(_server_bridge.describe()["players"])
	)

	_exchange()
	await _steps(4)

	_check(
		_client_bridge.local_player_id == SESSION,
		"the client is told who it is",
		str(_client_bridge.local_player_id)
	)
	_check(_client_player() != null, "and builds the player")
	_check(
		_client_player() != null and _client_player().sampler == null,
		"which samples nothing: a client's commands come from its own loop"
	)

	# The whole point of the disagreements set up in `_build`.
	_check(
		_client_game.tick_rate == _server_game.tick_rate,
		"the client adopted the server's tick rate through HELLO",
		"client %d, server %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	_check(
		Engine.physics_ticks_per_second == _server_game.tick_rate,
		"and so did the engine, which is what decides whether it looks smooth",
		"engine %d" % Engine.physics_ticks_per_second
	)
	_check(
		_client_net.clock.tick_rate == _server_game.tick_rate,
		"and the netcode clock, which is built from the config and not updated by it"
	)
	_check(
		absf(_client_game.arena.radius - _server_game.arena.radius) < 0.05,
		"and rebuilt its bowl at the server's radius, which in this game is the map",
		"client %.1f m, server %.1f m" % [
			_client_game.arena.radius, _server_game.arena.radius
		]
	)
	var layout_off := 0.0
	var client_obstacles := _client_game.arena.obstacles()
	var server_obstacles := _server_game.arena.obstacles()
	for i in range(mini(client_obstacles.size(), server_obstacles.size())):
		layout_off = maxf(layout_off, client_obstacles[i].distance_to(server_obstacles[i]))
	_check(
		client_obstacles.size() == server_obstacles.size() and layout_off < 0.01
			and _client_game.arena.hook_layout == _server_game.arena.hook_layout
			and _client_game.arena.hook_layout != "wide",
		"and built the server's hook and courtyard, not the ones it started with",
		"%d vs %d obstacles, furthest %.3f m apart, hook %s" % [
			client_obstacles.size(), server_obstacles.size(), layout_off,
			_client_game.arena.hook_layout
		]
	)
	_check(
		_client_game.team_of(BfhNetBridge.player_key(SESSION)) == BfhGame.TEAM_RUNNERS,
		"the client knows which side they are on",
		"team %d" % _client_game.team_of(BfhNetBridge.player_key(SESSION))
	)
	_check(
		_server_game.team_of(BfhNetBridge.player_key(SESSION)) == BfhGame.TEAM_RUNNERS,
		"which is the side the server put them on: the seats were already taken"
	)
	_done()



func _test_the_bowl_arrives() -> void:
	_section("the bowl arrives")

	await _steps(6)

	var server_bodies := int(_server_bridge.describe()["bodies"])
	var client_bodies := int(_client_bridge.describe()["bodies"])

	_check(
		client_bodies == server_bodies and client_bodies > 0,
		"every crate, barrel and block in the bowl is mirrored",
		"client %d, server %d" % [client_bodies, server_bodies]
	)

	# A mirrored body has to be where the server says, and it has to have got there from a SNAPSHOT
	# rather than from the announcement: the PROP event carries a spawn position, so a client that
	# never applied a snapshot would still pass a naive comparison.
	var moved := 0
	var matched := 0

	for prop in _server_game.props.all_props():
		if prop.body() == null:
			continue

		var mirror := _mirror_near(prop.body().global_position)

		if mirror == null:
			continue

		matched += 1

		if mirror.replicated_position().distance_to(prop.body().global_position) < 0.35:
			moved += 1

	_check(matched > 0, "the mirrors are findable", "%d matched" % matched)
	_check(
		moved == matched,
		"and each one is drawn where the server's body settled",
		"%d of %d within 35 cm" % [moved, matched]
	)

	var frozen := 0
	var total := 0

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour.prop is RigidBody3D:
			total += 1
			if (behaviour.prop as RigidBody3D).freeze:
				frozen += 1

	_check(
		total > 0 and frozen == total,
		"every mirrored body is frozen, or it fights the packets it is being moved by",
		"%d of %d" % [frozen, total]
	)
	_done()


## The client's table, which is private on purpose — a suite is allowed to reach in.
func _client_bodies() -> Dictionary:
	return _client_bridge.get("_bodies")


func _mirror_near(at: Vector3) -> BfhPropNet:
	var best: BfhPropNet = null
	var best_distance := 1.5

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour == null or behaviour.prop == null:
			continue

		var distance := behaviour.prop.global_position.distance_to(at)

		if distance < best_distance:
			best_distance = distance
			best = behaviour

	return best



func _test_the_bus() -> void:
	_section("the bus")

	await _steps(10)

	var buses := 0
	var client_buses: Array[BfhBusNet] = []

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour is BfhBusNet:
			client_buses.append(behaviour)

	for id in _server_game.vehicles.all_vehicles():
		buses += 1

	_check(buses > 0, "the server has a bus on the floor", "%d" % buses)
	_check(
		client_buses.size() == buses,
		"and the client mirrors it as a vehicle rather than as a crate",
		"%d of %d" % [client_buses.size(), buses]
	)

	if client_buses.is_empty():
		_check(false, "there is a mirrored bus to drive")
		_check(false, "the mirror's wheels are drawn from the wire")
		_check(false, "and its position follows the server's")
		_done()
		return

	_check(true, "there is a mirrored bus to drive")

	# The bot floors it at the nearest runner, so the bus moves — and everything about the
	# mirror below is only meaningful because it does.
	await _steps(60)

	var server_bus: DotVehicleInstance = _server_game.vehicles.all_vehicles()[0]
	var mirror := client_buses[0]

	_check(
		mirror.prop != null and mirror.prop.has_method("draw_steering"),
		"the mirror's wheels are drawn from the wire"
	)
	# [b]Off the replicated layout, not off the node.[/b] A bus goes over the wire through
	# [DotVehicleNetSync] — three floats, a quantised quaternion, a speed and a steering angle — and
	# NOT through the `net_position` a crate uses.
	_check(
		mirror.replicated_position().distance_to(server_bus.position()) < 1.5,
		"and its position follows the server's",
		"%.2f m apart" % mirror.replicated_position().distance_to(server_bus.position())
	)
	_check(
		mirror.prop.global_position.distance_to(server_bus.position()) < 1.5,
		"and the body is drawn there, rather than only the property being right",
		"%.2f m apart" % mirror.prop.global_position.distance_to(server_bus.position())
	)
	_done()



func _test_moving() -> void:
	_section("a runner moves")

	var server_player := _server_player()
	var client_player := _client_player()

	if server_player == null or client_player == null:
		_check(false, "both ends have the player")
		_done()
		return

	_check(true, "both ends have the player")

	var before := server_player.controller.state.position
	await _steps(40, _forward())
	var after := server_player.controller.state.position

	# [b]At what speed, not only whether.[/b] "More than a metre in 40 ticks" is a sixth of what 40
	# ticks at `runner_speed` covers, so a runner the server moved at a fifth of their speed passed it.
	var top := server_player.controller.tunables.max_speed
	var v := server_player.controller.state.velocity
	var speed := Vector2(v.x, v.z).length()
	print("  ..    40 ticks of forward from the client: the server moved them %.2f m of %.2f at max_speed, at %.2f m/s of %.2f"
		% [after.distance_to(before), top * 40.0 / float(SERVER_TICK_RATE), speed, top])
	_check(
		after.distance_to(before) > 1.0 and absf(speed - top) < 0.05,
		"the server moves them from the commands the client sent, at runner_speed",
		"%.2f m, %.2f of %.2f m/s" % [after.distance_to(before), speed, top]
	)

	# [b]The client predicted the same move rather than waiting for the answer.[/b] This is the one
	# thing in the whole game that IS predicted, and the measurement that says so is that the two are
	# close — not that the client moved at all, which a client simply adopting snapshots would also do.
	_check(
		client_player.controller.state.position.distance_to(after) < 1.0,
		"and the client's prediction agrees with it",
		"%.2f m apart" % client_player.controller.state.position.distance_to(after)
	)

	_check(
		_corrections() < 20,
		"without being corrected on every snapshot",
		"%d corrections" % _corrections()
	)
	_done()



func _identity_of(player: BfhPlayer) -> DotNetIdentity:
	if player == null:
		return null

	return player.get_node_or_null("Identity") as DotNetIdentity


## What the client shows of its own runner. The node, because that is what the camera
## hangs off and what the predictor measures a correction against.
func _client_shown() -> Vector3:
	var p := _client_player()
	return p.global_position if p != null else Vector3.ZERO


## Prediction corrections per second over [param ticks] ticks of [param command].
func _corrections_per_second(ticks: int, command: DotFpsCommand) -> float:
	var before := _corrections()
	await _steps(ticks, command)
	return float(_corrections() - before) * float(SERVER_TICK_RATE) / float(ticks)


## [b]The local runner is predicted, and nobody else is.[/b]
func _test_the_local_runner_is_predicted() -> void:
	_section("the local runner is predicted, and nobody else is")

	var client_player := _client_player()
	var server_player := _server_player()
	var mine := _identity_of(client_player)

	if mine == null or server_player == null:
		_check(false, "the client has an identity for its own runner")
		for _i in range(11):
			_check(false, "(skipped: no local identity)")
		_done()
		return

	_check(true, "the client has an identity for its own runner")
	_check(
		mine.owner_peer_id == _client_net.local_peer_id and mine.is_owner,
		"which this client owns",
		"owner %d, local peer %d, is_owner %s" % [
			mine.owner_peer_id, _client_net.local_peer_id, mine.is_owner
		]
	)

	var predicted := _client_net.registry.predicted()
	_check(
		mine.is_predicted() and predicted.has(mine),
		"and predicts: the registry's predicted set holds it",
		"%d predicted" % predicted.size()
	)

	# The bot driver is somebody else's, and a client predicting them would be simulating
	# a person whose keys it never had.
	var bot: BfhPlayer = null

	for id: StringName in _client_game.players:
		if id != BfhNetBridge.player_key(SESSION):
			bot = _client_game.players[id]

	var theirs := _identity_of(bot)
	_check(
		theirs != null and not theirs.is_owner and not theirs.is_predicted()
			and not predicted.has(theirs),
		"and nobody else's runner is predicted",
		"%d predicted of %d players" % [predicted.size(), _client_game.players.size()]
	)

	await _predicted_a_key_moves(server_player)
	await _predicted_straight_then_stopped(server_player)
	await _predicted_a_teleport_converges(server_player, client_player)
	await _predicted_a_crate_and_an_early_join(server_player, mine)
	_done()


## One tick by hand moves the runner on the client before the server has simulated it.
func _predicted_a_key_moves(server_player: BfhPlayer) -> void:
	# Stand still first, so the next tick starts from agreement.
	await _steps(30)

	# [b]One tick by hand, measured between the client's tick and the flush that would
	# carry anything back.[/b] The server has already simulated this tick without the
	# command — it is stamped `INPUT_LEAD` ahead — so any movement here is the client's own.
	_tick += 1
	_client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()

	var shown_before := _client_shown()
	var server_before := server_player.controller.state.position
	_client_bridge.client_tick(_tick + INPUT_LEAD, _forward())
	var shown_after := _client_shown()

	_check(
		shown_after.distance_to(shown_before) > 0.005,
		"a key moves the runner on the client in the tick it is pressed",
		"%.4f m" % shown_after.distance_to(shown_before)
	)
	_check(
		server_player.controller.state.position.distance_to(server_before) < 0.0001,
		"before the server has simulated it, and before any snapshot",
		"server moved %.4f m" % server_player.controller.state.position.distance_to(
			server_before
		)
	)

	_flush()
	await get_tree().physics_frame


## Corrections per second running straight, and the two ends agreeing once stopped.
func _predicted_straight_then_stopped(server_player: BfhPlayer) -> void:
	# A straight line: the two ends run the same controller from the same commands, so a
	# healthy predictor is corrected rarely. Printed, because it is the number to watch.
	var straight := await _corrections_per_second(120, _forward())
	# Signed, along the run (-Z): positive is the client showing the runner AHEAD of the
	# server, which is what prediction with an input lead looks like; negative is a client
	# drawing what the server said a round trip ago.
	var lead := (_client_shown() - server_player.controller.state.position).dot(Vector3.FORWARD)
	print("        corrections/s running straight: %.2f  (client shows the runner %+.2f m from the server)" % [
		straight, lead
	])

	await _steps(30)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.05,
		"stopped, the client shows the runner where the server has them",
		"%.3f m apart" % _client_shown().distance_to(server_player.controller.state.position)
	)



## A move the client did not predict is corrected, converges and then stays converged.
func _predicted_a_teleport_converges(server_player: BfhPlayer, client_player: BfhPlayer) -> void:
	# [b]A disagreement the client cannot know about[/b]: an admin moves the runner on the server.
	var corrections_before := _corrections()
	var moved_to := server_player.controller.state.position + Vector3(1.2, 0.0, 0.0)
	server_player.controller.teleport(
		moved_to, server_player.controller.state.yaw, server_player.controller.state.pitch
	)
	await _steps(30)

	_check(
		_corrections() > corrections_before,
		"a move the client did not predict is corrected",
		"%d corrections" % (_corrections() - corrections_before)
	)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.05
			and client_player.controller.state.position.distance_to(moved_to) < 0.1,
		"and converges on where the server put them",
		"%.3f m apart, %.3f m from the teleport" % [
			_client_shown().distance_to(server_player.controller.state.position),
			client_player.controller.state.position.distance_to(moved_to),
		]
	)

	var settled := _corrections()
	await _steps(30)
	_check(
		_corrections() == settled,
		"and then stays converged: no correction while nothing disagrees",
		"%d more" % (_corrections() - settled)
	)



## Running into a crate, then a local runner mirrored before its HELLO.
func _predicted_a_crate_and_an_early_join(server_player: BfhPlayer, mine: DotNetIdentity) -> void:
	# Into a crate: a body the server simulates and the client only mirrors, frozen, at the
	# snapshot's position. The one place the two ends are computing against different
	# geometry, so the one place corrections are expected. Measured, not asserted.
	var ahead := server_player.controller.state.position + Vector3(0.0, 0.6, -2.4)
	var crate := _server_game.props.spawn(BfhContent.CRATE, &"world", ahead)
	await _steps(10)
	var runner_from := server_player.controller.state.position
	var crate_from := crate.body().global_position if crate != null and crate.body() != null \
		else Vector3.ZERO
	var bump := await _corrections_per_second(90, _forward())
	var crate_moved := (
		crate.body().global_position.distance_to(crate_from)
		if crate != null and crate.body() != null else -1.0
	)
	print("        corrections/s running into a crate: %.2f  (runner %.2f m before it stopped them, crate %.2f m)" % [
		bump, server_player.controller.state.position.distance_to(runner_from), crate_moved,
	])

	await _steps(30)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.1,
		"and after the crate, the two ends agree again",
		"%.3f m apart" % _client_shown().distance_to(server_player.controller.state.position)
	)

	# [b]A JOIN that beat its HELLO.[/b] `_admit` sends HELLO first, so the order this guards is not
	# one the server produces today — which is exactly why it is driven through the real path rather
	# than trusted: the local entity is put back to how an early JOIN would have built it (owned by.
	var _unclaimed := _client_net.registry.change_owner(mine.net_id, 0)
	_server_bridge._admit(CLIENT_PEER)
	_exchange()
	await _steps(2)
	_check(
		mine.owner_peer_id == _client_net.local_peer_id and mine.is_predicted(),
		"a local runner mirrored before HELLO is claimed when HELLO arrives",
		"owner %d, predicted %s" % [mine.owner_peer_id, mine.is_predicted()]
	)
	var kc := BfhKillcam.new()
	_check(kc.camera_mode_fn.call() == DotKillViewRules.Camera.EYE, "the killcam camera is the eye until the server says")
	var framing := DotKillcamFraming.new(null, 1)
	var eye := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var placed: Dictionary = framing.place(DotKillViewRules.Camera.BEHIND, eye, 75.0, Vector3(0, 1.2, -20))
	_check((placed["transform"] as Transform3D).origin.z > 1.0, "the behind camera sits behind the killer's eye")
	kc.free()


