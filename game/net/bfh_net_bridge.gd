extends "bfh_net_bridge_server.gd"

## [param p_game] and [param p_net], in the shape [DotGameNetcode] calls it.
func attach(p_game: Object, p_net: DotNetManager) -> DotResult:
	var world := p_game as BfhGame

	if world == null or p_net == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs a world and a manager.")

	if world.authoritative != p_net.is_server:
		return DotResult.fail(
			DotError.CODE_STATE,
			"The world and the manager disagree about who is authoritative.",
			"world=%s net.is_server=%s" % [world.authoritative, p_net.is_server]
		)

	game = world
	net = p_net

	_entities = Node.new()
	_entities.name = "Entities"
	add_child(_entities)

	net.send_fn = _send

	var event := net.messages.register(
		BfhEvent.NAME, BfhEvent,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_CLIENT
	)
	if not event.ok:
		return event

	var request := net.messages.register(
		BfhRequest.NAME, BfhRequest,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_SERVER
	)
	if not request.ok:
		return request

	net.messages.on(BfhEvent.NAME, _on_event)
	net.messages.on(BfhRequest.NAME, _on_request)

	# Edited profiles reach every client, so a remote admin's panel shows what the server holds; edits themselves go through the remote workbench.
	profile_link = DotNetProfileLink.attach(net, world.ensure_runtime())

	# Both ends: a world still running its own `_physics_process` would move every player twice.
	game.external_tick = true

	# Server toys leave the registry before their nodes go; a client's mirrors stay registered.
	if net.is_server:
		game.toys_clearing.connect(_release_toys)
		game.toys_built.connect(_register_toys)
		if game.toys != null:
			_register_toys()
	else:
		game.toys_clearing.connect(_unpair_toys)
		game.toys_built.connect(_pair_pending_toys)

	if net.is_server:
		game.player_added.connect(_on_player_added)
		game.player_removed.connect(_on_player_removed)
		game.props.spawned.connect(_on_prop_spawned)
		game.props.removed.connect(_on_prop_removed)
		game.vehicles.spawned.connect(_on_vehicle_spawned)
		game.vehicles.removed.connect(_on_vehicle_removed)
		game.ride.entered.connect(_on_ride_entered)
		game.ride.exited.connect(_on_ride_exited)
		game.round_began.connect(_on_round_began)
		game.bowl_changed.connect(_on_bowl_changed)
		game.round_over.connect(_on_round_over)
		game.sides_swapped.connect(_on_sides_swapped)
		game.player_died.connect(_on_player_died)
		game.barrel_exploded.connect(_on_barrel_exploded)
		game.noise.connect(_on_noise)
		game.earned.connect(_on_earned)

	return DotResult.success(true)

## Opens the link under [param parent], whose NAME is half the RPC routing.
func open_link(parent: Node) -> void:
	if parent == null or link != null:
		return

	link = BfhNetLink.attached_to(parent, self, net != null and net.is_server) as BfhNetLink
	# Not a bare add_child: nothing would free the link when the module unloads, a reload
	# would add a second, and the live one would be renamed @Node@n and lose every RPC.
	DotGameLink.attach(link, parent, self, BfhNetLink.NODE_NAME)

## The other end of [method watch_state]: a client is told its own view. Client side.
func adopt_watch(player_id: StringName, mode: int, target_session: int) -> void:
	if game == null or game.spectate == null or net == null or net.is_server:
		return

	if local_player_id == 0 or session_of(player_id) != local_player_id:
		return

	game.spectate.adopt(
		player_id, mode, player_key(target_session) if target_session > 0 else &""
	)

## A spectator's click, sent to the server. See `BfhSpectate.ASK_*`.
func ask_watch(ask: int) -> void:
	_ask(BfhEvents.Ask.WATCH, BfhEvents.write_watch(ask))

# --- Server: the tick

func server_tick(tick: int) -> void:
	_tick = tick
	_game_ticked_for = -1

	if net != null:
		net.server_tick(tick)

	# Belt and braces: `net.server_tick` drives the entities, and the first player behaviour through
	# calls `ensure_game_ticked`.
	ensure_game_ticked(tick)

	if tick % CLOCK_EVERY == 0:
		_broadcast(BfhEvents.Kind.CLOCK, _clock_bytes())

