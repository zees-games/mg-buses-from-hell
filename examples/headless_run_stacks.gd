extends "headless_run_world.gd"
## The stacks, the tank farm and the reach sections.


func _test_bot_pack() -> void:
	print("four bot buses together keep moving on every map")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			only = arg.trim_prefix("--map=")
	for id in PACE_MAPS:
		if only != "" and String(id) != only:
			continue
		var r := await _pack_drive(id, PACE_SECONDS)
		var each: float = r.covered / (PACE_SECONDS * maxf(r.buses, 1))
		print("  ..    %-14s %d buses, %.2f m/s each, %d sent home, longest stall %.1f s at %s"
			% [id, r.buses, each, r.resets, r.longest_stall, str(r.stall_at.snappedf(0.1))])
		_check(r.buses == PACK_BUSES, "%s: all %d buses are on the floor" % [id, PACK_BUSES], "%d" % r.buses)
		_check(each >= PACE_FLOOR, "%s: each of them keeps an average pace" % id, "%.2f m/s, floor %.1f" % [each, PACE_FLOOR])
		_check(r.resets <= PACE_SENT_HOME_AT_MOST * PACK_BUSES, "%s: and none is sent home more than %d time" % [id, PACE_SENT_HOME_AT_MOST],
			"sent home %d times" % r.resets)
		_check(r.longest_stall < PACK_STALL_AT_MOST, "%s: and none is stuck for %.1f s (no progress while asking for throttle)" % [id, PACK_STALL_AT_MOST],
			"%.1f s at %s" % [r.longest_stall, str(r.stall_at.snappedf(0.1))])
	_done()


func _test_bowl_layout() -> void:
	print("laying the bowl out")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	_check(game.round_number >= 1, "a round begins", "round %d" % game.round_number)
	# The scattered twelve plus the scaffold, which is crates too and counts as cover.
	var scaffold := game.arena.scaffold_cells().size()
	_check(game.crates_left() == 12 + scaffold, "the crates are laid out",
		"%d, of %d scattered and %d in the scaffold" % [game.crates_left(), 12, scaffold])
	_check(game.props.world_count() > 12,
		"with barrels and blocks beside them", "%d props" % game.props.world_count())

	# [b]Seeded, so two servers on the same seed lay the same round out.[/b] Asserted against the
	# SCATTER rather than against where the crates ended up, and the first version of this check did
	# the latter: it built a second world, stepped it, and compared prop positions.
	var left := DotRandomStream.new(4242, &"bowl")
	var right := DotRandomStream.new(4242, &"bowl")
	var drifted := DotRandomStream.new(4243, &"bowl")

	var same := true
	var differs := false
	for _i in range(24):
		var a := game.arena.scatter_point(left, 8.0, 0.6)
		var b := game.arena.scatter_point(right, 8.0, 0.6)
		var c := game.arena.scatter_point(drifted, 8.0, 0.6)
		if a != b:
			same = false
		if a != c:
			differs = true

	_check(same, "and the same seed lays out the same bowl")
	_check(differs, "while a different one does not")

	var first: Array[Vector3] = []
	for prop in game.props.all_props():
		first.append(prop.position())

	var inside := true
	for at in first:
		if Vector2(at.x, at.z).length() > game.arena.radius:
			inside = false
			break
	_check(inside, "every one of them inside the wall")

	# The lanes in front of the bus starts are kept clear (`scatter_clears_bus_lanes`): none
	# of what the round laid out, and none of a large sample. And the same sample with the
	# lanes off does land in one, so the first two cannot pass by the lanes being nowhere.
	var lanes := game.arena.start_lanes.size()
	var in_lane := 0
	for prop in game.props.all_props():
		if not game.scaffold_ids.has(prop.instance_id) and game.arena._inside_a_start_lane(prop.position().x, prop.position().z, 0.0):
			in_lane += 1
	_check(lanes == maxi(game.config.driver_count, 1) and in_lane == 0,
		"nothing scattered lies in the lane in front of a bus start", "%d lanes, %d props in one" % [lanes, in_lane])
	var kept := DotRandomStream.new(777, &"bowl")
	var sampled_in := 0
	for _i in range(400):
		var at := game.arena.scatter_point(kept, 12.0, 0.5)
		if game.arena._inside_a_start_lane(at.x, at.z, 0.0):
			sampled_in += 1
	_check(sampled_in == 0, "and 400 more scatter points avoid it", "%d in a lane" % sampled_in)
	var saved_lanes := game.arena.start_lanes.duplicate()
	game.arena.start_lanes.clear()
	var loose := DotRandomStream.new(777, &"bowl")
	var would := 0
	for _i in range(400):
		var at := game.arena.scatter_point(loose, 12.0, 0.5)
		for lane in saved_lanes:
			if absf(at.x - lane.x) < lane.z and absf(at.z - lane.y) < lane.w:
				would += 1
				break
	game.arena.start_lanes = saved_lanes
	_check(would > 0, "while with the lanes off the same scatter does fall in them", "%d of 400" % would)

	# The scaffold's margin: nothing scattered within `scaffold_scatter_margin` of its footprint,
	# because a prop beside it braces it against a bus (see the scaffold section).
	var margin: float = game.config.scaffold_scatter_margin
	var footprint := game.arena.scaffold_footprint()
	var nearest := INF
	for prop in game.props.all_props():
		if game.scaffold_ids.has(prop.instance_id):
			continue
		var p := prop.position()
		var dx := maxf(maxf(footprint.position.x - p.x, p.x - footprint.end.x), 0.0)
		var dz := maxf(maxf(footprint.position.z - p.z, p.z - footprint.end.z), 0.0)
		nearest = minf(nearest, Vector2(dx, dz).length())
	_check(footprint.size == Vector3.ZERO or nearest >= margin,
		"nothing scattered lies within %.1f m of the scaffold" % margin, "nearest %.2f m" % nearest)
	var near_scaffold := func(stream: DotRandomStream) -> int:
		var n := 0
		for _i in range(400):
			var at := game.arena.scatter_point(stream, 12.0, 0.5)
			var dx := maxf(maxf(footprint.position.x - at.x, at.x - footprint.end.x), 0.0)
			var dz := maxf(maxf(footprint.position.z - at.z, at.z - footprint.end.z), 0.0)
			if Vector2(dx, dz).length() < margin:
				n += 1
		return n
	var kept_out: int = near_scaffold.call(DotRandomStream.new(778, &"bowl"))
	var saved_margin: float = game.arena.scaffold_keep_out
	game.arena.scaffold_keep_out = 0.0
	var without: int = near_scaffold.call(DotRandomStream.new(778, &"bowl"))
	game.arena.scaffold_keep_out = saved_margin
	_check(footprint.size == Vector3.ZERO or (kept_out == 0 and without > 0),
		"and 400 more scatter points keep the margin, where the obstacles' 2.2 m alone does not",
		"%d inside with the margin, %d with 2.2 m" % [kept_out, without])

	await _dispose(game)
	_done()


