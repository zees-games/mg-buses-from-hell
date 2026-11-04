extends "bfh_net_bridge_toys.gd"
## What a client does with each event the server sent: the HELLO, the join, props, seats and the clock.

## Text for one player: a refusal, a rate limit, a command's reply.
func notice(peer_id: int, text: String) -> void:
	_tell(peer_id, BfhEvents.Kind.NOTICE, BfhEvents.write_notice(text))

func _admit(peer_id: int) -> void:
	if peer_id <= 0:
		return

	if not _player_of_peer.has(peer_id):
		_ready_unseated[peer_id] = true
		return

	_ready_peers[peer_id] = true

	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	if profile_link != null:
		profile_link.peer_joined(peer_id)

	var session_id := int(_player_of_peer[peer_id])

	_tell(peer_id, BfhEvents.Kind.HELLO, BfhEvents.write_hello(
		session_id,
		game.tick_rate,
		net.clock.tick,
		game.arena.radius if game.arena != null else game.config.arena_radius,
		game.config.round_seconds,
		game.arena.hook_layout if game.arena != null else game.config.hook_layout,
		game.arena.courtyard_west_lane if game.arena != null else game.config.courtyard_west_lane,
		game.arena.district if game.arena != null else ""
	))

	# The bowl's toys by net id in ring order, which the joiner's own are paired with.
	if not _toys_body.is_empty():
		_tell(peer_id, BfhEvents.Kind.TOYS, _toys_body)

	for other in _behaviours.keys():
		_tell(peer_id, BfhEvents.Kind.JOIN, _join_body(int(other)))

	# And everything standing in the bowl. A player who joins halfway through a round has
	# to be told about every crate that is left, or they walk into cover they cannot see —
	# which in this game is the difference between being run over and not.
	for net_id in _bodies:
		var behaviour: BfhPropNet = _bodies[net_id]

		if behaviour == null or behaviour.prop == null or not is_instance_valid(behaviour.prop):
			continue

		_tell(peer_id, BfhEvents.Kind.PROP, BfhEvents.write_prop(
			int(net_id),
			_kind_of(behaviour),
			behaviour.replicated_position(),
			behaviour is BfhBusNet
		))

	_tell(peer_id, BfhEvents.Kind.CLOCK, _clock_bytes())

func _join_body(session_id: int) -> PackedByteArray:
	var behaviour: BfhPlayerNet = _behaviours.get(session_id)

	if behaviour == null or behaviour.identity == null or behaviour.player == null:
		return PackedByteArray()

	return BfhEvents.write_join(
		session_id,
		behaviour.identity.net_id,
		behaviour.player.display_name,
		game.team_of(behaviour.player.player_id),
		behaviour.player.avatar
	)

func _on_event(message: DotNetMessage) -> void:
	var event := message as BfhEvent

	if event == null or game == null or net == null or net.is_server:
		return

	var reader := event.reader()

	match event.kind:
		BfhEvents.Kind.HELLO:
			_apply_hello(reader)
		BfhEvents.Kind.TOYS:
			var told := BfhEvents.read_toys(reader)
			if bool(told["ok"]):
				_apply_toys(told)
		BfhEvents.Kind.JOIN:
			_apply_join(reader)
		BfhEvents.Kind.LEAVE:
			var session_id := BfhEvents.read_player(reader)
			_release_entity(session_id)
			game.remove_player(player_key(session_id))
			roster_changed.emit(session_id)
		BfhEvents.Kind.TEAM:
			var side := BfhEvents.read_team(reader)
			if bool(side["ok"]):
				game.sides[player_key(int(side["player_id"]))] = int(side["team"])
				roster_changed.emit(int(side["player_id"]))
				_heard_a_swap()
		BfhEvents.Kind.PROP:
			_apply_prop(reader)
		BfhEvents.Kind.PROP_GONE:
			_apply_prop_gone(reader)
		BfhEvents.Kind.SEAT:
			_apply_seat(reader)
		BfhEvents.Kind.CLOCK:
			_apply_clock(reader)
		BfhEvents.Kind.ROUND:
			var round_info := BfhEvents.read_round(reader)
			if bool(round_info["ok"]):
				game.round_number = int(round_info["round"])
				if bool(round_info["began"]):
					game.round_elapsed = 0.0
				round_changed.emit(
					int(round_info["round"]),
					bool(round_info["began"]),
					int(round_info["winner"])
				)
				# And as the world's own signal. See [method _heard_a_swap] for why a client
				# world says what the server's said.
				if bool(round_info["began"]):
					game.round_began.emit(int(round_info["round"]))
				else:
					game.round_over.emit(int(round_info["round"]), int(round_info["winner"]))
		BfhEvents.Kind.DEATH:
			var death := BfhEvents.read_death(reader)
			if bool(death["ok"]):
				# The fall goes on the player before anybody hears of the death, so the client
				# that draws it reads the server's pick.
				var fell: BfhPlayer = game.players.get(player_key(int(death["player_id"]))) \
					if game != null else null
				if fell != null and death.has("death"):
					fell.death = death["death"]
				death_received.emit(int(death["player_id"]), int(death["by"]))
				game.player_died.emit(
					player_key(int(death["player_id"])),
					player_key(int(death["by"])) if int(death["by"]) > 0 else &""
				)
		BfhEvents.Kind.BLAST:
			var blast := BfhEvents.read_blast(reader)
			if bool(blast["ok"]):
				blast_received.emit(blast["position"], float(blast["radius"]))
				game.barrel_exploded.emit(blast["position"], float(blast["radius"]))
		BfhEvents.Kind.BOWL:
			var bowl := BfhEvents.read_bowl(reader)
			if bool(bowl["ok"]):
				_adopt_map(float(bowl["arena_radius"]), str(bowl["hook_layout"]),
					float(bowl["courtyard_west_lane"]), str(bowl["district"]))
		BfhEvents.Kind.SOUND:
			var sound := BfhEvents.read_sound(reader)
			var id := BfhSounds.world_id(int(sound["index"]))
			# An index this build does not know is a newer server: silence, not an error.
			if bool(sound["ok"]) and id != &"":
				game.noise.emit(id, sound["position"])
		BfhEvents.Kind.CHAT:
			var wire := BfhEvents.read_chat(reader)

			if bool(wire["ok"]):
				chat_received.emit(wire)
		BfhEvents.Kind.NOTICE:
			var notice := BfhEvents.read_notice(reader)
			if bool(notice["ok"]):
				notice_received.emit(str(notice["text"]))

