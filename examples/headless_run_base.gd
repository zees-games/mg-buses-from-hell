extends DotGameCheckSuite

const BfhArena := preload("../game/bfh_arena.gd")
const BfhAudio := preload("../game/bfh_audio.gd")
const BfhAwards := preload("../game/bfh_awards.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhClient := preload("../game/bfh_client.gd")
const BfhViewmodel := preload("../game/bfh_viewmodel.gd")
const BfhClientChat := preload("../game/bfh_client_chat.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhEvents := preload("../game/net/bfh_events.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhHud := preload("../game/bfh_hud.gd")
const BfhPaths := preload("../game/bfh_paths.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhReach := preload("../game/bfh_reach.gd")
const BfhSettings := preload("../game/bfh_settings.gd")
const BfhSounds := preload("../game/bfh_sounds.gd")
const BfhSpectate := preload("../game/bfh_spectate.gd")
const BfhStats := preload("../game/bfh_stats.gd")

## Proves the bowl, the crates, the hammer, the barrels and the buses all actually work.

const CHECKS := 364

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 41

const TICK := 1.0 / 60.0

## Seconds a bot bus may stand still with its throttle off, mid-chase, before
## [method _watch_parked] calls it parked. The three-point turn passes through a standstill
## between legs, but with the throttle held.
const PARKED_LIMIT := 1.0

## Half the bus hull's length (props/bfh_bus.tscn: 2.5 x 1.8 x 5.4 m).
const BUS_HALF_LENGTH := 2.7

## The floor a drive's bus must have round it at the start, in metres, past the strip it
## sweeps. Covers the hull's corners, which a strip with round ends cuts off by 0.52 m.
const START_ROOM := 0.6

## The fraction of `max_speed` a runner bot's route has to average on flat ground or a
## walkable slope. Run-up is five ticks at these tunables, so a straight run of any length
## is within a few percent of it; the ramp reads 96%.
const RUN_PACE := 0.9

## The same for a route with jumps in it, and it is lower for a reason rather than for slack: the
## route bot stops pressing forward inside 0.2 m of each waypoint, turns to the next, and lands
## every jump with a tick of friction, so a crate from a run reads 73% and the scaffold's climbs.
const CLIMB_PACE := 0.55

var _completed := 0

## Every world this run has built and not yet taken down. See [method _dispose].
var _worlds: Array[BfhGame] = []
var _worlds_built := 0

## How the last [method _run_route] went: ticks taken, metres of ground covered, the
## length of the route as straight legs between its waypoints, and whether it finished.
## Read by [method _route_report], which prints it.
var _route := {}

## The longest a bot bus in any chase driven here sat still with its throttle off while
## its quarry was alive, and which drive it was. See [method _watch_parked].
var _parked_longest := 0.0
var _parked_where := ""
var _parked_for := 0.0


## A section reached its end. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


## A world at the shipped radius: a section runs the shipped configuration unless it says why not.
## Only the crate and barrel counts are cut down.
func _world(configure: Callable = Callable()) -> BfhGame:
	var config := BfhConfig.new()
	config.crate_count = 12
	config.barrel_count = 3
	config.round_seconds = 20.0
	config.intermission_seconds = 0.0
	config.warmup_seconds = 0.0
	config.driver_count = 1

	if configure.is_valid():
		configure.call(config)

	var game := BfhGame.new()
	game.config = config
	game.tick_rate = 60
	# [b]Off, because this file builds a dozen worlds in one process.[/b] A registry name is global and
	# the last one to register wins, so worlds that registered would take the name off each other — the
	# same shape as the two `DotRandomManager`s that laid out two different bowls from one seed.
	game.register_service = false
	# A bus wedged against a drum is contact physics sensitive enough to read that history: the
	# courtyard's east lane was "sent home at 6.22 s" after two earlier drives and "works free, reaches
	# at 3.73 s" with the stacks' second lane run first, or with nothing run first at all.
	var room := SubViewport.new()
	room.name = "World%d" % _worlds_built
	_worlds_built += 1
	room.own_world_3d = true
	room.size = Vector2i(64, 64)
	room.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(room)
	room.add_child(game)
	# Stepped by hand from here on. See the class note.
	game.set_physics_process(false)
	_worlds.append(game)
	return game


## Takes a world down NOW rather than at the end of the frame.
func _dispose(game: BfhGame) -> void:
	if game == null or not is_instance_valid(game):
		return

	_worlds.erase(game)

	var room := game.get_parent()
	if room != null:
		room.remove_child(game)

	game.free()

	# The world's own SubViewport, and with it the physics space (see `_world`).
	if room is SubViewport and room.get_parent() == self:
		remove_child(room)
		room.free()
	await get_tree().process_frame


## Whether a bus moved further in one tick than it can drive: the stuck rule's teleport.
func _sent_home(before: Vector3, after: Vector3) -> bool:
	return Vector2(after.x - before.x, after.z - before.z).length() > 3.0


## Called once a tick by every chase this file drives, with a fresh [param what] (and [param first]
## true) on its first tick.
func _watch_parked(bus: DotVehicleInstance, what: String, first: bool = false) -> void:
	if first:
		_parked_for = 0.0
	var idle := bus.command == null or absf(bus.command.throttle) < 0.05
	if idle and bus.speed() < 0.2:
		_parked_for += TICK
	else:
		_parked_for = 0.0
	if _parked_for > _parked_longest:
		_parked_longest = _parked_for
		_parked_where = what


## Prints how a bot bus's drive went: the ground it covered next to the straight line
## from its start to the finish ([param line]), the time, and its average and fastest
## speeds next to the configured top and lethal speeds.
func _print_drive(what: String, covered: float, line: float, ticks: int, fastest: float,
		config: BfhConfig) -> void:
	var seconds := float(ticks) * TICK
	print("  ..    the bot bus %s: %.1f m covered for a %.0f m straight line in %.2f s, %.2f m/s average, %.2f m/s fastest; bus_top_speed %.1f, lethal at %.1f"
		% [what, covered, line, seconds, covered / seconds if seconds > 0.0 else 0.0, fastest,
			config.bus_top_speed, config.bus_lethal_speed])


func _step(game: BfhGame, ticks: int) -> void:
	for _i in range(ticks):
		game.simulate(TICK)
		await get_tree().physics_frame


# --- The configuration

## What a bot bus is held to over [constant PACE_SECONDS] of chasing runners who stand wherever the
## scatter puts them. The floor is under every "after" with room and over the slowest "before", and
## the other bars are what separate the rest.
const PACE_SECONDS := 45.0
const PACE_FLOOR := 5.0
const PACE_SENT_HOME_AT_MOST := 1
const PACE_STALL_AT_MOST := 2.0
const REACH_M := 6.0
const REACH_GIVE_UP := 20.0
## Every map a bot bus is held to a pace on, and the bar for each.
const PACE_MAPS := [&"bfh_bowl", &"bfh_downtown", &"bfh_hill_town", &"bfh_suburb"]


const PACK_BUSES := 4
const PACK_RUNNERS := 3
const PACK_STALL_AT_MOST := 2.5


## Whether a prop scene's collision shape has [param expected] as its size.
func _prop_size_agrees(scene_path: String, expected: Vector3) -> bool:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return false
	var node := scene.instantiate()
	var size := Vector3.ZERO
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				size = (shape as BoxShape3D).size
			elif shape is CylinderShape3D:
				var cylinder := shape as CylinderShape3D
				size = Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	node.free()
	return size.is_equal_approx(expected)


## Removes every scattered prop (never the scaffold's) within [param reach] of
## [param at] in plan, and lets the removal land: for a section that sets a bus down by
## hand, which would otherwise set it down on whatever the round scattered there.
func _clear_round(game: BfhGame, at: Vector3, reach: float) -> void:
	for prop in game.props.all_props():
		if prop.instance_id in game.scaffold_ids or prop.body() == null:
			continue
		var where := prop.body().global_position
		if Vector2(where.x - at.x, where.z - at.z).length() < reach:
			game.props.remove(prop.instance_id)
	await _step(game, 2)


func _put(player: BfhPlayer, at: Vector3) -> void:
	player.global_position = at
	player.controller.state.position = at
	player.controller.state.velocity = Vector3.ZERO


## Drives a runner through [param waypoints] the way a person would: run at each one and jump when
## it is higher and close. Returns the highest the feet got.
func _run_route(game: BfhGame, player: BfhPlayer, waypoints: Array, ticks: int) -> float:
	var index := 0
	var best := player.global_position.y

	var planned := 0.0
	var from := player.controller.state.position
	for wp in waypoints:
		planned += Vector2(wp.x - from.x, wp.z - from.z).length()
		from = wp
	_route = {"ticks": 0, "covered": 0.0, "planned": planned, "finished": false}
	var last := player.controller.state.position

	for _i in range(ticks):
		var wp: Vector3 = waypoints[index]
		var state := player.controller.state
		var flat := Vector3(wp.x - state.position.x, 0.0, wp.z - state.position.z)

		if (
			state.mode == DotFpsState.Mode.GROUND
			and state.position.y > wp.y - 0.3
			and flat.length() < 0.5
		):
			if index == waypoints.size() - 1:
				_route["finished"] = true
				break
			index += 1
			continue

		var keys := DotFpsCommand.new()
		keys.yaw = rad_to_deg(atan2(-flat.x, -flat.z)) if flat.length() > 0.05 else state.yaw
		keys.move = Vector2(0.0, 1.0) if flat.length() > 0.2 else Vector2.ZERO
		# The face is about half a metre short of the waypoint; 1.9 m from it is the
		# distance a jump at running speed needs to clear a metre.
		if (
			state.mode == DotFpsState.Mode.GROUND
			and wp.y > state.position.y + 0.5
			and flat.length() < 1.9
		):
			keys.set_button(DotFpsCommand.BUTTON_JUMP, true)

		player.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		best = maxf(best, player.global_position.y)

		var now := player.controller.state.position
		_route["covered"] += Vector2(now.x - last.x, now.z - last.z).length()
		_route["ticks"] += 1
		last = now

	return best


## Prints how the last [method _run_route] went — the ground it covered next to the route's length,
## the time, and the average speed next to the runner's [code]max_speed[/code] — and returns that
## average as a fraction of it.
func _route_report(what: String, runner: BfhPlayer) -> float:
	var top := runner.controller.tunables.max_speed
	var seconds := float(_route.get("ticks", 0)) * TICK
	var covered: float = _route.get("covered", 0.0)
	var speed := covered / seconds if seconds > 0.0 else 0.0
	print("  ..    %s: %.1f m covered of a %.1f m route in %.2f s%s, %.2f m/s of a max_speed of %.2f (%.0f%%)"
		% [what, covered, _route.get("planned", 0.0), seconds,
			"" if _route.get("finished", false) else " WITHOUT FINISHING", speed, top,
			speed / top * 100.0])
	return speed / top


# --- The scaffold

## The straight [method _drive_straight] measures: west to east along z = 32, south of the stacks
## and the scaffold and nowhere near the farm.
const BUS_STRAIGHT := 40.0
