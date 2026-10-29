extends CharacterBody3D

const BfhConfig := preload("bfh_config.gd")

## Seconds between ripples, and between pings.
const BEACON_PERIOD := 1.0

## Red-orange: the one colour the sand, the concrete and the blue sky are not, so it reads
## as a mark rather than as part of the bowl.
const BEACON_COLOUR := Color(1.0, 0.28, 0.18)

## A person: a ring just outside a runner's capsule, a column from above their head.
const BEACON_PERSON_RING := 0.75
const BEACON_PERSON_BASE := 2.1

## A bus: round a 9 m by 3 m hull, and from above its 2.5 m roof. The ring is drawn at the
## bus's own origin height and a hull that long needs a radius past its corners, or the
## ring disappears into the bodywork at both ends.
const BEACON_BUS_RING := 5.2
const BEACON_BUS_BASE := 4.0

const BEACON_COLUMN := 14.0

## Further than the bowl is wide: a beacon that went quiet at the far wall would fail in the
## one place it is used.
const BEACON_PING_RANGE := 160.0
const BfhFigure := preload("bfh_figure.gd")
const BfhAvatars := preload("bfh_avatars.gd")
const BfhHammer := preload("bfh_hammer.gd")

## One person in the bowl: their movement, their view, their health, and their hammer.

# No `const CHANNEL`.

## Metres above a player's feet that their eyes are.
const EYE_HEIGHT := 1.6

## This player was run over or blown up.
signal died(by: StringName)

## A beacon on this player sent out a ripple: once a second while it is on, and once the
## moment it comes on. Client side, from [method present_beacon].
signal beacon_pulsed(at: Vector3)

@export var player_id: StringName = &"local"
@export var display_name: String = "Runner"

## What this player looks like on foot, as a dot-user-avatar document; null is the stock person. Set
## on a server from the platform — see `bfh_module._avatar_for` — and carried to every client in
## JOIN.
var avatar: DotAvatar = null

## Whether a command is sampled from the input devices each tick.
@export var samples_input: bool = false

## Whether this player is driven by the game rather than by a person.
@export var is_bot: bool = false

## The world's configuration, so the tunables below come from the same file as the rest of
## the game's numbers. Set by [BfhGame] before this enters the tree.
var config: BfhConfig = null

var controller: DotFpsController = null
var sampler: DotFpsSampler = null

## Set by the world each tick for somebody flying a free camera: their command is zeroed.
var input_off := false
var health: DotHealth = null

## The hammer, on a runner. Null on a driver: a bus is the weapon.
var hammer: BfhHammer = null

## Set by the world so a player rides what they are standing on.
var carry: DotPropCarry = null

## Their mass, which is what a crate feels.
var mass_kg: float = 80.0

## Whether this player is driving, and so is not walking.
##
## Read-only from outside; [method set_riding] is the switch.
var riding: bool = false

## The bus this player is driving, as the node that is DRAWN, or null on foot.
var ridden: Node3D = null

## An administrator's `blind`: this player's own screen is blacked out.
var blinded: bool = false

## An administrator's `beacon`: a pulsing ring and a column over this player that every client
## draws, and a ping every client hears, until it is turned off.
var beacon: bool = false

## The marker [member beacon] draws, while it does. Client side; built and freed by
## [method present_beacon].
var beacon_marker: DotFxBeacon = null

## Whether [member beacon_marker] is currently sized for a bus; see [method present_beacon].
var _beacon_on_bus: bool = false

## What other people see this player as. Client side; built and shown by
## [method present_body], never on a server, which draws nothing.
var figure: BfhFigure = null

## How this player's body falls on their death: the server's pick ([method BfhGame.decide_death]),
## carried on DEATH and set here before anybody hears of it. Null before a first death.
var death: DotPlayerDeath = null

## This bot's driver, built on first use. Null for a person.
var autopilot: DotVehicleDriver = null

## The entity id dot-combat knows them by.
var entity_id: int = 0

## Metres this player has been carried by a prop. Reported rather than kept, because
## it is the one number that says the ride actually happened.
var carried_metres: float = 0.0

var tick_rate: int = 60:
	set(value):
		tick_rate = value
		if controller != null:
			controller.tick_rate = value


