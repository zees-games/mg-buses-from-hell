extends "headless_net_wire.gd"
## Hammer, driving, clock, chat, voice, a gag, a lossy link and a snapshot in parts.


func _test_the_hammer() -> void:
	_section("the hammer")

	var server_player := _server_player()

	if server_player == null or server_player.hammer == null:
		_check(false, "the runner has a hammer")
		_check(false, "the button reaches the server")
		_check(false, "and the crate it broke goes from the client too")
		_done()
		return

	_check(true, "the runner has a hammer")

	# Put a crate directly in front of them and look at it. Aiming a runner at whatever
	# the scatter happened to put nearby is a test that passes on some seeds.
	var aim := DotFpsCommand.new()
	aim.yaw = 0.0
	aim.pitch = 0.0

	var eye := server_player.eye_position()
	var target := eye + server_player.aim_direction() * 1.6
	var crate := _server_game.props.spawn(BfhContent.CRATE, &"world", target)

	_check(crate != null, "a crate is put within reach")

	await _steps(4)

	var swings_before := server_player.hammer.swings
	var swing := DotFpsCommand.new()
	swing.buttons |= BfhNetCommand.BUTTON_SWING
	await _steps(30, swing)

	_check(
		server_player.hammer.swings > swings_before,
		"the button reaches the server and it swings",
		"%d swings" % (server_player.hammer.swings - swings_before)
	)

	# Three swings at 34 against 100 hit points, and the interval is 0.55 s — so half a
	# second of held button is one swing, and thirty ticks is enough for one more.
	_check(
		server_player.hammer.breaks > 0 or not crate.is_alive()
			or _server_game.prop_damage.health_of(crate.instance_id) < 100.0,
		"and what it hit is the worse for it"
	)
	_done()



func _test_driving() -> void:
	_section("driving")

	# The client's own player is put in a bus, which is the state a client cannot work out
	# for itself: the ride is the server's, and a client that kept predicting a driver
	# would fight every snapshot carrying the bus.
	var server_player := _server_player()
	var buses := _server_game.vehicles.all_vehicles()

	if server_player == null or buses.is_empty():
		_check(false, "there is a bus to get into")
		_check(false, "the client is told its player is driving")
		_check(false, "and stops predicting them")
		_done()
		return

	_check(true, "there is a bus to get into")

	_server_game.ride.exit(buses[0], _server_game.driver_of(buses[0].instance_id), true)
	await _steps(2)
	_server_game.ride.enter(buses[0], server_player.player_id, server_player, &"driver")
	await _steps(6)

	var client_player := _client_player()

	_check(
		client_player != null and client_player.riding,
		"the client is told its player is driving"
	)

	var before := client_player.controller.state.position
	await _steps(20, _forward())

	_check(
		client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		) < 2.0,
		"and stops predicting them: the server's answer is what is drawn",
		"%.2f m apart" % client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		)
	)

	_server_game.ride.exit(buses[0], server_player.player_id, true)
	await _steps(6)
	_check(not _client_player().riding, "and is told when they get out again")
	_done()



func _test_the_clock() -> void:
	_section("the round clock")

	await _steps(BfhNetBridge.CLOCK_EVERY + 2)

	_check(
		absf(_client_game.round_elapsed - _server_game.round_elapsed) < 1.0,
		"the client's clock is the server's",
		"client %.1f s, server %.1f s" % [
			_client_game.round_elapsed, _server_game.round_elapsed
		]
	)

	# [b]The number this message exists for.[/b] A client does not run the prop spawner, so
	# `crates_left()` on one counts zero — and that number is the most important thing on this game's
	# HUD, because it is what tells a runner whether standing still is still an option.
	_check(
		_client_game.crates_left() == _server_game.crates_left(),
		"and so is the cover count, which a client cannot count for itself",
		"client %d, server %d" % [
			_client_game.crates_left(), _server_game.crates_left()
		]
	)
	_check(
		_client_game.remote_cover >= 0,
		"which it knows it was told rather than counted"
	)
	_check(
		_client_game.sides_are_playable() == _server_game.sides_are_playable(),
		"and whether the round is playable at all"
	)
	_done()



