extends "bfh_game_pilot.gd"
## What the buses do to the bowl: run runners over, break props, get unstuck and upright, and what a blast does.

const BfhReach := preload("bfh_reach.gd")
const BfhSounds := preload("bfh_sounds.gd")

const CHANNEL := "bfh.game"

const TEAM_DRIVERS := 1
const TEAM_RUNNERS := 2

## A barrel went off. The client draws it; this decides it.
signal barrel_exploded(at: Vector3, radius: float)

## Something in the bowl made a noise worth hearing: one of `BfhSounds.WORLD`, where it happened.
signal noise(id: StringName, at: Vector3)

## A bus touched a runner. [param lethal] is whether they are out, read AFTER the damage
## rather than predicted from the speed — a runner an admin has put in god mode is hit at
## a lethal speed and is not flattened.
signal run_over(player_id: StringName, by: StringName, lethal: bool)

## A bus drove into a prop, at speed or stuck on it. [param by] is its driver, or empty.
signal bus_struck(instance_id: int, by: StringName)

var props: DotPropSpawner = null
var prop_damage: DotPropDamage = null

var combat: DotCombatManager = null

## player id -> team, for the sides that outlive a round.
var sides: Dictionary = {}

var _bus_ids: Array[int] = []

## Whether a player's client is still behind its loading cover: `func(player_key: StringName) -> bool`.
## The server module fills it from dot-game's roster; unset (offline, a suite, a bot) nobody is
## loading, so every offline suite is unchanged. A covered client froze itself and cannot see.
var loading_fn: Callable = Callable()

## Whether this instance decides anything. A client sets this false.
@export var authoritative: bool = true

## A bus that touched somebody, and what that costs them.
func _check_bus_impacts(delta: float) -> void:
	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			continue

		var body := bus.body()
		if body == null:
			continue

		var bus_velocity := bus.velocity()
		var driver_id := driver_of(instance_id)
		var roof := _roof_of(body)

		for id: StringName in players:
			var player: BfhPlayer = players[id]

			if player.riding or player.health == null or not player.health.alive:
				continue
			if int(sides.get(id, 0)) == TEAM_DRIVERS:
				continue

			var offset := player.global_position - body.global_position
			# A crude bound rather than a physics contact: the bus is a 2.5 x 2.6 x 9 box and this is the
			# sphere around it. Deliberately generous, because a miss that should have been a hit is the
			# complaint this game would actually get, and a hit is checked against closing speed anyway.
			if offset.length() > 4.2:
				continue

			# [b]And nothing above the roof, which the sphere cannot tell.[/b] A sphere round a box that is
			# wider than it is tall reaches over the top of it: a runner standing three crates up, with a bus
			# driving past the foot of the stack, was 3.2 m from its centre and killed — by a vehicle whose.
			if player.global_position.y > roof + BUS_ROOF_MARGIN:
				continue

			# [b]Along the offset, not against it.[/b] `offset` runs from the bus to the player, so a bus
			# moving toward them has a POSITIVE component along it.
			var closing := (bus_velocity - player.controller.state.velocity).dot(
				offset.normalized()
			)

			if closing < 1.0:
				continue

			_bus_hit(player, driver_id, closing, offset)

		_break_props_under(bus, bus_velocity.length(), driver_id)
		_unstick(bus, driver_id, delta)
		_upright(bus, delta)

## The top of a bus's hull in world height, from its own collider.
func _roof_of(body: Node3D) -> float:
	var hull := body.get_node_or_null(^"Collision") as CollisionShape3D
	if hull == null or not (hull.shape is BoxShape3D):
		return body.global_position.y + 3.0
	var top := hull.position + Vector3(0.0, (hull.shape as BoxShape3D).size.y * 0.5, 0.0)
	return (body.global_transform * top).y

## How far above the roof a runner's feet can be and still be hit: a bus bouncing on
## its springs, and a runner a few centimetres off the crate they are running across.
const BUS_ROOF_MARGIN := 0.25

## Whether [param player] is behind a loading cover and so may not be hurt. Only the two
## hazards (a bus, a barrel's blast) ask; an admin's slay or slap goes straight to dot-combat.
func is_loading(player: BfhPlayer) -> bool:
	return loading_fn.is_valid() and bool(loading_fn.call(player.player_id))

