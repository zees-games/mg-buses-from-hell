extends "bfh_net_bridge_apply.gd"
## What the server replicates: players and bots joining and leaving, props, vehicles, rides, rounds and deaths.

# --- Server: players

## Puts a connected peer into the game. What [DotGameRoster] calls.
func add_player(peer_id: int, session_id: int, display_name: String) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	if peer_id > 0:
		# FIRST, because `game.add_player` emits `player_added` and the handler has to be
		# able to find which peer this player belongs to.
		_player_of_peer[peer_id] = session_id
		_peer_of_player[session_id] = peer_id

	var player := game.add_player(player_key(session_id), display_name)

	if player == null:
		_player_of_peer.erase(peer_id)
		_peer_of_player.erase(session_id)
		return DotResult.fail(DotError.CODE_STATE, "The game refused the player.")

	if _ready_unseated.has(peer_id):
		_ready_unseated.erase(peer_id)
		_admit(peer_id)

	return DotResult.success(player)

## Somebody the world drives itself: a bot driver, or a test's stand-in for one.
func add_bot(display_name: String, team: int = 0) -> BfhPlayer:
	if net == null or not net.is_server or game == null:
		return null

	var session_id := _next_bot_session
	_next_bot_session += 1

	# A bot from its first line: `player_added` is answered by things that must not count
	# one, so the flag cannot wait for this call to return. See [method BfhGame.add_player].
	var player := game.add_player(player_key(session_id), display_name, team, false, true)

	if player == null:
		return null

	return player

func remove_peer(peer_id: int) -> void:
	_ready_unseated.erase(peer_id)

	if _player_of_peer.has(peer_id):
		remove_player(int(_player_of_peer[peer_id]))

## Removes a player whether or not a peer is behind it — a bot has none.
func remove_player(session_id: int) -> void:
	if not _behaviours.has(session_id):
		return

	var peer_id := peer_for_player(session_id)
	var was_ready := _ready_peers.has(peer_id)

	_player_of_peer.erase(peer_id)
	_peer_of_player.erase(session_id)
	_ready_peers.erase(peer_id)

	# Released BEFORE the game is told: `game.remove_player` emits `player_removed`, which
	# `_on_player_removed` answers by releasing the entity and broadcasting the LEAVE.
	_release_entity(session_id)
	game.remove_player(player_key(session_id))

	if net != null and peer_id > 0:
		if was_ready:
			net.remove_peer(peer_id)
		if net.interest != null:
			net.interest.forget_peer(peer_id)

	_broadcast(BfhEvents.Kind.LEAVE, BfhEvents.write_player(session_id))
	roster_changed.emit(session_id)

## A player the game made itself — a bot, a test — gets an entity exactly like one a peer asked for.
func _on_player_added(id: StringName) -> void:
	if net == null or not net.is_server:
		return

	var session_id := session_of(id)

	if _behaviours.has(session_id):
		return

	# [b]Every id on the wire is `u<session>`, and anything else parses back to zero.[/b] A world that
	# added a player called `bot` would replicate it under session 0 — which is also dot-net's
	# broadcast address — and a second one would silently replace the first in this table.
	if player_key(session_id) != id:
		DotLog.warn(CHANNEL, "a player whose id is not a session key is not replicated", {
			"id": String(id), "hint": "use add_bot() or BfhNetBridge.player_key()",
		})
		return

	var player: BfhPlayer = game.players.get(id)

	if player == null:
		return

	var identity := _build_entity(player, peer_for_player(session_id))
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a player", {"error": str(registered.error)})
		return

	# Before the JOIN, so the first thing anybody hears about this person is their face.
	if player.avatar == null and avatar_fn.is_valid():
		var avatar: Variant = avatar_fn.call(session_id)
		player.avatar = avatar as DotAvatar if avatar is DotAvatar else null

	_broadcast(BfhEvents.Kind.JOIN, _join_body(session_id))
	roster_changed.emit(session_id)

func _on_player_removed(id: StringName) -> void:
	var session_id := session_of(id)

	if _behaviours.has(session_id):
		# The game removed them itself; the entity and the LEAVE are still ours.
		_release_entity(session_id)
		_broadcast(BfhEvents.Kind.LEAVE, BfhEvents.write_player(session_id))
		roster_changed.emit(session_id)

# --- Server: what is in the bowl

## Every crate, barrel and block the world puts out becomes a replicated entity.
func _on_prop_spawned(prop: DotPropInstance) -> void:
	if net == null or not net.is_server or prop == null or prop.node == null:
		return

	var body := prop.node as Node3D

	if body == null:
		return

	var behaviour := BfhPropNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var net_id := _replicate_body(behaviour, body)

	if net_id == 0:
		return

	_net_of["p%d" % prop.instance_id] = net_id
	behaviour.pull()

	_broadcast(BfhEvents.Kind.PROP, BfhEvents.write_prop(
		net_id, prop.def.id, body.global_position, false
	))

func _on_prop_removed(prop: DotPropInstance, reason: StringName) -> void:
	_forget_body("p%d" % prop.instance_id, reason)

