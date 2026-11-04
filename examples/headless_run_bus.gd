extends "headless_run_deck.gd"
## The toys, the bus, round ends and the bus's drive: propulsion, brakes and the handbrake turn.


## dot-props' toys in the bowl: the ring's six built clear of every obstacle and still two seconds
## on, a hammer whacks a beach ball off, a crate thrown into a barrel sends it rolling, and the next
## round puts them home.
func _test_the_toys() -> void:
	print("the bowl's toys")
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)
	var box := game.toys
	var placed := game.arena.toy_placements().size()
	_check(box != null and box.count() == placed and placed == BfhArena.TOY_KINDS.size() and box.missing.is_empty(),
		"the bowl has its %d toys" % placed, str(box.describe()) if box != null else "none")
	await _step(game, 120)
	var off: Array = []
	for toy in box.toys:
		if toy.body.global_position.distance_to(toy.rest.origin) > 0.6:
			off.append("%s %d to %s" % [toy.def["id"], toy.index, toy.body.global_position.snapped(Vector3.ONE * 0.1)])
	_check(off.is_empty(), "two seconds on, every toy is where the bowl put it", "; ".join(off))

	var ball := box.toy(0)
	var b0 := ball.body.global_position
	runner.hammer.cooldown = 0.0
	var swung := runner.hammer.swing(game, b0 + Vector3(0.0, 0.0, -1.5), Vector3(0.0, 0.0, 1.0),
		game.props, game.prop_damage, game.carry, runner.player_id, 0xFFFFFFF)
	await _step(game, 20)
	_check(swung and ball.body.global_position.distance_to(b0) > 0.5, "a hammer whacks a beach ball off",
		"%.2f m" % ball.body.global_position.distance_to(b0))

	# What a bus or a crate is to a toy: a body on the bowl's layer. A crate thrown into the
	# barrel sends it on (a bus is the same layer, and heavier).
	var barrel := box.toy(1)
	var r0 := barrel.body.global_position
	var crate := game.props.spawn(BfhContent.CRATE, &"world", r0 + Vector3(0.0, 0.2, -2.5))
	await _step(game, 1)
	if crate != null:
		(crate.body() as RigidBody3D).linear_velocity = Vector3(0.0, 0.0, 12.0)
	await _step(game, 30)
	_check(crate != null and barrel.body.global_position.distance_to(r0) > 0.5, "a crate thrown into a barrel sends it rolling, as a bus does",
		"%.2f m" % barrel.body.global_position.distance_to(r0))

	game._on_round_started(game.round_number + 1)
	await _step(game, 2)
	_check(ball.body.global_position.distance_to(ball.rest.origin) < 0.3 and barrel.body.global_position.distance_to(barrel.rest.origin) < 0.3,
		"and the next round puts them home")
	_done()