## The round a side swap was last announced for, on a client. See [method _heard_a_swap].
var _swap_heard_for: int = -1

## A TEAM arrived: on a client, the world says its sides swapped, once per swap.
func _heard_a_swap() -> void:
	if game == null or _swap_heard_for == game.round_number:
		return

	_swap_heard_for = game.round_number
	game.sides_swapped.emit(game.round_number)

## The server's bowl, built here if it is not the one this client has: from the HELLO on joining,
## and from a BOWL when the players' vote changed it between rounds.
func _adopt_map(radius: float, hook: String, west: float, district: String = "") -> void:
	if game.arena != null and (absf(game.arena.radius - radius) > 0.01
			or game.arena.district != district
			or game.arena.hook_layout != hook
			or absf(game.arena.courtyard_west_lane - west) > 0.005):
		game.arena.hook_layout = hook
		game.arena.courtyard_west_lane = west
		game.arena.district = district
		game.arena.build(radius)

func _apply_hello(reader: DotNetReader) -> void:
	var hello := BfhEvents.read_hello(reader)

	if not bool(hello["ok"]):
		return

	local_player_id = int(hello["player_id"])

	# [b]The server's tick rate, before anything is derived from it.[/b] Another game in this family
	# shipped with HELLO carrying this and nothing reading it: a browser client counted at the 60 its
	# export declared against a server on 128, so the correction rate was 0.96 and every replicated.
	_adopt_tick_rate(int(hello["tick_rate"]))

	var rtt := float(rtt_source.call()) if rtt_source.is_valid() else 0.0
	net.clock.sync_from_server(int(hello["server_tick"]), maxf(0.0, rtt))

	# [b]The map, which in this game is one number.[/b] The bowl is not a file, it is
	# `BfhArena.build(radius)` run on both ends — so a client that kept its own default against a
	# server running a smaller bowl would have its wall, its ledge and its stacks all in the wrong.
	_adopt_map(float(hello["arena_radius"]), str(hello["hook_layout"]),
		float(hello["courtyard_west_lane"]), str(hello["district"]))

	game.config.round_seconds = float(hello["round_seconds"])

	_claim_local_player()

	hello_received.emit(local_player_id)

## Puts the whole client — the world, every player's controller and the ENGINE — on the server's
## tick rate.
func _adopt_tick_rate(rate: int) -> void:
	if net == null or net.is_server or game == null or rate <= 0 or rate == game.tick_rate:
		return

	var before := game.tick_rate

	if not game.set_tick_rate(rate):
		return

	net.config.tick_rate = game.tick_rate
	# The LIVE one, which is built from the config back at `setup()` and is therefore not
	# updated by writing the config alone.
	net.clock.tick_rate = game.tick_rate
	Engine.physics_ticks_per_second = game.tick_rate

	DotLog.info(CHANNEL, "adopted the server's tick rate", {
		"was": before, "now": game.tick_rate, "engine": Engine.physics_ticks_per_second,
	})