## A bus, which replicates through [DotVehicleNetSync] rather than as a plain body.
func _on_vehicle_spawned(vehicle: DotVehicleInstance) -> void:
	if net == null or not net.is_server or vehicle == null:
		return

	var body := vehicle.body()

	if body == null:
		return

	var behaviour := BfhBusNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	behaviour.vehicle = vehicle
	body.add_child(behaviour)

	var net_id := _replicate_body(behaviour, body)

	if net_id == 0:
		return

	_net_of["v%d" % vehicle.instance_id] = net_id
	behaviour.pull()

	_broadcast(BfhEvents.Kind.PROP, BfhEvents.write_prop(
		net_id, vehicle.def.id, body.global_position, true
	))

func _on_vehicle_removed(vehicle: DotVehicleInstance, reason: StringName) -> void:
	_forget_body("v%d" % vehicle.instance_id, reason)

## The half a crate and a bus do identically: an identity, a registration, a table entry.
func _replicate_body(behaviour: DotNetBehaviour, body: Node3D) -> int:
	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	# SERVER, not SHARED: nothing about a rigid body is predicted here, so there is no
	# owner to share with. See [BfhPropNet] for why that is a decision and not a gap.
	identity.authority = DotNetIdentity.Authority.SERVER
	identity.always_relevant = true
	body.add_child(identity)

	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a body", {"error": str(registered.error)})
		return 0

	_bodies[identity.net_id] = behaviour
	return identity.net_id

func _forget_body(key: String, reason: StringName) -> void:
	if net == null or not net.is_server or not _net_of.has(key):
		return

	var net_id := int(_net_of[key])
	_net_of.erase(key)
	_bodies.erase(net_id)

	net.registry.unregister(net_id)
	_broadcast(BfhEvents.Kind.PROP_GONE, BfhEvents.write_prop_gone(net_id, reason))

# --- Server: the round

func _on_ride_entered(
	vehicle: DotVehicleInstance, rider_id: StringName, _seat: DotVehicleSeat
) -> void:
	_announce_seat(vehicle, rider_id, true)

func _on_ride_exited(
	vehicle: DotVehicleInstance, rider_id: StringName, _seat: DotVehicleSeat, _at: Vector3
) -> void:
	_announce_seat(vehicle, rider_id, false)

func _announce_seat(vehicle: DotVehicleInstance, rider_id: StringName, seated: bool) -> void:
	if net == null or not net.is_server:
		return

	_broadcast(BfhEvents.Kind.SEAT, BfhEvents.write_seat(
		session_of(rider_id), net_id_of_node(vehicle.body()), seated
	))

## The bowl was rebuilt for the round about to begin. Told now, between the last round's
## PROP_GONEs and this round's PROPs, so every crate lands on the floor it was laid on.
func _on_bowl_changed(_bowl_id: StringName) -> void:
	_broadcast(BfhEvents.Kind.BOWL, BfhEvents.write_bowl(
		game.arena.radius, game.arena.hook_layout, game.arena.courtyard_west_lane,
		game.arena.district
	))

func _on_round_began(number: int) -> void:
	_broadcast(BfhEvents.Kind.ROUND, BfhEvents.write_round(number, true, 0))

func _on_round_over(number: int, winner: int) -> void:
	# The CLOCK first, carrying the tally dot-match has just counted this round into, so a client's
	# world has the new score by the time its `round_over` fires — which is when a scoreboard shows
	# itself.
	_broadcast(BfhEvents.Kind.CLOCK, _clock_bytes())
	_broadcast(BfhEvents.Kind.ROUND, BfhEvents.write_round(number, false, winner))

## Every player's side, one message each.
func _on_sides_swapped(_number: int) -> void:
	for id: StringName in game.sides:
		_broadcast(BfhEvents.Kind.TEAM, BfhEvents.write_team(
			session_of(id), game.team_of(id)
		))

func _on_player_died(player_id: StringName, by: StringName) -> void:
	var who: BfhPlayer = game.players.get(player_id) if game != null else null
	_broadcast(BfhEvents.Kind.DEATH, BfhEvents.write_death(
		session_of(player_id), session_of(by) if by != &"" else 0,
		who.death if who != null else null
	))

func _on_barrel_exploded(at: Vector3, radius: float) -> void:
	_broadcast(BfhEvents.Kind.BLAST, BfhEvents.write_blast(at, radius))

## A noise the world decided, to everybody. Only the ones in `BfhSounds.WORLD`: the engine
## is played by each client from the bus it is drawing, and a blast is already a BLAST.
func _on_noise(id: StringName, at: Vector3) -> void:
	var index := BfhSounds.world_index(id)

	if index < 0:
		return

	_broadcast(BfhEvents.Kind.SOUND, BfhEvents.write_sound(index, at))

## An achievement, told to the one person who earned it. A notice rather than a message
## kind of its own: it is a line of text for one player, which is exactly what a notice is,
## and a client that draws notices draws this with nothing added.
func _on_earned(player_id: StringName, title: String, points: int) -> void:
	notice(peer_for_player(session_of(player_id)), "Achievement unlocked: %s (+%d)" % [title, points])

# --- Where a runner who is out looks

## The view [param player_id] is in, as `(mode, target session)`, for their own snapshot.
## Server side; `BfhPlayerNet.pull` reads it. Zeroes when they are playing.
func watch_state(player_id: StringName) -> Vector2i:
	if game == null or game.spectate == null or net == null or not net.is_server:
		return Vector2i.ZERO

	var mode := game.spectate.mode_of(player_id)

	if mode == 0:
		return Vector2i.ZERO

	var target := game.spectate.target_of(player_id)
	return Vector2i(mode, session_of(target) if target != &"" else 0)