func _bus_hit(player: BfhPlayer, by: StringName, closing: float, offset: Vector3) -> void:
	# Before the damage, the knock and the sound: a hit that did not happen leaves no trace.
	if is_loading(player):
		return

	var lethal := closing >= config.bus_lethal_speed
	var amount := config.runner_health * 2.0 if lethal else closing * config.bus_bump_damage

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	var damage := DotDamage.make(attacker, player.entity_id, amount, null)
	damage.point = player.global_position
	damage.direction = offset.normalized()
	# What killed them, for how the body falls (`decide_death`): a bus throws it.
	damage.context = {"why": KILLED_BY_BUS}
	combat.apply_damage(damage)

	# Whether it put them down, from the health rather than from `lethal`: a runner in an
	# admin's god mode is hit at a killing speed and is not out, and a sound or a statistic
	# that said otherwise would be describing a different game from the one on screen.
	var down := player.health != null and not player.health.alive
	run_over.emit(player.player_id, by, down)
	noise.emit(BfhSounds.RUNNER_DOWN if down else BfhSounds.RUNNER_HIT, player.global_position)

	# Knocked away whether or not it killed them, because a bus that passes through
	# somebody standing still and leaves them standing still is the one thing in this
	# game that would look broken from every angle.
	player.controller.state.velocity += offset.normalized() * closing * 0.6

func _break_props_under(bus: DotVehicleInstance, speed: float, by: StringName) -> void:
	if speed < 4.0 or prop_damage == null:
		return

	var body := bus.body()
	var into_bus := body.global_transform.affine_inverse()

	for prop in props.all_props():
		if not prop.is_alive():
			continue

		var prop_body := prop.body()
		if prop_body == null:
			continue

		var local := into_bus * prop_body.global_position

		if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
			continue

		# Vertically too, or a bus passing under a ledge takes out whatever is standing
		# on top of it.
		if absf(local.y) > 2.5:
			continue

		# Before the impact, which may break it: whoever put this crate here is credited
		# with the bus finding it, whether or not it survives the finding.
		bus_struck.emit(prop.instance_id, by)
		prop_damage.impact(prop.instance_id, speed, by)

## Instance ids that have hopped in this stuck spell; forgotten once the bus moves.
var _bus_hopped: Dictionary = {}

## Instance id -> `{at, held}`: where a bus asking for throttle was last clear of, and for how long.
var _bus_pinned: Dictionary = {}

## Breaks whatever lies under the bus's footprint.
func _clear_props_under(bus: DotVehicleInstance, by: StringName) -> void:
	if prop_damage == null:
		return
	var into_bus := bus.body().global_transform.affine_inverse()
	for prop in props.all_props():
		if not prop.is_alive() or prop.body() == null:
			continue
		var local := into_bus * prop.body().global_position
		if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
			continue
		if absf(local.y) > 2.5:
			continue
		bus_struck.emit(prop.instance_id, by)
		prop_damage.break_now(prop.instance_id, by)

## A bus that is throttling and going nowhere, and what to do about it.
func _unstick(bus: DotVehicleInstance, by: StringName, delta: float) -> void:
	var asking := bus.command != null and absf(bus.command.throttle) > 0.3
	var moving := bus.speed() > 1.0

	# [b]Rocking in place is not moving.[/b] The back-off reverses and goes forward again, and each
	# lurch passes 1 m/s and restarts the clock below, so a bus wedged among crates in a street
	# shuffled within three metres for 20 s without ever being caught (hill town).
	var pin: Dictionary = _bus_pinned.get(bus.instance_id, {})
	var here := bus.position()
	if pin.is_empty() or not asking or here.distance_to(pin["at"]) > config.bus_pinned_radius:
		pin = {"at": here, "held": 0.0}
	else:
		pin["held"] = float(pin["held"]) + delta
	_bus_pinned[bus.instance_id] = pin
	var pinned := float(pin["held"]) >= config.bus_pinned_seconds
	if pinned:
		moving = false

	if not asking or moving:
		_bus_stuck.erase(bus.instance_id)
		_bus_hopped.erase(bus.instance_id)
		return

	var held := float(_bus_stuck.get(bus.instance_id, 0.0)) + delta
	if pinned:
		held = maxf(held, config.bus_stuck_reset_seconds)
	_bus_stuck[bus.instance_id] = held

	if held < config.bus_stuck_break_seconds:
		return

	# Whatever is under it, at any speed. This is the one place the closing-speed rule
	# is deliberately not applied: the bus is not hitting the crate, it is sitting on it.
	_clear_props_under(bus, by)

	# [b]Before the start line, a short hop back the way it came.[/b] A bus sitting on a concrete block
	# (it cannot be broken or pushed, so the rule above has nothing to remove) is high-centred in both
	# directions, and the back-off rocking cannot lift it.
	var hop_at := minf(config.bus_stuck_hop_seconds, config.bus_stuck_reset_seconds * 0.5)
	if held >= hop_at and not _bus_hopped.has(bus.instance_id):
		_bus_hopped[bus.instance_id] = true
		var behind := bus.body().global_basis.z
		behind.y = 0.0
		if behind.length() > 0.01 and bus.body().global_basis.y.y > 0.5:
			var hop_body := bus.body()
			hop_body.linear_velocity = Vector3.ZERO
			hop_body.angular_velocity = Vector3.ZERO
			hop_body.global_position += behind.normalized() * config.bus_stuck_hop_metres + Vector3.UP * 0.4
			DotLog.debug(CHANNEL, "a stuck bus hopped back", {"stuck_for": held})
			return

	if held < config.bus_stuck_reset_seconds:
		return

	var index := maxi(_bus_ids.find(bus.instance_id), 0)
	var at := arena.bus_start(index, maxi(_bus_ids.size(), 1))
	var facing := Vector3(-at.x, 0.0, -at.z)

	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01 else Basis.IDENTITY,
		at,
	)

	_bus_stuck.erase(bus.instance_id)
	_bus_pinned.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was put back on its start line", {"stuck_for": held})