func _test_chat() -> void:
	_section("a line crosses the wire")

	# The router, driven directly: this harness has no `DotServer`, so the parts of the
	# services layer that need sessions cannot run — and the parts that carry a line can.
	var router := DotChatRouter.new()
	router.name = "Chat"
	router.rules = BfhServices.chat_rules()
	router.rules_file = ""
	router.install_default_channels = false
	router.register_as = &"bfh_chat_test"
	router.send_fn = func(wire: Dictionary, recipients: PackedInt32Array) -> void:
		for peer_id in recipients:
			_server_bridge.send_chat(int(peer_id), wire)
	router.peers_fn = func() -> PackedInt32Array:
		return PackedInt32Array([CLIENT_PEER])
	router.name_fn = func(_peer: int) -> String:
		return "Ada"
	router.key_fn = func(_peer: int) -> String:
		return str(SESSION)
	router.is_admin_fn = func(_peer: int) -> bool:
		return false
	add_child(router)

	var started := router.start()
	_check(started.ok, "the chat router starts", str(started.error) if not started.ok else "")

	for channel in BfhServices.chat_channels():
		router.add_channel(channel)

	_check(
		router.has_channel(BfhServices.CH_ALL) and router.has_channel(BfhServices.CH_TEAM),
		"with this game's channels on it: all, team, admin and whisper",
		"%d channels" % router.channel_ids().size()
	)

	var heard: Array[Dictionary] = []
	_client_bridge.chat_received.connect(func(wire: Dictionary) -> void:
		heard.append(wire)
	)

	# What a player actually does: the client asks, the server decides.
	_client_bridge.ask_say(BfhServices.CH_ALL, "north ramp")
	_exchange()

	var asked: Array = []
	_server_bridge.say_requested.connect(func(peer: int, ch: StringName, text: String) -> void:
		asked.append([peer, ch, text])
	)

	# The first ask was already delivered, so ask again now the listener is on — which is
	# also the check that a second line is not swallowed by the rate limiter.
	_client_bridge.ask_say(BfhServices.CH_ALL, "he is coming round the stacks")
	_exchange()

	_check(asked.size() == 1, "the server is told somebody said something", "%d" % asked.size())
	_check(
		asked.size() == 1 and str((asked[0] as Array)[2]) == "he is coming round the stacks",
		"with the text they typed and nothing else"
	)

	var sent := router.submit(CLIENT_PEER, BfhServices.CH_ALL, "he is coming round the stacks")
	_check(sent.ok, "the router accepts it", str(sent.error) if not sent.ok else "")
	_exchange()
	await _steps(2)

	_check(heard.size() > 0, "and the client is sent the routed line", "%d lines" % heard.size())

	if heard.is_empty():
		_check(false, "with the speaker's name on it")
		_check(false, "and the text intact")
		router.queue_free()
		_done()
		return

	var wire: Dictionary = heard[heard.size() - 1]
	_check(str(wire.get("d", "")) == "Ada", "with the speaker's name on it", str(wire.get("d", "")))
	_check(
		str(wire.get("m", "")) == "he is coming round the stacks",
		"and the text intact",
		str(wire.get("m", ""))
	)

	# [b]A line too long for the wire is not a line the wire silently cuts.[/b] The rules cap
	# a message at 140 and the field is 200, so what the rules let through always fits —
	# which is the invariant this check exists to hold, not the truncation itself.
	var long_line := "x".repeat(400)
	var refused := router.submit(CLIENT_PEER, BfhServices.CH_ALL, long_line)
	_exchange()
	await _steps(2)

	var last: Dictionary = heard[heard.size() - 1]
	_check(
		refused.ok and str(last.get("m", "")).length() <= 140,
		"a 400-character line is cut to what the rules allow before it reaches the wire",
		"%d characters" % str(last.get("m", "")).length()
	)

	router.queue_free()
	_done()