## The stacks, which are the only permanent geometry on the floor.
func _test_the_stacks() -> void:
	print("the stacks")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var pillars := arena.pillars()

	_check(
		pillars.size() == BfhArena.PILLAR_LAYOUT.size(),
		"the stacks stand in the bowl",
		"%d pillars" % pillars.size()
	)

	# Inside the floor a runner is allowed on, or a pillar is cover nobody can use --
	# and one overlapping the wall is a collider pair grinding against each other for
	# the lifetime of the server.
	var reach := arena.runner_area_radius()
	var outside := 0
	for pillar in pillars:
		if Vector2(pillar.x, pillar.z).length() + BfhArena.PILLAR_RADIUS > reach:
			outside += 1
	_check(outside == 0, "every one of them is on floor a runner can reach",
		"%d outside %.0f m" % [outside, reach])

	# The ramp is the only route between the ledge and the floor. A pillar at the
	# bottom of it is a map with no way down, which no assertion elsewhere would notice
	# because the bus would simply be found stationary and blamed on the suspension.
	var foot := arena.ramp_foot()
	var nearest_to_foot := INF
	for pillar in pillars:
		nearest_to_foot = minf(
			nearest_to_foot, Vector2(pillar.x - foot.x, pillar.z - foot.z).length()
		)
	_check(nearest_to_foot > 8.0, "and none of them is on the ramp's landing",
		"nearest %.1f m" % nearest_to_foot)

	# The lane, asserted off the layout rather than off the built world, because the
	# layout is the thing somebody edits.
	var lane_half := INF
	for local in BfhArena.PILLAR_LAYOUT:
		if local.x < 14.0:
			lane_half = minf(lane_half, absf(local.y))
	_check(
		lane_half - BfhArena.PILLAR_RADIUS >= 3.0,
		"the lane between the rows is wide enough for a bus",
		"%.1f m of clear floor either side of the centre" % (lane_half - BfhArena.PILLAR_RADIUS)
	)

	# [b]And the same question of the WHOLE layout, which the check above cannot ask.[/b] That one
	# filters on `local.x < 14.0` -- it is about the two rows, it was written when the two rows were
	# all there was, and it goes on passing about them however many pillars are added past the dog-leg.
	var tightest := BfhArena.narrowest_pillar_gap()
	_check(
		tightest >= BfhArena.PILLAR_CLEARANCE * 2.0,
		"and no pair anywhere in the stacks is too tight for a bus to pass between",
		"%.2f m between the closest two, against the %.2f a bus needs"
			% [tightest, BfhArena.PILLAR_CLEARANCE * 2.0]
	)

	# And the half of the design that makes the lane a decision rather than a gift.
	var plugged := false
	for local in BfhArena.PILLAR_LAYOUT:
		if local.x >= 14.0 and absf(local.y) < lane_half:
			plugged = true
	_check(plugged, "and it does not run clean through")

	# Nothing shares a volume with a pillar. Two solid bodies in one place is resolved
	# by the physics flinging the lighter one across the bowl on the first step, and
	# with a runner in it that is a camera going with it.
	var intruders := 0
	for prop in game.props.all_props():
		if prop.body() == null:
			continue
		var at := prop.body().global_position
		for pillar in pillars:
			if Vector2(at.x - pillar.x, at.z - pillar.z).length() < BfhArena.PILLAR_RADIUS:
				intruders += 1
	for player in game.runners():
		for pillar in pillars:
			var offset := player.global_position - pillar
			if Vector2(offset.x, offset.z).length() < BfhArena.PILLAR_RADIUS:
				intruders += 1
	_check(intruders == 0, "and the round is laid out around them, not into them",
		"%d overlapping" % intruders)

	# --- The steering
	var pillar := pillars[5]
	var approach := pillar + Vector3(0.0, 0.0, -24.0)
	var beyond := pillar + Vector3(0.0, 0.0, 12.0)

	var steered := arena.steer_around(approach, beyond)
	var miss := Vector2(steered.x - pillar.x, steered.z - pillar.z).length()
	_check(
		miss >= BfhArena.PILLAR_RADIUS + 1.0,
		"a line through a pillar is steered off it",
		"aim point %.1f m from the axis" % miss
	)

	# The other half, and the one that would be missed: a driver whose way is clear
	# must be left alone, or every chase in the bowl is a bus weaving at nothing.
	var clear_from := Vector3(0.0, 1.0, -reach + 2.0)
	var clear_to := Vector3(0.0, 1.0, -reach + 20.0)
	_check(
		arena.steer_around(clear_from, clear_to) == clear_to,
		"and a clear line is left exactly as it was"
	)

	await _dispose(game)
	await _test_driving_the_stacks()
	_done()


