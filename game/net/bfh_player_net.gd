extends DotNetBehaviour

const BfhNetCommand := preload("bfh_net_command.gd")

const BfhPlayer := preload("../bfh_player.gd")

## What a networked player replicates: the movement state, their health, their side, and whether
## they are driving.

var player: BfhPlayer = null
var bridge: Node = null

var net_position: Vector3 = Vector3.ZERO
var net_velocity: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: float = 0.0
var net_flags: int = 0
var net_modifiers: int = 0

## Hit points, and the one field with a hard cap on the wire.
var net_health: float = 100.0

## Whether they are in a bus. See [method _net_simulate] for what a client does with it.
var net_riding: bool = false

# --- An administrator's marks, and where to draw them

## `BfhPlayer.blinded`. Owner only: see [method _register_net_vars].
var net_blind: bool = false

## `BfhPlayer.beacon`. Everybody's.
var net_beacon: bool = false

## The net id of the bus they are driving, or 0 on foot.
var net_bus: int = 0

# --- Where they look while they are out

## `DotSpectatorView.Mode` of the view the server has them in; 0 when they are playing.
var net_watch: int = 0

## Who that view is on: the session id of the target, or of the killer a death camera looks
## at. 0 for nobody.
var net_watch_target: int = 0

## Retained, not cleared: a player whose packet was lost keeps moving in a straight line
## rather than stopping dead. The controller says the same of its own command.
var last_move: DotFpsCommand = DotFpsCommand.new()
var last_state_tick: int = -1


func _register_net_vars() -> void:
	for spec in DotFpsNetSync.state_specs():
		var declaration := replicate(spec["property"], DotNetVar.Type[spec["type"]])
		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))
		if bool(spec["interpolated"]):
			declaration.interpolated()
		if spec["property"] == &"net_crouch":
			declaration.range_of(0.0, 1.0)

	replicate(&"net_health", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 1000.0).bits(12)
	replicate(&"net_riding", DotNetVar.Type.BOOL)

	# [b]Per-player state rather than an event, and that is what makes both of these survive what an
	# event does not.[/b] A client that joins after the admin typed `beacon`, a snapshot lost on the
	# way, a round re-laying the bowl: each is a baseline the next snapshot corrects, where an event.
	replicate(&"net_blind", DotNetVar.Type.BOOL).to_owner_only()
	replicate(&"net_beacon", DotNetVar.Type.BOOL)
	replicate(&"net_bus", DotNetVar.Type.VARINT)

	# Seven modes fit in three bits. The owner's alone: see [member net_watch].
	replicate(&"net_watch", DotNetVar.Type.UINT).bits(3).to_owner_only()
	replicate(&"net_watch_target", DotNetVar.Type.VARINT).to_owner_only()


func _net_apply_input(input: DotNetInput, _tick: int) -> void:
	var command := input as BfhNetCommand
	if command != null:
		last_move = command.move


## On the authority the whole game ticks as one — every player moves, then the buses are driven,
## then what a bus hit is decided — so the first behaviour through drives the whole world and the
## rest find it done.
func _net_simulate(tick: int, delta: float) -> void:
	if player == null:
		return

	if identity != null and identity.is_authoritative:
		if bridge != null:
			bridge.ensure_game_ticked(tick)
	elif player.riding:
		# [b]A rider is not predicted, because a rider is not walking.[/b] The controller is the thing
		# that would be predicting and while its owner is in a bus it has no answer to predict: the bus's
		# position comes from the server, it is not reproducible across machines, and a controller.
		player.controller.apply_command(last_move.duplicate_command())
	else:
		player.controller.apply_command(last_move.duplicate_command())
		player.controller.simulate_tick(tick, delta)

	pull()


## Authority only: what the simulation left this player as.
func pull() -> void:
	if player == null:
		return

	DotFpsNetSync.pull(player.controller.state, self)

	if player.health != null:
		net_health = player.health.health

	net_riding = player.riding
	net_blind = player.blinded
	net_beacon = player.beacon
	net_bus = 0

	if player.riding and bridge != null and player.ridden != null:
		net_bus = int(bridge.call("net_id_of_node", player.ridden))

	net_watch = 0
	net_watch_target = 0

	if bridge != null:
		var watching: Vector2i = bridge.call("watch_state", player.player_id)
		net_watch = watching.x
		net_watch_target = watching.y

	# No relevance decision for the beacon, unlike a game with an interest set: every player here is
	# already always relevant (see `BfhNetBridge._build_entity`), because a 46 m disc with nothing tall
	# in it is a map where everybody can see everybody.


## The server's answer, adopted wholesale. On the owner it is the rewind half of
## reconciliation and the predictor replays every unacknowledged command on top.
func _net_state_applied(tick: int) -> void:
	if player == null:
		return

	last_state_tick = tick
	DotFpsNetSync.push(self, player.controller.state)
	_adopt()

	# NOT the node, on a predicted entity: `receive_snapshot` calls this BEFORE the predictor
	# reconciles, and reconcile's first act is to read the node as "what the client is showing".
	if identity == null or not identity.is_predicted() or player.riding:
		player.global_position = player.controller.state.position


## Every frame on a remote player. Without this the interpolator's work sits in a property
## nothing reads and a remote player moves in snapshot-sized steps.
func _net_interpolated(_tick: int) -> void:
	if player == null:
		return

	DotFpsNetSync.push(self, player.controller.state)
	player.global_position = player.controller.state.position


## The game half of a snapshot, on a mirror.
func _adopt() -> void:
	if player == null or identity == null or identity.is_authoritative:
		return

	if player.health != null:
		player.health.health = net_health
		player.health.alive = net_health > 0.0

	if player.riding != net_riding:
		player.set_riding(net_riding)

	player.blinded = net_blind
	player.beacon = net_beacon

	if net_riding and net_bus != 0 and bridge != null:
		var bus: Variant = bridge.call("body_of_net_id", net_bus)
		if bus is Node3D:
			player.ridden = bus as Node3D

	# Only the owner is ever sent a view, and the bridge adopts it only for the player this
	# client IS — see [method BfhNetBridge.adopt_watch] for why that is not `is_owner`.
	if bridge != null:
		bridge.call("adopt_watch", player.player_id, net_watch, net_watch_target)
