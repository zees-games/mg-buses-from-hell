extends "headless_run_base.gd"
## The world, bowl and district sections: building, layouts and the bots' pace.


## A bus on its roof rights itself.
func _test_a_rolled_bus() -> void:
	print("a bus on its roof")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
	)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	var buses := game.vehicles.all_vehicles()

	if buses.is_empty():
		_check(false, "there is a bus to roll")
		_check(false, "which the game notices is upside down")
		_check(false, "and puts back on its wheels")
		await _dispose(game)
		_done()
		return

	_check(true, "there is a bus to roll")

	var bus: DotVehicleInstance = buses[0]
	var body := bus.body()
	var where := body.global_position

	# Rolled onto its roof deliberately, which is what a ramp and a hard turn do.
	body.global_transform = Transform3D(
		Basis(Vector3.FORWARD, PI) * body.global_basis, where + Vector3(0.0, 1.0, 0.0)
	)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _step(game, 10)

	_check(bus.is_inverted(), "which the game notices is upside down")

	# Longer than INVERTED_RIGHT_SEC, plus the frames it takes to settle.
	await _step(game, int(BfhGame.INVERTED_RIGHT_SEC * 60.0) + 40)

	_check(
		not bus.is_inverted(),
		"and puts back on its wheels rather than leaving a driver out of the round",
		"up=%.2f" % body.global_basis.y.y
	)

	await _dispose(game)
	_done()


## The family's rule since the first play test: H opens help in every game, nothing else in
## the table is on H, and the Escape menu has Help & commands and Leave.
func _test_help_and_menu() -> void:
	print("H opens help, and the Escape menu has Help and Leave")
	var settings := BfhSettings.new()
	add_child(settings)
	var built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	var keys: DotMenuBindings = settings.bindings
	_check(built.ok and keys != null and keys.key_for(DotMenuBindings.HELP_ACTION) == "H", "help is on H")
	_check(keys.defaults_on("H").size() == 1, "and nothing else in the table defaults to H",
		str(keys.defaults_on("H").map(func(r: Dictionary) -> String: return str(r["label"]))))
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.keycode = KEY_H
	h.pressed = true
	_check(settings.menu.handle_event(h) and settings.menu.help.is_open(), "H opens the help screen")
	_check(settings.menu.help.about != "" and settings.menu.help.heading() == "How to play Buses from Hell",
		"which says what the game is before the keys")
	settings.menu.help.close()
	settings.open()
	var help_button := settings.menu.screen.find_child("Action_help", true, false) as Button
	var leave_button := settings.menu.screen.find_child("Action_leave", true, false) as Button
	_check(help_button != null and leave_button != null and leave_button.visible,
		"the Escape menu has Help & commands and Leave")
	settings.close()
	settings.queue_free()
	await get_tree().process_frame
	_done()


## The mouse wheel jumps, rebindably, and a tick (press and release in one frame) is one jump.
func _test_wheel_jump() -> void:
	print("the wheel jumps")
	var settings := BfhSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	var labels: Array = []
	for row in settings.bindings.rows:
		if StringName(row["action"]) == &"dot_fps_jump":
			labels.append(str(row["label"]))
	_check(labels.size() >= 3, "jump has Space plus two wheel rows", str(labels))
	var found := 0
	for row in settings.bindings.rows:
		if StringName(row["action"]) == &"dot_fps_jump" and (str(row["default"]) == "Wheel up" or str(row["default"]) == "Wheel down"):
			found += 1
	_check(found == 2, "the rows are Wheel up and Wheel down", str(found))
	var sampler := DotFpsSampler.new(DotFpsTunables.with_profile("legacy"))
	DotFpsSampler.register_default_actions(sampler)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	up.pressed = true
	sampler.handle_event(up)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_WHEEL_UP
	rel.pressed = false
	sampler.handle_event(rel)
	var cmd := sampler.sample(0.016)
	_check(cmd.is_pressed(DotFpsCommand.BUTTON_JUMP), "a wheel-up tick is a jump in the next command")
	_check(not sampler.sample(0.016).is_pressed(DotFpsCommand.BUTTON_JUMP), "and only that one")
	settings.queue_free()
	await get_tree().process_frame
	_done()