## The check the rest of this section cannot make: a bot bus actually gets past one.
func _test_driving_the_stacks() -> void:
	var game := _world(func(config: BfhConfig) -> void:
		# Long enough that the round cannot end underneath the measurement.
		config.round_seconds = 120.0
	)

	# [b]`is_bot`, and nothing else in this file sets it.[/b] `add_player` leaves it false, so every
	# other section's driver is a person who never presses anything -- which is why the bus in them
	# only ever moves when a check drives it by hand, and why `_autopilot` had no coverage at all.
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	driver.is_bot = true
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)


	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	_stacks_bot_difficulty(game, bus)
	var quarry := game.runners()[0]
	await _stacks_round_the_pillar(game, bus, quarry)
	await _stacks_through_the_hook(game, bus, quarry)
	await _dispose(game)


## How far ahead of a running target a bot bus aims, by difficulty.
func _stacks_bot_difficulty(game: BfhGame, bus: DotVehicleInstance) -> void:
	# bot_difficulty at the wheel: how far ahead of a running target a bus aims, relative to
	# medium (which aims where this game always did) -- ahead of the run at nightmare, behind
	# it at easy -- and how fast it drives.
	var running: BfhPlayer = null
	for p in game.runners():
		running = p
	if running != null and running.controller != null:
		running.controller.state.velocity = Vector3(6.0, 0.0, 0.0)
	var leads := {}
	for preset in ["easy", "medium", "nightmare"]:
		var s := DotBotSettings.new()
		var _p := s.set_difficulty(preset)
		leads[preset] = game._bot_lead(bus, running, s.profile).x if running != null else NAN
	_check(is_zero_approx(float(leads["medium"])) and float(leads["nightmare"]) > 0.0 and float(leads["easy"]) < 0.0,
		"a bot bus leads a runner at nightmare, trails one at easy, and aims as before at medium", str(leads))
	_check(DotBotSettings.of(game).difficulty() == "medium", "and the world's bots are medium unless told otherwise")
	if running != null and running.controller != null:
		running.controller.state.velocity = Vector3.ZERO


