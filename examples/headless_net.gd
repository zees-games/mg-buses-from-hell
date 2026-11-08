extends "headless_net_flashlight.gd"

## game-buses-from-hell over the wire: a real server, a real client, and a lossy loopback between
## them.


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var errors := EngineErrors.new()
	OS.add_logger(errors)

	# One physics step per frame, and a frame this suite awaits per tick. At the default of eight a
	# slow frame (the first ones, or a loaded machine) runs the bus's wheels and every other rigid
	# body several steps for one tick of the game, so when the bot's bus reaches the runner, and so
	# what every later section starts from, differs between runs of the same code.
	Engine.max_physics_steps_per_frame = 1

	print("buses-from-hell over the wire")
	print("")

	_test_the_wire()

	if await _build():
		await _test_a_client_joins()
		await _test_the_bowl_arrives()
		await _test_the_bus()
		await _test_moving()
		await _test_the_local_runner_is_predicted()
		await _test_the_hammer()
		await _test_driving()
		await _test_the_clock()
		await _test_chat()
		await _test_voice()
		await _test_a_gag()
		await _test_a_lossy_link()
		await _test_a_snapshot_in_parts()
		await _test_blind_and_beacon()
		await _test_the_flashlight_crosses()
		await _test_somebody_else_is_drawn()
		await _test_who_somebody_is_crosses()
		await _test_a_runner_who_is_out()
		await _test_a_barrel_is_drawn()
		await _test_a_crate_breaks_in_splinters()
		await _test_the_scoreboard()
		await _test_a_voted_bowl_crosses()
		await _test_the_toys_reach_the_client()
		await _test_leaving()

	_test_the_remote_workbench()

	OS.remove_logger(errors)
	# Engine errors go to stderr and change no exit code: a toy pulled out of the tree after a
	# mid-tick rebuild (dot-net history #30) printed `!is_inside_tree()` on green runs elsewhere.
	var seen := errors.seen()
	_check(seen.is_empty(), "the engine reported no error over the whole run",
		"%d: %s" % [seen.size(), ", ".join(seen.slice(0, 3))])

	BfhGame.clear_cache()
	_report_sections(_completed, _completed, SECTIONS, CHECKS)