func _ready() -> void:
	controller = DotFpsController.new()
	controller.name = "Controller"
	controller.tick_rate = tick_rate

	# EXTERNAL rather than LOCAL even offline: the game owns the tick, so the order "sample, move, then
	# ride what you are standing on" is explicit here rather than happening inside somebody else's
	# loop.
	controller.drive = DotFpsController.Drive.EXTERNAL
	controller.tunables = tunables_for(config)
	# Every player, both ends: an admin's noclip or freeze is a modifier whose index
	# travels on the wire, and a client that had not registered it would read it as
	# something else. See dot-player-controller's DotFpsAdminModifiers.
	controller.admin_abilities = true
	add_child(controller)

	controller.simulated.connect(_on_simulated)

	if samples_input:
		sampler = DotFpsSampler.new(controller.tunables)
		DotFpsSampler.register_default_actions(sampler)


## How a runner moves.
static func tunables_for(config: BfhConfig) -> DotFpsTunables:
	var t := DotFpsTunables.with_profile("legacy")

	# [b]No bunny hopping, and that is a design decision rather than an omission.[/b] Every other 3D
	# game in this family turns auto-hop on because their genres are about carrying speed.
	t.auto_hop = false
	t.max_speed = config.runner_speed if config != null else 6.5
	t.accelerate = 12.0
	t.friction = 7.0
	t.stop_speed = 3.0

	t.air_accelerate = 30.0
	t.max_air_wish_speed = 1.6
	t.gravity = config.gravity if config != null else 20.0
	t.jump_height = config.runner_jump_height if config != null else 1.15

	t.coyote_time = 0.08
	t.jump_buffer_time = 0.1

	t.max_slope_angle = 48.0
	# Enough to step onto a crate lying flat without jumping, which is what makes the
	# bowl readable: a crate is cover you can also get onto, and having to jump for
	# every one of them turns a chase into a platforming test.
	t.step_height = 0.45

	return t


## Called once per simulated tick by the world.
func simulate(tick: int, delta: float) -> void:
	# The world calls this by name, so a body the load gate froze is skipped here.
	if is_inside_tree() and not can_process():
		return

	if sampler != null:
		# Settling under the cover runs the body with its input off (falls, lands, no keys).
		var gate := DotLoadGate.of(self) if is_inside_tree() else null
		var open := gate == null or gate.is_open()
		# A roamer's keys fly the camera; they must not also walk the body that fell.
		controller.apply_command(
			sampler.sample(delta) if open and not input_off else DotFpsCommand.new()
		)

	# Sampled above and then dropped: those same keys are what the bus is steered with, and the world
	# reads the pending command out for that. Not simulating is what stops the controller writing its
	# own answer into a transform the vehicle owns.
	if riding:
		return

	controller.simulate_tick(tick, delta)

	if hammer != null:
		hammer.advance(delta)


## After the move, which is the only place riding can go.
func _on_simulated(_tick: int, state: DotFpsState) -> void:
	global_position = state.position

	if carry == null:
		return

	# [b]`ground_id` is the whole mechanism, and it is deliberately not simulation state.[/b]
	# `DotFpsState` documents it as a local physics handle whose value differs between machines — which
	# is exactly right for this: riding is resolved per frame from a handle each machine has, rather.
	var lift := carry.ride(state.ground_id, state.position, mass_kg, delta_for_tick())

	if lift == Vector3.ZERO:
		return

	global_position += lift

	# Written back into the state as well as onto the node.
	state.position = global_position
	carried_metres += lift.length()


func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))


## Where this player's eyes are, in the world.
func eye_position() -> Vector3:
	return controller.state.position + Vector3(0.0, EYE_HEIGHT, 0.0)


## Which way they are looking, as a unit vector.
func aim_direction() -> Vector3:
	var view := Basis.from_euler(Vector3(
		deg_to_rad(controller.state.pitch), deg_to_rad(controller.state.yaw), 0.0
	))
	return -view.z


## Gets in or out of a bus.
func set_riding(value: bool) -> void:
	if riding == value:
		return

	riding = value
	controller.state.velocity = Vector3.ZERO

	if not riding:
		controller.state.mode = DotFpsState.Mode.AIR
		ridden = null