## A bus lined up on a pillar with the quarry behind it comes round at a speed that kills.
func _stacks_round_the_pillar(game: BfhGame, bus: DotVehicleInstance, quarry: BfhPlayer) -> void:
	var arena := game.arena
	var pillar := arena.pillars()[5]
	var body := bus.body()
	# Lined up on the pillar with the quarry directly behind it, which is the geometry
	# a runner using one for cover creates and the one the bot has no answer to.
	var start := pillar + Vector3(0.0, 1.4, -26.0)
	# Nothing the round scattered under the spot the bus is set down on: on seed 7 a crate
	# lay 0.7 m from it, and the drive began with the bus climbing off it.
	await _clear_round(game, start, 7.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.0, 1.0)), start)

	# [b]Put, not moved: `_put` writes the controller's state as well as the node.[/b] This set
	# `global_position` alone, which the runner's next tick overwrites from its state, so the quarry
	# was never behind the pillar at all: the bot chased wherever the round had scattered the runner.
	_put(quarry, pillar + Vector3(0.0, 1.2, 14.0))

	var last := bus.position()
	var reset := false
	var past := false
	var top_speed := 0.0
	var covered := 0.0
	var took := 0

	for _i in range(300):
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1

		if not bus.is_alive():
			break

		var at := bus.position()
		top_speed = maxf(top_speed, bus.speed())
		if not _sent_home(last, at):
			covered += Vector2(at.x - last.x, at.z - last.z).length()

		# Held in place, because the quarry is being pushed around by the round and the
		# bus's own start line is a long way from here: a bus back on it has been reset.
		_put(quarry, pillar + Vector3(0.0, 1.2, 14.0))

		if _sent_home(last, at):
			reset = true
			break

		last = at

		if at.z > pillar.z + 1.0:
			past = true
			break

	_print_drive("round the pillar", covered, 27.0, took, top_speed, game.config)
	_check(not reset, "a bus chasing somebody behind a pillar is not sent home")
	# [b]Past the speed that kills, not "moving at all".[/b] This asked for 4 m/s, which
	# is under half of `bus_lethal_speed`: a bus crawling round a pillar at a speed that
	# cannot hurt the runner behind it passed. Measured, 16.7 m/s.
	_check(top_speed > game.config.bus_lethal_speed, "it gets up to a speed that kills on the way",
		"%.1f m/s against %.1f" % [top_speed, game.config.bus_lethal_speed])
	_check(past, "and it comes round the pillar rather than wedging on it",
		"%.1f m/s at the end" % bus.speed() if bus.is_alive() else "the bus was lost")



## The same drive through the hook's pillars.
func _stacks_through_the_hook(game: BfhGame, bus: DotVehicleInstance, quarry: BfhPlayer) -> void:
	var arena := game.arena
	var body := bus.body()
	# --- Through the hook
	var hook := arena.pillars()[BfhArena.HOOK_FIRST]
	await _clear_round(game, hook + Vector3(0.0, 1.4, -26.0), 7.0)

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, 1.0)), hook + Vector3(0.0, 1.4, -26.0)
	)
	_put(quarry, hook + Vector3(0.0, 1.2, 14.0))

	var through := false
	var hook_reset := false
	var hook_last := bus.position()
	var hook_fastest := 0.0
	var hook_covered := 0.0
	var hook_took := 0

	for _i in range(360):
		game.simulate(TICK)
		await get_tree().physics_frame
		hook_took += 1

		if not bus.is_alive():
			break

		_put(quarry, hook + Vector3(0.0, 1.2, 14.0))
		var here := bus.position()
		hook_fastest = maxf(hook_fastest, bus.speed())
		if not _sent_home(hook_last, here):
			hook_covered += Vector2(here.x - hook_last.x, here.z - hook_last.z).length()

		if _sent_home(hook_last, here):
			hook_reset = true
			break

		hook_last = here

		if here.z > hook.z + 1.0:
			through = true
			break

	_print_drive("round the hook", hook_covered, 27.0, hook_took, hook_fastest, game.config)
	_check(not hook_reset, "a bus in the hook is not sent home either")
	_check(hook_fastest > game.config.bus_lethal_speed, "and gets up to a speed that kills there too",
		"%.1f m/s against %.1f" % [hook_fastest, game.config.bus_lethal_speed])
	_check(
		through,
		"and it comes round the hook's pillars rather than wedging between two of them",
		"%.1f m/s at the end" % bus.speed() if bus.is_alive() else "the bus was lost"
	)


