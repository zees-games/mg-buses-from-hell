extends "headless_run_stacks.gd"
## The scaffold, the back yard, the second lane and the colonnade.


## How far the scaffold crate furthest from its cell is from it, in metres.
func _scaffold_drift(game: BfhGame, cells: Array[AABB]) -> float:
	var worst := 0.0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop == null or not prop.is_alive():
			return INF
		worst = maxf(worst, prop.body().global_position.distance_to(cells[i].get_center()))
	return worst


var _sc_game: BfhGame
var _sc_driver: BfhPlayer
var _sc_runner: BfhPlayer
var _sc_cells: Array[AABB]
var _sc_footprint: AABB
var _by_game: BfhGame
var _by_driver: BfhPlayer
var _by_runner: BfhPlayer


## The height a runner can climb and a bus can take away, which is the whole level.
func _test_the_scaffold() -> void:
	print("the scaffold")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	# Somewhere else while the round lays out, so the scatter cannot drop them into it.
	_put(runner, Vector3(-30.0, 0.05, 20.0))
	game.start()
	await _step(game, 60)

	_sc_game = game
	_sc_driver = driver
	_sc_runner = runner
	_sc_cells = game.arena.scaffold_cells()
	_sc_footprint = game.arena.scaffold_footprint()

	_scaffold_stands()
	await _scaffold_climbs()
	await _scaffold_bus_brings_them_down()
	await _dispose(game)
	_done()


## The scaffold is built, settled, clear of the obstacles and free of strays.
func _scaffold_stands() -> void:
	var game := _sc_game
	var arena := game.arena
	var cells := _sc_cells
	var footprint := _sc_footprint

	_check(arena.has_scaffold() and game.scaffold_ids.size() == cells.size(),
		"the scaffold is built, one crate to a cell",
		"%d crates for %d cells" % [game.scaffold_ids.size(), cells.size()])

	var drift := 0.0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop != null:
			drift = maxf(drift, prop.body().global_position.distance_to(cells[i].get_center()))
	_check(drift < 0.1, "and every crate has settled into its cell",
		"worst %.3f m off" % drift)

	# A bus has to be able to get to the bottom step: held to the same clear floor as any
	# gap between two obstacles, measured from the footprint's edge to each surface.
	var nearest := arena.scaffold_clearance()
	_check(nearest >= BfhArena.BUS_GAP,
		"it stands clear of every pillar and tank by a bus's gap",
		"%.1f m" % nearest)

	# [b]And on the smallest bowl that has it,[/b] which nobody had asked until the back yard put two
	# drums beside it.
	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.SCAFFOLD_MIN_RADIUS)
	var squeezed := small.scaffold_clearance()
	var small_has := small.has_scaffold()
	remove_child(small)
	small.free()
	print("  ..    the scaffold's clearance: %.2f m at %.0f m, %.2f m at %.0f m"
		% [nearest, arena.radius, squeezed, BfhArena.SCAFFOLD_MIN_RADIUS])
	_check(small_has and squeezed >= BfhArena.BUS_GAP,
		"and still that far on the smallest bowl that has one",
		"%.2f m at %.0f m radius" % [squeezed, BfhArena.SCAFFOLD_MIN_RADIUS])

	var strays := 0
	for prop in game.props.all_props():
		if prop.instance_id in game.scaffold_ids:
			continue
		var at := prop.body().global_position
		if footprint.grow(0.3).has_point(Vector3(at.x, 0.5, at.z)):
			strays += 1
	_check(strays == 0, "and nothing scattered was dropped into it", "%d" % strays)