## Where this player is drawn: their bus while they drive one, their body otherwise.
func drawn_position() -> Vector3:
	if riding and ridden != null and is_instance_valid(ridden):
		return ridden.global_position

	return global_position


## Draws [member beacon], and says when it pings. Client side, once a frame, from `BfhClient`; a
## server never builds a marker.
func present_beacon(delta: float, own_view: bool) -> void:
	var alive := health == null or health.alive

	if not beacon or not alive:
		if beacon_marker != null:
			beacon_marker.queue_free()
			beacon_marker = null
		return

	var on_bus := riding and ridden != null and is_instance_valid(ridden)

	if beacon_marker == null:
		beacon_marker = DotFxBeacon.new()
		beacon_marker.name = "Beacon"
		beacon_marker.period = BEACON_PERIOD
		beacon_marker.ripple_scale = 3.0
		beacon_marker.colour = BEACON_COLOUR
		beacon_marker.ping_range = BEACON_PING_RANGE
		_beacon_on_bus = on_bus
		beacon_marker.ring_radius = BEACON_BUS_RING if on_bus else BEACON_PERSON_RING
		beacon_marker.column_height = BEACON_COLUMN
		beacon_marker.column_base = BEACON_BUS_BASE if on_bus else BEACON_PERSON_BASE
		add_child(beacon_marker)

	# Boarding or leaving a bus resizes the marker that is already there: rebuilding it
	# would restart its ping.
	if on_bus != _beacon_on_bus:
		_beacon_on_bus = on_bus
		beacon_marker.resize(
			BEACON_BUS_RING if on_bus else BEACON_PERSON_RING, BEACON_COLUMN,
			BEACON_BUS_BASE if on_bus else BEACON_PERSON_BASE
		)
	beacon_marker.local_view = own_view
	var at := drawn_position()
	beacon_marker.global_position = at

	if beacon_marker.advance(delta):
		beacon_pulsed.emit(at)


## Draws this player's body for one frame. Client side, once a frame, from
## `BfhClient.present_frame`. Returns whether it is shown.
func present_body(own_view: bool, driver_side: bool = false) -> bool:
	var alive := health == null or health.alive
	var shown := not own_view and not riding and alive

	if figure == null:
		# Built lazily and only once there is something to show, so a client never builds a
		# figure for its own player and a round full of drivers builds none at all.
		if not shown:
			return false

		figure = BfhFigure.new()
		figure.name = "Figure"
		add_child(figure)

	var wanted: String = BfhFigure.DRIVER_ATLAS if driver_side else _runner_atlas()

	if figure.atlas != wanted:
		# Rebuilt on a side swap: every third round the runners become the drivers, and a
		# figure dressed for the side it started on would put a uniform on somebody running.
		var height := controller.tunables.stand_height \
			if controller != null and controller.tunables != null else 1.8
		figure.build(height, wanted)

	figure.visible = shown

	if shown and controller != null:
		figure.face(deg_to_rad(controller.state.yaw))
		if figure.person != null:
			# The view's pitch: the head and the upper body follow where they look. The rest
			# of the motion the person measures itself (`auto_animate`).
			figure.person.set_motion({"aim": deg_to_rad(controller.state.pitch)})

	return shown


## Which of the runner atlases this player wears: their avatar's skin, or the one their id
## hashes to — from the id rather than a random draw, so every client dresses the same
## person the same way. A document naming a skin this build lacks is the hash, not a guess.
func _runner_atlas() -> String:
	var index := BfhAvatars.skin_index(avatar)

	if index < 0 or index >= BfhFigure.RUNNER_ATLASES.size():
		index = BfhAvatars.stock_index(player_id)

	return str(BfhFigure.RUNNER_ATLASES[index])


func give_hammer(config: BfhConfig) -> void:
	hammer = BfhHammer.new()
	hammer.configure(config)


func describe() -> Dictionary:
	return {
		"id": String(player_id),
		"riding": riding,
		"alive": health == null or health.alive,
		"health": health.health if health != null else 0.0,
		"carried": "%.1f m" % carried_metres,
		"blinded": blinded,
		"beacon": beacon,
		"figure": figure.describe() if figure != null else {},
	}
