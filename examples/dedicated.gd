extends "dedicated_exit.gd"


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell as a dedicated server")
	print("")

	var probe: Array = []
	if not _is_exit_probe():
		probe = await _run_exit_probe()

	# A member's site avatar, translated into this game's schema. The site's document is the
	# Kenney skins filed as `top.skin-c` (the site's slot.option part id); without a translation every member is stock here.
	var site_avatars = preload("res://game/bfh_avatars.gd")
	var site_doc := DotAvatar.make(&"builtin")
	site_doc.set_part(&"top", &"top.skin-c")
	site_doc.set_part(&"face", &"face.skin-k")
	var as_ours: DotAvatar = site_avatars.from_site(site_doc)
	_check(
		as_ours != null and site_avatars.schema().validate(as_ours).ok and as_ours.part_in(&"skin") == &"skin_c",
		"a member's site avatar becomes this game's, and its schema accepts it",
		str(as_ours.to_dict()) if as_ours != null else "null"
	)
	var unknown_skin := DotAvatar.make(&"builtin")
	unknown_skin.set_part(&"top", &"top.skin-r")
	unknown_skin.set_part(&"face", &"face.skin-r")
	var not_site := DotAvatar.make(&"elsewhere")
	not_site.set_part(&"top", &"top.skin-c")
	_check(
		site_avatars.from_site(unknown_skin) == null and site_avatars.from_site(not_site) == null,
		"a skin this game does not draw, or a document that is not the site's, is stock"
	)

	DotPaths.remove_tree(SERVER_DIR)
	DirAccess.make_dir_recursive_absolute(SERVER_DIR)

	await _boot()

	if server != null and server.state == DotServer.State.RUNNING:
		await _test_the_module_loads()
		_test_the_commands()
		_test_the_tunables()
		await _test_the_round_runs()
		await _test_the_bots()
		_test_the_services()
		await _test_the_live_tools()
		await _test_progress_and_spectating()
		_test_stats_report()
		await _test_who_they_are()
		await _test_loading_cover()
		_test_the_bowl_vote()
		_test_rotation_file()
		_test_finish_round_waits_for_a_live_round()
		await _test_it_unloads_cleanly()
		await _test_a_reload_leaves_one_live_link()
		await _test_ambient_cvars_reach_the_client()
		_test_no_message_preloads_itself()

	if not probe.is_empty():
		_test_exits_clean(probe)

	var sections := SECTIONS - (1 if _is_exit_probe() else 0)
	var checks := CHECKS - (EXIT_PROBE_CHECKS if _is_exit_probe() else 0)

	await _shut_down()
	DotPaths.remove_tree(SERVER_DIR)
	_report_sections(_completed, _completed, sections, checks)