## A runner climbs it from each end, at a climber's pace, moving no crate.
func _scaffold_climbs() -> void:
	var game := _sc_game
	var runner := _sc_runner
	var arena := game.arena
	var cells := _sc_cells
	var footprint := _sc_footprint
	# --- A runner climbs it, from each end. The route is the steps' own tops, low end
	# first. The east end first, because the west climb ends where the bus section wants
	# the runner, and the east one is the one the saddle added.
	var steps := arena.scaffold_steps()
	var peak := arena.scaffold_peak()
	var top: AABB = steps[peak]
	_check(peak > 0 and peak < steps.size() - 1 and top.end.y > steps[0].end.y,
		"its peak is between two ends a runner can climb",
		"peak is step %d of %d" % [peak + 1, steps.size()])

	var east: Array = []
	for i in range(steps.size() - 1, peak - 1, -1):
		east.append(Vector3(steps[i].end.x - 0.6, steps[i].end.y, steps[i].get_center().z))
	east.append(Vector3(top.position.x + 0.6, top.end.y, top.get_center().z))

	_put(runner, Vector3(footprint.end.x + 5.0, 0.05, footprint.get_center().z))
	await _step(game, 5)
	var best_east := await _run_route(game, runner, east, 600)
	var climb_east := _route_report("the scaffold from the east end", runner)
	var on_east := game.carry.prop_under(runner.controller.state.ground_id)
	# [b]With the scaffold where it was[/b], so a way up made by shoving crates is not a climb.
	var shoved_east := _scaffold_drift(game, cells)
	_check(
		runner.global_position.y > top.end.y - 0.1
		and on_east != null and on_east.instance_id in game.scaffold_ids
		and shoved_east < 0.2,
		"a runner climbs to the top of it from the east end too, moving no crate",
		"best %.2f, feet at %.2f, top %.2f, a crate moved %.2f m"
		% [best_east, runner.global_position.y, top.end.y, shoved_east])
	_check(climb_east >= CLIMB_PACE, "at a climber's pace rather than a crawl",
		"%.0f%% of max_speed" % (climb_east * 100.0))

	var route: Array = []
	for i in range(peak + 1):
		route.append(Vector3(steps[i].position.x + 0.6, steps[i].end.y, steps[i].get_center().z))
	route.append(Vector3(top.end.x - 0.6, top.end.y, top.get_center().z))

	_put(runner, Vector3(footprint.position.x - 5.0, 0.05, footprint.get_center().z))
	await _step(game, 5)
	var best := await _run_route(game, runner, route, 600)
	var climb_west := _route_report("the scaffold from the west end", runner)
	var standing_on := game.carry.prop_under(runner.controller.state.ground_id)
	var shoved := _scaffold_drift(game, cells)
	_check(
		runner.global_position.y > top.end.y - 0.1
		and standing_on != null and standing_on.instance_id in game.scaffold_ids
		and shoved < 0.2,
		"a runner climbs to the top of it in three jumps, moving no crate",
		"best %.2f, feet at %.2f, top %.2f, a crate moved %.2f m"
		% [best, runner.global_position.y, top.end.y, shoved])
	_check(climb_west >= CLIMB_PACE, "and from the west, at a climber's pace",
		"%.0f%% of max_speed" % (climb_west * 100.0))



## A bus brings the runner down off the peak, going through the scaffold.
func _scaffold_bus_brings_them_down() -> void:
	var game := _sc_game
	var driver := _sc_driver
	var runner := _sc_runner
	var arena := game.arena
	var cells := _sc_cells
	var footprint := _sc_footprint
	var top: AABB = arena.scaffold_steps()[arena.scaffold_peak()]
	# --- And a bus brings them down. The bot, pointed at them from 24 m off the low end.
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	var toward := Vector3(1.0, 0.0, 0.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(toward),
		Vector3(footprint.position.x - 24.0, 1.4, footprint.get_center().z))
	driver.is_bot = true

	# Against the scaffold as the round laid it out. Once the scatter began keeping the start lanes
	# clear every prop in the bowl moved, a barrel landed 2.44 m off the scaffold's west end, and this
	# bus could not bring the runner down (34 of 36 crates standing): the barrel braced it.

	var standing_before := game.scaffold_standing()
	var down := false
	var took := 0
	for _i in range(600):
		# Standing still, and told so every tick: a tick with no command REPEATS the last one, which is
		# what a netcode wants of a lost packet — and the last one was "run along the top step", so the
		# first version of this watched the runner walk off the far end 0.7 s before the bus arrived and.
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1
		# Off the peak by a whole crate. [b]Not "on the sand"[/b], since the saddle: the
		# first run of it knocked the runner off the peak onto the east end's first step,
		# which is the way down the bus did not take and the reason the saddle is there.
		if not runner.health.alive or runner.global_position.y < top.end.y - BfhContent.CRATE_SIZE:
			down = true
			break
	print("  ..    %s after %.1f s, feet at %.2f" % [
		"killed" if not runner.health.alive else "off the peak", float(took) * TICK,
		runner.global_position.y])

	_check(down, "and a bus chasing them brings them down off the peak",
		"feet at %.2f, %s, %d of %d crates standing" % [
			runner.global_position.y, "alive" if runner.health.alive else "dead",
			game.scaffold_standing(), game.scaffold_ids.size()])
	# [b]Out of its cells, not broken.[/b] The first version of this asserted crates BROKEN and the bus
	# brought the runner down with every crate intact: it hit the low end at the speed the chase
	# allowed, under the 5 m/s a crate breaks at, and shoved the steps apart instead.
	var vacated := 0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop == null or not prop.is_alive() \
				or prop.body().global_position.distance_to(cells[i].get_center()) > 0.5:
			vacated += 1
	print("  ..    the bus left %d of %d crates standing and %d out of their cells"
		% [game.scaffold_standing(), standing_before, vacated])
	_check(vacated >= cells.size() / 4,
		"by going through the scaffold: a quarter of it is no longer where it stood",
		"%d of %d cells vacated" % [vacated, cells.size()])


