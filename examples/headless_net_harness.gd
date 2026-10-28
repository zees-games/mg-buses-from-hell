extends DotGameCheckSuite
## The wire suite's harness: both halves of a game over a lossy loopback, brought up and stepped.
## Split from headless_net.gd (which extends this) so that file stays a size the gate allows.

const BfhArena := preload("../game/bfh_arena.gd")
const BfhAudio := preload("../game/bfh_audio.gd")
const BfhAvatars := preload("../game/bfh_avatars.gd")
const BfhFigure := preload("../game/bfh_figure.gd")
const BfhBusNet := preload("../game/net/bfh_bus_net.gd")
const BfhClient := preload("../game/bfh_client.gd")
const BfhEvent := preload("../game/net/bfh_event.gd")
const BfhEvents := preload("../game/net/bfh_events.gd")
const BfhRequest := preload("../game/net/bfh_request.gd")
const BfhFx := preload("../game/bfh_fx.gd")
const BfhScoreboard := preload("../game/bfh_scoreboard.gd")
const BfhNetBridge := preload("../game/net/bfh_net_bridge.gd")
const BfhNetCommand := preload("../game/net/bfh_net_command.gd")
const BfhPropNet := preload("../game/net/bfh_prop_net.gd")
const BfhServices := preload("../game/bfh_services.gd")

const BfhConfig := preload("../game/bfh_config.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhSounds := preload("../game/bfh_sounds.gd")
const BfhSpectate := preload("../game/bfh_spectate.gd")

## Who the client is, on both ends.
const CLIENT_PEER := 7
const SESSION := 42

const SNAPSHOT_RATE := 20

## What the client's own project would have been exported at.
const CLIENT_ENGINE_TICK_RATE := 30

## What the client's own config file says the bowl is, which is not what the server runs.
const CLIENT_RADIUS := 60.0
const SERVER_RADIUS := 44.0

const SERVER_TICK_RATE := 60

## Ticks a client stamps ahead of the server, so its command arrives before its tick.
const INPUT_LEAD := 3

var _completed := 0

var _server_game: BfhGame = null
var _client_game: BfhGame = null
var _server_net: DotNetManager = null
var _client_net: DotNetManager = null
var _server_bridge: BfhNetBridge = null
var _client_bridge: BfhNetBridge = null

var _to_client: Array = []
var _to_server: Array = []

var _tick: int = 0
var _snapshot_count: int = 0

## Drop one snapshot in this many. Zero for a perfect link.
var _drop_every: int = 0

## The largest snapshot payload the server has sent since this was last zeroed.
var _largest_snapshot: int = 0


func _make_game(server: bool, parent: Node) -> BfhGame:
	var config := BfhConfig.new()
	config.crate_count = 10
	config.barrel_count = 2
	config.arena_radius = SERVER_RADIUS if server else CLIENT_RADIUS
	# And the client on the layout alternatives rather than the defaults, so a client that
	# ignored the server's in the HELLO would keep a different hook and courtyard (checked).
	# The client, not the server: the server's runner walks a line in these sections that
	# the wide hook's middle pillar stands across on a 44 m bowl.
	if not server:
		config.hook_layout = "wide"
		config.courtyard_west_lane = BfhArena.COURTYARD_WEST_LANE_NARROW
	config.round_seconds = 120.0
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.driver_count = 1

	var game := BfhGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = server
	game.tick_rate = SERVER_TICK_RATE if server else CLIENT_ENGINE_TICK_RATE
	# Neither registers: a registry name is global to the process and the last one to
	# register wins, which is precisely the situation a server and a client in one
	# process is.
	game.register_service = false
	parent.add_child(game)
	game.set_physics_process(false)
	return game


func _make_manager(
	server: bool, scope: StringName, peer_id: int, parent: Node, tick_rate: int
) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	manager.config = config

	parent.add_child(manager)
	manager.setup()
	return manager


func _build() -> bool:
	_section("bringing both halves up")

	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)

	# The client's own physics space. See the class note: without it the client's frozen
	# mirrors and the server's real bodies are in one world, occupying the same cubic
	# metres, and the server's bowl is quietly pushed apart by a copy of itself.
	var client_view := SubViewport.new()
	client_view.name = "ClientView"
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	client_view.add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)

	await get_tree().process_frame

	_check(
		_server_game.get_world_3d() != _client_game.get_world_3d(),
		"the two halves are in separate physics worlds, as two processes would be"
	)
	_check(
		_client_game.tick_rate != _server_game.tick_rate,
		"the client is on its own export's tick rate",
		"%d vs %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	_check(
		absf(_client_game.arena.radius - _server_game.arena.radius) > 1.0,
		"and has built its own default bowl, which is not the server's",
		"%.0f m vs %.0f m" % [_client_game.arena.radius, _server_game.arena.radius]
	)

	Engine.physics_ticks_per_second = CLIENT_ENGINE_TICK_RATE

	_server_net = _make_manager(true, &"server", 1, server_side, _server_game.tick_rate)
	_client_net = _make_manager(
		false, &"client", CLIENT_PEER, client_side, _client_game.tick_rate
	)
	# This harness stamps every command itself (`_tick + INPUT_LEAD`), not from the client's
	# clock, so the client must not ask for dot-net's input-lead report: steered by reports
	# about commands it never stamped, the clock runs away from them (only dot-net's cap
	# holds it). By the constant map, so this parses against a dot-net from before the report.
	var lead_bit := int((DotNetMessageRegistry as Script).get_script_constant_map().get("FEATURE_INPUT_LEAD", 0))
	_client_net.messages.features &= ~lead_bit

	_server_bridge = BfhNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)

	_client_bridge = BfhNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)

	var attached := _server_bridge.attach(_server_game, _server_net)
	_check(attached.ok, "the server bridge attaches", str(attached.error) if not attached.ok else "")

	var client_attached := _client_bridge.attach(_client_game, _client_net)
	_check(
		client_attached.ok, "the client bridge attaches",
		str(client_attached.error) if not client_attached.ok else ""
	)

	# The one mistake this check exists for: a client world handed a server manager. Both
	# halves are the same class, so nothing but this comparison can tell them apart.
	var wrong := BfhNetBridge.new()
	add_child(wrong)
	var refused := wrong.attach(_client_game, _server_net)
	_check(
		not refused.ok and refused.error.code == DotError.CODE_STATE,
		"a client world on a server manager is refused"
	)
	wrong.queue_free()

	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	_check(
		_server_bridge.link != null and _client_bridge.link != null,
		"both links open"
	)

	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(
		_server_net.messages.schema_hash() == _client_net.messages.schema_hash(),
		"both ends agree on the message schema"
	)

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send

	# What a real client wires to `DotClientLink.ping_ms()`. Nothing in dot-net writes an
	# RTT sample, and a client that feeds none has a clock that believes the link is
	# instant — so every command it stamps arrives after its tick has passed.
	_client_bridge.rtt_source = func() -> float:
		return 40.0

	_check(_server_game.external_tick, "the server world hands its tick to the bridge")
	_check(
		_client_game.external_tick,
		"and so does the client's, which predicts and interpolates instead"
	)

	_server_net.start()
	_client_net.start()

	# [b]The bot driver goes in BEFORE the first player joins, and that ordering is the
	# game's rule rather than the harness's convenience.[/b] `_side_for_new_player` fills
	# the driving seats first, so the first person to connect to an empty server is a
	# driver — which is correct, and would make this suite's "client" the one in the bus.
	# A server that is already holding its bot drivers hands a joining player the side the
	# rest of these sections are about.
	var driver := _server_bridge.add_bot("Bus driver", BfhGame.TEAM_DRIVERS)
	_check(driver != null and driver.is_bot, "a bot driver is seated before anybody joins")
	_check(
		int(_server_bridge.describe()["players"]) == 1,
		"and is replicated exactly like a person, minus the socket"
	)

	# The world is started AFTER the bridge is attached, which is what the module does and
	# for the reason written there: a bowl laid out before anything was listening to
	# `props.spawned` is a bowl no client is ever told about.
	_server_game.start()
	await get_tree().physics_frame

	_check(
		_server_bridge.describe()["bodies"] as int > 0,
		"and the server's bowl is replicated from the moment it is laid out",
		"%d bodies" % int(_server_bridge.describe()["bodies"])
	)

	_done()
	return attached.ok and client_attached.ok


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if method == &"snapshot":
		_snapshot_count += 1
		_largest_snapshot = maxi(_largest_snapshot, payload.size())

		if _drop_every > 0 and _snapshot_count % _drop_every == 0:
			return

	if peer_id != 0 and peer_id != CLIENT_PEER:
		return

	_to_client.append({"method": method, "payload": payload})