func ensure_game_ticked(tick: int) -> void:
	if _game_ticked_for == tick or game == null:
		return

	_game_ticked_for = tick

	for session_id in _behaviours:
		var behaviour: BfhPlayerNet = _behaviours[session_id]

		# Only what a peer sent. A bot has no peer and is driven by the game itself, and
		# an empty command applied over the top of that would stand it still — which for
		# a bot DRIVER means a bus that never moves, on the deployment this game is for.
		if behaviour.player != null and behaviour.identity != null \
				and behaviour.identity.owner_peer_id > 0:
			behaviour.player.controller.apply_command(behaviour.last_move.duplicate_command())

	game.tick_once(tick)

	# The toys where the physics left them, before the snapshot.
	for behaviour: DotGameToyNet in _toy_nets:
		behaviour.pull()

	# The hammer, from the button the command carried. AFTER the movement, because a
	# hammer is swung from where the player ended the tick.
	for session_id in _behaviours:
		_drive_hammer(int(session_id), _behaviours[session_id])

	# After the world moved them, before the snapshot is built. A body pulled before the physics step
	# would replicate where it was last tick — the family's own "produced correctly and consumed by
	# nothing" one step along: correct data, wrong instant, and nothing errors.
	for net_id in _bodies:
		(_bodies[net_id] as BfhPropNet).pull()

## One player's hammer, from the buttons their command carried.
func _drive_hammer(session_id: int, behaviour: BfhPlayerNet) -> void:
	if behaviour == null or behaviour.player == null or behaviour.identity == null:
		return
	if behaviour.identity.owner_peer_id <= 0:
		return

	var player := behaviour.player
	var buttons := behaviour.last_move.buttons

	# A driver's swing button is the horn: somebody whose weapon is the bus has no hammer,
	# and one button that means "use what you have" is one less control to learn for the
	# half of the game a player drives every third round. Rate-limited by the world.
	if player.riding and (buttons & BfhNetCommand.BUTTON_SWING) != 0:
		game.sound_horn(player)
		return

	if player.hammer == null or player.riding:
		return
	if player.health != null and not player.health.alive:
		return
	if (buttons & BfhNetCommand.BUTTON_SWING) == 0:
		return

	player.hammer.swing(
		game,
		player.eye_position(),
		player.aim_direction(),
		game.props,
		game.prop_damage,
		game.carry,
		player.player_id,
		0xFFFFFFF,
	)

# --- The client tick

func client_tick(tick: int, command: DotFpsCommand) -> void:
	if net == null or net.is_server or game == null:
		return

	_tick = tick

	var packet := BfhNetCommand.new()
	packet.tick = tick
	packet.delta = net.clock.tick_duration()
	packet.move = command if command != null else DotFpsCommand.new()

	# Into the local history BEFORE predicting: reconciliation replays it.
	net.local_inputs().push(packet)

	# The behaviour simulates from `last_move` on a fresh tick and on a replayed one
	# alike — the predictor's replay sets it through `_net_apply_input`, and this is the
	# fresh tick's equivalent.
	var mine: BfhPlayerNet = _behaviours.get(local_player_id)

	if mine != null:
		mine.last_move = packet.move

		# The local hammer's cooldown, which is drawn and not decided. The server owns
		# whether a swing happened; this is what stops the crosshair saying "ready" for
		# half a second after a swing the server has already taken.
		if mine.player != null and mine.player.hammer != null:
			mine.player.hammer.advance(net.clock.tick_duration())

	if link != null:
		var payload := net.encode_ack()
		var writer := DotNetWriter.new()
		DotNetInput.write_batch(writer, _input_copies(packet))
		payload.append_array(writer.to_bytes())
		link.send_input(payload)

	# One predicted player, and nothing else: the crates and the buses are drawn from
	# snapshots and are never simulated here.
	if _client_ticked_for != tick:
		_client_ticked_for = tick

		# Through the predictor, which remembers each tick: a snapshot can only skip its replay when the
		# tick it describes was remembered.
		net.predict_tick(tick, packet)

		# The clock a client shows, advanced between the twice-a-second messages that
		# correct it. Without this the round timer on a client ticks in half-second steps.
		game.round_elapsed += net.clock.tick_duration()

# --- Receiving

## [param packet] and the commands before it from the local replay history, oldest first,
## for one input packet. See [constant INPUT_COPIES].
func _input_copies(packet: DotNetInput) -> Array:
	var batch: Array = Array(net.local_inputs().recent(INPUT_COPIES, packet.tick - 1))
	batch = batch.slice(maxi(0, batch.size() - (INPUT_COPIES - 1)))
	batch.append(packet)
	return batch

func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")
	if not _player_of_peer.has(peer_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "That peer has no player.")
	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))

	# A batch: this tick's command and the ones before it (see [constant INPUT_COPIES]).
	# Copies of ticks already simulated are skipped rather than pushed, or each would count
	# as a late input; the packet's own tick is always pushed, so a late one still counts.
	var batch := DotNetInput.read_batch(
		DotNetReader.new(payload.slice(ACK_BYTES)),
		func() -> DotNetInput: return BfhNetCommand.new()
	)
	if batch.is_empty():
		return DotResult.fail(DotError.CODE_PARSE, "Input packet carries no command.")
	var buffer := net.input_buffer_for(peer_id)
	var newest := batch[batch.size() - 1]
	var pushed := DotResult.success(false)
	for input in batch:
		if input != newest and input.tick <= buffer.last_consumed_tick():
			continue
		pushed = buffer.push(input)
	return pushed

