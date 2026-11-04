extends "headless_run_lanes.gd"
## The courtyard lanes, the deck, the hook gaps, and the hammer and barrel sections.


## Which lanes into the courtyard the bot bus can come through, driven rather than computed, and the
## answer held as a property of the map.
func _test_the_courtyard_lanes() -> void:
	print("the courtyard's four lanes, driven")

	var probe := _world()
	probe.start()
	await _step(probe, 2)
	var lanes := probe.arena.yard_lanes(0)
	var refuges := probe.arena.yard_refuges(0)
	var ways_in := 0
	var every_room_has_a_way_in := true
	for yard in range(BfhArena.TANK_YARDS.size()):
		var open := 0
		for w in probe.arena.yard_lanes(yard):
			if w >= BfhArena.LANE_THROUGH:
				open += 1
		every_room_has_a_way_in = every_room_has_a_way_in and open > 0
		if yard == 0:
			ways_in = open
	var mouths: Array[Vector3] = []
	var middle := probe.arena.yard_middle(0)
	# Whether the steering's own straight-line test is clear from each drive's start to the
	# point the bot aims at past the middle: the lane AND the floor beyond the middle.
	var straight: Array[bool] = []
	for i in range(lanes.size()):
		var mouth := probe.arena.yard_lane_middle(0, i)
		mouths.append(mouth)
		var out := mouth - middle
		out.y = 0.0
		var from := mouth + out.normalized() * 8.0
		var aim := middle - out.normalized() * BfhConfig.new().bot_aim_past
		straight.append(probe.arena.steer_around(from, aim).distance_to(aim) < 0.01)
	await _dispose(probe)

	var through: Array[Dictionary] = []
	var standing: Array[Dictionary] = []
	for i in range(lanes.size()):
		through.append(await _drive_a_lane(i, 8.0))
		standing.append(await _drive_a_lane(i, 8.0, true))

	print("  ..    lane  side   width   | runner in the middle                         | runner in the lane")
	for i in range(lanes.size()):
		var side := mouths[i] - middle
		var compass := (
			("east" if side.x > 0.0 else "west") if absf(side.x) > absf(side.z)
			else ("south" if side.z > 0.0 else "north")
		)
		var a: Dictionary = through[i]
		var b: Dictionary = standing[i]
		print("  ..    %d     %-5s  %.2f m  | %-9s %4.1f m/s peak %5.2f s %-12s | %-9s %4.1f m/s peak %5.2f s"
			% [i, compass, lanes[i], a.outcome, a.peak, a.seconds,
				"(wedged %.1f)" % a.wedged if a.wedged >= 0.0 else "",
				b.outcome, b.peak, b.seconds])

	# With the west lane widened to 7.6 m the line through it crosses the east drum's ring 8 m past the
	# middle (5.2 m off its axis against 6.6), and the bus wedges in the lane from 7 to 12 m out: a
	# runner in the middle is reached by the other three lanes, not that one.
	var clear_lanes := 0
	for i in range(lanes.size()):
		var a: Dictionary = through[i]
		if not straight[i]:
			print("  ..    lane %d (%.2f m): the steering's straight line to the middle is blocked; %s, wedged %.1f s (printed)"
				% [i, lanes[i], a.outcome, a.wedged])
			continue
		clear_lanes += 1
		_check(a.outcome == "reaches" and a.wedged < 0.0 and lanes[i] >= BfhArena.LANE_THROUGH,
			"lane %d (%.2f m): a straight line to the middle, and the bot bus comes straight through"
				% [i, lanes[i]],
			"%s, %.1f m/s peak, %.2f s, wedged %.1f s, nearest %.1f m"
				% [a.outcome, a.peak, a.seconds, a.wedged, a.nearest])
	_check(clear_lanes == 2,
		"and the courtyard has two such lanes, north and south",
		"%d of %d" % [clear_lanes, lanes.size()])

	var cfg := BfhConfig.new()
	var slow_through := 0
	for i in range(lanes.size()):
		var a: Dictionary = through[i]
		if lanes[i] >= BfhArena.LANE_THROUGH and a.outcome == "reaches" \
				and a.peak < cfg.bus_lethal_speed:
			slow_through += 1
	_check(slow_through == 0, "and through a wide lane it arrives at a speed that kills",
		"%d below %.1f m/s" % [slow_through, cfg.bus_lethal_speed])

	# It is 7.6 m now, past LANE_THROUGH, so this asks every lane with no list of known refuges in it.
	var safe_detail := PackedStringArray()
	for i in range(lanes.size()):
		var b: Dictionary = standing[i]
		if b.outcome != "reaches":
			safe_detail.append("%d (%s, nearest %.1f m)" % [i, b.outcome, b.nearest])
	_check(safe_detail.is_empty(),
		"nobody standing in a lane is safe there, narrow or wide",
		"safe in lane %s" % ", ".join(safe_detail))

	# And the west lane from every start the finding was made from, not only the 8 m the
	# table drives: 7 to 12 m out, a runner standing still in its mouth.
	var west := 3
	var west_safe := PackedStringArray()
	for out_by: float in [7.0, 9.5, 12.0]:
		var r := await _drive_a_lane(west, out_by, true)
		print("  ..    west lane, runner in it, %4.1f m out: %-9s %4.1f m/s peak %5.2f s nearest %4.1f"
			% [out_by, r.outcome, r.peak, r.seconds, r.nearest])
		if r.outcome != "reaches":
			west_safe.append("%.1f m: %s, nearest %.1f m" % [out_by, r.outcome, r.nearest])
	_check(lanes[west] >= BfhArena.LANE_THROUGH and west_safe.is_empty(),
		"the west lane is a way in, and a runner standing in it is run down from 7, 9.5 and 12 m out",
		"%.2f m wide; safe from %s" % [lanes[west], ", ".join(west_safe)])

	# Printed, not asserted; see docs/map.md, "The tank farm".
	for out_by: float in [8.1, 10.0]:
		var r := await _drive_a_lane(1, out_by, true)
		print("  ..    east lane, runner in it, %4.1f m out: %-9s %4.1f m/s peak %5.2f s nearest %4.1f"
			% [out_by, r.outcome, r.peak, r.seconds, r.nearest])

	_check(every_room_has_a_way_in,
		"every room in the farm keeps a lane the bot bus can come in by")
	_check(refuges.size() == 1 and ways_in == 3,
		"and the courtyard has one lane a runner can shut behind them, and three ways in",
		"refuges %s, ways in %d, against LANE_THROUGH %.1f m"
			% [refuges, ways_in, BfhArena.LANE_THROUGH])

	_done()