# --- The tank farm's back yard

## The farm's second room, between the courtyard and the scaffold, and the two things it is for: a
## runner goes through it, and a bus comes into it.
func _test_the_back_yard() -> void:
	print("the tank farm's back yard")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	_put(runner, Vector3(-30.0, 0.05, 20.0))
	game.start()
	await _step(game, 60)

	# The round's concrete blocks are scattered even with no crates, and a 4-tonne block
	# on a route is a different test from this one. The scaffold's crates stay.
	for prop in game.props.all_props():
		if not prop.instance_id in game.scaffold_ids:
			game.props.remove(prop.instance_id)
	await _step(game, 2)

	_by_game = game
	_by_driver = driver
	_by_runner = runner
	_yard_is_a_room()
	var south := await _yard_runner_goes_through()
	await _yard_bus_comes_in(south)
	await _dispose(game)
	_done()


## Four lanes a bus can use, and a middle that is open floor.
func _yard_is_a_room() -> void:
	var arena := _by_game.arena
	var yard := arena.yard_middle(1)
	var lanes := arena.yard_lanes(1)
	var tightest := INF
	for lane in lanes:
		tightest = minf(tightest, lane)
	print("  ..    the yard's middle at (%.1f, %.1f); its lanes %s m, against %.2f"
		% [yard.x, yard.z, ", ".join(PackedStringArray(Array(lanes).map(func(w: float) -> String: return "%.2f" % w))),
			BfhArena.BUS_GAP])
	_check(lanes.size() == 4 and tightest >= BfhArena.BUS_GAP,
		"a bus can come into the back yard by any of its four lanes",
		"%.2f m in the tightest" % tightest)

	# A room rather than a pinch: from its middle, a bus's gap of floor to every drum.
	var farm := arena.tanks()
	var pillar_count := arena.pillars().size()
	var room := INF
	for i in range(farm.size()):
		room = minf(room, Vector2(yard.x - farm[i].x, yard.z - farm[i].z).length()
			- arena.obstacle_radius(pillar_count + i))
	_check(room >= BfhArena.BUS_GAP, "and its middle is open floor, not a pinch between drums",
		"%.2f m to the nearest drum" % room)