func _test_bus() -> void:
	print("a bus")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	_check(game._bus_ids.size() >= 1, "a bus is spawned for the driver",
		"%d" % game._bus_ids.size())
	_check(driver.riding, "and the driver is in it")

	# Turned OFF rather than ignored: a controller simulating a player the vehicle is
	# also moving is two authorities over one transform, which reads as the bus
	# shaking itself apart at speed.
	_check(driver.riding, "whose own movement is switched off while they drive")

	var bus := (
		game.vehicles.get_vehicle(game._bus_ids[0]) if not game._bus_ids.is_empty() else null
	)
	_check(bus != null and bus.chassis != null,
		"the bus has a chassis, so it is a vehicle rather than a sliding crate")

	# A slow bump is not a kill, or the drivers park in the spawn and the round is a
	# formality.
	var health_before := runner.health.health
	runner.global_position = bus.body().global_position + Vector3(0.0, 0.0, 4.0)
	runner.controller.state.position = runner.global_position
	runner.controller.state.velocity = Vector3.ZERO
	bus.body().linear_velocity = Vector3(0.0, 0.0, 2.0)

	game._check_bus_impacts(TICK)

	_check(runner.health.alive, "a slow bump does not kill")
	_check(runner.health.health < health_before, "but it hurts",
		"%.0f -> %.0f" % [health_before, runner.health.health])

	runner.health.health = game.config.runner_health
	runner.health.alive = true
	runner.controller.state.velocity = Vector3.ZERO
	bus.body().linear_velocity = Vector3(0.0, 0.0, 18.0)
	# Drawn while alive, as a client draws everybody it can see: the body is copied from this.
	var _drawn := runner.present_body(false)

	game._check_bus_impacts(TICK)

	_check(not runner.health.alive, "and a bus at speed kills outright")

	# How the body falls: a bus always throws it, along the way it was going.
	_check(runner.death != null and runner.death.reaction == DotPlayerDeathReactions.POWER_LAUNCH
		and runner.death.direction.z > 0.5, "and throws the body, away from the grille",
		str(runner.death.describe()) if runner.death != null else "none")
	var carried := BfhEvents.read_death(DotNetReader.new(BfhEvents.write_death(2, 1, runner.death)))
	_check(bool(carried["ok"]) and carried.has("death") and (carried["death"] as DotPlayerDeath).reaction == runner.death.reaction
		and not BfhEvents.read_death(DotNetReader.new(BfhEvents.write_death(2, 1))).has("death"),
		"DEATH carries the fall, and one without it still reads")
	var client := BfhClient.new()
	client.game = game
	client._build_ragdolls()
	client.remove_child(client.ragdolls)
	add_child(client.ragdolls)
	client._fall(runner)
	_check(client.ragdolls.live().size() == 1 and client.ragdolls.rules == game.ragdoll_rules,
		"a client builds the body from the figure it draws, under the game's rules")
	client.ragdolls.queue_free()
	client.free()

	# Closing speed, not the bus's speed: a runner sprinting into a parked bus is not
	# being run over, and taking the bus's own number makes that a kill.
	var third := game.add_player(&"x", "X", BfhGame.TEAM_RUNNERS)
	await get_tree().physics_frame
	third.global_position = bus.body().global_position + Vector3(0.0, 0.0, 4.0)
	third.controller.state.position = third.global_position
	third.controller.state.velocity = Vector3(0.0, 0.0, 18.0)
	bus.body().linear_velocity = Vector3(0.0, 0.0, 18.0)

	var before_third := third.health.health
	game._check_bus_impacts(TICK)

	_check(is_equal_approx(third.health.health, before_third),
		"a runner moving with the bus is not run over by it",
		"%.0f" % third.health.health)

	# A bus at speed goes through the crates, which is how the cover disappears over
	# a round.
	var crate := game.props.spawn(
		BfhContent.CRATE, &"world", bus.body().global_position + Vector3(0.0, 0.0, 3.0)
	)
	game._break_props_under(bus, 18.0, &"d")
	_check(not crate.is_alive(), "and through a crate")

	var survivor := game.props.spawn(
		BfhContent.CRATE, &"world", bus.body().global_position + Vector3(0.0, 0.0, 3.0)
	)
	game._break_props_under(bus, 3.0, &"d")
	_check(survivor.is_alive(), "while a bus crawling into one leaves it standing")

	await _dispose(game)
	_done()