## One drive of the autopilot into the courtyard through its [param lane]th lane, at a runner
## standing in the courtyard's middle, from [param out_by] metres outside the lane.
func _drive_a_lane(lane: int, out_by: float, in_the_lane: bool = false) -> Dictionary:
	return await _drive_into(func(arena: BfhArena) -> Array:
		var middle := arena.yard_middle(0)
		var mouth := arena.yard_lane_middle(0, lane)
		var out := mouth - middle
		out.y = 0.0
		return [mouth, middle, out.normalized()], out_by, in_the_lane)


## The drive [method _drive_a_lane] makes, into any gap: [param where] is given the built arena and
## returns [code][mouth, middle, out][/code] — the gap's middle, where the runner stands when not in
## it, and the unit direction out of the gap.
func _drive_into(where: Callable, out_by: float, in_the_lane: bool = false) -> Dictionary:
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	_put(runner, Vector3(-30.0, 0.05, 20.0))
	game.start()
	await _step(game, 30)
	for prop in game.props.all_props():
		if not prop.instance_id in game.scaffold_ids:
			game.props.remove(prop.instance_id)
	await _step(game, 2)

	var at_gap: Array = where.call(game.arena)
	var mouth: Vector3 = at_gap[0]
	var middle: Vector3 = at_gap[1]
	var out: Vector3 = _clear_line(game.arena, mouth, at_gap[2], out_by)
	var turned := rad_to_deg((at_gap[2] as Vector3).signed_angle_to(out, Vector3.UP))
	var start := mouth + out * out_by

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(-out), start + Vector3(0.0, 1.4, 0.0))
	driver.is_bot = true

	var hide := (mouth if in_the_lane else middle) + Vector3(0.0, 0.05, 0.0)
	_put(runner, hide)
	var last := bus.position()
	var peak := 0.0
	var nearest := INF
	var outcome := "wedges"
	var wedged := -1.0
	var took := 0
	# Twelve seconds: past the stuck rule's five, so a bus that wedges and is left there
	# long enough to be sent home says so rather than being reported as wedged.
	for _i in range(720):
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1
		_watch_parked(bus, "into %s, %.0f m out%s" % [str(mouth.snapped(Vector3.ONE)), out_by,
			", runner in it" if in_the_lane else ""], took == 1)
		var at := bus.position()
		if _sent_home(last, at):
			outcome = "sent home"
			break
		peak = maxf(peak, bus.speed())
		# Wedged: stopped against something after the first half second, asking to go.
		if wedged < 0.0 and took > 30 and bus.speed() < 1.0:
			wedged = float(took) * TICK
		nearest = minf(nearest, Vector2(at.x - hide.x, at.z - hide.z).length())
		last = at
		if not runner.health.alive:
			outcome = "reaches"
			break

	var clear := _line_room(game.arena, mouth, out, out_by)
	await _dispose(game)
	return {
		"outcome": outcome, "peak": peak, "seconds": float(took) * TICK,
		"nearest": nearest, "start": start, "wedged": wedged, "turned": turned,
		"clear": clear,
	}