## The family's rule since the first play test: M opens the bowl list, and solo a choice
## changes it now. The server's half (the owner's flag, the vote) is in `dedicated` and dot-vote.
func _test_the_map_menu() -> void:
	print("M opens the bowl list, and solo a choice changes it")
	var game := await _world()
	var _a := game.add_player(&"u1", "Ada")
	var _b := game.add_player(&"u2", "Bo")
	game.start()
	await _step(game, 4)
	var settings := BfhSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	var keys: DotMenuBindings = settings.bindings
	_check(keys.key_for(DotMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
		"the map menu is on M, and nothing else in the table defaults to M",
		str(keys.defaults_on("M").map(func(r: Dictionary) -> String: return str(r["label"]))))
	var rows: Array = game.bowl_rows()
	_check(rows.size() > 1 and rows.filter(func(r: Dictionary) -> bool: return bool(r["current"])).size() == 1,
		"there is more than one to choose, the one playing marked", "%d" % rows.size())
	var _maps := settings.use_maps(game.bowl_rows, game.change_bowl_now)
	var m := InputEventKey.new()
	m.physical_keycode = KEY_M
	m.keycode = KEY_M
	m.pressed = true
	_check(settings.menu.handle_event(m) and settings.menu.picker.is_open(), "M opens the picker")
	var wanted: StringName = &""
	var key := KEY_NONE
	for row in range(1, DotMenuPicker.PAGE_SIZE + 1):
		var it: Variant = settings.menu.picker.at_row(row)
		if it is Dictionary and not bool((it as Dictionary)["current"]):
			wanted = StringName(str((it as Dictionary)["id"]))
			key = KEY_0 + row
			break
	var digit := InputEventKey.new()
	digit.physical_keycode = key
	digit.keycode = key
	digit.pressed = true
	var _k := settings.menu.handle_event(digit)
	for _i in 4:
		await get_tree().physics_frame
	_check(wanted != &"" and game.bowl_id == wanted, "choosing one changes to it now", "%s, now %s" % [wanted, game.bowl_id])
	_check(not settings.menu.picker.is_open(), "and the picker is closed")
	settings.queue_free()
	await get_tree().process_frame
	_done()


## An administrator's blind and beacon, as a client draws them.
func _test_blind_and_beacon_drawn() -> void:
	print("blind and beacon, as a client draws them")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	var hud := BfhHud.new()
	add_child(hud)
	hud.bind(game, runner)

	var settings := BfhSettings.new()
	add_child(settings)
	var _built: Variant = settings.setup(DotSettingsStoreMemory.new())
	hud.follow_menu(settings.menu)
	var plate := hud.vitals.colour(&"plate")
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7, "the HUD is dark by default, in the menu's theme", str(plate))
	var _t := settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: DotMenuPalette = settings.menu.palette()
	_check(contrast.id == &"contrast" and hud.vitals.colour(&"plate") == contrast.hud_plate and hud.vitals.colour(&"text") == contrast.hud_text,
		"a theme picked in the menu reaches the pieces at once")
	_check(hud.vitals.colour(&"highlight") == BfhArena.SAND and hud._cover.get_theme_color(&"font_color") == contrast.hud_text,
		"keeping this game's accent, and the HUD's own lines follow it too")
	_t = settings.settings.set_value(&"ui_theme", &"midnight")
	settings.queue_free()
	await get_tree().process_frame

	runner.blinded = true
	hud.present_blind(BfhHud.BLIND_FADE_SEC + 0.05)
	_check(
		hud.blind_overlay.visible and is_equal_approx(hud.blind_overlay.modulate.a, 1.0),
		"a blind fades the overlay all the way in"
	)
	var viewport := get_viewport().get_visible_rect()
	_check(
		hud.blind_rect().encloses(viewport),
		"and it covers the whole viewport, not a HUD-sized rect inside it",
		"%s against %s" % [str(hud.blind_rect()), str(viewport)]
	)
	_check(
		hud.blind_overlay.get_index() == 0,
		"under the clock, the health and the cover count, which still say the round is on"
	)
	runner.blinded = false
	hud.present_blind(BfhHud.BLIND_FADE_SEC + 0.05)
	_check(not hud.blind_overlay.visible, "and lifting it takes it away again")

	runner.health.health = 17.4
	await get_tree().process_frame
	var left := maxf(game.config.round_seconds - game.round_elapsed, 0.0)
	_check(
		hud.vitals.number_text() == "18" and hud.vitals.is_low()
		and hud.strip.clock == DotScoreStrip.clock_text(left),
		"the HUD hands health and the clock to DotVitals and DotScoreStrip, red at a quarter",
		"%s low=%s, clock %s for %.1f s" % [hud.vitals.number_text(), str(hud.vitals.is_low()), hud.strip.clock, left]
	)
	runner.health.health = runner.health.max_health

	# Both bottom-anchored, so this holds at any height.
	var chat_box: Node = BfhClientChat.new()
	add_child(chat_box)
	chat_box.call("_build_window")
	var chat_bottom: float = chat_box.get("window").margin_bottom
	_check(
		-hud.vitals.offset_top <= chat_bottom,
		"the health plate stays under the chat box",
		"plate top %.0f px off the bottom, chat from %.0f" % [-hud.vitals.offset_top, chat_bottom]
	)
	chat_box.queue_free()

	# A pack naming these classes needs dot-ui 4 in the derived requires.json; nothing may lower it.
	var asks := DotAddonApi.derive()
	_check(
		int(asks.get("dot_ui", 0)) >= 4 and not FileAccess.file_exists("res://" + DotAddonApi.FLOOR_FILE),
		"the pack asks a shell for dot-ui level 4, the glance pieces",
		str(asks.get("dot_ui"))
	)

	runner.beacon = true
	runner.present_beacon(0.0, false)
	for _i in range(150):
		runner.present_beacon(TICK, false)
	var marker := runner.beacon_marker
	_check(
		marker != null and marker.pings == 3,
		"a beacon pings the moment it comes on and once a second after, not once a frame",
		"%d pings in 2.5 s" % (marker.pings if marker != null else -1)
	)
	runner.present_beacon(TICK, true)
	_check(
		marker != null and not marker.get_node("Column").visible
		and marker.get_node("Ring").visible,
		"and on the beaconed player's own screen the column is left out and the ring is not"
	)

	# A driver is marked round their bus, because the bus is the only thing of them anybody
	# sees: their own position is where they sat down.
	driver.beacon = true
	driver.present_beacon(TICK, false)
	var bus := driver.ridden
	var on_bus := driver.beacon_marker
	_check(
		driver.riding and bus != null and on_bus != null
		and on_bus.global_position.distance_to(bus.global_position) < 0.01
		and on_bus.ring_radius > 4.0,
		"a beaconed driver's marker is drawn round their bus, wide enough to circle it",
		"riding %s, bus %s, ring %.1f m" % [
			str(driver.riding), str(bus), on_bus.ring_radius if on_bus != null else 0.0
		]
	)

	runner.beacon = false
	runner.present_beacon(TICK, false)
	_check(runner.beacon_marker == null, "turning the beacon off takes the marker away")

	driver.health.alive = false
	driver.present_beacon(TICK, false)
	_check(
		driver.beacon_marker == null,
		"and so does being out: a column over an empty patch of sand points at nobody"
	)

	remove_child(hud)
	hud.free()
	await _dispose(game)
	_done()