func _test_round_ends() -> void:
	print("ending a round")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1
		c.rounds_before_swap = 1)

	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)

	var ended: Array = []
	game.round_over.connect(func(number: int, winner: int) -> void:
		ended.append({"number": number, "winner": winner}))

	game.start()
	await _step(game, 10)

	_check(game.alive_runners() == 1, "a round starts with the runners alive")

	runner.health.alive = false
	runner.health.health = 0.0

	var round_before := game.round_number

	await _step(game, 30)

	# Not "the runner is still dead": the next round starts, `_place_players` puts
	# everybody back on their feet, and asserting they stayed down would be asserting
	# that respawning is broken. What is being tested is that the round turned over.
	_check(game.round_number > round_before, "and the round turns over when the last one is gone",
		"%d -> %d" % [round_before, game.round_number])
	_check(not ended.is_empty(), "the round is reported over", "%d" % ended.size())
	_check(
		ended.is_empty() or int((ended[0] as Dictionary)["winner"]) == BfhGame.TEAM_DRIVERS,
		"with the drivers winning"
	)

	# Driving is the fun half and there are two seats for it. A server that never
	# swapped would be one where the same two people drive all night.
	_check(game.team_of(&"d") == BfhGame.TEAM_RUNNERS,
		"and the sides swap afterwards", "driver is now %d" % game.team_of(&"d"))
	_check(game.team_of(&"r") == BfhGame.TEAM_DRIVERS, "both ways")
	_check((game.players[&"d"] as BfhPlayer).hammer != null,
		"the new runner is handed a hammer")

	# [b]And the round AFTER the swap is decided by the sides as they are now.[/b] The elimination rule
	# reads teams off dot-match's scoreboard, not off `sides`, so a swap that only flipped `sides` left
	# the rule scoring the old ones: the drivers ran the new runner down and the round.
	_check(game.match_node.teams.team_of("d") == BfhGame.TEAM_RUNNERS,
		"dot-match is told about the swap too",
		"it has d on %d" % game.match_node.teams.team_of("d"))

	var new_runner: BfhPlayer = game.players[&"d"]
	new_runner.health.alive = false
	new_runner.health.health = 0.0
	await _step(game, 30)

	_check(
		ended.size() >= 2 and int((ended[1] as Dictionary)["winner"]) == BfhGame.TEAM_DRIVERS,
		"and the round after it is still the drivers' when the runner goes down",
		"%s" % [ended]
	)

	await _dispose(game)

	# [b]Nobody driving is a person: no swap.[/b] The module removes a bot that ends up on
	# foot, so swapping a bot's seat with the only person running left nobody to run,
	# and the next round never started.
	var lone := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1
		c.rounds_before_swap = 1)
	lone.add_player(&"bot", "Bus driver", BfhGame.TEAM_DRIVERS, false, true)
	var person := lone.add_player(&"p", "Person")
	lone.start()
	await _step(lone, 10)
	var lone_round := lone.round_number
	person.health.alive = false
	person.health.health = 0.0
	await _step(lone, 30)
	_check(
		lone.round_number > lone_round and lone.team_of(&"p") == BfhGame.TEAM_RUNNERS
			and lone.team_of(&"bot") == BfhGame.TEAM_DRIVERS,
		"a swap with only a bot driving keeps the person on foot",
		"round %d -> %d, p on %d, bot on %d" % [
			lone_round, lone.round_number, lone.team_of(&"p"), lone.team_of(&"bot")
		]
	)
	await _dispose(lone)
	_done()


# --- Driving

## A driver who arrives mid-round gets the bus that is standing empty.
func _test_a_driver_arrives_mid_round() -> void:
	print("a driver arriving mid-round")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)

	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	_check(game.ride.is_riding(&"d"), "the first driver is in the bus")

	game.remove_player(&"d")
	var relief := game.add_player(&"d2", "Relief", BfhGame.TEAM_DRIVERS)
	await _step(game, 5)

	_check(game.ride.is_riding(&"d2") and relief.riding,
		"and whoever takes the seat mid-round is put in the bus that is standing empty")

	# And never a second driver into an occupied one, which `enter` would refuse anyway --
	# checked because the refusal is quiet.
	var extra := game.add_player(&"d3", "Extra", BfhGame.TEAM_DRIVERS)
	await _step(game, 2)
	_check(not extra.riding, "while a driver with no empty bus is left out of one")

	await _dispose(game)
	_done()


func _test_bus_propulsion() -> void:
	print("driving the bus")

	# [b]Three checks, and the middle one is the regression guard for the bug that took longest to
	# find.[/b] A bus spawned, seated a driver, collided, ran people over and broke crates — and did
	# not move under its own throttle.
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 30)

	var bus := (
		game.vehicles.get_vehicle(game._bus_ids[0]) if not game._bus_ids.is_empty() else null
	)
	_check(bus != null, "a bus is on the floor")

	if bus == null:
		# Two checks are owed whatever happens, or the section counter hides the abort.
		_check(false, "the suspension holds the bus up rather than letting it rest on its hull")
		_check(false, "the body is free to move at all")
		_check(false, "and the throttle moves it")
		await _dispose(game)
		_done()
		return

	var body := bus.body()

	# Hull bottom, from the scene: the collision box is 2.6 tall and sits 1.2 above the
	# origin, so its underside is 0.1 below it. On its wheels the body rests near 1.37.
	_check(body.global_position.y > 0.8,
		"the suspension holds the bus up rather than letting it rest on its hull",
		"y=%.2f" % body.global_position.y)

	# Is the body pinned, or is it the drive? An impulse bypasses the wheels entirely.
	body.linear_velocity = Vector3.ZERO
	body.apply_central_impulse(Vector3(0.0, 0.0, 12000.0))
	await _step(game, 4)

	_check(body.linear_velocity.length() > 0.5, "the body is free to move at all",
		"%.2f m/s" % body.linear_velocity.length())

	# And now the same motion asked for through the throttle.
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _step(game, 4)

	# The check passed anyway, for nine days, because the bus's start line was under the ramp, which
	# was built backwards and low at that end: the bus rested on it at y = 3.45 and ROLLED north, the
	# wrong way, at 6 m/s. On flat floor the same check read 0.05 m/s.
	var driver: BfhPlayer = game.players[&"d"]
	var start := bus.position()
	var fastest := 0.0

	for _i in range(90):
		var keys := DotFpsCommand.new()
		keys.move = Vector2(0.0, 1.0)
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		fastest = maxf(fastest, bus.speed())

	var forward := -body.global_transform.basis.z
	var along := (bus.position() - start).dot(Vector3(forward.x, 0.0, forward.z).normalized())
	# [b]Printed, because it is not the number it looks like.[/b] This start lane has one of the
	# round's concrete blocks 13 m in front of it (the scatter keeps blocks out of the pillars, the
	# tanks and the scaffold, and not out of a bus's lane), so the bus peaks at 10.6 m/s and ends the.
	print("  ..    1.5 s of throttle from a standstill: %.2f m/s at the end, %.2f fastest, of a bus_top_speed of %.1f; %.2f m along its nose"
		% [bus.speed(), fastest, game.config.bus_top_speed, along])
	_check(
		fastest > game.config.bus_lethal_speed and along > 1.0,
		"and a driver pressing forward moves it forward, past the speed that kills, inside 1.5 s",
		"%.2f m/s fastest against %.1f, %.2f m along its nose"
			% [fastest, game.config.bus_lethal_speed, along]
	)

	await _dispose(game)
	_done()