## The direction to put a drive's bus out along: [param out] itself if a bus started [param out_by]
## metres along it from [param mouth] stands on clear floor with a clear line to the gap, otherwise
## the nearest direction either side of it, in 2.5 degree steps up to 45, that does.
func _clear_line(arena: BfhArena, mouth: Vector3, out: Vector3, out_by: float) -> Vector3:
	for step in range(19):
		for side: float in ([1.0] if step == 0 else [1.0, -1.0]):
			var turned := out.rotated(Vector3.UP, deg_to_rad(2.5 * step * side))
			if _line_room(arena, mouth, turned, out_by) >= START_ROOM:
				return turned
	return out


## How far the bus is from touching anything on a drive started [param out_by] metres along [param
## out] from [param mouth]: the least, over every pillar and drum, of the distance from its surface
## to the strip a bus sweeps from the mouth to the tail of a bus parked at the start, less half a.
func _line_room(arena: BfhArena, mouth: Vector3, out: Vector3, out_by: float) -> float:
	var a := Vector2(mouth.x, mouth.z)
	var b := a + Vector2(out.x, out.z) * (out_by + BUS_HALF_LENGTH)
	var room := INF
	var obstacles := arena.obstacles()
	for i in range(obstacles.size()):
		var axis := Vector2(obstacles[i].x, obstacles[i].z)
		var on := Geometry2D.get_closest_point_to_segment(axis, a, b)
		room = minf(room, axis.distance_to(on) - arena.obstacle_radius(i) - BfhArena.BUS_HALF_WIDTH)
	return minf(room, arena.radius - b.length() - BfhArena.BUS_HALF_WIDTH)