## From the courtyard through the yard to the scaffold's east end and up it; returns the south lane.
func _yard_runner_goes_through() -> int:
	var game := _by_game
	var runner := _by_runner
	var arena := game.arena
	var yard := arena.yard_middle(1)
	# --- A runner goes through it: from the middle of the courtyard, through the lane the
	# two rooms share, across the yard, out of its south lane to the scaffold's east end,
	# and up it. The flat half is held to a runner's pace and the climb to a climber's.
	var shared := -1
	var south := -1
	var yard_tanks: Array = BfhArena.TANK_YARDS[1]
	for i in range(yard_tanks.size()):
		var a: int = yard_tanks[i]
		var b: int = yard_tanks[(i + 1) % yard_tanks.size()]
		if BfhArena.TANK_YARDS[0].has(a) and BfhArena.TANK_YARDS[0].has(b):
			shared = i
		elif south < 0 or arena.yard_lane_middle(1, i).z > arena.yard_lane_middle(1, south).z:
			south = i
	var footprint := arena.scaffold_footprint()
	var steps := arena.scaffold_steps()
	var peak := arena.scaffold_peak()
	var top: AABB = steps[peak]
	var foot := Vector3(footprint.end.x + 4.0, 0.0, footprint.get_center().z)

	var through: Array = [
		arena.yard_lane_middle(1, shared), yard, arena.yard_lane_middle(1, south), foot,
	]
	_put(runner, arena.yard_middle(0) + Vector3(0.0, 0.05, 0.0))
	await _step(game, 5)
	await _run_route(game, runner, through, 900)
	var flat := _route_report("from the courtyard through the back yard to the scaffold", runner)
	var arrived: bool = _route.get("finished", false)
	_check(arrived, "a runner goes from the courtyard through the back yard to the scaffold",
		"stopped at (%.1f, %.1f)" % [runner.global_position.x, runner.global_position.z])
	_check(flat >= RUN_PACE, "at a runner's pace: nothing in the way",
		"%.0f%% of max_speed" % (flat * 100.0))

	var up: Array = []
	for i in range(steps.size() - 1, peak - 1, -1):
		up.append(Vector3(steps[i].end.x - 0.6, steps[i].end.y, steps[i].get_center().z))
	up.append(Vector3(top.position.x + 0.6, top.end.y, top.get_center().z))
	await _run_route(game, runner, up, 600)
	var climb := _route_report("and on up the scaffold's east end", runner)
	var on := game.carry.prop_under(runner.controller.state.ground_id)
	_check(runner.global_position.y > top.end.y - 0.1 and on != null
		and on.instance_id in game.scaffold_ids,
		"and on up to the scaffold's peak, the covered way the yard exists to make",
		"feet at %.2f, top %.2f" % [runner.global_position.y, top.end.y])
	_check(climb >= CLIMB_PACE, "at a climber's pace",
		"%.0f%% of max_speed" % (climb * 100.0))
	return south


## The autopilot comes into the yard by the south lane and runs down somebody standing in its middle.
func _yard_bus_comes_in(south: int) -> void:
	var game := _by_game
	var driver := _by_driver
	var runner := _by_runner
	var arena := game.arena
	var yard := arena.yard_middle(1)
	# --- And a bus comes into it. The autopilot, from 14 m out beyond the south lane --
	# the one that faces the scaffold, and the tightest of the four -- pointed at a runner
	# standing in the middle of the yard.
	var lane := arena.yard_lane_middle(1, south)
	var out := (lane - yard).normalized()
	var start := lane + out * 14.0
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(-out), start + Vector3(0.0, 1.4, 0.0))
	driver.is_bot = true

	var hide := yard + Vector3(0.0, 0.05, 0.0)
	_put(runner, hide)
	var last := bus.position()
	var covered := 0.0
	var fastest := 0.0
	var reset := false
	var took := 0
	for _i in range(600):
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1
		var at := bus.position()
		if _sent_home(last, at):
			reset = true
			break
		covered += Vector2(at.x - last.x, at.z - last.z).length()
		fastest = maxf(fastest, bus.speed())
		last = at
		if not runner.health.alive:
			break

	_print_drive("into the back yard", covered, start.distance_to(hide), took, fastest,
		game.config)
	_check(not reset, "a bus chasing somebody in the back yard is not sent home")
	_check(fastest >= game.config.bus_lethal_speed,
		"and gets up to a speed that kills on the way in",
		"%.1f m/s against %.1f" % [fastest, game.config.bus_lethal_speed])
	_check(not runner.health.alive, "and runs them down in the middle of it",
		"%.1f s, the bus at (%.1f, %.1f), %.1f m from them"
		% [float(took) * TICK, last.x, last.z,
			Vector2(last.x - hide.x, last.z - hide.z).length()])


