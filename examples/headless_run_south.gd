extends "headless_run_lanes.gd"
## The south rim's colonnade.


## The south rim: four pillars a walk's width off the wall, from the scaffold's side (66 deg) to about
## 122 deg, 12.0 m apart.
func _test_the_south_run() -> void:
	print("the south run")

	var shipped := BfhArena.new()
	add_child(shipped)
	shipped.build(46.0)
	var row := shipped.south_run_pillars()
	var walk := INF
	var gap := INF
	for i in range(row.size()):
		walk = minf(walk, shipped.radius - Vector2(row[i].x, row[i].z).length() - BfhArena.PILLAR_RADIUS)
		if i > 0:
			gap = minf(gap, Vector2(row[i].x - row[i - 1].x, row[i].z - row[i - 1].z).length()
				- 2.0 * BfhArena.PILLAR_RADIUS)
	var room := shipped.south_run_clearance()
	var first_deg := rad_to_deg(atan2(row[0].z, row[0].x)) if row.size() > 0 else 0.0
	var last_deg := rad_to_deg(atan2(row[-1].z, row[-1].x)) if row.size() > 0 else 0.0
	var north_still := shipped.colonnade().size()
	var narrowest := shipped.narrowest_gap()
	shipped.south_run = false
	shipped.build(46.0)
	var cleared := not shipped.has_south_run() and shipped.colonnade().size() == north_still
	remove_child(shipped)
	shipped.free()
	print("  ..    %.0f to %.0f deg, the walk %.2f m, the gaps %.2f m, %.2f m to anything else (stacks, farm, scaffold, ramp, deck); LANE_THROUGH %.2f"
		% [first_deg, last_deg, walk, gap, room, BfhArena.LANE_THROUGH])
	_check(row.size() == BfhArena.SOUTH_RUN_PILLARS and absf(first_deg - 66.0) < 0.5
			and last_deg > 115.0 and last_deg < 123.0,
		"the south run is built on the shipped bowl, from 66 deg to about 122", "%d pillars" % row.size())
	_check(row.size() > 1 and walk >= BfhArena.LANE_THROUGH and gap >= BfhArena.LANE_THROUGH,
		"the walk behind it and every gap in it are lanes the autopilot drives straight down",
		"walk %.2f m, narrowest gap %.2f m" % [walk, gap])
	_check(row.size() > 0 and room >= BfhArena.LANE_THROUGH and narrowest >= BfhArena.BUS_GAP,
		"and so is the floor between it and everything else", "%.2f m, tightest gap %.2f m" % [room, narrowest])
	_check(cleared, "south_run off leaves the south rim open floor and the north run alone")

	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.SOUTH_RUN_MIN_RADIUS)
	var small_room := small.south_run_clearance()
	var small_has := small.has_south_run()
	small.build(BfhArena.SOUTH_RUN_MIN_RADIUS - 1.0)
	var below_has := small.has_south_run()
	remove_child(small)
	small.free()
	_check(small_has and small_room >= BfhArena.LANE_THROUGH,
		"and still on the smallest bowl it is built in",
		"%.2f m at %.0f m" % [small_room, BfhArena.SOUTH_RUN_MIN_RADIUS])
	_check(not below_has, "and a smaller bowl leaves it out rather than closing a door")
	await _south_run_walk()
	await _south_run_drives()
	_done()


## A runner along the south walk, from the scaffold's end to the stacks'.
func _south_run_walk() -> void:
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
	var route: Array = []
	for k in range(9):
		route.append(game.arena.south_run_walk_point(-0.15 + 1.3 * float(k) / 8.0))
	_put(runner, game.arena.south_run_walk_point(-0.25) + Vector3(0.0, 0.05, 0.0))
	await _step(game, 5)
	await _run_route(game, runner, route, 900)
	var pace := _route_report("along the south walk from the scaffold's end", runner)
	_check(_route.get("finished", false), "a runner goes the whole length of the south walk",
		"stopped at (%.1f, %.1f)" % [runner.global_position.x, runner.global_position.z])
	_check(pace >= RUN_PACE, "at a runner's pace: a covered way, not an obstacle course",
		"%.0f%% of max_speed" % (pace * 100.0))
	await _dispose(game)


## A bus comes down the south run, each drive in its own world.
func _south_run_drives() -> void:
	var probe := BfhArena.new()
	add_child(probe)
	probe.build(46.0)
	var pillars := probe.south_run_pillars()
	var drives := []
	for i in range(pillars.size() - 1):
		var middle := (pillars[i] + pillars[i + 1]) * 0.5
		var out := Vector3(middle.x, 0.0, middle.z).normalized()
		var start := middle - out * 16.0
		drives.append(["in gap %d" % i, middle, start, 0])
		drives.append(["on the walk behind gap %d" % i,
			middle + out * (BfhArena.PILLAR_RADIUS + BfhArena.COLONNADE_WALK * 0.5), start, 1])
	drives.append(["on the walk, from the scaffold's end", probe.south_run_walk_point(0.5),
		probe.south_run_walk_point(-0.4), 2])
	drives.append(["on the walk, from the stacks' end", probe.south_run_walk_point(0.5),
		probe.south_run_walk_point(1.4), 2])
	remove_child(probe)
	probe.free()

	var down := [0, 0, 0]
	var of := [0, 0, 0]
	var slowest := INF
	var missed := [PackedStringArray(), PackedStringArray(), PackedStringArray()]
	for d in drives:
		var result: Dictionary = await _colonnade_chase("south " + d[0], d[1], d[2], false)
		of[d[3]] += 1
		if result["killed"]:
			down[d[3]] += 1
		else:
			missed[d[3]].append(d[0])
		slowest = minf(slowest, result["fastest"])
	_check(down[0] == of[0], "the bot bus runs down a runner standing still in every gap of the south run",
		"missed: %s" % ", ".join(missed[0]))
	_check(down[1] == of[1], "and on the walk behind every gap", "missed: %s" % ", ".join(missed[1]))
	_check(down[2] == of[2], "and on the walk from either end of it, coming along it",
		"missed: %s" % ", ".join(missed[2]))
	_check(slowest >= BfhConfig.new().bus_lethal_speed,
		"every one of those drives gets up to a speed that kills", "slowest peak %.1f m/s" % slowest)