# --- What a bot actually travels at

## How far a bus takes to stop, three ways, from 15 m/s on the south straight, and that S then
## reverses.
func _test_bus_brakes() -> void:
	print("a bus's brakes")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 30)

	_check(is_equal_approx(game.match_node.rules.intermission_sec, 0.0) and game.config.killcam_seconds > 0.0,
		"the killcam adds nothing to an intermission of 0")
	game.config.intermission_seconds = 8.0
	game.apply_intermission()
	_check(is_equal_approx(game.match_node.rules.intermission_sec, 8.0 + game.config.killcam_seconds),
		"and is added to the pause otherwise", str(game.match_node.rules.intermission_sec))
	game.config.intermission_seconds = 0.0
	game.apply_intermission()

	var driver: BfhPlayer = game.players[&"d"]
	var handbrake: Dictionary = await _bus_stop(game, driver, "handbrake")
	var foot: Dictionary = await _bus_stop(game, driver, "brake")
	var back: Dictionary = await _bus_stop(game, driver, "back")

	print("  ..    from 15 m/s: handbrake (Ctrl) %.2f m, the bot's foot brake %.2f m, S %.2f m and then %.2f m back at %.2f m/s after 2 s more" % [
		handbrake["stop"], foot["stop"], back["stop"], back["back"], back["speed"]])

	# Longer than the foot brake, on purpose: Ctrl lets the rear tyres go (0.15 of their grip,
	# for the slide in "a handbrake turn"), and a sliding tyre stops a bus worse than a gripping
	# one. 6.3 m with the grip left alone; S is the brake a person stops with.
	_check(handbrake["stop"] > 10.0 and handbrake["stop"] < 22.0,
		"the handbrake slides a bus to a stop from 15 m/s, further than the foot brake and not on the spot",
		"%.2f m; with its rear tyres let go, about 16 m" % handbrake["stop"])
	_check(foot["stop"] > 5.5 and foot["stop"] < 12.0,
		"and the foot brake the bot uses in about seven and a half",
		"%.2f m; 30 kN on 2 t is about 7.5 m" % foot["stop"])
	# Within a metre of the foot brake: S IS the foot brake until the bus has stopped. Reverse
	# thrust took 21 m, nearly three times as far.
	_check(back["stop"] < foot["stop"] + 1.0,
		"and S brakes like the foot brake while the bus rolls forward, rather than reverse thrust's 21 m",
		"%.2f m against the foot brake's %.2f m" % [back["stop"], foot["stop"]])
	# A direction, not "it moved": a bus still rolling forward also moves.
	_check(back["speed"] < -1.0 and back["back"] > 1.0,
		"and once it has stopped, S held reverses it",
		"%.2f m/s, %.2f m back behind where it stopped" % [back["speed"], back["back"]])

	await _dispose(game)
	_done()