func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_to_server.append({"method": method, "payload": payload})


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


## A request and its answer: the answer is queued during the first flush and delivered by
## the second.
func _exchange() -> void:
	_flush()
	_flush()


## One tick on both ends, with a real physics frame between them.
##
## [b]The awaited physics frame is not padding.[/b] Almost everything in this game is a
## [RigidBody3D] — the crates, the barrels and the bus — and a rigid body is integrated by
## Godot's physics server on the physics frame and by nothing else. A suite that drove
## ticks in a tight loop would move no crate at all: the server's bowl would stay exactly
## where it was put, the client's copy would match it exactly, and every assertion about
## replication would pass without anything having been replicated.
func _step(command: DotFpsCommand = null) -> void:
	_tick += 1
	_client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(
		_tick + INPUT_LEAD, command if command != null else DotFpsCommand.new()
	)
	_flush()
	await get_tree().physics_frame


func _steps(count: int, command: DotFpsCommand = null) -> void:
	for _i in range(count):
		await _step(command)


## How many times the predictor has had to correct this client.
##
## Off the predictor rather than off [DotNetStats], which counts packets. A correction is
## the number that says whether the two ends are computing the same thing.
func _corrections() -> int:
	if _client_net == null or _client_net.predictor == null:
		return 0

	return int(_client_net.predictor.describe()["corrections"])


func _forward() -> DotFpsCommand:
	var c := DotFpsCommand.new()
	c.move = Vector2(0.0, 1.0)
	return c


func _server_player() -> BfhPlayer:
	return _server_game.players.get(BfhNetBridge.player_key(SESSION))


func _client_player() -> BfhPlayer:
	return _client_game.players.get(BfhNetBridge.player_key(SESSION))


func _section(title: String) -> void:
	print(title)


## A section reached its end. See [constant SECTIONS].
func _done() -> void:
	_completed += 1