## This is that measurement, kept. Eight starts, a runner standing still on the deck's middle,
## twenty seconds each; a start counts when the bus kills them.
func _test_up_onto_the_deck() -> void:
	print("up the ramp onto the deck, driven by a bot")
	var asserted := ["spawn", "spawn_west", "foot8", "south20", "east", "ne", "sw", "west"]
	var missed := PackedStringArray()
	for start_kind: String in asserted:
		var game := _world(func(c: BfhConfig) -> void:
			c.crate_count = 0
			c.barrel_count = 0
			c.round_seconds = 120.0)
		var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
		var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
		_put(runner, Vector3(-30.0, 0.05, 20.0))
		game.start()
		await _step(game, 30)
		for prop in game.props.all_props():
			if not prop.instance_id in game.scaffold_ids:
				game.props.remove(prop.instance_id)
		await _step(game, 2)

		var arena := game.arena
		var foot := arena.ramp_foot()
		var bus := game.vehicles.get_vehicle(game._bus_ids[0])
		if start_kind == asserted[0]:
			# The turning point is where a bus with its back to the ramp turns round, and a
			# bus turning on the spot sweeps its half-diagonal; the legs keep
			# RAMP_TURN_MARGIN of floor beyond that.
			var turn_at := arena.ramp_turn_point()
			var sweep := Vector2(BfhGame.BUS_HALF_WIDTH, BfhGame.BUS_HALF_LENGTH).length() \
				+ BfhGame.RAMP_TURN_MARGIN
			_check(arena.floor_clear_at(turn_at) >= sweep,
				"the floor in front of the ramp's foot has room for a bus to turn round in",
				"%.2f m clear at %.1f m out, a turning bus needs %.2f"
					% [arena.floor_clear_at(turn_at), turn_at.z - foot.z, sweep])
		var starts := {
			"foot8": Vector3(0.0, 1.4, foot.z + 8.0),
			"south20": Vector3(0.0, 1.4, foot.z + 20.0),
			"east": Vector3(8.0, 1.4, 2.0),
			"ne": Vector3(10.0, 1.4, -2.0),
			"sw": Vector3(-8.0, 1.4, 3.0),
			"west": Vector3(-6.0, 1.4, 0.0),
		}
		# The second bus's lane, west of the slab, faced the way `_place_buses` faces it.
		var west_lane := arena.bus_start(1, 2)
		var facing := Vector3.FORWARD
		if start_kind == "spawn_west":
			starts["spawn_west"] = west_lane
			facing = Vector3(-west_lane.x, 0.0, -west_lane.z).normalized()
		if starts.has(start_kind):
			var body := bus.body()
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.global_transform = Transform3D(Basis.looking_at(facing), starts[start_kind])
		driver.is_bot = true
		var deck := arena.ledge_centre()
		deck.y = arena.deck_top() + 0.05
		_put(runner, deck)

		var killed_at := -1.0
		var peak := 0.0
		for i in range(int(20.0 / TICK)):
			var still := DotFpsCommand.new()
			still.yaw = runner.controller.state.yaw
			runner.controller.apply_command(still)
			game.simulate(TICK)
			await get_tree().physics_frame
			peak = maxf(peak, bus.speed())
			if not runner.health.alive:
				killed_at = float(i) * TICK
				break
			_watch_parked(bus, "up the ramp from %s" % start_kind, i == 0)
		print("  ..    %-10s %s" % [start_kind,
			"on the deck, killed at %.2f s, peak %.1f m/s" % [killed_at, peak] if killed_at >= 0.0
			else "never reached them (bus at %s)" % str(bus.position().snapped(Vector3(0.1, 0.1, 0.1)))])
		if start_kind in asserted and killed_at < 0.0:
			missed.append(start_kind)
		await _dispose(game)

	_check(missed.is_empty(),
		"a bot bus reaches a runner on the deck from both spawn lanes, in front of the ramp and from either side",
		"missed: %s" % ", ".join(missed))
	# Every chase driven so far: the courtyard's lanes, the hook's gaps and these.
	_check(_parked_longest < PARKED_LIMIT,
		"no bot bus chasing a runner it can see is ever parked with the throttle off",
		"%.2f s, %s" % [_parked_longest, _parked_where])
	_done()