## Seconds a bus may lie on its roof before it is rolled back over.
const INVERTED_RIGHT_SEC := 2.0

## Instance id -> seconds this bus has been upside down.
var _bus_inverted: Dictionary = {}

## A bus that has rolled over, and why it is not left there.
func _upright(bus: DotVehicleInstance, delta: float) -> void:
	if not bus.is_inverted():
		_bus_inverted.erase(bus.instance_id)
		return

	var held := float(_bus_inverted.get(bus.instance_id, 0.0)) + delta
	_bus_inverted[bus.instance_id] = held

	if held < INVERTED_RIGHT_SEC:
		return

	var body := bus.body()

	if body == null:
		return

	# The heading, flattened. `global_basis.z` on an upside-down body still points the way
	# the bus was facing; what has to go is the roll and the pitch around it.
	var facing := -body.global_basis.z
	facing.y = 0.0

	var orientation := (
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01
		else Basis.IDENTITY
	)

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		orientation, body.global_position + Vector3(0.0, 1.0, 0.0)
	)

	_bus_inverted.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was rolled back onto its wheels", {"upside_down_for": held})

## Who is driving the bus with this instance id, or an empty name.
func driver_of(instance_id: int) -> StringName:
	for id: StringName in players:
		if ride.vehicle_id_of(id) == instance_id:
			return id
	return &""

## A barrel went off. dot-props described the blast; this is what it does to people.
func _on_prop_exploded(
	at: Vector3, radius: float, damage_amount: float, force: float, by: StringName
) -> void:
	barrel_exploded.emit(at, radius)

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if player.health == null or not player.health.alive or player.riding or is_loading(player):
			continue

		var offset := player.global_position - at
		var distance := offset.length()

		if distance > radius:
			continue

		var falloff := 1.0 - (distance / radius)
		var damage := DotDamage.make(
			attacker, player.entity_id, damage_amount * falloff, null
		)
		damage.point = player.global_position
		damage.direction = offset.normalized() if distance > 0.01 else Vector3.UP
		damage.context = {"why": KILLED_BY_BARREL}
		combat.apply_damage(damage)

		# Thrown, and a barrel is the only thing in the game that throws a runner UPWARD — two metres from
		# the hammer's reach, past any jump, which is why a barrel is worth standing near as well as away
		# from. See docs/map.md, "What a runner can climb".
		var push := damage.direction * force * falloff * 0.004
		push.y = 0.0
		var state := player.controller.state
		state.velocity += push
		state.velocity.y = maxf(
			state.velocity.y, BfhReach.launch_speed(config.gravity, config.barrel_lift_height * falloff)
		)
		# [b]And off the ground, or none of that survives the tick.[/b] A velocity added to a runner the
		# motor still has as GROUND is snapped back onto the sand before it moves them — which is what
		# this did for nine days, and a barrel lifted people 7 cm.
		state.mode = DotFpsState.Mode.AIR
		state.time_since_grounded = 1000.0

## What a lethal hit was, on [member DotDamage.context] as `why`: run over, or thrown by a blast.
const KILLED_BY_BUS := &"bus"
const KILLED_BY_BARREL := &"barrel"