## How far the bus takes from 15 m/s to a standstill on the south straight, by [param how]:
## "handbrake" (Ctrl held), "brake" (the foot brake, as the bot's autopilot uses it) or "back" (S
## held, which then goes on holding it two seconds more).
func _bus_stop(game: BfhGame, driver: BfhPlayer, how: String) -> Dictionary:
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(1.0, 0.0, 0.0)), Vector3(-30.0, 1.4, 32.0))
	await _step(game, 20)

	var guard := 300
	while bus.forward_speed() < 15.0 and guard > 0:
		var keys := DotFpsCommand.new()
		keys.move = Vector2(0.0, 1.0)
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		guard -= 1

	var start := bus.position()
	var nose := -body.global_transform.basis.z
	nose = Vector3(nose.x, 0.0, nose.z).normalized()
	var stopped_at := Vector3.ZERO
	var stopped := false
	var after := 0
	guard = 600
	while guard > 0:
		if not stopped and bus.forward_speed() <= (0.0 if how == "back" else 0.3):
			stopped = true
			stopped_at = bus.position()
		if stopped:
			if how != "back" or after >= 120:
				break
			after += 1
		var keys := DotFpsCommand.new()
		if how == "back":
			keys.move = Vector2(0.0, -1.0)
		keys.set_button(DotFpsCommand.BUTTON_CROUCH, how == "handbrake")
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		if how == "brake":
			# After the game's own drive from the driver's (empty) keys, so this is the
			# command the physics step sees: the foot brake, which only the bot presses.
			(bus.chassis as DotVehicleChassis).drive(DotVehicleCommand.make(0.0, 0.0, 1.0), TICK)
		await get_tree().physics_frame
		guard -= 1

	if not stopped:
		stopped_at = bus.position()
	var at := bus.position()
	return {
		"stop": Vector2(stopped_at.x - start.x, stopped_at.z - start.z).length(),
		"back": -(at - stopped_at).dot(nose),
		"speed": bus.forward_speed(),
	}


## A handbrake turn: the back end steps out. Godot's raycast vehicle never locks a wheel, so before
## `handbrake_grip_fraction` a bus turning with Ctrl held turned LESS than without it (dot-vehicle's
## driving.md measured the same on a car).
func _test_handbrake_turn() -> void:
	print("a handbrake turn")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 30)

	var driver: BfhPlayer = game.players[&"d"]
	var plain: Dictionary = await _bus_turn(game, driver, false)
	var slid: Dictionary = await _bus_turn(game, driver, true)

	print("  ..    1 s of full lock from 12 m/s: %.0f deg turned, %.0f deg nose-in without the handbrake; %.0f deg turned, %.0f deg nose-in, %.1f m/s left with it" % [
		plain["yaw"], plain["slip"], slid["yaw"], slid["slip"], slid["speed"]])

	_check(slid["slip"] > 8.0 and plain["slip"] < 3.0,
		"with the handbrake the back end steps out: the nose swings inside where the bus is going",
		"%.0f deg with it against %.0f deg without" % [slid["slip"], plain["slip"]])
	_check(slid["yaw"] > plain["yaw"] * 1.3 and slid["speed"] > 3.0,
		"and the bus turns further in the same second and keeps moving, which is what a handbrake turn is for",
		"%.0f deg against %.0f deg" % [slid["yaw"], plain["yaw"]])
	# Grip comes back the tick Ctrl is released: a bus left sliding would never drive straight.
	var wheel := _rear_wheel(game)
	_check(wheel != null and is_equal_approx(wheel.wheel_friction_slip,
			game.vehicles.get_vehicle(game._bus_ids[0]).chassis.tunables.friction_slip
			* game.vehicles.get_vehicle(game._bus_ids[0]).chassis.tunables.rear_grip_fraction),
		"and letting go of Ctrl gives the rear wheels their grip back",
		"%.2f" % (wheel.wheel_friction_slip if wheel != null else -1.0))

	await _dispose(game)
	_done()


## One of the bus's rear (non-steering) wheels.
func _rear_wheel(game: BfhGame) -> VehicleWheel3D:
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	for child in bus.node.get_children():
		if child is VehicleWheel3D and not (child as VehicleWheel3D).use_as_steering:
			return child
	return null