func _test_config() -> void:
	print("the configuration")

	var config := BfhConfig.new()
	_check(config.validate().ok, "the shipped defaults are usable")
	_check(
		config.gravity >= 19.0,
		"and carry the gravity this game's numbers were chosen for",
		"%.1f" % config.gravity
	)

	# The one cross-field rule, and the reason it is a rule: a bus that can never
	# reach its own lethal speed is a bus that can never kill anybody, which reads as
	# the collision code being broken rather than as two numbers disagreeing.
	config.bus_lethal_speed = config.bus_top_speed + 1.0
	var refused := config.validate()
	_check(not refused.ok, "a lethal speed above the top speed is refused")
	_check(
		refused.ok or refused.error.message.contains("bus_top_speed"),
		"and the message names both numbers"
	)

	config.bus_lethal_speed = 9.0
	config.round_seconds = 0.0
	_check(not config.validate().ok, "so is a round with no clock")

	# The hook ships as built, because the decided "wide" hook breaks the gap rule at the scaffold (see
	# `BfhArena.HOOK_LAYOUTS`); "wide" is selectable and its gaps are the bot's.
	var shipped := BfhConfig.new()
	var hook := BfhArena.hook_gaps(shipped.hook_layout)
	var wide := BfhArena.hook_gaps("wide")
	_check(
		shipped.courtyard_west_lane >= BfhArena.LANE_THROUGH
			and BfhArena.COURTYARD_WEST_LANE_NARROW >= BfhArena.BUS_GAP,
		"the shipped courtyard west lane is wide enough for the bot bus, and the old one is still a bus's gap",
		"%.2f m, and %.2f m" % [shipped.courtyard_west_lane, BfhArena.COURTYARD_WEST_LANE_NARROW]
	)
	_check(
		shipped.hook_layout == "tight" and minf(hook.x, hook.y) >= BfhArena.BUS_GAP
			and minf(wide.x, wide.y) >= BfhArena.LANE_THROUGH,
		"the shipped hook is the one as built, and the wide one is selectable and the bot's",
		"%s %.2f / %.2f m; wide %.2f / %.2f m" % [shipped.hook_layout, hook.x, hook.y, wide.x, wide.y]
	)
	var layered := BfhConfig.new()
	layered.apply_dictionary({"hook_layout": "wide", "courtyard_west_lane": 6.6,
		"bot_aim_past": 6.0, "bus_stuck_reset_seconds": 0.5})
	_check(
		layered.hook_layout == "wide" and is_equal_approx(layered.courtyard_west_lane, 6.6)
			and is_equal_approx(layered.bot_aim_past, 6.0),
		"and both, with the bots' knobs, are keys the layered config sets"
	)
	_check(not layered.validate().ok,
		"a bus given up on before what is under it is broken is refused",
		"reset %.1f s, break %.1f s" % [layered.bus_stuck_reset_seconds, layered.bus_stuck_break_seconds])
	_done()


