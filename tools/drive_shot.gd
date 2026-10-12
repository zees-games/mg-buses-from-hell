extends Node

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")

## Renders a person driving a bus, from straight above, as a contact sheet of frames a
## quarter of a second apart. What headless_run's "a bus's brakes" and "a handbrake turn"
## measure, drawn, because a number cannot say whether a slide looks like one.
##
## [codeblock]
## tools/drive_shot.sh stop        # S from 15 m/s: the brake, a standstill, then reverse
## tools/drive_shot.sh handbrake   # D and Ctrl from 12 m/s: the back end steps out
## tools/drive_shot.sh turn        # D alone from 12 m/s, to compare
## [/codeblock]
##
## The world is stepped by hand, as the suites step it, so the frames fall on the same ticks
## every run. Frames read left to right, top to bottom; the first is the moment the keys go
## down.

const TICK := 1.0 / 60.0
const FRAMES := 8
const EVERY := 15
const START := Vector3(-30.0, 1.4, 32.0)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var how := "stop"
	var out := "res://screenshots/drive.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--drive="):
			how = arg.substr(8)
		elif arg.begins_with("--out="):
			out = arg.substr(6)

	var config := BfhConfig.new()
	config.crate_count = 0
	config.barrel_count = 0
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.driver_count = 1

	var game := BfhGame.new()
	game.config = config
	game.tick_rate = 60
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 30, null)

	var driver: BfhPlayer = game.players[&"d"]
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(1.0, 0.0, 0.0)), START)
	await _step(game, 20, null)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26.0
	add_child(cam)
	cam.global_position = Vector3(-17.0, 40.0, 27.0)
	cam.look_at(Vector3(-17.0, 0.0, 27.0), Vector3(0.0, 0.0, -1.0))
	cam.current = true

	var go := DotFpsCommand.new()
	go.move = Vector2(0.0, 1.0)
	var wanted := 15.0 if how == "stop" else 12.0
	var guard := 300
	while bus.forward_speed() < wanted and guard > 0:
		await _step(game, 1, driver, go)
		guard -= 1

	var keys := DotFpsCommand.new()
	match how:
		"stop":
			keys.move = Vector2(0.0, -1.0)
		"handbrake":
			keys.move = Vector2(1.0, 0.0)
			keys.set_button(DotFpsCommand.BUTTON_CROUCH, true)
		"turn":
			keys.move = Vector2(1.0, 0.0)

	var shots: Array[Image] = []
	for f in FRAMES:
		await RenderingServer.frame_post_draw
		shots.append(get_viewport().get_texture().get_image())
		print("frame %d: %.1f m/s forward, at (%.1f, %.1f), heading %.0f deg" % [
			f, bus.forward_speed(), bus.position().x, bus.position().z,
			rad_to_deg(body.global_rotation.y)])
		await _step(game, EVERY, driver, keys)

	var w := shots[0].get_width() / 2
	var h := shots[0].get_height() / 2
	var sheet := Image.create(w * 4, h * 2, false, shots[0].get_format())
	for i in shots.size():
		var small := shots[i]
		small.resize(w, h)
		sheet.blit_rect(small, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("saved %s" % out)
	get_tree().quit()


func _step(game: BfhGame, ticks: int, driver: BfhPlayer, keys: DotFpsCommand = null) -> void:
	for _i in ticks:
		if driver != null and keys != null:
			driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