## The tank farm, which is the east half of the bowl and a different question from the stacks.
func _test_the_tank_farm() -> void:
	print("the tank farm")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var farm := arena.tanks()

	_check(
		farm.size() == BfhArena.TANK_LAYOUT.size(),
		"the tanks stand in the bowl",
		"%d tanks" % farm.size()
	)

	# Each of them on floor a runner can reach, measured to the SURFACE. A tank is 4 m
	# of radius and the pillar version of this check -- axis distance plus a constant --
	# would clear a drum overlapping the wall by three metres.
	var reach := arena.runner_area_radius()
	var outside := 0
	var nearest_to_ramp := INF
	var foot := arena.ramp_foot()
	for i in range(farm.size()):
		var at := farm[i]
		var tank_radius := arena.obstacle_radius(arena.pillars().size() + i)
		if Vector2(at.x, at.z).length() + tank_radius > reach:
			outside += 1
		nearest_to_ramp = minf(
			nearest_to_ramp,
			Vector2(at.x - foot.x, at.z - foot.z).length() - tank_radius
		)
	_check(outside == 0, "every one of them on floor a runner can reach",
		"%d outside %.0f m" % [outside, reach])
	_check(nearest_to_ramp > 8.0, "and none of them across the ramp's landing",
		"nearest surface %.1f m" % nearest_to_ramp)

	# [b]The courtyard, and the reason it is the point of the farm.[/b] Four tanks in a diamond leave
	# open floor in the middle, and open floor surrounded by cover is only a place worth standing if
	# the thing chasing you can come into it.
	var pillar_count := arena.pillars().size()
	var tightest_lane := INF
	for lane in arena.yard_lanes(0):
		tightest_lane = minf(tightest_lane, lane)
	_check(
		tightest_lane >= BfhArena.BUS_GAP,
		"and a bus can come into the courtyard by any of its four lanes",
		"%.2f m of floor in the tightest, against the %.2f a bus needs"
			% [tightest_lane, BfhArena.BUS_GAP]
	)

	# The whole map, both features at once, face to face. This is the question
	# `narrowest_pillar_gap` cannot ask: it is static and stack-local, so it knows
	# nothing about a tank and nothing about how close the two clusters are.
	var tightest := arena.narrowest_gap()
	_check(
		tightest >= BfhArena.BUS_GAP,
		"no two obstacles anywhere on the map are closer than a bus can pass",
		"%.2f m between the closest two, against the %.2f a bus needs"
			% [tightest, BfhArena.BUS_GAP]
	)

	# [b]And the same question at the smallest bowl that has both features, which is the one nobody
	# would think to ask.[/b] Both clusters are positioned as a fraction of the radius, so shrinking
	# the bowl walks them towards each other while the width a bus needs stays 4.8 m of absolute floor.
	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.TANK_MIN_RADIUS)
	var squeezed := small.narrowest_gap()
	var small_tanks := small.tanks().size()
	remove_child(small)
	small.free()

	_check(
		small_tanks == BfhArena.TANK_LAYOUT.size() and squeezed >= BfhArena.BUS_GAP,
		"and they are still that far apart on the smallest bowl that has both features",
		"%.2f m at %.0f m radius, %d tanks"
			% [squeezed, BfhArena.TANK_MIN_RADIUS, small_tanks]
	)

	# Nothing is dropped inside a drum.
	var intruders := 0
	for prop in game.props.all_props():
		if prop.body() == null:
			continue
		var at := prop.body().global_position
		for i in range(farm.size()):
			var tank_radius := arena.obstacle_radius(pillar_count + i)
			if Vector2(at.x - farm[i].x, at.z - farm[i].z).length() < tank_radius:
				intruders += 1
	_check(intruders == 0, "and the round is laid out around the tanks, not into them",
		"%d overlapping" % intruders)

	# --- The steering, at a radius the constant does not cover
	var big := farm[0]
	var big_radius := arena.obstacle_radius(pillar_count)
	var steered := arena.steer_around(
		big + Vector3(0.0, 0.0, -30.0), big + Vector3(0.0, 0.0, 16.0)
	)
	var miss := Vector2(steered.x - big.x, steered.z - big.z).length()
	_check(
		miss >= big_radius + 1.5,
		"a line through a tank is steered off it by more than the tank is wide",
		"aim point %.1f m from the axis of a %.1f m drum" % [miss, big_radius]
	)

	await _dispose(game)
	await _test_driving_the_farm()
	_done()