func _test_voice() -> void:
	_section("voice crosses the wire")

	var router := DotVoiceRouter.new()
	router.name = "Voice"
	router.config = BfhServices.voice_format()
	router.default_channel = DotVoiceRouter.Channel.ALL
	router.send_fn = func(peer_id: int, payload: PackedByteArray) -> void:
		_server_bridge.link.send_voice(peer_id, payload)
	add_child(router)

	# Two peers, because voice is the one thing a server never sends back to its speaker.
	router.add_peer(CLIENT_PEER)
	router.add_peer(CLIENT_PEER + 1)

	var arrived: Array[PackedByteArray] = []
	_client_bridge.voice_arrived.connect(func(payload: PackedByteArray) -> void:
		arrived.append(payload)
	)

	# A frame from the OTHER peer, which is the direction that reaches this client.
	var packet := DotVoicePacket.new()
	packet.speaker = CLIENT_PEER + 1
	packet.sequence = 1
	packet.codec_id = BfhServices.voice_format().codec_id
	packet.sample_count = 320
	packet.payload = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])

	var relayed := router.relay(CLIENT_PEER + 1, packet.to_bytes())
	_check(relayed.ok, "the router relays a frame", str(relayed.error) if not relayed.ok else "")

	_flush()
	await _steps(2)

	_check(arrived.size() > 0, "and it arrives on the client", "%d frames" % arrived.size())
	_check(
		int(_client_bridge.link.get("voice_received")) > 0,
		"on the link's own voice channel rather than as an event",
		"%d" % int(_client_bridge.link.get("voice_received"))
	)

	# [b]A frame from a peer with nobody in the world is refused.[/b] The router stamps the
	# speaker from the peer id the transport reported, so relaying one that belongs to
	# nobody puts a voice in the game with no name on it.
	var orphan := _server_bridge.receive_voice(4242, packet.to_bytes())
	_check(
		not orphan.ok and orphan.error.code == DotError.CODE_FORBIDDEN,
		"a frame from a peer with nobody in the world is refused"
	)

	var heard_at_server: Array[int] = []
	_server_bridge.voice_relay_fn = func(peer_id: int, _payload: PackedByteArray) -> void:
		heard_at_server.append(peer_id)
	var client_chat_script := preload("../game/bfh_client_chat.gd")
	var client_chat: Node = client_chat_script.new()
	client_chat.name = "VoiceClientChat"
	add_child(client_chat)
	var attached: DotResult = client_chat.call(&"attach", _client_bridge)
	var talker: DotVoiceManager = client_chat.get(&"voice")
	_check(attached.ok and talker != null and not talker.is_capturing(),
		"the client's microphone is not open before the talk key")
	if talker != null:
		var mic := DotVoiceSourceBuffer.new()
		mic.sample_rate = talker.config.sample_rate
		mic.write(DotVoiceSourceBuffer.tone(440.0, 0.2, mic.sample_rate, 0.4))
		talker.source = mic
		Input.action_press(DotVoiceManager.TALK_ACTION)
		await _steps(4)
		_flush()
		await _steps(2)
		Input.action_release(DotVoiceManager.TALK_ACTION)
	_check(talker != null and talker.frames_sent > 0 and heard_at_server.size() == talker.frames_sent,
		"holding it sends the player's speech to the server (%d sent, %d relayed)" % [talker.frames_sent if talker != null else 0, heard_at_server.size()])
	_server_bridge.voice_relay_fn = Callable()
	client_chat.queue_free()

	router.queue_free()
	_done()


func _test_a_gag() -> void:
	_section("a gag actually silences somebody")

	# [b]The one piece of state in this suite that outlives the process.[/b] A punishment store is a
	# FILE, and a gag issued by the last run is loaded by this one — so the check that a line goes
	# through BEFORE the gag fails on the second run and passes on the first, which is the worst way.
	var store_path := "user://bfh_net_test_punishments.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))

	var moderation := DotModerationManager.new()
	moderation.name = "Moderation"
	moderation.store = DotPunishmentStoreFile.new(store_path)
	moderation.server_scope = ""
	moderation.register_mute_source = true
	moderation.register_ban_source = false
	moderation.key_for_peer = func(peer_id: int) -> String:
		return DotPunishmentSubject.for_uid("peer%d" % peer_id)
	add_child(moderation)
	moderation.load_all()

	var router := DotChatRouter.new()
	router.name = "GaggedChat"
	router.rules = BfhServices.chat_rules()
	router.rules_file = ""
	router.install_default_channels = false
	router.register_as = &""
	router.mute_service = DotModerationManager.MUTE_SERVICE
	router.send_fn = func(_wire: Dictionary, _to: PackedInt32Array) -> void:
		pass
	router.peers_fn = func() -> PackedInt32Array:
		return PackedInt32Array([CLIENT_PEER])
	router.name_fn = func(_peer: int) -> String:
		return "Ada"
	router.key_fn = func(_peer: int) -> String:
		return str(SESSION)
	router.is_admin_fn = func(_peer: int) -> bool:
		return false
	add_child(router)
	router.start()

	for channel in BfhServices.chat_channels():
		router.add_channel(channel)

	_check(
		router.submit(CLIENT_PEER, BfhServices.CH_ALL, "before").ok,
		"before the gag, a line goes through"
	)

	# Through `issue`, with the SUBJECT spelling dot-moderation uses — `key_for_peer` above answers the
	# same way, and a gag against a differently-spelled subject is a gag that silences nobody and
	# reports success.
	var gagged: DotResult = await moderation.issue(
		DotPunishment.Kind.GAG,
		DotPunishmentSubject.for_uid("peer%d" % CLIENT_PEER),
		"talking about the bus",
		"console",
		600
	)
	_check(gagged.ok, "the player is gagged", str(gagged.error) if not gagged.ok else "")

	var after := router.submit(CLIENT_PEER, BfhServices.CH_ALL, "after")
	_check(
		not after.ok,
		"and the next line is refused rather than quietly dropped",
		str(after.error) if not after.ok else "it went through"
	)

	# [b]The admin channel ignores a gag, and this game's does on purpose.[/b] A gag is
	# about a player's speech; an admin who has been gagged has a bigger problem than chat.
	var admin_channel := router.channel(BfhServices.CH_ADMIN)
	_check(
		admin_channel != null and admin_channel.ignores_gag,
		"while the admin channel is declared to ignore one"
	)

	moderation.queue_free()
	router.queue_free()
	_done()