# --- The world

func _test_world_builds() -> void:
	print("the world")

	var game := _world()
	await get_tree().physics_frame

	_check(game.arena != null, "the bowl is built")

	var space_gravity := float(PhysicsServer3D.area_get_param(
		game.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY
	))
	_check(
		absf(space_gravity - game.config.gravity) < 0.01,
		"on a space carrying the game's gravity rather than the project's",
		"%.1f" % space_gravity
	)
	_check(game.props != null and game.props.authoritative, "props are spawnable")
	_check(game.prop_damage != null, "and breakable")
	_check(game.carry != null, "and can be stood on")
	_check(game.vehicles != null, "there is a vehicle spawner")
	_check(game.combat != null, "a combat manager")
	_check(game.match_node != null, "and a match")

	# The seam dot-match is built around: it has no idea what "alive" means, so the
	# elimination rule asks. Unset, the round runs to the clock instead of ending on
	# the last kill — which is the kind of wrong that looks like a tuning problem.
	var rules := game.match_node.rules as DotRulesElimination
	_check(rules != null, "the round is decided by elimination")
	_check(rules != null and rules.alive_fn.is_valid(),
		"and the rule has been told how to ask who is alive")

	await _dispose(game)
	_done()


## Every bowl the players can vote for holds the map-wide rules the shipped one is held to: no gap
## under a bus's width between any two obstacles, nor between an obstacle and the scaffold.
func _test_every_bowl() -> void:
	print("every bowl on the ballot")
	var config := BfhConfig.new()
	var tight := PackedStringArray()
	var unshaped := PackedStringArray()
	var radii := {}

	for bowl in BfhBowls.all(config):
		var arena := BfhArena.new()
		add_child(arena)
		arena.district = String(bowl.get("district", ""))
		arena.build(float(bowl["radius"]))
		var gap := arena.narrowest_gap()
		var scaffold := arena.scaffold_clearance()
		print("  ..    %-15s %4.0f m  tightest %.2f m, scaffold %.2f m, %d obstacles" % [
			String(bowl["id"]), arena.radius, gap, scaffold, arena.obstacles().size()])
		if minf(gap, scaffold) < BfhArena.BUS_GAP:
			tight.append("%s (%.2f / %.2f m)" % [bowl["id"], gap, scaffold])
		radii[snappedf(arena.radius, 0.5)] = true

		# dot-core's audit: drawn geometry nothing collides with is walked through.
		var res := DotCollisionAudit.audit(arena, true)
		if res.ok:
			var report: DotCollisionAudit = res.value
			print("  ..    %s collision audit: %d of %d" % [String(bowl["id"]), report.count(), report.examined])
			if report.count() > 0:
				unshaped.append("%s (%d)" % [bowl["id"], report.count()])
				for line in report.describe_lines().slice(1, 12):
					print("    %s" % line)
		else:
			unshaped.append("%s (audit failed: %s)" % [bowl["id"], res.error.message])
		remove_child(arena)
		arena.free()

	_check(tight.is_empty(), "no bowl on the ballot has a gap a bus cannot take",
		"too tight: %s, against %.2f m" % [", ".join(tight), BfhArena.BUS_GAP])
	_check(unshaped.is_empty(), "and nothing drawn in a bowl is walked through", ", ".join(unshaped))
	_check(radii.size() == BfhBowls.all(config).size(),
		"and every bowl is a different size: two of one radius are one map under two names", str(radii.keys()))
	_done()


