extends "headless_run_flashlight.gd"
## Proves the bowl, the crates, the hammer, the barrels and the buses all actually work. Runs the sections in order.


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell headless run")
	print("")

	# `-- --only=<method>` runs that one section and nothing else, for working on it; the
	# totals are not checked. The playground's suite has the same switch.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			await call(arg.trim_prefix("--only="))
			print("")
			print("ONLY %s: %d passed, %d failed (totals not checked)" % [arg.trim_prefix("--only="), _passed, _failed])
			get_tree().quit(1 if _failed > 0 else 0)
			return

	_test_config()
	await _test_world_builds()
	await _test_bowl_layout()
	_test_every_bowl()
	_test_districts()
	await _test_driving_a_district()
	await _test_bot_pace()
	await _test_bot_pack()
	await _test_the_stacks()
	await _test_the_tank_farm()
	await _test_reach()
	await _test_the_scaffold()
	await _test_the_back_yard()
	await _test_the_second_lane()
	await _test_the_colonnade()
	await _test_the_courtyard_lanes()
	await _test_the_hook_gaps()
	await _test_up_onto_the_deck()
	await _test_sides()
	await _test_standing_on_a_crate()
	await _test_hammer()
	await _test_hammer_viewmodel()
	await _test_the_toys()
	await _test_barrel()
	await _test_bus()
	await _test_round_ends()
	await _test_a_driver_arrives_mid_round()
	await _test_bus_propulsion()
	await _test_what_a_bot_travels_at()
	await _test_bus_brakes()
	await _test_handbrake_turn()
	await _test_a_rolled_bus()
	await _test_blind_and_beacon_drawn()
	await _test_spectating()
	await _test_the_flashlight()
	await _test_the_sounds()
	await _test_progress()
	_test_settings()
	_test_pack_paths()
	await _test_help_and_menu()
	await _test_the_map_menu()
	await _test_wheel_jump()
	_test_spectate_tap()

	# Anything a section did not take down itself, before the counts are printed: a world
	# freed after `quit()` is a world the engine reports as a leak.
	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame

	BfhGame.clear_cache()
	_report_sections(_completed, _completed, SECTIONS, CHECKS)


## The document, what reads it, and the screen that changes it.
func _test_settings() -> void:
	print("a player's settings")

	var schema := BfhSettings.spec_for().make_schema()
	# reduce_motion is read by the client when the winner reveal is presented, not pushed by the menu.
	# ambient and ambient_volume are followed by the client's ambience director.
	# LEFT_TO_THE_GAME keys are applied by DotGameClient (slide sounds, DotFxRenderQuality), as in dot-menu's selftest.
	var applied := DotMenuApplier.APPLIES + DotMenuApplier.APPLIED_BY_MENU + DotMenuApplier.LEFT_TO_THE_GAME + [&"reduce_motion", &"ambient", &"ambient_volume"]
	var unapplied := schema.keys().filter(func(k: StringName) -> bool: return not applied.has(k))
	_check(
		schema.validate().ok and unapplied.is_empty() and schema.has(&"ui_volume") and schema.has(&"shake_scale"),
		"the settings document is valid, and every setting in it is applied by something",
		str(unapplied)
	)

	var fov := schema.find(&"field_of_view")
	var turn := schema.find(&"sensitivity")
	_check(
		turn != null and turn.scope == DotSettingsDef.Scope.ACCOUNT
		and fov != null and fov.scope == DotSettingsDef.Scope.SERVER_CLAMPED
		and fov.min_value == 70.0 and fov.max_value == 120.0,
		"sensitivity follows the person, and a server may cap the field of view"
	)

	# One launch saves...
	var store := DotSettingsStoreMemory.new()
	var first := BfhSettings.new()
	add_child(first)
	var _first_built := first.setup(store, false)
	var _a := first.settings.set_value(&"sensitivity", 4.0)
	var _b := first.settings.set_value(&"field_of_view", 110)
	var _c := first.settings.set_value(&"master_volume", 0.3)
	var _flushed := first.settings.flush()
	remove_child(first)
	first.free()

	# ...and the next one loads, binds, and has changed nothing.
	var look := DotFpsTunables.with_profile("legacy")
	var camera := Camera3D.new()
	add_child(camera)
	var mixed := DotAudioManager.new()
	mixed.register_as_service = false
	mixed.catalogue = DotAudioCatalogue.new()
	add_child(mixed)
	var _mixed := mixed.setup()

	var next := BfhSettings.new()
	add_child(next)
	var built := next.setup(store, true)
	next.bind_look(look)
	next.bind_camera(camera)
	next.bind_audio(mixed)

	_check(
		built.ok
		and is_equal_approx(look.mouse_sensitivity, 4.0 * DotMenuApplier.DEGREES_PER_COUNT)
		and is_equal_approx(camera.fov, 110.0)
		and is_equal_approx(mixed.mixer.master, 0.3),
		"a saved setting reaches the sampler, the camera and the mixer on load, "
		+ "though loading changed nothing",
		"turn %.4f, fov %.0f, master %.2f" % [look.mouse_sensitivity, camera.fov, mixed.mixer.master]
	)

	var _d := next.settings.set_value(&"sensitivity", 1.0)
	_check(
		is_equal_approx(look.mouse_sensitivity, DotMenuApplier.DEGREES_PER_COUNT),
		"and one changed while playing is applied as it changes",
		"%.4f" % look.mouse_sensitivity
	)

	var _e := next.settings.set_value(&"field_of_view", 200)
	_check(
		camera.fov <= 120.0,
		"a field of view past the document's bound never reaches the camera",
		"%.0f" % camera.fov
	)

	_check(
		next.menu != null and not next.is_open(),
		"the menu is built, and closed"
	)
	next.open()
	_check(
		next.is_open() and next.menu.screen.visible,
		"it opens over the bowl"
	)
	next.close()
	_check(not next.is_open() and not next.menu.screen.visible, "and closes again")

	remove_child(next)
	next.free()
	remove_child(mixed)
	mixed.free()
	remove_child(camera)
	camera.free()
	_done()