func _test_the_hook_gaps() -> void:
	print("the hook's gaps, driven")
	# The decided fix, the middle pillar at x = 30.3, is `hook_layout = "wide"`: it breaks the gap rule
	# at the scaffold, so it is selectable and not shipped (see `BfhArena.HOOK_LAYOUTS`).
	var probe := _world()
	probe.start()
	await _step(probe, 2)
	var widths := BfhArena.hook_gaps(probe.arena.hook_layout)
	await _dispose(probe)
	_check(minf(widths.x, widths.y) >= BfhArena.BUS_GAP
			and maxf(widths.x, widths.y) < BfhArena.LANE_THROUGH,
		"the hook's gaps are a bus's and not the bot bus's (known, runner-standing-1)",
		"south-middle %.2f m, middle-north %.2f m, against BUS_GAP %.1f and LANE_THROUGH %.1f"
			% [widths.x, widths.y, BfhArena.BUS_GAP, BfhArena.LANE_THROUGH])

	var gaps := [[2, 1, "south-middle"], [1, 0, "middle-north"]]
	var rows: Array[Dictionary] = []
	for g: Array in gaps:
		for out_by: float in [8.0, 11.0, 14.0]:
			for in_gap: bool in [true, false]:
				var r := await _drive_into(_hook_gap.bind(g[0], g[1]), out_by, in_gap)
				r["gap"] = g[2]
				r["out_by"] = out_by
				r["in_gap"] = in_gap
				rows.append(r)
				print("  ..    %-12s %4.1f m out  runner %-8s | %-9s %4.1f m/s peak %5.2f s wedged %4.1f nearest %4.1f"
					% [g[2], out_by, "in gap" if in_gap else "centroid", r.outcome, r.peak,
						r.seconds, r.wedged, r.nearest]
					+ "  start (%.1f, %.1f), %.1f deg off square, %.2f m room" % [
						r.start.x, r.start.z, r.turned, r.clear])

	# Not measuring the inside of a drum: see `_clear_line`.
	var cramped := PackedStringArray()
	for r: Dictionary in rows:
		if r.clear < START_ROOM:
			cramped.append("%s %.0f m (%.2f m)" % [r.gap, r.out_by, r.clear])
	_check(cramped.is_empty(),
		"every drive at the hook's gaps starts on clear floor with a clear line in",
		"cramped: %s" % ", ".join(cramped))

	for g: Array in gaps:
		var reached := PackedStringArray()
		for r: Dictionary in rows:
			if r.gap != g[2] or not r.in_gap:
				continue
			if r.outcome == "reaches":
				reached.append("%.0f m out in %.2f s" % [r.out_by, r.seconds])
		_check(reached.is_empty(),
			"a runner standing still in the hook's %s gap is not reached by a bot bus from 8, 11 or 14 m out (known)" % g[2],
			"reached from %s: the hook is fixed, turn this check round" % ", ".join(reached))
	_done()


## [code][mouth, middle, out][/code] for [method _drive_into]: the gap between hook pillars [param
## a] and [param b] (offsets from [constant BfhArena.HOOK_FIRST]), its middle on clear floor, the
## hook's centroid, and the direction out of the gap away from that centroid, square to the gap.
func _hook_gap(arena: BfhArena, a: int, b: int) -> Array:
	var p := arena.pillars()
	var h := BfhArena.HOOK_FIRST
	var pa := p[h + a]
	var pb := p[h + b]
	var centroid := (p[h] + p[h + 1] + p[h + 2]) / 3.0
	centroid.y = 0.0
	var along := pb - pa
	along.y = 0.0
	var gap := along.length() - 2.0 * BfhArena.PILLAR_RADIUS
	var mouth := Vector3(pa.x, 0.0, pa.z) + along.normalized() * (BfhArena.PILLAR_RADIUS + gap * 0.5)
	var out := Vector3(-along.z, 0.0, along.x).normalized()
	if out.dot(mouth - centroid) < 0.0:
		out = -out
	return [mouth, centroid, out]


func _test_sides() -> void:
	print("the two sides")

	var game := _world(func(c: BfhConfig) -> void: c.driver_count = 2)
	game.add_player(&"a", "A")
	# A round needs a runner and a bot only drives, so the first person in takes the side
	# nothing else can fill. When they took a seat, the module's bot took the other and a
	# dedicated server sat in warmup for ever with nobody on foot.
	_check(game.team_of(&"a") == BfhGame.TEAM_RUNNERS,
		"the first person on a server runs, because a bot cannot",
		"a is on %d" % game.team_of(&"a"))
	game.add_player(&"b", "B")
	game.add_player(&"c", "C")
	game.add_player(&"d", "D")
	await get_tree().physics_frame

	_check(game.drivers().size() == 2, "the seats fill first",
		"%d drivers" % game.drivers().size())
	_check(game.runners().size() == 2, "and everybody else runs",
		"%d runners" % game.runners().size())

	# Not a balancer: two against six is the design. A balancer that did not know
	# that would move four people into two buses every round.
	_check(not game.match_node.teams.force_balance,
		"and nothing tries to even them up")

	# [b]And nothing REFUSES them either, which `force_balance` alone does not say.[/b] dot-match's
	# team manager has a second rule, `max_difference`, that refuses a join putting one side more than
	# one ahead — so the fifth person here was left on no team in dot-match while `sides`.
	game.add_player(&"e", "E")
	game.add_player(&"f", "F")
	var unknown := PackedStringArray()
	for id: StringName in game.sides:
		if game.match_node.teams.team_of(String(id)) != game.team_of(id):
			unknown.append(String(id))
	_check(unknown.is_empty(), "dot-match puts every runner on the runners' side",
		"it disagrees about %s" % ", ".join(unknown))

	# Somebody leaving leaves dot-match too, or they go on counting as present — towards
	# `min_players` and on the side they left from.
	game.remove_player(&"f")
	_check(game.match_node.scoreboard.present_count() == game.players.size(),
		"and somebody who leaves is not still counted by it",
		"%d present, %d players" % [game.match_node.scoreboard.present_count(), game.players.size()])

	var runner: BfhPlayer = game.runners()[0]
	_check(runner.hammer != null, "a runner carries a hammer")
	_check((game.drivers()[0] as BfhPlayer).hammer == null,
		"and a driver does not, because the bus is the weapon")

	await _dispose(game)
	_done()