func _test_districts() -> void:
	print("districts: maps drawn as places")
	var config := BfhConfig.new()
	var found := 0

	for bowl in BfhBowls.all(config):
		if String(bowl.get("district", "")) == "":
			continue
		found += 1
		var id := String(bowl["id"])
		var arena := BfhArena.new()
		add_child(arena)
		arena.district = String(bowl["district"])
		arena.build(float(bowl["radius"]))

		var buildings := arena.district_buildings()
		_check(buildings.size() >= 8, "%s has a town on it" % id, "%d buildings" % buildings.size())
		_check(arena.narrowest_gap() >= BfhArena.BUS_GAP,
			"%s leaves every gap a bus can take" % id, "%.2f m" % arena.narrowest_gap())
		_check(arena.scaffold_clearance() >= BfhArena.BUS_GAP,
			"and a bus can pass the scaffold", "%.2f m" % arena.scaffold_clearance())

		# No building on a bus's start lane, or the drivers would begin inside one.
		var blocked := 0
		for b: Dictionary in buildings:
			var at: Vector3 = b["at"]
			if absf(at.x) < 17.0 + float(b["radius"]) and at.z < -arena.radius + 4.0 + 24.0 + 6.0 + float(b["radius"]):
				blocked += 1
		_check(blocked == 0, "and nothing stands on the buses' start lanes", "%d in the way" % blocked)

		# Downtown's north quarter: towers south of its cross street, shops north of it and on the edges.
		if id == "bfh_downtown":
			var north := 0
			var shops := 0
			for b: Dictionary in buildings:
				if b["at"].z < -10.0:
					north += 1
				if b["kind"] == BfhBowls.BfhDistricts.HOUSE:
					shops += 1
			print("  ..    %s: %d buildings, %d north of the middle, %d shops" % [id, buildings.size(), north, shops])
			_check(north >= 2, "and downtown's north quarter is built", "%d north of z -10" % north)
			_check(shops >= 2, "and its north corners hold shops", "%d shops" % shops)

		# Runner spawns: every scattered point is on the floor and outside every obstacle.
		var stream := DotRandomStream.new(7, &"district")
		var bad := 0
		var obstacles := arena.obstacles()
		for _i in range(120):
			var p := arena.scatter_point(stream, 1.0, 0.0)
			if Vector2(p.x, p.z).length() > arena.radius:
				bad += 1
				continue
			for k in range(obstacles.size()):
				if Vector2(p.x - obstacles[k].x, p.z - obstacles[k].z).length() < arena.obstacle_radius(k):
					bad += 1
					break
		_check(bad == 0, "and every runner spawn is on the floor and clear of a building", "%d bad of 120" % bad)

		remove_child(arena)
		arena.free()

	_check(found == 3, "three districts are on the ballot", str(found))
	_done()


