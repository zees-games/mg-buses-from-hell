extends Node3D
## The bus autopilot: how a stand-in driver steers, backs off, lines up for the ramp and gets unstuck.

const BfhArena := preload("bfh_arena.gd")
const BfhConfig := preload("bfh_config.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhTextures := preload("bfh_textures.gd")

## How squarely in front a runner has to be before a bot sounds its horn.
const BOT_HORN_ALIGNMENT := 0.85

## Half the width and length of a bus, in metres.
const BUS_HALF_WIDTH := 1.5
const BUS_HALF_LENGTH := 3.2

@export var config: BfhConfig = null

var arena: BfhArena = null
var vehicles: DotVehicleSpawner = null
var ride: DotVehicleRide = null

## player id -> BfhPlayer.
var players: Dictionary = {}

## Instance id -> seconds this bus has been asking to move and not moving.
var _bus_stuck: Dictionary = {}

## Bus instance id -> seconds a bot has been backing round to face the ramp.
var _bus_backing: Dictionary = {}

## Bus instance id -> the planned turn a bot is making in front of the ramp's foot.
var _bus_turning: Dictionary = {}


## Overridden by the game: the runner team.
func runners() -> Array[BfhPlayer]:
	return []


## Overridden by the game: where the concrete blocks lie. A bus cannot break one and can climb onto one.
func block_positions() -> Array[Vector3]:
	return []


## How far ahead a bot looks for a block (more at speed: a bus doing 14 m/s needs the room), the
## room it leaves beside one past the bus's half width, and the speed it allows itself at a block
## `ahead` metres off: `BLOCK_SPEED_BASE + ahead * BLOCK_SPEED_PER_M`.
const BLOCK_LOOK_AHEAD := 12.0
const BLOCK_LOOK_SECONDS := 1.2
const BLOCK_ROOM := 2.5
const BLOCK_SPEED_BASE := 4.0
const BLOCK_SPEED_PER_M := 0.8


## Bus instance id -> `{block, sign}`: the side of a block a bot has chosen to pass on.
var _bus_block_side: Dictionary = {}


## [param aim] (on the way to [param goal]) swung round the nearest block lying across the bus's way,
## or [param aim] itself, and slows the bot's driver for it. A block cannot be broken, so a bus that
## drives onto one sits high-centred on it until the stuck rule hops it off (`bfh_downtown`,
## `--pace-seed=12`: two seconds on open floor where an avenue crosses a street). Judged against the
## bus's heading, so a block beside the way is left alone.
func _round_the_blocks(player: BfhPlayer, bus: DotVehicleInstance, aim: Vector3, goal: Vector3) -> Vector3:
	var at := bus.position()
	var forward := -bus.body().global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return aim
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var to_goal := Vector2(goal.x - at.x, goal.z - at.z).length()
	var nearest := Vector3.INF
	var nearest_ahead := maxf(BLOCK_LOOK_AHEAD, bus.speed() * BLOCK_LOOK_SECONDS)
	for block in block_positions():
		var rel := block - at
		rel.y = 0.0
		var ahead := rel.dot(forward)
		if ahead < 1.0 or ahead >= nearest_ahead or ahead > to_goal:
			continue
		if absf(rel.dot(right)) > BUS_HALF_WIDTH + BLOCK_ROOM:
			continue
		nearest = block
		nearest_ahead = ahead
	if nearest == Vector3.INF:
		return aim
	player.autopilot.target_speed = minf(player.autopilot.target_speed,
		BLOCK_SPEED_BASE + nearest_ahead * BLOCK_SPEED_PER_M)
	# The side nearer the aim when the block is first met, and the same side after: the aim moves as
	# the bus turns, and a bus swung back and forth between the two sides drives along the block.
	var room := BUS_HALF_WIDTH + BLOCK_ROOM + 1.0
	var held: Dictionary = _bus_block_side.get(bus.instance_id, {})
	var side_sign := float(held.get("sign", 0.0))
	if held.is_empty() or Vector3(held["block"]).distance_to(nearest) > 1.0:
		var left := nearest - right * room
		var right_of := nearest + right * room
		side_sign = -1.0 if left.distance_squared_to(aim) < right_of.distance_squared_to(aim) else 1.0
		_bus_block_side[bus.instance_id] = {"block": nearest, "sign": side_sign}
	var detour := nearest + right * room * side_sign
	detour.y = aim.y
	return detour


## Overridden by the game: sounds a driver's horn.
func sound_horn(_player: BfhPlayer) -> bool:
	return false


## Turns each driver's movement keys into throttle and steering.
func _drive_buses(delta: float) -> void:
	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if not player.riding:
			continue

		var instance_id := ride.vehicle_id_of(player.player_id)
		if instance_id == 0:
			continue

		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			continue

		# `current_command` is what `apply_command` stored and what the next tick would have moved them
		# with.
		var command: DotVehicleCommand = null

		if player.is_bot:
			command = _autopilot(player, bus, delta)
			bus.command = command
			if bus.chassis != null:
				(bus.chassis as DotVehicleChassis).drive(command, delta)
			continue

		var pending := player.controller.current_command
		command = DotVehicleCommand.new()

		if pending != null:
			# `move.y` is forward and `move.x` strafes right. The wheel is the strafe
			# axis negated, because steering right is a negative yaw in Godot's frame
			# and a driver pressing D expects the bus to go right.
			command.throttle = clampf(pending.move.y, -1.0, 1.0)
			command.steer = clampf(-pending.move.x, -1.0, 1.0)
			command.handbrake = pending.is_pressed(DotFpsCommand.BUTTON_CROUCH)
			command.aim_yaw = pending.yaw
			command.aim_pitch = pending.pitch
			# S brakes while the bus is still rolling forward and reverses once it has (nearly) stopped, as
			# the key list says; W while rolling back brakes too. Reverse thrust stopped a bus from 15 m/s in
			# 21 m against the foot brake's 7.6.
			command.brake_then_reverse(bus.forward_speed())

		bus.command = command

		if bus.chassis != null:
			(bus.chassis as DotVehicleChassis).drive(command, delta)


## Drives a bot's bus at whoever is nearest.
func _autopilot(player: BfhPlayer, bus: DotVehicleInstance, delta: float) -> DotVehicleCommand:
	_ensure_autopilot(player)
	var quarry := _nearest_runner(bus.position())

	if quarry == null:
		# Nobody left to chase. Returned idle rather than left holding the last
		# command: a bus still flooring it at a target that no longer exists is a bus
		# that drives into the wall for the rest of the round.
		return DotVehicleCommand.new()

	# Aimed PAST them, not at them. The driver decides its speed from the distance to its target, so a
	# target sitting on the runner is a target that is always nearly reached — the bus arrives gently.
	var skill := DotBotSettings.of(self).profile
	var target := quarry.global_position + _bot_lead(bus, quarry, skill)
	var line := target - bus.position()
	line.y = 0.0

	var beyond := (
		target + line.normalized() * config.bot_aim_past if line.length() > 0.5
		else target
	)

	_horn_at_the_quarry(player, bus, line)

	# And round the stacks, because the driver has no idea they are there. A bus aimed through a pillar
	# wedges nose-on and the stuck rule then teleports it back to its start line, which from the
	# runner's side reads as hiding behind a pillar deleting the bus.
	var bound := _bound_for_the_ramp(bus, beyond, delta)
	var pace := config.bus_top_speed * clampf(1.0 + 0.4 * (skill.aggression - _MEDIUM.aggression), 0.5, 1.0)
	player.autopilot.target_speed = minf(pace, config.bot_ramp_speed) if bound else pace
	# Written every tick rather than once, so `bfh_bot_steer_clearance` takes effect on the
	# next tick. Only the bots read it; see [member BfhArena.steer_clearance].
	arena.steer_clearance = config.bot_steer_clearance
	arena.route_clearance = config.bot_route_clearance

	# [b]A district is a maze and is driven by a route.[/b] Through the streets with [method
	# BfhArena.street_route]; the first waypoints are passed at speed like any detour and the point
	# past the quarry is last.
	if not bound and arena.routes_through_streets():
		var path := _street_path(bus, quarry.global_position, beyond, delta)
		var head := path[0] if not path.is_empty() else beyond
		var round_block := _round_the_blocks(player, bus, head, beyond)
		if round_block != head:
			path.insert(0, round_block)
		var backed := _back_off(bus, path[0] if not path.is_empty() else beyond, delta)
		if backed != null:
			return backed
		path.append(beyond)
		player.autopilot.set_route(path)
		return player.autopilot.drive(bus, delta)

	var aim := arena.steer_around(bus.position(), beyond)
	# Level with a pillar is past it, so a bus at a standstill on its waypoint drives on along its line
	# to the quarry. Only at a standstill: done at speed, inside `steer_around`, it threw the stacks'
	# pillar drive off its line onto the next pillar in the row. `headless_run`'s "no bot bus ...
	var on_it := Vector2(aim.x - bus.position().x, aim.z - bus.position().z).length()
	if on_it < PARKED_ON_WAYPOINT and bus.speed() < 1.0 and line.length() > 0.5:
		aim = bus.position() + line.normalized() * config.bot_steer_clearance
		aim.y = beyond.y
	if not bound:
		var backed_off := _back_off(bus, aim, delta)
		if backed_off != null:
			return backed_off
	if bound:
		var turned := _turn_round_for_the_ramp(player, bus, delta)
		if turned != null:
			return turned
		var backing := _turn_for_the_ramp(bus, aim, delta)
		if backing != null:
			return backing
	else:
		_bus_backing.erase(bus.instance_id)
		_bus_turning.erase(bus.instance_id)
	# So the detour is the first of two waypoints and the point past the quarry the second, which the
	# driver passes at `waypoint_radius` with no slowing. Not up the ramp, whose line-up points are
	# meant to be arrived at slowly and are tuned for it.
	if not bound and Vector2(aim.x - beyond.x, aim.z - beyond.z).length() > 0.5:
		player.autopilot.set_route(PackedVector3Array([aim, beyond]))
	else:
		player.autopilot.set_target(aim)
	return player.autopilot.drive(bus, delta)


## The bot driver, made once and tuned for a nine-metre bus.
func _ensure_autopilot(player: BfhPlayer) -> void:
	if player.autopilot == null:
		player.autopilot = DotVehicleDriver.new()
		player.autopilot.target_speed = config.bus_top_speed
		# Wider than the default, because a bus is nine metres long: a waypoint radius tighter than the
		# vehicle means it can never be "at" its target and it circles the spot for ever.
		player.autopilot.arrive_radius = 0.5
		player.autopilot.waypoint_radius = 2.0
		# [b]No corner-cutting toward the next waypoint.[/b] The point beside a pillar is placed at
		# exactly the clearance `steer_around` measured; blending it 4 m toward the quarry (the driver's
		# default) drove the bus inside that clearance, and the colonnade's drive along the walk from its.
		player.autopilot.look_ahead = 0.0


## The horn, when somebody is lined up in front of the bus.
func _horn_at_the_quarry(player: BfhPlayer, bus: DotVehicleInstance, line: Vector3) -> void:
	# Not every tick — see [method sound_horn] —
	# and not at somebody behind it or off to one side, because a horn is a bus saying "you", and a bot
	# that honked at everybody would be saying nothing.
	var forward := -bus.body().global_basis.z
	forward.y = 0.0
	if line.length() < config.bot_horn_range and line.length() > 0.5 and forward.length() > 0.01 \
			and line.normalized().dot(forward.normalized()) > BOT_HORN_ALIGNMENT:
		sound_horn(player)


## Whether the bus is on the ramp rules this tick: not while resting from a turn, and not in the
## streets until it is near the foot.
func _bound_for_the_ramp(bus: DotVehicleInstance, beyond: Vector3, delta: float) -> bool:
	var bound := arena.ramp_bound(bus.position(), beyond)
	var resting := float(_bus_turn_rest.get(bus.instance_id, 0.0))
	if resting > 0.0:
		_bus_turn_rest[bus.instance_id] = resting - delta
		bound = false
	if bound and arena.routes_through_streets() \
			and bus.position().distance_to(arena.ramp_foot()) > STREET_RAMP_NEAR:
		bound = false
	return bound


## Instance id -> seconds of reversing a wedged bot bus has left.
var _bus_backing_off: Dictionary = {}


## A bot bus that has been throttling against something, backing out of it: reverse with the wheel
## over (in reverse it swings the nose towards the side [param toward] is on) for
## `bot_unwedge_seconds`, then null so the ordinary drive takes over from where it got to.
func _back_off(bus: DotVehicleInstance, toward: Vector3, delta: float) -> DotVehicleCommand:
	var left := float(_bus_backing_off.get(bus.instance_id, 0.0))
	var held := float(_bus_stuck.get(bus.instance_id, 0.0))
	if held <= 0.0:
		# Free (or never caught): the next wedge starts by reversing again.
		_bus_back_forward.erase(bus.instance_id)
	if left <= 0.0:
		if held < config.bot_unwedge_after:
			return null
		left = config.bot_unwedge_seconds
	left -= delta
	if left <= 0.0:
		_bus_backing_off.erase(bus.instance_id)
		if held >= config.bot_unwedge_after:
			_bus_back_forward[bus.instance_id] = not _bus_back_forward.get(bus.instance_id, false)
		return null
	_bus_backing_off[bus.instance_id] = left

	var right := bus.body().global_basis.x
	right.y = 0.0
	var to := toward - bus.position()
	to.y = 0.0
	var side := 1.0 if right.dot(to) >= 0.0 else -1.0
	var forward: bool = _bus_back_forward.get(bus.instance_id, false)
	var command := DotVehicleCommand.new()
	command.throttle = BACK_OFF_THROTTLE if forward else -BACK_OFF_THROTTLE
	command.steer = side if forward else -side
	command.sanitise()
	return command


## Instance id -> true when the wedged bus's current leg is forward rather than reverse.
var _bus_back_forward: Dictionary = {}


const BACK_OFF_THROTTLE := 0.9


## Instance id -> `{path, age, to}`: the street route a bot bus is following.
var _bus_routes: Dictionary = {}


## The waypoints a bot bus follows through a district to [param beyond], replanned every
## `bot_route_replan` seconds or when the quarry has moved on, with the ones it has reached
## dropped each tick. Empty when the line is clear.
func _street_path(bus: DotVehicleInstance, quarry_at: Vector3, beyond: Vector3,
		delta: float) -> PackedVector3Array:
	var held: Dictionary = _bus_routes.get(bus.instance_id, {})
	var age := float(held.get("age", INF)) + delta
	var stale := held.is_empty() or age >= config.bot_route_replan \
		or Vector3(held["to"]).distance_to(quarry_at) > STREET_REPLAN_MOVED
	if stale:
		held = {"path": arena.street_route(bus.position(), quarry_at), "to": quarry_at}
		age = 0.0
	held["age"] = age

	var path: PackedVector3Array = held["path"]
	# Dropped once passed, so the first waypoint is always ahead: the driver is handed the
	# list afresh each tick and aims at its head.
	var at := bus.position()
	while not path.is_empty() and Vector2(path[0].x - at.x, path[0].z - at.z).length() < STREET_PASSED:
		path.remove_at(0)
	held["path"] = path
	_bus_routes[bus.instance_id] = held
	return path.duplicate()


## How far a bot's quarry may move before its route is planned again, and how close to a
## waypoint a bus is before it counts as passed. Metres.
const STREET_REPLAN_MOVED := 6.0
const STREET_PASSED := 3.5


## A bot bus that has to face the other way to get up the ramp turns round in legs, or null to drive
## on.
func _turn_for_the_ramp(bus: DotVehicleInstance, aim: Vector3, delta: float) -> DotVehicleCommand:
	var basis := bus.body().global_basis
	var forward := -basis.z
	forward.y = 0.0
	var right := basis.x
	right.y = 0.0
	var to := aim - bus.position()
	to.y = 0.0
	if forward.length() < 0.01 or to.length() < 0.5:
		_bus_backing.erase(bus.instance_id)
		return null
	var wanted := to.normalized()
	var off := rad_to_deg(acos(clampf(wanted.dot(forward.normalized()), -1.0, 1.0)))

	var turning: Dictionary = _bus_backing.get(bus.instance_id, {})
	if turning.is_empty():
		var limit := RAMP_LINED_UP if arena.lining_up(bus.position()) else RAMP_BACK_FROM
		if off < limit:
			return null
		turning = {"reverse": true, "held": 0.0}
	elif off < RAMP_BACK_TO:
		_bus_backing.erase(bus.instance_id)
		return null

	var reverse: bool = turning["reverse"]
	var held: float = float(turning["held"]) + delta
	if held > (RAMP_BACK_LONGEST if reverse else RAMP_FORWARD_LONGEST):
		reverse = not reverse
		held = 0.0
	turning["reverse"] = reverse
	turning["held"] = held
	_bus_backing[bus.instance_id] = turning

	# +1 steers right (DotVehicleCommand's convention). Forward, the wheel points at the
	# side the point is on; in reverse it goes the other way, which brings the nose round
	# towards the same side.
	var toward := 1.0 if wanted.dot(right.normalized()) >= 0.0 else -1.0
	var command := DotVehicleCommand.new()
	command.throttle = -RAMP_TURN_THROTTLE if reverse else RAMP_TURN_THROTTLE
	command.steer = -toward if reverse else toward
	command.sanitise()
	return command


## A bot bus bound up the ramp that cannot simply drive at it (back to it, or climbing off the
## middle) turns or backs down and lines up again. Null when neither applies and the ordinary line-
## up drives.
func _turn_round_for_the_ramp(player: BfhPlayer, bus: DotVehicleInstance,
		delta: float) -> DotVehicleCommand:
	var id := bus.instance_id
	var pos := bus.position()
	var basis := bus.body().global_basis
	var forward := -basis.z
	forward.y = 0.0
	var right := basis.x
	right.y = 0.0
	if forward.length() < 0.01:
		_bus_turning.erase(id)
		return null
	forward = forward.normalized()
	right = right.normalized()
	# Up the ramp is -Z: the deck is at the north rim.
	var axis := Vector3(0.0, 0.0, -1.0)
	var off := rad_to_deg(acos(clampf(forward.dot(axis), -1.0, 1.0)))
	var foot_z := arena.ramp_foot().z
	var out := pos.z - foot_z
	var speed := bus.velocity().dot(forward)
	# Where the bus would come out across the centreline if it straightened up from here
	# at full lock: [constant RAMP_LINE_RADIUS] (1 - cos) of the angle it is heading in at,
	# taken off its offset when it is heading towards the line and added when away.
	var toward_line := -signf(pos.x) if absf(pos.x) > 0.01 else 0.0
	var slant := atan2(forward.x * toward_line, -forward.z)
	var settles := absf(pos.x) - signf(slant) * RAMP_LINE_RADIUS * (1.0 - cos(slant))
	var lined := absf(settles) <= RAMP_LINED_X and off <= RAMP_LINED_OFF

	var plan: Dictionary = _bus_turning.get(id, {})
	if plan.is_empty():
		plan = _ramp_turn_plan(bus, pos, off, out, speed)
		if plan.is_empty():
			return null

	# [b]A turn that is not finishing is given up.[/b] In a district the turning point can have
	# buildings round it and the legs shuffle for ever (hill town, 40 s, never reaching the
	# line-up); the bus rests from the ramp rules and drives its route or nudge instead.
	plan["age"] = float(plan.get("age", 0.0)) + delta
	if float(plan["age"]) > RAMP_TURN_GIVE_UP:
		_bus_turning.erase(id)
		_bus_turn_rest[id] = RAMP_TURN_REST
		return null

	var centre: Vector3 = plan["centre"]
	var to_centre := Vector3(centre.x - pos.x, 0.0, centre.z - pos.z)
	plan["held"] = float(plan["held"]) + delta

	if plan["phase"] == "approach":
		if not _ramp_turn_arrived(bus, pos, forward, right, out, speed, centre, to_centre):
			player.autopilot.target_speed = minf(config.bus_top_speed, RAMP_TURN_APPROACH)
			player.autopilot.set_target(arena.steer_around(pos, centre))
			return player.autopilot.drive(bus, delta)
		_ramp_turn_begin_legs(plan, pos, forward, right, axis, speed, to_centre)

	_ramp_turn_next_phase(plan, off, out, settles, lined, axis, right)

	var command := DotVehicleCommand.new()
	if plan["phase"] == "line":
		return _ramp_turn_line(bus, plan, command, pos, forward, right, axis, out, speed, lined)
	return _ramp_turn_legs(bus, plan, command, pos, forward, right, speed, centre)


## A new turn's plan: facing away from the ramp, or climbing its first metres off the middle. Empty
## when the bus needs neither; it records the plan and clears the backing-off state when it starts.
func _ramp_turn_plan(bus: DotVehicleInstance, pos: Vector3, off: float, out: float,
		speed: float) -> Dictionary:
	var plan := {}
	# Facing away from the ramp, wherever it is: beside the slab, where the buses
	# start, or in front of the foot.
	if off >= RAMP_FACING_AWAY:
		plan = {"phase": "approach"}
	elif out < 0.0 and out > -RAMP_EDGE_CHECK and absf(pos.x) > RAMP_EDGE_X \
			and arena.lining_up(pos) and speed > 0.0:
		# Climbing the ramp's first metres off the middle, heading for its edge: back
		# down it and line up again, rather than wedge a wheel over the side.
		plan = {"phase": "line", "reverse": true}
	else:
		return {}
	plan["centre"] = arena.ramp_turn_point()
	if not plan.has("reverse"):
		plan["reverse"] = false
	# Stopped first if it is to back off while still rolling at the slab.
	plan["settling"] = plan["reverse"] and speed > RAMP_LEG_STILL
	plan["held"] = 0.0
	plan["sense"] = 1.0
	_bus_turning[bus.instance_id] = plan
	_bus_backing.erase(bus.instance_id)
	return plan


## Whether the approach is over: arrived, or going past the turning point, or far enough out that
## its tail is clear of the foot and the floor ahead is open (the first leg begins on the way in,
## which is two seconds of a twenty-second chase).
func _ramp_turn_arrived(bus: DotVehicleInstance, pos: Vector3, forward: Vector3, right: Vector3,
		out: float, speed: float, centre: Vector3, to_centre: Vector3) -> bool:
	return to_centre.length() < RAMP_TURN_ARRIVE or (
		to_centre.length() < RAMP_TURN_ARRIVE * 2.0 and forward.dot(to_centre) < 0.0) \
		or (out > BUS_HALF_LENGTH + RAMP_TURN_MARGIN and speed > 0.5
			and not _end_blocked(bus, pos, forward, right, false, centre))


## The approach hands over to the first leg.
func _ramp_turn_begin_legs(plan: Dictionary, pos: Vector3, forward: Vector3, right: Vector3,
		axis: Vector3, speed: float, to_centre: Vector3) -> void:
	plan["phase"] = "legs"
	plan["held"] = 0.0
	plan["leg_from"] = pos
	# The way round, once. Straight behind, either way is half a turn, so it goes the
	# way that swings the nose across the centre rather than away from it.
	if forward.dot(axis) > -0.985:
		plan["sense"] = 1.0 if axis.dot(right) >= 0.0 else -1.0
	else:
		plan["sense"] = 1.0 if to_centre.dot(right) >= 0.0 else -1.0
	# The leg it is already rolling on, or the one that leads towards the middle.
	if absf(speed) > 0.5:
		plan["reverse"] = speed < 0.0
	else:
		plan["reverse"] = forward.dot(to_centre) < 0.0


## Legs become the line-up once it is nearly facing the ramp, and the line-up goes back to legs if
## it is far off again.
func _ramp_turn_next_phase(plan: Dictionary, off: float, out: float, settles: float,
		lined: bool, axis: Vector3, right: Vector3) -> void:
	if plan["phase"] == "legs" and (off < RAMP_TURN_DONE
			or (off < RAMP_LINED_OFF and absf(settles) < RAMP_TURN_NEARLY)):
		plan["phase"] = "line"
		plan["held"] = 0.0
		plan["settling"] = true
		plan["reverse"] = out < RAMP_LINE_COMMIT and not lined
	elif plan["phase"] == "line" and off > RAMP_TURN_AGAIN:
		plan["phase"] = "legs"
		plan["held"] = 0.0
		plan["settling"] = true
		plan["sense"] = 1.0 if axis.dot(right) >= 0.0 else -1.0
		plan["reverse"] = not plan["reverse"]


## One tick of the line-up: back for room, then forward onto the centreline. Null once the bus is
## onto the slab going forward, where the ordinary climb takes over.
func _ramp_turn_line(bus: DotVehicleInstance, plan: Dictionary, command: DotVehicleCommand,
		pos: Vector3, forward: Vector3, right: Vector3, axis: Vector3, out: float, speed: float,
		lined: bool) -> DotVehicleCommand:
	var held := float(plan["held"])
	var reverse: bool = plan["reverse"]
	if out < 0.0 and not reverse and not plan["settling"]:
		# Onto the slab going forward: the ordinary climb takes it from here.
		_bus_turning.erase(bus.instance_id)
		return null
	if not plan["settling"]:
		var change := false
		if reverse:
			# Back far enough to straighten out in, or as far as the floor goes.
			# (The floor test is for the floor: backing down the slab, the slab is under it.)
			change = out >= RAMP_LINE_BACK_TO \
				or (out > 0.0 and _end_blocked(bus, pos, forward, right, true)) \
				or (held > RAMP_LEG_STALL and absf(speed) < 0.3)
		else:
			# Too close to the foot to come right before the slab: back off and try again.
			change = not lined and out < RAMP_LINE_COMMIT \
				or (held > RAMP_LEG_STALL and absf(speed) < 0.3)
		if change:
			reverse = not reverse
			plan["reverse"] = reverse
			plan["held"] = 0.0
			plan["settling"] = true
	if plan["settling"]:
		command.brake = 1.0
		if absf(speed) < RAMP_LEG_STILL and float(plan["held"]) > RAMP_LEG_SETTLE:
			plan["settling"] = false
			plan["held"] = 0.0
		command.sanitise()
		return command
	if not reverse:
		_ramp_line_forward(command, pos, forward, right, axis, speed, lined)
		command.sanitise()
		return command
	# Backing straight down the ramp's axis, for room: the nose held on the axis, so the
	# forward run after it starts square and has only the offset to take out.
	var angle := rad_to_deg(acos(clampf(axis.dot(forward), -1.0, 1.0)))
	var side := 1.0 if axis.dot(right) >= 0.0 else -1.0
	command.steer = -side * clampf(angle / 20.0, 0.0, 1.0)
	if absf(speed) < config.bot_ramp_leg_speed:
		command.throttle = -1.0
	command.sanitise()
	return command


## Onto the centreline the way a lane-keeping controller does it: the heading it wants is the
## ramp's axis turned towards the centreline by an angle that grows with how far off it is, so the
## offset and the heading are taken out together and the bus arrives on the line pointing along.
func _ramp_line_forward(command: DotVehicleCommand, pos: Vector3, forward: Vector3, right: Vector3,
		axis: Vector3, speed: float, lined: bool) -> void:
	var across := minf(acos(clampf(1.0 - absf(pos.x) / RAMP_LINE_RADIUS, -1.0, 1.0)),
		deg_to_rad(RAMP_LINE_STEEPEST))
	var wanted := axis * cos(across) + Vector3(-signf(pos.x), 0.0, 0.0) * sin(across)
	var turn := acos(clampf(wanted.dot(forward), -1.0, 1.0))
	var toward := 1.0 if wanted.dot(right) >= 0.0 else -1.0
	command.steer = toward * clampf(rad_to_deg(turn) / RAMP_LINE_STEER, 0.0, 1.0)
	var fast := config.bot_ramp_speed if lined else RAMP_LINE_SLOW
	if speed < fast:
		command.throttle = RAMP_TURN_THROTTLE
	elif speed > fast + 1.0:
		command.brake = 0.5


## One tick of the turn's legs: forward and back with the wheel over, braking to a stop between.
func _ramp_turn_legs(bus: DotVehicleInstance, plan: Dictionary, command: DotVehicleCommand,
		pos: Vector3, forward: Vector3, right: Vector3, speed: float,
		centre: Vector3) -> DotVehicleCommand:
	# `held` is read here: a phase that just began has reset it.
	var held := float(plan["held"])
	var reverse: bool = plan["reverse"]
	if not plan["settling"]:
		var stopped := held > RAMP_LEG_STALL and absf(speed) < 0.3
		# The turning point's reach and the centreline's bounds only once a leg is under
		# way: a bus already outside them would otherwise find both ends "blocked" and
		# never move again (measured from the sw start, stood still for 17 s).
		var bounds: Variant = centre if held > RAMP_LEG_FREE else null
		# [b]A leg that has not moved is not ended by the floor.[/b] A bus within the margin of something
		# at both ends found each new leg blocked on its first tick, flipped and braked again, and stood
		# braking for 27 s with no throttle for the stuck rule to see (small bowl, in front of the foot).
		var moved := pos.distance_to(plan.get("leg_from", pos)) > RAMP_LEG_MOVED
		if (moved and _end_blocked(bus, pos, forward, right, reverse, bounds)) or stopped \
				or held > RAMP_LEG_LONGEST:
			reverse = not reverse
			plan["reverse"] = reverse
			plan["held"] = 0.0
			plan["settling"] = true

	# +1 steers right (DotVehicleCommand's convention). Forward, the wheel is over to the
	# side the turn goes; in reverse it is over the other way, which turns the nose the
	# same way round.
	var sense: float = plan["sense"]
	command.steer = -sense if reverse else sense
	if plan["settling"]:
		command.brake = 1.0
		if absf(speed) < RAMP_LEG_STILL and float(plan["held"]) > RAMP_LEG_SETTLE:
			plan["settling"] = false
			plan["held"] = 0.0
			plan["leg_from"] = pos
	elif absf(speed) < config.bot_ramp_leg_speed:
		command.throttle = -1.0 if reverse else RAMP_TURN_THROTTLE
	command.sanitise()
	return command


## Whether the end of [param bus] it is moving towards ([param reverse] for the tail) is about to
## run out of floor: any of its two corners and its middle, a margin ahead along the way that point
## is moving, inside [constant RAMP_TURN_MARGIN] of an obstacle, the slab or the deck, or, with a.
func _end_blocked(bus: DotVehicleInstance, pos: Vector3, forward: Vector3, right: Vector3,
		reverse: bool, centre: Variant = null) -> bool:
	var lead := forward * (-BUS_HALF_LENGTH if reverse else BUS_HALF_LENGTH)
	var spin := bus.body().angular_velocity
	var velocity := bus.velocity()
	velocity.y = 0.0
	for across: float in [-BUS_HALF_WIDTH, 0.0, BUS_HALF_WIDTH]:
		var r := lead + right * across
		var point := pos + r
		var moving := velocity + spin.cross(r)
		moving.y = 0.0
		if moving.length() < 0.2:
			continue
		if arena.floor_clear_at(point + moving.normalized() * RAMP_TURN_MARGIN) < RAMP_TURN_MARGIN:
			return true
		if centre is Vector3:
			var c: Vector3 = centre
			var from_centre := Vector3(point.x - c.x, 0.0, point.z - c.z)
			if from_centre.length() > RAMP_TURN_REACH and moving.dot(from_centre) > 0.0:
				return true
	# And the middle of the bus no further across from the centreline than
	# [constant RAMP_TURN_ACROSS], so the turn ends in front of the ramp rather than beside it.
	if centre is Vector3:
		var c: Vector3 = centre
		if absf(pos.x - c.x) > RAMP_TURN_ACROSS and velocity.x * (pos.x - c.x) > 0.0:
			return true
	return false


## [method _turn_round_for_the_ramp]'s numbers. Degrees off the ramp's axis a ramp-bound
## bot has to face for it to turn round; how fast it drives to the turning point (m/s) and
## how near that counts as there (m).
const RAMP_FACING_AWAY := 110.0
const RAMP_TURN_APPROACH := 8.0
const RAMP_TURN_ARRIVE := 2.0
## How much floor the bus keeps ahead of the end it is moving towards; how far from the
## turning point its corners may go; and how far across from the centreline its middle may
## go, all in metres.
const RAMP_TURN_MARGIN := 0.8
const RAMP_TURN_REACH := 8.0
const RAMP_TURN_ACROSS := 2.5
## The turn becomes the line-up once the nose is within this many degrees of the axis, or
## within [constant RAMP_LINED_OFF] with a straightening that would land it within this
## many metres of the centreline; and goes back to turning beyond the third.
const RAMP_TURN_DONE := 20.0
const RAMP_TURN_NEARLY := 2.0
const RAMP_TURN_AGAIN := 60.0
## Lined up: a full-lock straightening at [constant RAMP_LINE_RADIUS] (the bus's turning
## radius at line-up speed, with a margin) would put it within this many metres of the
## centreline, and it is within this many degrees of the axis.
const RAMP_LINED_X := 1.0
const RAMP_LINED_OFF := 35.0
const RAMP_LINE_RADIUS := 12.0
## How far in front of the foot a bus backs off to before trying again, and how close it
## can come to it not lined up before it does (m); the steepest it comes at the centreline,
## and the error that is full lock (degrees); and how fast it lines up (m/s).
const RAMP_LINE_BACK_TO := 9.0
const RAMP_LINE_COMMIT := 4.0
const RAMP_LINE_STEEPEST := 35.0
const RAMP_LINE_STEER := 15.0
const RAMP_LINE_SLOW := 4.0
## A bus on the ramp's first this-many metres, more than this far off its middle, backs
## down and lines up again: the bus is 2.5 m across on 5 m of slab, so at 1.5 m its outer
## wheels are a quarter of a metre from the edge.
const RAMP_EDGE_CHECK := 10.0
const RAMP_EDGE_X := 1.5
## The speed a leg is held under (m/s); how still the bus has to be, and for how long the wheel has
## to swing, between legs; how long a leg can push without moving before it counts as stopped; how
## long a leg runs before the turning point's bounds apply; and the longest a leg.
const RAMP_LEG_STILL := 0.8
const RAMP_LEG_SETTLE := 0.2
const RAMP_LEG_STALL := 0.6
const RAMP_LEG_FREE := 0.4
const RAMP_LEG_LONGEST := 3.0
## How far a leg has to go before the floor can end it (m).
const RAMP_LEG_MOVED := 0.4
## How long a turn may take before the bus gives it up, and how long it then rests from the
## ramp rules (s).
const RAMP_TURN_GIVE_UP := 12.0
const RAMP_TURN_REST := 8.0

## Instance id -> seconds a bus that gave up its turn has left away from the ramp rules.
var _bus_turn_rest: Dictionary = {}


## How near its waypoint a stopped bot bus has to be to be standing on it: twice the
## autopilot's 0.5 m `arrive_radius`. See [method _autopilot].
const PARKED_ON_WAYPOINT := 1.0

## How fast a bot drives while it is lining up on and climbing the ramp, in m/s.

## How near the ramp's foot a district bus is before the ramp rules take over from its route (m).
const STREET_RAMP_NEAR := 24.0

## Degrees off its nose the point a ramp-bound bot steers for has to be before it turns round, on
## the floor and on the line-up; the angle it turns round to; the longest each leg of the turn
## lasts, in seconds; and the throttle it turns at. See [method _turn_for_the_ramp].
const RAMP_BACK_FROM := 110.0
const RAMP_BACK_TO := 15.0
const RAMP_LINED_UP := 35.0
const RAMP_BACK_LONGEST := 2.5
const RAMP_FORWARD_LONGEST := 1.5
const RAMP_TURN_THROTTLE := 0.7



## The preset a bot's numbers are taken relative to, so medium drives as before presets.
static var _MEDIUM: DotBotProfile = DotBotProfile.new()


## Releases every static resource the game holds, plus the family's shared caches, for a suite
## to call before quit(); after it the statics are unusable until the script reloads.
static func clear_cache() -> void:
	_MEDIUM = null
	BfhTextures.clear_cache()
	DotHumanoidFigure.clear_cache()
	DotHudPiece.clear_cache()
	DotMenuKit.clear_cache()
	DotPropBodyLook.clear_cache()
	DotPropModel.clear_cache()
	DotLog.clear_cache()
	DotRegistry.clear_cache()


## Where a bot aims past a runner, from where they are now: their run times the seconds the
## bus needs to get there (capped at two), by how much more (or less) than medium this bot
## reads a moving target. Zero at medium.
func _bot_lead(bus: DotVehicleInstance, quarry: BfhPlayer, skill: DotBotProfile) -> Vector3:
	if quarry.controller == null:
		return Vector3.ZERO
	var run: Vector3 = quarry.controller.state.velocity
	run.y = 0.0
	var seconds := minf(quarry.global_position.distance_to(bus.position()) / maxf(config.bus_top_speed, 1.0), 2.0)
	return run * seconds * (skill.prediction - _MEDIUM.prediction)


func _nearest_runner(to: Vector3) -> BfhPlayer:
	var best: BfhPlayer = null
	var best_distance := INF

	for candidate in runners():
		if candidate.health == null or not candidate.health.alive:
			continue

		var distance := candidate.global_position.distance_to(to)
		if distance < best_distance:
			best = candidate
			best_distance = distance

	return best