# --- The join this game exists for

func _test_standing_on_a_crate() -> void:
	print("standing on a crate")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var player := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	# Placed by hand rather than scattered, because what is being tested is the join
	# and not the scatter.
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 0.0))
	var body := crate.body()
	body.freeze = false
	# Gravity LEFT ON, and the first version of this check turned it off. A crate with no gravity still
	# takes the player's weight — that is the whole point of `DotPropCarry.stand` — so it accelerates
	# downward out from under them and they are carried for about four ticks.
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO

	player.global_position = Vector3(0.0, 1.9, 0.0)
	player.controller.state.position = player.global_position
	player.controller.state.velocity = Vector3.ZERO

	await _step(game, 30)

	var ground_id := player.controller.state.ground_id
	_check(ground_id != 0, "the player lands on something")
	_check(game.carry.prop_under(ground_id) == crate,
		"and what they are standing on is the crate")

	# The half that is invisible when it is missing. A character motor sweeps a shape
	# and slides, so a crate is exactly as solid as the floor and exactly as
	# immovable — a player stands on one, it slides away, and they do not go with it.
	var before := player.global_position

	# Driven each tick rather than set once: a crate on the ground has friction with
	# it, so one assignment is a crate that stops. What is being tested is whether a
	# player on a MOVING crate moves with it, not how long a shove lasts.
	for _i in range(30):
		body.linear_velocity.x = 3.0
		game.simulate(TICK)
		await get_tree().physics_frame

	var travelled := player.global_position.x - before.x
	_check(travelled > 0.5, "and is carried when the crate moves",
		"%.2f m" % travelled)
	_check(player.carried_metres > 0.5, "which the player counts",
		"%.2f m" % player.carried_metres)

	# Written back into the state as well as onto the node: the controller starts the next tick from
	# `state.position`, so a displacement applied only to the node is undone by the very next move and
	# the player rides for one frame per tick and stands still overall.
	_check(
		player.controller.state.position.distance_to(player.global_position) < 0.01,
		"with the motor's own state moved with them",
		"%.3f m apart" % player.controller.state.position.distance_to(player.global_position)
	)

	await _dispose(game)
	_done()


func _test_hammer() -> void:
	print("the hammer")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var player := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)

	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF

	var health_before := game.prop_damage.health_of(crate.instance_id)
	_check(health_before > 0.0, "a crate has health", "%.0f" % health_before)

	var swung := player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	_check(swung, "a swing happens")
	_check(game.prop_damage.health_of(crate.instance_id) < health_before,
		"and takes health off the crate",
		"%.0f" % game.prop_damage.health_of(crate.instance_id))

	# The cooldown is what stops a hammer being a chainsaw.
	_check(
		not player.hammer.swing(
			game, origin, forward, game.props, game.prop_damage, game.carry,
			player.player_id, mask
		),
		"a second swing on the same tick is refused"
	)

	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)

	_check(not crate.is_alive(), "three swings break it")
	_check(player.hammer.breaks == 1, "and the hammer counts the break",
		"%d" % player.hammer.breaks)

	# A hammer that only deletes crates is a worse tool than one that also moves them.
	var pushable := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	var push_body := pushable.body()
	push_body.freeze = false
	push_body.gravity_scale = 0.0
	push_body.linear_velocity = Vector3.ZERO
	await _step(game, 2)

	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	await _step(game, 2)

	_check(push_body.linear_velocity.z > 0.05, "and a swing shoves what it does not break",
		"%.2f m/s" % push_body.linear_velocity.z)

	# The one thing in the bowl that is not a toy: whatever the drivers break, this
	# much cover remains.
	var block := game.props.spawn(BfhContent.BLOCK, &"world", Vector3(0.0, 0.5, 8.0))
	_check(not game.prop_damage.is_breakable(block.instance_id),
		"a concrete block cannot be broken at all")

	await _dispose(game)
	_done()