func _test_driving_a_district() -> void:
	print("a bot bus drives each district")
	var config := BfhConfig.new()

	for bowl in BfhBowls.all(config):
		var id := String(bowl.get("district", ""))
		if id == "":
			continue
		var game := _world(func(c: BfhConfig) -> void:
			c.round_seconds = 120.0
		)
		var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
		driver.is_bot = true
		game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
		game.start()
		await _step(game, 8)

		var changed := game.change_bowl_now(StringName(bowl["id"]))
		_check(changed.ok, "%s can be chosen from the map menu" % id, "refused")
		await _step(game, 20)
		_check(game.arena.district == id, "and the arena is that district", game.arena.district)

		var bus := game.vehicles.get_vehicle(game._bus_ids[0])
		var reach := game.arena.radius
		var last := bus.position()
		var covered := 0.0
		var outside := false
		var reset := false
		var took := 0

		for _i in range(420):
			game.simulate(TICK)
			await get_tree().physics_frame
			took += 1
			if not bus.is_alive():
				break
			var at := bus.position()
			if Vector2(at.x, at.z).length() > reach + 2.0 or at.y < -3.0:
				outside = true
				break
			if _sent_home(last, at):
				reset = true
				break
			covered += Vector2(at.x - last.x, at.z - last.z).length()
			last = at

		print("  ..    %-15s covered %.0f m in %d ticks" % [id, covered, took])
		_check(not outside, "a bot bus stays inside %s" % id)
		_check(not reset, "and is not sent home")
		_check(covered > 30.0, "and it gets somewhere", "%.0f m" % covered)
		await _dispose(game)

	_done()


## One bot bus chasing a runner who stands still wherever the scatter put them, and who is moved to
## a fresh spot each time the bus gets within [constant REACH_M] of them (or after [constant
## REACH_GIVE_UP] seconds without).
func _pace_drive(bowl_id: StringName, seconds: float, extra: Callable = Callable()) -> Dictionary:
	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = seconds + 60.0
		c.crate_count = 12
		c.barrel_count = 3
		if extra.is_valid():
			extra.call(c)
	)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	driver.is_bot = true
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)
	if bowl_id != &"bfh_bowl":
		game.change_bowl_now(bowl_id)
		await _step(game, 20)

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var stream := DotRandomStream.new(11, &"pace")
	var out := {"covered": 0.0, "seconds": 0.0, "resets": 0, "reaches": 0, "stalls": 0,
		"longest_stall": 0.0, "stall_at": Vector3.ZERO}
	var last := bus.position()
	var stalled := 0.0
	var since := 0.0
	var spots := 0
	var ticks := int(seconds / TICK)

	for _i in range(ticks):
		# A fresh runner spot, at least 25 m from the bus, from the seeded stream.
		var near := runner.global_position.distance_to(bus.position()) < REACH_M
		if spots == 0 or near or since > REACH_GIVE_UP:
			if near:
				out.reaches += 1
			var at := runner.global_position
			for _try in range(30):
				at = game.arena.scatter_point(stream, 1.0, 0.0)
				if at.distance_to(bus.position()) > 25.0:
					break
			_put(runner, at)
			spots += 1
			since = 0.0
		game.simulate(TICK)
		await get_tree().physics_frame
		since += TICK
		if not bus.is_alive():
			break
		var now := bus.position()
		if _sent_home(last, now):
			out.resets += 1
		else:
			out.covered += Vector2(now.x - last.x, now.z - last.z).length()
		last = now
		var asking := bus.command != null and absf(bus.command.throttle) > 0.3
		if asking and bus.speed() < 1.0:
			if stalled == 0.0:
				out.stalls += 1
			stalled += TICK
			if stalled > out.longest_stall:
				out.longest_stall = stalled
				out.stall_at = now
		else:
			stalled = 0.0
	out.seconds = float(ticks) * TICK
	await _dispose(game)
	return out


