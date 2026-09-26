extends Node
const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const TICK := 1.0 / 60.0
func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()
func _run() -> void:
	for spd in [4.0, 7.0, 10.0]:
		var config := BfhConfig.new()
		config.crate_count = 0
		config.barrel_count = 0
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
		var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
		game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
		game.start()
		for _j in range(20):
			game.simulate(TICK)
			await get_tree().physics_frame
		var bus := game.vehicles.get_vehicle(game._bus_ids[0])
		var body := bus.body()
		body.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0)), Vector3(-20, 1.4, 25))
		var xs := []
		for i in range(900):
			var k := DotFpsCommand.new()
			k.move = Vector2(1.0 if i > 120 else 0.0, 0.6 if bus.speed() < spd else 0.0)
			driver.controller.apply_command(k)
			game.simulate(TICK)
			await get_tree().physics_frame
			if i > 400:
				xs.append(bus.position())
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for p in xs:
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
		print("speed %.0f: circle extent %s -> diameter ~%.1f, %.1f (v=%.1f)" % [spd, str(mx - mn), mx.x - mn.x, mx.y - mn.y, bus.speed()])
		remove_child(game)
		game.free()
		await get_tree().process_frame
	get_tree().quit(0)