## A delivered pack's own paths: each is rebased where it is defined (`static var X := BfhPaths.rebase(...)`),
## never a bare `const`, or a crate silently fails to spawn once the game is mounted.
func _test_pack_paths() -> void:
	print("a delivered pack's own paths")

	const MOUNT := "res://dot_cloud/tmc/buses/0.1.0"
	_check(
		BfhPaths.rebase_onto(BfhContent.CRATE_SCENE, MOUNT) == MOUNT + "/props/bfh_crate.tscn",
		"a prop scene rebased onto a mount lands inside the pack"
	)

	var bare := _bare_own_paths()
	_check(bare.is_empty(), "no shipped script names this game's own file by a bare res:// path", ", ".join(bare))
	_done()


## Every bare `"res://…"` string in a SHIPPED script that names one of this game's own directories,
## as `file:line`. See the form-three check that calls it.
func _bare_own_paths() -> PackedStringArray:
	var skip := ["addons", "examples", "tools", "screenshots"]
	var owned := PackedStringArray()

	for directory: String in DirAccess.get_directories_at("res://"):
		if not directory.begins_with(".") and not skip.has(directory):
			owned.append(directory)

	var wrapped := RegEx.create_from_string("[A-Za-z0-9_]*Paths\\.rebase\\(\"res://[^\"]*\"\\)")
	var bare := RegEx.create_from_string("\"res://([^/\"]+)")
	var hits := PackedStringArray()
	var pending: Array[String] = []

	for directory: String in owned:
		pending.append("res://".path_join(directory))

	while not pending.is_empty():
		var at: String = pending.pop_back()

		for sub: String in DirAccess.get_directories_at(at):
			pending.append(at.path_join(sub))

		for file: String in DirAccess.get_files_at(at):
			if not file.ends_with(".gd"):
				continue

			var path := at.path_join(file)
			var lines := FileAccess.get_file_as_string(path).split("\n")

			for i in lines.size():
				if lines[i].strip_edges().begins_with("#"):
					continue

				for found in bare.search_all(wrapped.sub(lines[i], "", true)):
					if owned.has(found.get_string(1)):
						hits.append("%s:%d" % [path, i + 1])

	return hits