func _test_a_lossy_link() -> void:
	_section("a link that drops snapshots")

	_drop_every = 3
	var before := _corrections()
	await _steps(60, _forward())
	_drop_every = 0
	await _steps(20)

	var server_player := _server_player()
	var client_player := _client_player()

	_check(
		client_player != null and server_player != null
			and client_player.controller.state.position.distance_to(
				server_player.controller.state.position
			) < 1.5,
		"a third of the snapshots are dropped and the player still agrees",
		"%.2f m apart" % client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		)
	)

	var crates_apart := 0

	for prop in _server_game.props.all_props():
		if prop.body() == null:
			continue

		var mirror := _mirror_near(prop.body().global_position)

		if mirror == null:
			crates_apart += 1

	_check(
		crates_apart == 0,
		"and every body in the bowl is still where it should be",
		"%d unaccounted for" % crates_apart
	)
	_check(
		_corrections() >= before,
		"with the corrections counted rather than hidden"
	)
	_done()



## A snapshot bigger than [member DotNetConfig.mtu] arrives in parts, through this game's own link
## and bridge, and every body ends up where the server's is.
func _test_a_snapshot_in_parts() -> void:
	_section("a snapshot over the MTU arrives in parts")

	const MTU := 160
	var split_before := _server_net.snapshots_split
	var failures_before := _client_net.stats.decode_failures
	var shipped_mtu := _server_net.config.mtu
	_server_net.config.mtu = MTU
	_largest_snapshot = 0

	var bodies: Dictionary = _server_bridge.get("_bodies")
	var thrown := 0
	for prop in _server_game.props.all_props():
		var body := prop.body() as RigidBody3D
		if body == null:
			continue
		body.sleeping = false
		body.linear_velocity = Vector3(0.0, 8.0, 0.0)
		thrown += 1

	await _steps(9)

	var split := _server_net.snapshots_split - split_before
	_check(
		thrown > 0 and split > 0,
		"a snapshot over the MTU is sent in parts",
		"%d bodies thrown, %d snapshots split" % [thrown, split]
	)
	_check(
		_largest_snapshot <= MTU,
		"and no part is bigger than the MTU",
		"largest %d of %d" % [_largest_snapshot, MTU]
	)
	_check(
		_client_net.ack_tick() >= _tick - 3,
		"the client acknowledges the split snapshots, so nothing is re-sent for ever",
		"acked %d at tick %d" % [_client_net.ack_tick(), _tick]
	)

	# In flight, against what the client was last SENT (the property itself holds the
	# interpolator's blend): every part was applied, not only the first.
	var apart := 0
	var compared := 0
	var worst := 0.0
	for net_id in bodies:
		var on_server: BfhPropNet = bodies[net_id]
		var on_client: BfhPropNet = _client_bodies().get(net_id)
		if on_server == null or on_client == null:
			continue
		var sent: Variant = on_client.received_values().get(&"net_position")
		if sent == null:
			continue
		compared += 1
		var gap := (sent as Vector3).distance_to(on_server.net_position)
		worst = maxf(worst, gap)
		if gap > 0.5:
			apart += 1
	_check(
		compared >= thrown and apart == 0,
		"every body is where the server put it, whichever part carried it",
		"%d of %d over 50 cm, worst %.2f m" % [apart, compared, worst]
	)

	_server_net.config.mtu = shipped_mtu
	await _steps(30)
	_check(
		_client_net.stats.decode_failures == failures_before,
		"and every part decodes",
		"%d failures" % (_client_net.stats.decode_failures - failures_before)
	)
	_done()