func _test_hammer_viewmodel() -> void:
	print("the first-person hammer")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.start()
	await _step(game, 4)

	var mine := BfhClient.new()
	mine.game = game
	mine.player = runner
	mine._build_camera()
	var theirs := BfhClient.new()
	theirs.game = game
	theirs.player = driver
	theirs._build_camera()

	mine._present_viewmodel()
	theirs._present_viewmodel()
	_check(mine.viewmodel != null and mine.viewmodel.visible, "a runner's camera carries a visible hammer")
	_check(theirs.viewmodel != null and not theirs.viewmodel.visible, "a driver's does not")

	var bare := BfhViewmodel.wanted(runner.hammer, true, false, false, false)
	_check(bare and not BfhViewmodel.wanted(runner.hammer, false, false, false, false)
		and not BfhViewmodel.wanted(runner.hammer, true, true, false, false)
		and not BfhViewmodel.wanted(runner.hammer, true, false, true, false)
		and not BfhViewmodel.wanted(runner.hammer, true, false, false, true)
		and not BfhViewmodel.wanted(null, true, false, false, false),
		"shown only alive, on foot, in their own eyes, with a hammer")

	runner.health.alive = false
	mine._present_viewmodel()
	_check(not mine.viewmodel.visible, "and hidden when the runner is dead")
	runner.health.alive = true

	runner.hammer.cooldown = 0.0
	var before: int = mine.viewmodel.swings
	var _swung := runner.hammer.swing(game, Vector3(0.0, 1.0, 0.0), Vector3.UP, game.props,
		game.prop_damage, game.carry, runner.player_id, 0xFFFFFFF)
	_check(mine.viewmodel.swings == before + 1 and mine.viewmodel.swinging(),
		"the hammer's use starts the swing")
	mine.viewmodel._process(BfhViewmodel.SWING_TIME + 0.01)
	_check(not mine.viewmodel.swinging(), "and the swing ends back at rest")

	mine.free()
	theirs.free()
	await _dispose(game)
	_done()


func _test_barrel() -> void:
	print("a barrel")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var near := game.add_player(&"near", "Near", BfhGame.TEAM_RUNNERS)
	var far := game.add_player(&"far", "Far", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var barrel := game.props.spawn(BfhContent.BARREL, &"world", Vector3(0.0, 0.6, 0.0))
	barrel.body().freeze = true

	near.global_position = Vector3(1.5, 1.0, 0.0)
	near.controller.state.position = near.global_position
	far.global_position = Vector3(20.0, 1.0, 0.0)
	far.controller.state.position = far.global_position

	await _step(game, 2)

	var blasts: Array = []
	game.barrel_exploded.connect(func(at: Vector3, radius: float) -> void:
		blasts.append({"at": at, "radius": radius}))

	var near_health := near.health.health
	var far_health := far.health.health

	game.prop_damage.break_now(barrel.instance_id, &"near")
	await _step(game, 2)

	_check(blasts.size() == 1, "breaking one sets it off", "%d" % blasts.size())
	_check(near.health.health < near_health, "somebody beside it is hurt",
		"%.0f -> %.0f" % [near_health, near.health.health])
	_check(is_equal_approx(far.health.health, far_health),
		"and somebody across the bowl is not",
		"%.0f" % far.health.health)

	# The one thing in the game that throws a runner UPWARD, which is the only way
	# onto a crate stack the crates themselves do not offer.
	_check(near.controller.state.velocity.y > 0.5, "and is thrown up by it",
		"%.2f m/s" % near.controller.state.velocity.y)

	_check(not barrel.is_alive(), "the barrel is gone")

	await _dispose(game)
	_done()