func _test_bot_pace() -> void:
	print("a bot bus keeps moving on every map")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			only = arg.trim_prefix("--map=")
	for id in PACE_MAPS:
		if only != "" and String(id) != only:
			continue
		var r := await _pace_drive(id, PACE_SECONDS)
		print("  ..    %-14s %.0f m in %.0f s = %.2f m/s, %d reaches, %d sent home, %d stalls (longest %.1f s at %s)"
			% [id, r.covered, r.seconds, r.covered / r.seconds, r.reaches, r.resets, r.stalls,
				r.longest_stall, str(r.stall_at.snappedf(0.1))])
		_check(r.covered / r.seconds >= PACE_FLOOR, "%s: a bot bus keeps an average pace over %.0f s" % [id, PACE_SECONDS],
			"%.2f m/s, floor %.1f" % [r.covered / r.seconds, PACE_FLOOR])
		_check(r.resets <= PACE_SENT_HOME_AT_MOST, "%s: and is not sent home more than %d time" % [id, PACE_SENT_HOME_AT_MOST],
			"sent home %d times" % r.resets)
		_check(r.longest_stall < PACE_STALL_AT_MOST, "%s: and never throttles against something for %.0f s" % [id, PACE_STALL_AT_MOST],
			"%.1f s at %s" % [r.longest_stall, str(r.stall_at.snappedf(0.1))])
		_check(r.reaches >= 1, "%s: and gets to a runner" % id, "%d reaches" % r.reaches)
	_done()


## A full table of bot buses, as a server runs: [constant PACK_BUSES] bots driving at [constant
## PACK_RUNNERS] runners standing wherever the stream puts them. One bus alone never meets another,
## and a pair wedged nose to flank is a stall no single-bus drive can show.
func _pack_drive(bowl_id: StringName, seconds: float) -> Dictionary:
	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = seconds + 60.0
		c.driver_count = PACK_BUSES
	)
	for i in range(PACK_BUSES):
		var driver := game.add_player(StringName("d%d" % i), "Driver %d" % i, BfhGame.TEAM_DRIVERS)
		driver.is_bot = true
	var runners: Array = []
	for i in range(PACK_RUNNERS):
		runners.append(game.add_player(StringName("r%d" % i), "Runner %d" % i, BfhGame.TEAM_RUNNERS))
	game.start()
	await _step(game, 8)
	if bowl_id != &"bfh_bowl":
		game.change_bowl_now(bowl_id)
		await _step(game, 20)

	var buses: Array = []
	for id in game._bus_ids:
		buses.append(game.vehicles.get_vehicle(id))
	var stream := DotRandomStream.new(23, &"pack")
	var n := buses.size()
	var last: Array = []
	var stalled: Array = []
	var began: Array = []
	var out := {"buses": n, "covered": 0.0, "resets": 0, "longest_stall": 0.0, "stall_at": Vector3.ZERO}
	for bus in buses:
		last.append(bus.position())
		stalled.append(0.0)
		began.append(bus.position())
	var ticks := int(seconds / TICK)
	var since := 0.0

	for _i in range(ticks):
		since += TICK
		for runner: BfhPlayer in runners:
			var closest := 1e9
			for bus in buses:
				closest = minf(closest, runner.global_position.distance_to(bus.position()))
			if since > REACH_GIVE_UP or closest < REACH_M:
				var at: Vector3 = runner.global_position
				for _try in range(30):
					at = game.arena.scatter_point(stream, 1.0, 0.0)
					if at.distance_to(runner.global_position) > 20.0:
						break
				_put(runner, at)
		if since > REACH_GIVE_UP:
			since = 0.0
		game.simulate(TICK)
		await get_tree().physics_frame
		for k in range(n):
			var bus = buses[k]
			if not bus.is_alive():
				continue
			var now: Vector3 = bus.position()
			# Past a hop back (4 m): only the start line is that far.
			if Vector2(now.x - last[k].x, now.z - last[k].z).length() > 6.0:
				out.resets += 1
			else:
				out.covered += Vector2(now.x - last[k].x, now.z - last[k].z).length()
			last[k] = now
			var asking: bool = bus.command != null and absf(bus.command.throttle) > 0.3
			# On its roof is `_upright`'s to answer, not a wedge.
			if asking and bus.speed() < 1.0 and bus.body().global_basis.y.y > 0.5:
				if stalled[k] == 0.0:
					began[k] = now
				stalled[k] += TICK
				if stalled[k] > out.longest_stall:
					out.longest_stall = stalled[k]
					out.stall_at = began[k]
			else:
				stalled[k] = 0.0
	await _dispose(game)
	return out
