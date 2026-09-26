extends Node

const BfhArena := preload("../game/bfh_arena.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const TICK := 1.0 / 60.0

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()

func _world() -> BfhGame:
	var config := BfhConfig.new()
	config.crate_count = 12
	config.barrel_count = 3
	config.round_seconds = 120.0
	config.intermission_seconds = 0.0
	config.warmup_seconds = 0.0
	config.driver_count = 1
	var game := BfhGame.new()
	game.config = config
	game.tick_rate = 60
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	return game

func _put(player: BfhPlayer, at: Vector3) -> void:
	player.global_position = at
	player.controller.state.position = at
	player.controller.state.velocity = Vector3.ZERO

func _run() -> void:
	var starts := [null, Vector3(0, 1.4, 20), Vector3(25, 1.4, -5), Vector3(-25, 1.4, 0), Vector3(15, 1.4, 30)]
	for s in starts + [Vector3(-5.25, 1.4, -26.0)]:
		var game := _world()
		var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
		driver.is_bot = true
		var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
		game.start()
		for _i in range(8):
			game.simulate(TICK)
			await get_tree().physics_frame
		var arena := game.arena
		var deck := arena.ledge_centre()
		var stand := Vector3(0.0, arena.deck_top() + 0.05, deck.z)
		_put(runner, stand)
		var bus := game.vehicles.get_vehicle(game._bus_ids[0])
		var body := bus.body()
		if s != null:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.global_transform = Transform3D(Basis.looking_at(Vector3(-s.x, 0, -s.z).normalized()), s)
		print("=== start ", bus.position(), " foot ", arena.ramp_foot(), " road ", arena.ramp_approach(), " near ", arena._nearest_on(arena.ramp_approach(), bus.position()), " up ", arena._up_the_ramp(bus.position(), -body.global_basis.z, Vector3(0,7.5,-47)))
		var last := bus.position()
		var result := "timeout"
		for i in range(900):
			var still := DotFpsCommand.new()
			still.yaw = runner.controller.state.yaw
			runner.controller.apply_command(still)
			game.simulate(TICK)
			await get_tree().physics_frame
			var at := bus.position()
			if Vector2(at.x - last.x, at.z - last.z).length() > 3.0:
				print("  RESET at tick ", i, " from ", last)
			last = at
			if i % 30 == 0:
				print("  t=%.1f bus %s v=%.1f tgt %s runner %s alive %s" % [i * TICK, at, bus.speed(), driver.autopilot.current_waypoint() if driver.autopilot else Vector3.ZERO, runner.global_position, runner.health.alive])
			if not runner.health.alive:
				result = "killed at %.1f s" % (i * TICK)
				break
		print("  RESULT ", result, " bus ", bus.position())
		remove_child(game)
		game.free()
		await get_tree().process_frame
	get_tree().quit(0)