## The third row and the lane it makes, and the three claims a lane is: it is a bus's width and a
## straight line for the autopilot, a runner can take it to the scaffold, and a runner who stands in
## it is run down.
func _test_the_second_lane() -> void:
	print("the stacks' second lane")

	var width := BfhArena.stack_lane_width(1)
	print("  ..    the lanes' clear floor: %.2f m and %.2f m, against LANE_THROUGH %.2f"
		% [BfhArena.stack_lane_width(0), width, BfhArena.LANE_THROUGH])
	_check(width >= BfhArena.LANE_THROUGH,
		"the second lane is wide enough for the autopilot to drive straight down",
		"%.2f m of clear floor" % width)
	_check(BfhArena.stack_lane_plugged(1),
		"and it does not run clean through either: the hook's south pillar stands across its end")

	# [b]And on the smallest bowl that has the stacks.[/b] The third row is the furthest
	# the stacks reach from the bowl's middle, and the lanes do not scale with it.
	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.STACK_MIN_RADIUS)
	var small_pillars := small.pillars()
	var small_reach := small.runner_area_radius()
	var worst := -INF
	for pillar in small_pillars:
		worst = maxf(worst, Vector2(pillar.x, pillar.z).length() + BfhArena.PILLAR_RADIUS - small_reach)
	remove_child(small)
	small.free()
	_check(small_pillars.size() == BfhArena.PILLAR_LAYOUT.size() and worst <= 0.0,
		"every pillar is on floor a runner can reach on the smallest bowl with the stacks",
		"%d pillars at %.0f m, the worst %.2f m outside" % [small_pillars.size(),
			BfhArena.STACK_MIN_RADIUS, worst])

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	_put(runner, Vector3(-20.0, 0.05, -20.0))
	game.start()
	await _step(game, 60)
	for prop in game.props.all_props():
		if not prop.instance_id in game.scaffold_ids:
			game.props.remove(prop.instance_id)
	await _step(game, 2)

	var arena := game.arena
	var lane_z: float = BfhArena.STACK_LANES[1]
	var hook_south := BfhArena.PILLAR_LAYOUT[BfhArena.HOOK_FIRST + 2]
	var footprint := arena.scaffold_footprint()
	var steps := arena.scaffold_steps()
	var peak := arena.scaffold_peak()
	var top: AABB = steps[peak]

	# --- A runner takes it: in at the west mouth, down the lane, round the hook's south
	# pillar on the open side, across to the scaffold's low west end, and up it.
	var mouth := arena.stack_point(Vector2(-12.0, lane_z))
	var through: Array = [
		arena.stack_point(Vector2(BfhArena.STACK_LANE_END, lane_z)),
		arena.stack_point(Vector2(hook_south.x, lane_z + 5.0)),
		Vector3(footprint.position.x - 5.0, 0.0, footprint.get_center().z),
	]
	_put(runner, mouth + Vector3(0.0, 0.05, 0.0))
	await _step(game, 5)
	await _run_route(game, runner, through, 900)
	var flat := _route_report("down the second lane and across to the scaffold", runner)
	_check(_route.get("finished", false),
		"a runner goes down the second lane, round the hook and across to the scaffold",
		"stopped at (%.1f, %.1f)" % [runner.global_position.x, runner.global_position.z])
	_check(flat >= RUN_PACE, "at a runner's pace: nothing in the way",
		"%.0f%% of max_speed" % (flat * 100.0))

	var up: Array = []
	for i in range(peak + 1):
		up.append(Vector3(steps[i].position.x + 0.6, steps[i].end.y, steps[i].get_center().z))
	up.append(Vector3(top.end.x - 0.6, top.end.y, top.get_center().z))
	await _run_route(game, runner, up, 600)
	var climb := _route_report("and on up the scaffold's west end", runner)
	var on := game.carry.prop_under(runner.controller.state.ground_id)
	_check(runner.global_position.y > top.end.y - 0.1 and on != null
		and on.instance_id in game.scaffold_ids,
		"and on up to the peak: the covered way from the stacks to the height",
		"feet at %.2f, top %.2f" % [runner.global_position.y, top.end.y])
	_check(climb >= CLIMB_PACE, "at a climber's pace",
		"%.0f%% of max_speed" % (climb * 100.0))

	# --- And a bus comes down it. The autopilot, 8 m outside the lane's west mouth and
	# facing along it, pointed at a runner standing still in the middle of the lane.
	var along := arena.stack_point(Vector2(1.0, 0.0)) - arena.stack_point(Vector2.ZERO)
	var start := arena.stack_point(Vector2(BfhArena.PILLAR_LAYOUT[4].x - 8.0, lane_z))
	var hide := arena.stack_point(Vector2(4.0, lane_z)) + Vector3(0.0, 0.05, 0.0)
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(along), start + Vector3(0.0, 1.4, 0.0))
	driver.is_bot = true
	_put(runner, hide)

	var last := bus.position()
	var covered := 0.0
	var fastest := 0.0
	var reset := false
	var took := 0
	for _i in range(600):
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1
		var at := bus.position()
		if _sent_home(last, at):
			reset = true
			break
		covered += Vector2(at.x - last.x, at.z - last.z).length()
		fastest = maxf(fastest, bus.speed())
		last = at
		if not runner.health.alive:
			break

	_print_drive("down the second lane", covered, start.distance_to(hide), took, fastest,
		game.config)
	_check(not reset, "a bus chasing somebody down the second lane is not sent home")
	_check(fastest >= game.config.bus_lethal_speed,
		"and gets up to a speed that kills in it",
		"%.1f m/s against %.1f" % [fastest, game.config.bus_lethal_speed])
	_check(not runner.health.alive, "and runs down a runner standing in the middle of it",
		"%.1f s, the bus at (%.1f, %.1f), %.1f m from them"
		% [float(took) * TICK, last.x, last.z,
			Vector2(last.x - hide.x, last.z - hide.z).length()])

	await _dispose(game)
	_done()