## The check the rest of that section cannot make: a bot bus gets round a drum.
func _test_driving_the_farm() -> void:
	var game := _world(func(config: BfhConfig) -> void:
		config.round_seconds = 120.0
	)

	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	driver.is_bot = true
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)


	var arena := game.arena
	var tank := arena.tanks()[0]

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()

	# Lined up on the drum with the quarry hidden directly behind it: the geometry a
	# runner using it for cover creates, and the one the bot has to solve blind.
	await _clear_round(game, tank + Vector3(0.0, 1.4, -30.0), 7.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, 1.0)), tank + Vector3(0.0, 1.4, -30.0)
	)

	var quarry := game.runners()[0]
	var hide := tank + Vector3(0.0, 1.2, 16.0)
	# `_put`, for the reason `_test_driving_the_stacks` gives: moving the node alone left
	# the runner where the round scattered them.
	_put(quarry, hide)

	var last := bus.position()
	var reset := false
	var past := false
	var top_speed := 0.0

	var covered := 0.0
	var took := 0

	for _i in range(420):
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1

		if not bus.is_alive():
			break

		_put(quarry, hide)
		var at := bus.position()
		top_speed = maxf(top_speed, bus.speed())
		if not _sent_home(last, at):
			covered += Vector2(at.x - last.x, at.z - last.z).length()

		if _sent_home(last, at):
			reset = true
			break

		last = at

		if at.z > tank.z + 1.0:
			past = true
			break

	_print_drive("round the drum", covered, 31.0, took, top_speed, game.config)
	_check(not reset, "a bus chasing somebody behind a tank is not sent home")
	_check(top_speed > game.config.bus_lethal_speed, "and gets up to a speed that kills on the way",
		"%.1f m/s against %.1f" % [top_speed, game.config.bus_lethal_speed])
	_check(
		past,
		"and it comes round the drum rather than wedging on it",
		"%.1f m/s top, %.1f m/s at the end"
			% [top_speed, bus.speed() if bus.is_alive() else 0.0]
	)

	await _dispose(game)


# --- What a runner can climb