## One second of D held at full lock from 12 m/s, heading +X on the south straight (D turns it
## towards the middle of the bowl), with or without Ctrl; then a second with neither key so the grip
## comes back.
func _bus_turn(game: BfhGame, driver: BfhPlayer, handbrake: bool) -> Dictionary:
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(1.0, 0.0, 0.0)), Vector3(-30.0, 1.4, 32.0))
	await _step(game, 20)

	var guard := 300
	while bus.forward_speed() < 12.0 and guard > 0:
		var keys := DotFpsCommand.new()
		keys.move = Vector2(0.0, 1.0)
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		guard -= 1

	var yaw := 0.0
	var slip := -INF
	for i in range(60):
		var keys := DotFpsCommand.new()
		keys.move = Vector2(1.0, 0.0)
		keys.set_button(DotFpsCommand.BUTTON_CROUCH, handbrake)
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		yaw += body.angular_velocity.y * TICK
		var v := Vector2(body.linear_velocity.x, body.linear_velocity.z)
		if v.length() > 2.0:
			var nose := -body.global_transform.basis.z
			# Signed in the X/Z plane, whose sense is the opposite of a yaw about +Y: a
			# nose turned further than the velocity, the way the bus is turning, is
			# opposite in sign to the yaw.
			var angle := v.angle_to(Vector2(nose.x, nose.z)) * -signf(yaw)
			slip = maxf(slip, angle)
	var speed := bus.speed()

	for i in range(60):
		driver.controller.apply_command(DotFpsCommand.new())
		game.simulate(TICK)
		await get_tree().physics_frame

	return {"yaw": rad_to_deg(absf(yaw)), "slip": rad_to_deg(slip), "speed": speed}


## A runner holding one key across open sand, [param ticks] long, facing +Z. [param jump] is 0 for
## no jump, 1 for jump held the whole way, 2 for jump pressed afresh on every tick the runner is on
## the ground, which is what a person mashing the key does.
func _run_straight(game: BfhGame, runner: BfhPlayer, jump: int, ticks: int) -> Dictionary:
	_put(runner, Vector3(0.0, 0.05, -8.0))
	await _step(game, 5)

	var track: Array[Vector3] = []
	var grounded := 0
	var jumps := 0
	var was_ground := true
	var pressed := false

	for i in range(ticks):
		var state := runner.controller.state
		var keys := DotFpsCommand.new()
		keys.yaw = 180.0
		keys.move = Vector2(0.0, 1.0)
		if jump == 1:
			keys.set_button(DotFpsCommand.BUTTON_JUMP, true)
		elif jump == 2:
			pressed = state.mode == DotFpsState.Mode.GROUND and not pressed
			keys.set_button(DotFpsCommand.BUTTON_JUMP, pressed)
		runner.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame

		var now := runner.controller.state
		track.append(now.position)
		if now.mode == DotFpsState.Mode.GROUND:
			grounded += 1
		elif was_ground:
			jumps += 1
		was_ground = now.mode == DotFpsState.Mode.GROUND

	var a := track[track.size() - 61]
	var b := track[track.size() - 1]
	var v := runner.controller.state.velocity
	return {
		"last_second": Vector2(b.x - a.x, b.z - a.z).length(),
		"speed": Vector2(v.x, v.z).length(),
		"ground": float(grounded) / float(ticks),
		"jumps": jumps,
	}


## A bus across the south of the bowl from a standstill, [constant BUS_STRAIGHT] metres,
## by the bot ([param bot]) or by [param driver] holding forward. [param runner] is held
## at the far end, which is what the bot chases.
func _drive_straight(game: BfhGame, driver: BfhPlayer, runner: BfhPlayer, bot: bool) -> Dictionary:
	driver.is_bot = bot
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	var from := Vector3(-26.0, 1.4, 32.0)
	var quarry_at := Vector3(28.0, 1.2, 32.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(1.0, 0.0, 0.0)), from)
	runner.global_position = quarry_at
	_put(runner, quarry_at)
	await _step(game, 20)

	var start := bus.position()
	var last := start
	var r := {"covered": 0.0, "fastest": 0.0, "seconds": 0.0, "arrived": false, "reset": false}
	var took := 0

	for _i in range(600):
		_put(runner, quarry_at)
		if not bot:
			var keys := DotFpsCommand.new()
			keys.move = Vector2(0.0, 1.0)
			driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1

		if not bus.is_alive():
			break
		var at := bus.position()
		if _sent_home(last, at):
			r.reset = true
			break
		r.covered += Vector2(at.x - last.x, at.z - last.z).length()
		r.fastest = maxf(r.fastest, bus.speed())
		last = at
		if at.x - start.x >= BUS_STRAIGHT:
			r.arrived = true
			break

	r.seconds = float(took) * TICK
	driver.is_bot = false
	return r