## The north-west rim: four pillars a walk's width off the wall, from the stacks' west end to the
## deck's west corner.
func _test_the_colonnade() -> void:
	print("the colonnade")

	var shipped := BfhArena.new()
	add_child(shipped)
	shipped.build(46.0)
	var row := shipped.colonnade()
	var walk := INF
	var gap := INF
	for i in range(row.size()):
		walk = minf(walk, shipped.radius - Vector2(row[i].x, row[i].z).length() - BfhArena.PILLAR_RADIUS)
		if i > 0:
			gap = minf(gap, Vector2(row[i].x - row[i - 1].x, row[i].z - row[i - 1].z).length()
				- 2.0 * BfhArena.PILLAR_RADIUS)
	var room := shipped.colonnade_clearance()
	remove_child(shipped)
	shipped.free()
	print("  ..    the walk %.2f m of clear floor to the wall, the gaps %.2f m, %.2f m to anything else (stacks, farm, ramp, deck); LANE_THROUGH %.2f"
		% [walk, gap, room, BfhArena.LANE_THROUGH])
	_check(row.size() == BfhArena.COLONNADE_PILLARS,
		"the colonnade is built on the shipped bowl", "%d pillars" % row.size())
	_check(row.size() > 1 and walk >= BfhArena.LANE_THROUGH and gap >= BfhArena.LANE_THROUGH,
		"the walk behind it and every gap in it are lanes the autopilot drives straight down",
		"walk %.2f m, narrowest gap %.2f m" % [walk, gap])
	_check(row.size() > 0 and room >= BfhArena.LANE_THROUGH,
		"and so is the floor between it and everything else", "%.2f m" % room)

	# [b]And on the smallest bowl that has it, and not on the one below.[/b] The pillars
	# keep their distance from the wall and from each other, so the arc swings in towards
	# the deck's corner and the stacks' west end as the bowl shrinks.
	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.COLONNADE_MIN_RADIUS)
	var small_room := small.colonnade_clearance()
	var small_has := small.has_colonnade()
	small.build(BfhArena.COLONNADE_MIN_RADIUS - 1.0)
	var below_has := small.has_colonnade()
	remove_child(small)
	small.free()
	_check(small_has and small_room >= BfhArena.LANE_THROUGH,
		"and still on the smallest bowl it is built in",
		"%.2f m at %.0f m" % [small_room, BfhArena.COLONNADE_MIN_RADIUS])
	_check(not below_has, "and a smaller bowl leaves it out rather than closing a door")

	# --- A runner takes it: down the stacks' first lane and out of its west mouth, onto
	# the walk past the last pillar, and along it to the deck's west corner.
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var _driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	_put(runner, Vector3(10.0, 0.05, 30.0))
	game.start()
	await _step(game, 60)
	for prop in game.props.all_props():
		if not prop.instance_id in game.scaffold_ids:
			game.props.remove(prop.instance_id)
	await _step(game, 2)

	var arena := game.arena
	var route: Array = [arena.stack_point(Vector2(-17.0, 0.0))]
	for k in range(9):
		route.append(arena.colonnade_walk_point(1.15 - 1.25 * float(k) / 8.0))
	_put(runner, arena.stack_point(Vector2(10.0, 0.0)) + Vector3(0.0, 0.05, 0.0))
	await _step(game, 5)
	await _run_route(game, runner, route, 900)
	var pace := _route_report("out of the stacks' west mouth and along the walk to the deck's corner", runner)
	_check(_route.get("finished", false),
		"a runner goes from the stacks' first lane along the whole walk to the deck's corner",
		"stopped at (%.1f, %.1f)" % [runner.global_position.x, runner.global_position.z])
	_check(pace >= RUN_PACE, "at a runner's pace: a covered way, not an obstacle course",
		"%.0f%% of max_speed" % (pace * 100.0))
	await _dispose(game)

	# --- And a bus comes down it. Each drive in its own world, because a runner run down is the end of
	# that round: the autopilot facing the runner from 16 m out on the floor, at somebody standing in a
	# gap and on the walk behind it; and from either end of the walk along it.
	var probe := BfhArena.new()
	add_child(probe)
	probe.build(46.0)
	var pillars := probe.colonnade()
	var drives := []
	for i in range(pillars.size() - 1):
		var middle := (pillars[i] + pillars[i + 1]) * 0.5
		var out := Vector3(middle.x, 0.0, middle.z).normalized()
		var start := middle - out * 16.0
		drives.append(["in gap %d" % i, middle, start, 0])
		drives.append(["on the walk behind gap %d" % i,
			middle + out * (BfhArena.PILLAR_RADIUS + BfhArena.COLONNADE_WALK * 0.5), start, 1])
	drives.append(["on the walk, from its stacks end", probe.colonnade_walk_point(0.5),
		probe.colonnade_walk_point(1.5), 2])
	drives.append(["on the walk, from its deck end", probe.colonnade_walk_point(0.8),
		probe.colonnade_walk_point(0.0), 2])
	var west_start := probe.bus_start(1, 2)
	var from_the_start: Vector3 = probe.colonnade_walk_point(0.5)
	remove_child(probe)
	probe.free()

	var down := [0, 0, 0]
	var of := [0, 0, 0]
	var slowest := INF
	var missed := [PackedStringArray(), PackedStringArray(), PackedStringArray()]
	for d in drives:
		var result: Dictionary = await _colonnade_chase(d[0], d[1], d[2], false)
		of[d[3]] += 1
		if result["killed"]:
			down[d[3]] += 1
		else:
			missed[d[3]].append(d[0])
		slowest = minf(slowest, result["fastest"])
	_check(down[0] == of[0], "the bot bus runs down a runner standing still in every gap in the row",
		"missed: %s" % ", ".join(missed[0]))
	_check(down[1] == of[1], "and on the walk behind every gap", "missed: %s" % ", ".join(missed[1]))
	_check(down[2] == of[2], "and on the walk from either end of it, coming along it",
		"missed: %s" % ", ".join(missed[2]))
	_check(slowest >= BfhConfig.new().bus_lethal_speed,
		"every one of those drives gets up to a speed that kills",
		"slowest peak %.1f m/s" % slowest)

	# Printed, not asserted: see this section's doc.
	var _from_start: Dictionary = await _colonnade_chase(
		"on the walk, from the west bus's start (not asserted)", from_the_start, west_start, true)
	_done()