## One routed line to one peer. What [DotGameServices] sends through, via the link.
func send_chat(peer_id: int, wire: Dictionary) -> void:
	_tell(peer_id, BfhEvents.Kind.CHAT, BfhEvents.write_chat(wire))

## A voice frame off [method BfhNetLink.send_voice], in whichever direction.
func receive_voice(peer_id: int, payload: PackedByteArray) -> DotResult:
	if payload.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "An empty voice frame.")

	if net != null and net.is_server:
		if peer_id <= 0 or player_for_peer(peer_id) == 0:
			# A peer with nobody in the world. Refused rather than relayed: the router
			# stamps the speaker from this id, so relaying one that belongs to nobody puts
			# a voice in the game with no name on it.
			return DotResult.fail(
				DotError.CODE_FORBIDDEN, "That peer has nobody in the world."
			)

		# [b]One path or the other, never both.[/b] [DotGameModule] assigns `voice_relay_fn` to the
		# services layer's `relay_voice`; a game that ALSO connected `voice_requested` to the same router
		# would relay every frame twice — which is a doubled talk spurt, a doubled rate limit, and a.
		if voice_relay_fn.is_valid():
			voice_relay_fn.call(peer_id, payload)
		else:
			voice_requested.emit(peer_id, payload)

		return DotResult.success(null)

	voice_arrived.emit(payload)
	return DotResult.success(null)

# --- Server: what a joining peer is told

func _on_request(message: DotNetMessage) -> void:
	var ask := message as BfhRequest

	if ask == null or net == null or not net.is_server:
		return

	# [b]From the message, which dot-net stamped from the TRANSPORT.[/b] A peer id inside
	# a body is a claim; `sender_peer_id` is what the socket said, which is the only
	# version of it a server may act on.
	var peer_id := ask.sender_peer_id

	match ask.kind:
		BfhEvents.Ask.READY:
			_admit(peer_id)
		BfhEvents.Ask.WATCH:
			_answer_watch(peer_id, BfhEvents.read_watch(ask.reader()))
		BfhEvents.Ask.SAY:
			var said := BfhEvents.read_say(ask.reader())

			if bool(said["ok"]):
				# Emitted rather than acted on: everything about what a line means is
				# [DotChatRouter]'s, and the router is the module's.
				say_requested.emit(
					peer_id, StringName(str(said["channel"])), str(said["text"])
				)

## A spectator's click, answered by the world's own rules. A refusal goes back to the one
## person who asked, as a notice: "a living player is playing, not watching" is theirs to
## read and nobody else's.
func _answer_watch(peer_id: int, asked: Dictionary) -> void:
	if not bool(asked["ok"]) or game == null or game.spectate == null:
		return

	var session_id := player_for_peer(peer_id)

	if session_id == 0:
		return

	var answered: DotResult = game.spectate.request(player_key(session_id), int(asked["ask"]))

	if not answered.ok:
		notice(peer_id, answered.error.message)

## Tells everybody who somebody is now: a profile that arrived after they were seated, a wardrobe
## change, an operator's rename. Server only.
func refresh_player(session_id: int, display_name: String, avatar: DotAvatar) -> bool:
	if net == null or not net.is_server or game == null:
		return false

	var player: BfhPlayer = game.players.get(player_key(session_id))

	if player == null or not _behaviours.has(session_id):
		return false

	if display_name != "":
		player.display_name = display_name

	player.avatar = avatar
	_broadcast(BfhEvents.Kind.JOIN, _join_body(session_id))
	return true

# --- Reporting

func describe() -> Dictionary:
	var out := {
		"server": net != null and net.is_server,
		"players": _behaviours.size(),
		"bodies": _bodies.size(),
		"ready_peers": _ready_peers.size(),
		"tick": _tick,
	}

	if not (net != null and net.is_server):
		out["local_player"] = local_player_id

	if link != null:
		out["link"] = link.describe()

	return out

func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray([
		"bridge     %s" % ("server" if net != null and net.is_server else "client"),
		"players    %d" % _behaviours.size(),
		"bodies     %d replicated" % _bodies.size(),
		"peers      %d ready" % _ready_peers.size(),
		"tick       %d" % _tick,
	])

	if link != null:
		lines.append_array(link.describe_lines())

	return lines