## Every way up the bowl, measured against what a runner can actually do, and then done.
func _test_reach() -> void:
	print("what a runner can climb")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var t := runner.controller.tunables
	var arena := game.arena

	# The map's props are measured off constants, so the constants are held to the scenes.
	_check(
		_prop_size_agrees(BfhContent.CRATE_SCENE, Vector3.ONE * BfhContent.CRATE_SIZE)
		and _prop_size_agrees(BfhContent.BARREL_SCENE, Vector3(
			BfhContent.BARREL_RADIUS * 2.0, BfhContent.BARREL_HEIGHT, BfhContent.BARREL_RADIUS * 2.0)),
		"the sizes the climbs are measured with are the props' own colliders"
	)

	print("  ..    a jump peaks at %.2f m; climb limit %.2f m; reach %.2f m flat, %.2f m onto 1 m"
		% [t.jump_height, BfhReach.climb_limit(t), BfhReach.jump_reach(t, 0.0),
			BfhReach.jump_reach(t, 1.0)])

	var climbs := arena.climbs(game.config)
	var refused := PackedStringArray()
	for climb in climbs:
		var why := BfhReach.refusal(climb, t)
		print("  ..    %s%s" % [climb.describe(), "  <- " + why if why != "" else ""])
		if why != "":
			refused.append("%s: %s" % [climb.name, why])

	_check(climbs.size() >= 9, "the map declares its climbs", "%d" % climbs.size())
	_check(refused.is_empty(), "and every one is inside what a runner can do",
		"; ".join(refused))

	# [b]The regression guard for the backwards ramp, on the BUILT map.[/b] Every constant
	# that places the ramp was right for nine days; what was wrong was the sign of one
	# rotation, and the only place that shows is the surface itself.
	var foot := arena.ramp_surface_at(0.0, arena.ramp_foot().z)
	var top := arena.ramp_surface_at(0.0, -(arena.radius - BfhArena.LEDGE_DEPTH))
	_check(top - foot > BfhArena.LEDGE_HEIGHT,
		"the ramp rises from the sand to the deck, not away from it",
		"%.2f at the foot, %.2f at the deck" % [foot, top])

	# --- Onto a crate, from a run.
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.55, 12.0))
	await _step(game, 20)
	_put(runner, Vector3(0.0, 0.05, 18.0))
	await _step(game, 5)
	await _run_route(game, runner, [Vector3(0.0, 1.0, 12.0)], 150)
	var onto_crate := _route_report("onto a crate from a run", runner)
	_check(game.carry.prop_under(runner.controller.state.ground_id) == crate,
		"a runner jumps onto a crate from a run",
		"feet at %.2f" % runner.global_position.y)
	# A climb, not a sprint: see CLIMB_PACE. Measured, 73%.
	_check(onto_crate >= CLIMB_PACE, "at running pace rather than a crawl",
		"%.0f%% of max_speed" % (onto_crate * 100.0))
	game.props.remove(crate.instance_id)

	# --- Up the ramp, on the stock motor. The fix is in the addon now and the stand-in is gone.
	var start := arena.ramp_foot() + Vector3(0.0, -0.45, 6.0)
	# The middle of the deck, well past the lip, so the route's "jump when the next
	# surface is higher and close" never fires at the lip itself: a ramp is walked.
	var deck := arena.ledge_centre()
	_put(runner, start)
	await _step(game, 5)
	var walked := await _run_route(game, runner, [Vector3(0.0, arena.deck_top(), deck.z)], 480)
	var up_ramp := _route_report("up the ramp onto the ledge", runner)
	_check(runner.global_position.y > arena.deck_top() - 0.1,
		"a runner walks up the ramp onto the ledge",
		"best %.2f, feet at %.2f, deck %.2f" % [walked, runner.global_position.y, arena.deck_top()])
	# A walk, so held to the walking floor. Measured, 96%: the 18-degree slope costs the
	# horizontal speed its cosine and nothing else.
	_check(up_ramp >= RUN_PACE, "at running pace, the whole way up",
		"%.0f%% of max_speed" % (up_ramp * 100.0))

	await _dispose(game)

	# --- Thrown onto a stack of two by a barrel set off from the hammer's reach.
	await _test_the_throw()
	_done()


## A barrel throws a runner onto two crates, which nothing else does.
func _test_the_throw() -> void:
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var at := Vector3(-20.0, 0.0, 26.0)
	var barrel := game.props.spawn(BfhContent.BARREL, &"world",
		at + Vector3(0.0, BfhContent.BARREL_HEIGHT * 0.5 + 0.05, 0.0))
	var stand := game.config.hammer_reach + BfhContent.BARREL_RADIUS
	# [b]No stack beside them, and that is a finding.[/b] The same blast shoves every loose prop in its
	# radius: measured, a stack of two 4 m from the barrel came apart before the runner came down — the
	# bottom crate 2.5 m along, the top one 6.4 m — while the runner's arc passed over.
	await _step(game, 30)

	_put(runner, at + Vector3(stand, 0.05, 0.0))
	runner.health.health = game.config.runner_health
	await _step(game, 10)

	var before := runner.global_position.y
	game.prop_damage.break_now(barrel.instance_id, &"r")
	var apex := before
	for _i in range(90):
		var keys := DotFpsCommand.new()
		keys.yaw = -90.0
		keys.move = Vector2(0.0, 1.0)
		runner.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		apex = maxf(apex, runner.global_position.y)

	_check(apex - before > 2.0,
		"a barrel set off from the hammer's reach throws a runner higher than a stack of two",
		"%.2f m" % (apex - before))
	_check(runner.health.alive,
		"and survive it, from there",
		"%.0f of %.0f health left" % [runner.health.health, game.config.runner_health])

	await _dispose(game)