## One bot bus from [param start] at a runner standing still at [param hide], facing them
## or, with [param as_spawned], the way a bus faces at the top of a round. Prints the drive
## and returns whether it killed and how fast it got.
func _colonnade_chase(what: String, hide: Vector3, start: Vector3, as_spawned: bool) -> Dictionary:
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	_put(runner, Vector3(10.0, 0.05, 30.0))
	game.start()
	await _step(game, 60)
	for prop in game.props.all_props():
		if not prop.instance_id in game.scaffold_ids:
			game.props.remove(prop.instance_id)
	await _step(game, 2)

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	var facing := Vector3(-start.x, 0.0, -start.z) if as_spawned \
		else Vector3(hide.x - start.x, 0.0, hide.z - start.z)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(facing.normalized()),
		Vector3(start.x, 1.4, start.z))
	driver.is_bot = true
	_put(runner, hide + Vector3(0.0, 0.05, 0.0))

	var last := bus.position()
	var covered := 0.0
	var fastest := 0.0
	var reset := false
	var took := 0
	for i in range(720):
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		_watch_parked(bus, "at a runner %s" % what, i == 0)
		took += 1
		var at := bus.position()
		if _sent_home(last, at):
			reset = true
			break
		covered += Vector2(at.x - last.x, at.z - last.z).length()
		fastest = maxf(fastest, bus.speed())
		last = at
		if not runner.health.alive:
			break

	var killed := not reset and not runner.health.alive
	print("  ..    %-50s %s at %.2f s, %.1f m covered, %.1f m/s fastest, bus ends (%.1f, %.1f)"
		% [what, "runs them down" if killed else ("SENT HOME" if reset else "never reaches them"),
			float(took) * TICK, covered, fastest, last.x, last.z])
	await _dispose(game)
	return {"killed": killed, "fastest": fastest}


# --- The courtyard's four lanes, driven (`[steer-3]`)