## An administrator's blind and beacon, through this game's real handlers, over a link that drops
## one snapshot in five.
func _test_blind_and_beacon() -> void:
	_section("an admin's blind and beacon: who is told")

	var services := BfhServices.new()
	services.game = _server_game
	var handlers := services._mod_abilities()
	var blind: Callable = handlers["blind"]
	var beacon: Callable = handlers["beacon"]

	var bot_session := BfhNetBridge.FIRST_BOT_SESSION
	var bot_key := BfhNetBridge.player_key(bot_session)
	var server_net := _server_player().get_node("Net") as DotNetBehaviour

	_check(
		server_net.find_var(&"net_blind").audience == DotNetVar.Audience.OWNER
		and server_net.find_var(&"net_beacon").audience == DotNetVar.Audience.EVERYONE,
		"the blind is declared owner-only and the beacon for everybody"
	)

	# The bot back behind a wheel, so the beacon on a DRIVER is asserted where it is drawn.
	# `_test_driving` took it out of the first bus to seat this client in it.
	var buses := _server_game.vehicles.all_vehicles()
	var bot: BfhPlayer = _server_game.players.get(bot_key)
	if not buses.is_empty() and bot != null and not bot.riding:
		var sitting := _server_game.driver_of(buses[0].instance_id)
		if sitting != &"":
			_server_game.ride.exit(buses[0], sitting, true)
		_server_game.ride.enter(buses[0], bot_key, bot, &"driver")

	var results: Array[DotResult] = [
		blind.call(StringName(str(SESSION)), {"on": true}),
		blind.call(StringName(str(bot_session)), {"on": true}),
		beacon.call(StringName(str(SESSION)), {"on": true}),
		beacon.call(StringName(str(bot_session)), {"on": true}),
	]
	_check(
		results.all(func(r: DotResult) -> bool: return r.ok),
		"the server blinds and beacons this client's player and the bot driver"
	)

	_drop_every = 5
	await _steps(30)
	_drop_every = 0

	var mine := _client_player()
	var theirs: BfhPlayer = _client_game.players.get(bot_key)

	_check(mine != null and mine.blinded, "the owner's client blacks its own screen out")
	_check(
		theirs != null and not theirs.blinded
		and not bool((theirs.get_node("Net") as Object).get("net_blind")),
		"and is never told about somebody else's blind",
		"the bot's mirror received net_blind = %s" % str(
			(theirs.get_node("Net") as Object).get("net_blind") if theirs != null else "?"
		)
	)
	_check(
		mine != null and mine.beacon and theirs != null and theirs.beacon,
		"while it draws the beacon on both"
	)

	# The driver's beacon is drawn at the bus, and the client knows which bus from the
	# snapshot rather than from a SEAT it might have missed.
	var client_bus: Node3D = null
	if not buses.is_empty():
		client_bus = _client_bridge.body_of_net_id(
			_server_bridge.net_id_of_node(buses[0].body())
		)
	_check(
		theirs != null and theirs.riding and client_bus != null and theirs.ridden == client_bus
		and theirs.drawn_position().distance_to(client_bus.global_position) < 0.01,
		"and a beaconed driver is drawn where the client draws their bus",
		"riding %s, ridden %s, bus %s" % [
			str(theirs.riding) if theirs != null else "?",
			str(theirs.ridden) if theirs != null else "?",
			str(client_bus),
		]
	)

	# A client that joined after the seat was taken was never sent the SEAT. Forgetting
	# the bus here is that client; the next snapshot's `net_bus` has to put it back.
	if theirs != null:
		theirs.ridden = null
	await _steps(6)
	_check(
		theirs != null and client_bus != null and theirs.ridden == client_bus,
		"and a client that missed the SEAT finds the bus from the snapshot alone"
	)

	for id in [StringName(str(SESSION)), StringName(str(bot_session))]:
		var _b: DotResult = blind.call(id, {"on": false})
		var _c: DotResult = beacon.call(id, {"on": false})

	await _steps(12)

	_check(
		not mine.blinded and not mine.beacon and not theirs.beacon,
		"and turning both off reaches the client"
	)

	services.free()
	_done()