func _apply_join(reader: DotNetReader) -> void:
	var join := BfhEvents.read_join(reader)

	if not bool(join["ok"]):
		return

	var session_id := int(join["player_id"])
	var id := player_key(session_id)
	var player: BfhPlayer = game.players.get(id)

	if player == null:
		player = game.add_player(id, str(join["name"]), int(join["team"]))

		if player == null:
			return

		# A client never samples: the client loop hands it commands, and the local player
		# is the only one whose commands exist at all.
		player.sampler = null
		player.samples_input = false

		# Every check passed anyway, because a client adopting the server's answer also agrees with the
		# server.
		var identity := _build_entity(player, _mirror_owner(session_id))
		var registered := net.registry.register(
			identity, int(join["net_id"]), net.clock.tick, net.config
		)

		if not registered.ok:
			DotLog.warn(CHANNEL, "could not mirror a player", {"error": str(registered.error)})
			return
	else:
		player.display_name = str(join["name"])

	# Both branches: a JOIN for somebody this client already has is the server saying who
	# they are NOW — see [method refresh_player].
	player.avatar = join["avatar"]
	game.sides[id] = int(join["team"])
	roster_changed.emit(session_id)

## The local player's mirror, claimed if it arrived before HELLO said whose it was.
func _claim_local_player() -> void:
	var mine: BfhPlayerNet = _behaviours.get(local_player_id)

	if mine == null or mine.identity == null or not mine.identity.is_registered():
		return

	var claimed := _mirror_owner(local_player_id)

	if claimed == 0 or mine.identity.owner_peer_id == claimed:
		return

	DotLog.debug(CHANNEL, "claimed the local player after HELLO", {
		"session": local_player_id, "net_id": mine.identity.net_id,
	})
	var _changed := net.registry.change_owner(mine.identity.net_id, claimed)

## A crate, a barrel, a block or a bus the server has put out.
func _apply_prop(reader: DotNetReader) -> void:
	var info := BfhEvents.read_prop(reader)

	if not bool(info["ok"]):
		return

	var net_id := int(info["net_id"])

	if _bodies.has(net_id):
		return

	var kind_id: StringName = info["kind_id"]
	var scene_path := _scene_for(kind_id, bool(info["vehicle"]))

	if scene_path == "":
		# Not an error: a server may run a catalogue this build does not have, and the
		# honest answer is to draw nothing rather than to guess.
		DotLog.debug(CHANNEL, "something this build does not have", {"id": String(kind_id)})
		return

	var scene: PackedScene = load(scene_path)

	if scene == null:
		DotLog.warn(CHANNEL, "a scene would not load", {"path": scene_path})
		return

	var body := scene.instantiate() as Node3D

	if body == null:
		return

	game.add_child(body)
	body.global_position = info["position"]

	# [b]Frozen before anything else touches it.[/b] A mirrored body must not be simulated
	# locally as well: an unfrozen [RigidBody3D] fights every position written into it and
	# the result is a crate that jitters against gravity while the packets say it is still.
	var rigid := body as RigidBody3D

	if rigid != null:
		rigid.freeze = true

	var behaviour: BfhPropNet = BfhBusNet.new() if bool(info["vehicle"]) else BfhPropNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	identity.always_relevant = true
	body.add_child(identity)

	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not mirror a body", {"error": str(registered.error)})
		body.queue_free()
		return

	_bodies[net_id] = behaviour

## Where a client finds the scene for something the server named.
func _scene_for(kind_id: StringName, vehicle: bool) -> String:
	if vehicle:
		var def := game.vehicles.catalogue.get_vehicle(kind_id) if game.vehicles != null else null
		return def.scene_path if def != null else ""

	var prop := game.props.catalogue.get_prop(kind_id) if game.props != null else null
	return prop.scene_path if prop != null else ""

func _apply_prop_gone(reader: DotNetReader) -> void:
	var info := BfhEvents.read_prop_gone(reader)

	if not bool(info["ok"]):
		return

	var net_id := int(info["net_id"])
	var behaviour: BfhPropNet = _bodies.get(net_id)
	_bodies.erase(net_id)

	if behaviour == null:
		return

	if net != null:
		net.registry.unregister(net_id)

	if behaviour.prop != null and is_instance_valid(behaviour.prop):
		behaviour.prop.queue_free()

## A client's copy of "that player is driving".
func _apply_seat(reader: DotNetReader) -> void:
	var info := BfhEvents.read_seat(reader)

	if not bool(info["ok"]):
		return

	var behaviour: BfhPlayerNet = _behaviours.get(int(info["player_id"]))

	if behaviour == null or behaviour.player == null:
		return

	behaviour.player.set_riding(bool(info["seated"]))

	# The bus they are drawn at, at once. The snapshot's `net_bus` says the same thing and
	# is what a client that joined later goes by; this is only the event arriving first.
	if bool(info["seated"]):
		behaviour.player.ridden = body_of_net_id(int(info["net_id"]))

	seat_changed.emit(int(info["player_id"]), bool(info["seated"]))

func _apply_clock(reader: DotNetReader) -> void:
	var clock := BfhEvents.read_clock(reader)

	if not bool(clock["ok"]):
		return

	game.round_number = int(clock["round"])
	game.round_elapsed = float(clock["elapsed"])
	game.remote_cover = int(clock["cover"])
	game.remote_playable = bool(clock["playable"])
	game.remote_rounds = {
		BfhGame.TEAM_DRIVERS: int(clock["drivers_won"]),
		BfhGame.TEAM_RUNNERS: int(clock["runners_won"]),
	}
