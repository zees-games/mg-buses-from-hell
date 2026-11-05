extends "headless_run_bus.gd"
## Spectating, sounds and progress.


## What a bot on foot and a bot in a bus actually travel at, beside the numbers the configuration
## says they should.
func _test_what_a_bot_travels_at() -> void:
	print("what a bot actually travels at")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	# The runner's own tunables, which are what `BfhPlayer.tunables_for` built from the
	# config: `runner_speed` read through the thing that moves them, not the cvar.
	var top := runner.controller.tunables.max_speed
	var air := runner.controller.tunables.max_air_wish_speed

	var run := await _run_straight(game, runner, 0, 180)
	var held := await _run_straight(game, runner, 1, 180)
	var mashed := await _run_straight(game, runner, 2, 180)

	for row in [["holding forward", run], ["holding forward and jump", held],
			["holding forward and pressing jump on every landing", mashed]]:
		var r: Dictionary = row[1]
		print("  ..    %s: %.2f m/s at the end, %.2f m in the last second, of a max_speed of %.2f (air cap %.2f); %d jumps, %.0f%% of ticks on the ground"
			% [row[0], r.speed, r.last_second, top, air, r.jumps, r.ground * 100.0])

	_check(
		absf(run.speed - top) < 0.05 and run.last_second > top * 0.98,
		"a runner bot holding forward travels at runner_speed",
		"%.2f m/s, %.2f m in a second, of %.2f" % [run.speed, run.last_second, top]
	)
	# [b]A held jump is one jump here.[/b] Auto-hop is off, so the key has to come up before it jumps
	# again, and a bot that held it would run the rest of the way at speed — which is what makes
	# `_run_route`'s "hold it near a face" safe in this game when it is not in the auto-hop ones.
	_check(
		held.jumps == 1 and held.last_second > top * 0.98,
		"holding jump as well jumps once and then runs at it",
		"%d jumps, %.2f m in the last second" % [held.jumps, held.last_second]
	)
	# [b]And jumping every landing is not faster, which is Decision 4.[/b] Friction on the
	# landing tick and a %.1f m/s air cap: a runner who chains hops covers no more ground
	# than one who runs, so there is no outrunning a bus by hopping.
	_check(
		mashed.jumps >= 3 and mashed.last_second <= top * 1.02,
		"and a bot jumping on every landing is no faster than one running",
		"%d jumps, %.2f m in the last second, of %.2f" % [mashed.jumps, mashed.last_second, top]
	)

	# --- A bus, across the bowl, by the bot and by a person
	var bus_top := game.config.bus_top_speed
	var by_hand := await _drive_straight(game, driver, runner, false)
	var by_bot := await _drive_straight(game, driver, runner, true)

	for row in [["a person holding the throttle", by_hand], ["the bot, chasing", by_bot]]:
		var r: Dictionary = row[1]
		print("  ..    %s: %.1f m covered of a %.0f m straight in %.2f s%s, %.2f m/s average, %.2f m/s fastest, of a bus_top_speed of %.1f"
			% [row[0], r.covered, BUS_STRAIGHT, r.seconds,
				"" if r.arrived else " WITHOUT ARRIVING", r.covered / r.seconds, r.fastest,
				bus_top])

	_check(by_hand.arrived and by_hand.fastest > bus_top * 0.95,
		"a person holding the throttle reaches bus_top_speed on open floor",
		"%.2f of %.1f m/s" % [by_hand.fastest, bus_top])
	_check(by_bot.arrived and not by_bot.reset, "a bot bus covers a straight of open floor",
		"%.1f m in %.2f s%s" % [by_bot.covered, by_bot.seconds,
			", sent home" if by_bot.reset else ""])
	_check(
		by_hand.arrived and by_bot.seconds <= by_hand.seconds * 1.05,
		"as fast as a person holding the throttle down the same straight",
		"%.2f s against %.2f s" % [by_bot.seconds, by_hand.seconds]
	)

	await _dispose(game)
	_done()


# --- A runner who is out

## Where a runner who has been run down looks, decided by the authority.
func _test_spectating() -> void:
	print("a runner who is out, and where they look")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var out := game.add_player(&"r1", "Out", BfhGame.TEAM_RUNNERS)
	var _up := game.add_player(&"r2", "Up", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	var spectate := game.spectate
	_check(
		spectate != null and spectate.manager != null and spectate.manager.authoritative,
		"an authoritative world has a spectator manager that decides"
	)

	if spectate == null or driver.ridden == null:
		for _i in range(19):
			_check(false, "(no spectate, or no bus to be run over by)")
		await _dispose(game)
		_done()
		return

	var refused := spectate.request(&"r1", BfhSpectate.ASK_NEXT)
	_check(
		not refused.ok and not spectate.is_spectating(&"r1"),
		"a runner who is up is playing, and asking to watch is refused",
		refused.error.message if not refused.ok else "it was allowed"
	)

	var bus := driver.ridden
	game._bus_hit(out, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	var eye := spectate.camera_for(&"r1")
	# [b]At the bus's CAB, which is what the death camera looks at[/b] (`pose_of` the killer, 3.8 m
	# up), not at the body's origin under it.
	var to_bus := (spectate.pose_of("d").origin - eye.origin).normalized()
	_check(
		not out.health.alive
		and spectate.mode_of(&"r1") == DotSpectatorView.Mode.DEATH_CAM
		and spectate.target_of(&"r1") == &"d"
		and (-eye.basis.z).dot(to_bus) > 0.95,
		"run over, they look from where they fell at the bus that did it",
		"%s, facing %.2f of the way to the bus" % [spectate.describe_view(&"r1"), (-eye.basis.z).dot(to_bus)]
	)

	await _step(game, int(BfhSpectate.DEATH_CAM_SEC * 60.0) + 2)
	var cab := spectate.camera_for(&"r1").origin
	_check(
		spectate.mode_of(&"r1") == DotSpectatorView.Mode.FREEZE_CAM
		and spectate.target_of(&"r1") == &"d"
		and cab.distance_to(bus.global_position) < 5.0
		and cab.distance_to(driver.global_position) > 5.0,
		"then from the CAB of that bus, not from where its driver sat down",
		"%s, %.1f m from the bus, %.1f m from the driver's own body" % [
			spectate.describe_view(&"r1"),
			cab.distance_to(bus.global_position),
			cab.distance_to(driver.global_position),
		]
	)

	await _step(game, int(BfhSpectate.FREEZE_CAM_SEC * 60.0) + 2)
	await _spectate_follow(game, spectate, out)


## Following somebody up: the first target, the list, a click and the chase camera.
func _spectate_follow(game: BfhGame, spectate: BfhSpectate, out: BfhPlayer) -> void:
	var first := spectate.target_of(&"r1")
	_check(
		spectate.mode_of(&"r1") == DotSpectatorView.Mode.FIRST_PERSON
		and (first == &"d" or first == &"r2"),
		"and then somebody to follow, through their eyes",
		spectate.describe_view(&"r1")
	)
	_check(
		spectate.manager.targets_for("r1") == PackedStringArray(["d", "r2"]),
		"anybody up may be watched, the bus included, and never themselves",
		str(spectate.manager.targets_for("r1"))
	)

	var clicked := spectate.request(&"r1", BfhSpectate.ASK_NEXT)
	var second := spectate.target_of(&"r1")
	_check(
		clicked.ok and second != first and (second == &"d" or second == &"r2"),
		"a click moves them to the next",
		"%s -> %s" % [first, second]
	)

	spectate.manager.watch("r1", "r2")
	var eyes := spectate.pose_of("r2").origin
	var viewed := spectate.request(&"r1", BfhSpectate.ASK_VIEW)
	var behind := spectate.camera_for(&"r1").origin
	_check(
		viewed.ok and spectate.mode_of(&"r1") == DotSpectatorView.Mode.CHASE
		and behind.distance_to(eyes) > 5.0 and behind.distance_to(eyes) < 10.0,
		"space puts the camera behind them rather than in their head",
		"%s, %.1f m from their eyes" % [spectate.describe_view(&"r1"), behind.distance_to(eyes)]
	)

	var line := BfhHud.watching_line(game, out)
	_check(
		line.contains("Up") and line.contains("click"),
		"and the HUD says whose eyes, and how to change them",
		line
	)

	await _spectate_roam(game, spectate, out)


## Free roam: on by default, entered by the ask, flown at the cvar's speed, left by the same ask.
func _spectate_roam(game: BfhGame, spectate: BfhSpectate, out: BfhPlayer) -> void:
	# --- Free roam: on by default, the server's call, the restriction wins silently.
	var rules := spectate.manager.rules
	_check(
		rules.allow_roaming and rules.force_camera == 0 and rules.roaming_permitted()
		and spectate.can_roam(&"r1"),
		"free roam is on by default and the key is offered",
		"allow=%s force=%d" % [rules.allow_roaming, rules.force_camera]
	)

	var entered := spectate.request(&"r1", BfhSpectate.ASK_ROAM)
	_check(
		entered.ok and spectate.is_roaming(&"r1") and spectate.is_spectating(&"r1"),
		"the roam ask enters a free camera",
		spectate.describe_view(&"r1")
	)
	_check(
		BfhHud.watching_line(game, out).contains("free camera"),
		"and the HUD names the free camera",
		BfhHud.watching_line(game, out)
	)

	var fly := DotSpectatorFreeCam.new()
	fly.rules = rules
	fly.seed_from(spectate.camera_for(&"r1"))
	var flown := fly.step(Vector3(0.0, 0.0, 1.0), false, false, 1.0).origin.distance_to(
		spectate.camera_for(&"r1").origin
	)
	_check(
		absf(flown - rules.roam_speed) < 0.5,
		"the free camera flies at mp_freeroam_speed",
		"%.1f m in a second at %.1f" % [flown, rules.roam_speed]
	)

	await _step(game, 2)
	_check(
		out.input_off,
		"a roamer's body is not walked by the keys that fly the camera (command zeroed)"
	)

	var left := spectate.request(&"r1", BfhSpectate.ASK_ROAM)
	_check(
		left.ok and not spectate.is_roaming(&"r1") and spectate.is_spectating(&"r1"),
		"the same ask leaves it, back onto a player",
		spectate.describe_view(&"r1")
	)

	await _spectate_roam_refused(game, spectate, out)


## The server's cvars against the free camera: off refuses, forcecamera wins, off mid-roam returns.
func _spectate_roam_refused(game: BfhGame, spectate: BfhSpectate, out: BfhPlayer) -> void:
	var rules := spectate.manager.rules
	var _off := rules.set_cvar("mp_freeroam", "0")
	var refused_off := spectate.request(&"r1", BfhSpectate.ASK_ROAM)
	_check(
		not refused_off.ok and not spectate.is_roaming(&"r1") and not spectate.can_roam(&"r1"),
		"mp_freeroam 0 refuses the free camera",
		refused_off.error.message if not refused_off.ok else "it was allowed"
	)
	var _on := rules.set_cvar("mp_freeroam", "1")

	var _own_side := rules.set_cvar("mp_forcecamera", "1")
	var refused_forced := spectate.request(&"r1", BfhSpectate.ASK_ROAM)
	_check(
		not refused_forced.ok and not spectate.is_roaming(&"r1"),
		"mp_forcecamera 1 refuses it too: the restriction wins",
		refused_forced.error.message if not refused_forced.ok else "it was allowed"
	)
	var _anybody := rules.set_cvar("mp_forcecamera", "0")

	var _again := spectate.request(&"r1", BfhSpectate.ASK_ROAM)
	var _off_mid := rules.set_cvar("mp_freeroam", "0")
	await _step(game, 3)
	_check(
		_again.ok and not spectate.is_roaming(&"r1") and spectate.is_spectating(&"r1"),
		"mp_freeroam 0 mid-roam returns the roamer to a player",
		spectate.describe_view(&"r1")
	)
	var _restored := rules.set_cvar("mp_freeroam", "1")

	await _spectate_leaves(game, spectate, out)

	await _dispose(game)
	_done()


## A target who leaves, and the new round that follows when nobody on the side is up.
func _spectate_leaves(game: BfhGame, spectate: BfhSpectate, out: BfhPlayer) -> void:
	# The target leaves. dot-spectate picks the replacement from the participants, so the
	# world has to have dropped them first or the leaver is picked again.
	game.remove_player(&"r2")
	_check(
		spectate.target_of(&"r1") == &"d",
		"a target who leaves hands the camera to somebody still there",
		spectate.describe_view(&"r1")
	)

	# Nobody up on the runners' side: the round turns over, and a round is a new body.
	await _step(game, 30)
	_check(
		not spectate.is_spectating(&"r1") and out.health.alive,
		"a new round is everybody's new body, so nobody is watching any more",
		spectate.describe_view(&"r1")
	)


# --- What the bowl sounds like

## The catalogue, the stand-ins, and every noise reaching a client's ears.
func _test_the_sounds() -> void:
	print("what the bowl sounds like")
	_sounds_catalogue_checks()

	# The world, and a client's ears on it.
	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Arr", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	var audio := BfhAudio.new()
	add_child(audio)
	var built := audio.setup(game, func() -> BfhPlayer: return runner)
	var sink := audio.audio.sink as DotAudioSinkNull if audio.audio != null else null
	_check(
		built.ok and sink != null,
		"headless, a client's audio builds on the sink that writes down what it would play",
		str(built.error) if not built.ok else ""
	)

	if sink == null:
		for _i in range(8):
			_check(false, "(no sink to listen on)")
		remove_child(audio)
		audio.free()
		await _dispose(game)
		_done()
		return

	var heard: Array[StringName] = []
	game.noise.connect(func(id: StringName, _at: Vector3) -> void: heard.append(id))

	await _sounds_hammer(game, runner, audio, heard)
	_sounds_horn_and_bump(game, driver, runner, heard)
	await _sounds_reached_the_ears(game, sink)
	_sounds_engine(game, driver, audio, sink)

	remove_child(audio)
	audio.free()
	await _dispose(game)
	_done()


## The catalogue, the stand-in voices and the pack paths: no world needed.
func _sounds_catalogue_checks() -> void:
	var catalogue := BfhSounds.catalogue()
	var recipes := BfhSounds.sound_recipes()
	_check(catalogue.validate().ok, "the catalogue is a document dot-audio accepts")

	# dot-audio's stock footsteps and beds are files the addon ships, so they need no stand-in.
	var stock := DotAudioStock.ids()
	var silent := PackedStringArray()
	for id in catalogue.ids():
		if not recipes.has(id) and not stock.has(id):
			silent.append(String(id))
	_check(silent.is_empty(), "every sound has a stand-in voice, so none is silent for ever", str(silent))

	var orphans := PackedStringArray()
	for id: Variant in recipes.keys():
		if not catalogue.has(StringName(id)):
			orphans.append(str(id))
	_check(orphans.is_empty(), "and every stand-in names a sound the catalogue has", str(orphans))

	var unsent := BfhSounds.WORLD.filter(func(id: StringName) -> bool: return not catalogue.has(id))
	_check(
		unsent.is_empty() and BfhSounds.WORLD.size() <= (1 << BfhSounds.WORLD_BITS),
		"every noise a server sends by index is catalogued, and the list fits its bits",
		str(unsent)
	)

	# Inside a pack. Built in, the root is `res://` and every path is under it whatever the
	# code says, so the question is asked with a mount prefix: see BfhPaths.rebase_onto.
	var mount := "res://dot_cloud/buses/9"
	var outside := PackedStringArray()
	for def in BfhSounds.catalogue(mount).defs:
		# Except an addon's own files (dot-player-char's death sounds): an addon is the host's,
		# delivered as an addon pack under its own res://addons/ path, never inside this one.
		if def.path.begins_with("res://addons/"):
			continue
		if not def.path.begins_with(mount + "/audio/"):
			outside.append(def.path)
	_check(
		outside.is_empty(),
		"inside a pack, every sound's path is under the pack's own root, not the host's",
		str(outside)
	)

	var bank := DotAudioSynth.bank(catalogue, recipes)
	var unbaked := PackedStringArray()
	for id in catalogue.ids():
		if not bank.has(id) and not stock.has(id):
			unbaked.append(String(id))
	_check(unbaked.is_empty(), "the synthesiser bakes a stand-in for every one", str(unbaked))


## Hammer blows on nothing, a crate and a concrete block, and what each sounds like.
func _sounds_hammer(game: BfhGame, runner: BfhPlayer, audio: BfhAudio, heard: Array[StringName]) -> void:
	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF
	audio.present(0.0, origin)
	# The swing is heard from the swinger's eyes, so the swinger is put where the listener
	# is. Left where the round scattered them, the swing is culled for distance — which is
	# dot-audio doing its job, and was this check's first failure.
	_put(runner, Vector3(0.0, 0.1, 0.4))

	runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard == [BfhSounds.HAMMER_SWING],
		"a hammer swung at nothing is a swing and nothing else",
		str(heard)
	)

	heard.clear()
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		runner.hammer.cooldown = 0.0
		runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard.count(BfhSounds.HAMMER_HIT) == 3 and heard.count(BfhSounds.CRATE_SHOVE) == 2
		and heard.count(BfhSounds.CRATE_BREAK) == 1,
		"three blows on a crate: three hits, two shoves and then the break",
		str(heard)
	)

	heard.clear()
	var block := game.props.spawn(BfhContent.BLOCK, &"world", Vector3(0.0, 0.5, 4.0))
	block.body().freeze = true
	await _step(game, 2)
	runner.hammer.cooldown = 0.0
	runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard.has(BfhSounds.HAMMER_HIT) and not heard.has(BfhSounds.CRATE_SHOVE),
		"a concrete block takes the blow and does not scrape, because it did not move",
		str(heard)
	)



## The horn, and a bump against a flattening.
func _sounds_horn_and_bump(game: BfhGame, driver: BfhPlayer, runner: BfhPlayer, heard: Array[StringName]) -> void:
	heard.clear()
	var sounded := game.sound_horn(driver)
	var again := game.sound_horn(driver)
	_check(
		sounded and not again and heard == [BfhSounds.BUS_HORN],
		"a driver's horn sounds, and not again on the same tick however hard it is pressed",
		str(heard)
	)

	heard.clear()
	game._bus_hit(runner, &"d", 2.0, Vector3(0.0, 0.0, 1.0))
	game._bus_hit(runner, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	_check(
		heard == [BfhSounds.RUNNER_HIT, BfhSounds.RUNNER_DOWN],
		"a bump is a hit and a flattening is somebody going down: two different sounds",
		str(heard)
	)



## Every one of those reached the client's ears, plus the round's flat cues.
func _sounds_reached_the_ears(game: BfhGame, sink: DotAudioSinkNull) -> void:
	# And every one of those reached the client's ears, plus the flat cues of a round that
	# ended with the drivers' win — this client is a runner, so it is a loss.
	await _step(game, 30)
	var played := sink.played_ids()
	var missing := PackedStringArray()
	for id: StringName in [
		BfhSounds.HAMMER_SWING, BfhSounds.HAMMER_HIT, BfhSounds.CRATE_SHOVE,
		BfhSounds.CRATE_BREAK, BfhSounds.BUS_HORN, BfhSounds.RUNNER_HIT,
		BfhSounds.RUNNER_DOWN, BfhSounds.ROUND_LOST, BfhSounds.ROUND_START,
	]:
		if not played.has(String(id)):
			missing.append(String(id))
	_check(
		missing.is_empty() and not played.has(String(BfhSounds.ROUND_WON)),
		"and a client hears every one, and the round's end as a loss for its side",
		"missing %s of %s" % [str(missing), str(played)]
	)



## The engine, from the bus as drawn, and an empty bus.
func _sounds_engine(game: BfhGame, driver: BfhPlayer, audio: BfhAudio, sink: DotAudioSinkNull) -> void:
	# The engine, from the bus as drawn. Still, it idles; moved at 18 m/s it pulses faster and the
	# client hears the speed it is being drawn at.
	var bus := driver.ridden
	sink.stop_all()
	sink.forget()
	for _i in range(60):
		audio.present(1.0 / 60.0, bus.global_position)
		sink.stop_all()
	var idle := sink.count_of(BfhSounds.BUS_ENGINE)

	sink.forget()
	var heading := -bus.global_basis.z
	for _i in range(60):
		bus.global_position += heading * (18.0 / 60.0)
		audio.present(1.0 / 60.0, bus.global_position)
		sink.stop_all()
	var running := sink.count_of(BfhSounds.BUS_ENGINE)
	var speed := audio.engine_speed(bus)
	_check(
		idle >= 1 and running >= idle * 2 and absf(speed - 18.0) < 3.0,
		"a driven bus's engine pulses faster the faster it is drawn moving",
		"%d pulses standing, %d at speed, heard at %.1f m/s" % [idle, running, speed]
	)

	# A bus nobody is driving has no engine: a thud from one would tell runners to be
	# afraid of nothing.
	game.ride.exit(game.vehicles.get_vehicle(game.ride.vehicle_id_of(&"d")), &"d", true)
	sink.forget()
	for _i in range(60):
		audio.present(1.0 / 60.0, bus.global_position)
	_check(
		sink.count_of(BfhSounds.BUS_ENGINE) == 0,
		"and an empty bus is silent",
		"%d pulses" % sink.count_of(BfhSounds.BUS_ENGINE)
	)


# --- A player's numbers

## The five numbers, counted from what happened, and what they earn.
func _test_progress() -> void:
	print("what a player's numbers are, and what they earn")

	var schema := BfhStats.schema()
	var awards := BfhAwards.catalogue()
	_check(schema.validate().ok and awards.validate().ok, "the stats schema and the achievements are valid documents")

	var unread := PackedStringArray()
	for id in BfhStats.ids():
		if awards.affected_by(id).is_empty():
			unread.append(String(id))
	var undeclared := PackedStringArray()
	for id in awards.watched_stats():
		if not schema.has(id):
			undeclared.append(String(id))
	_check(
		unread.is_empty() and undeclared.is_empty() and schema.size() == BfhStats.ids().size(),
		"every stat is read by an achievement, and every achievement reads a declared stat",
		"unread %s, undeclared %s" % [str(unread), str(undeclared)]
	)

	var game := _world(func(c: BfhConfig) -> void:
		# The shortest round the configuration allows, run out on the clock below.
		c.round_seconds = 10.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Arr", BfhGame.TEAM_RUNNERS)
	var victim := game.add_player(&"v", "Vee", BfhGame.TEAM_RUNNERS)
	var bot := game.add_player(&"b", "Bot", BfhGame.TEAM_RUNNERS, false, true)
	game.start()
	await _step(game, 10)

	var progress := game.progress
	_check(
		progress != null and progress.key_of(&"r") == "bfh-r" and progress.key_of(&"b") == "",
		"an authoritative world counts people, and not bots"
	)

	if progress == null or driver.ridden == null:
		for _i in range(7):
			_check(false, "(no progress, or no bus)")
		await _dispose(game)
		_done()
		return

	var earned: Array = []
	game.earned.connect(func(id: StringName, title: String, _points: int) -> void:
		earned.append("%s:%s" % [id, title]))

	await _progress_crates_broken(game, runner, bot)
	await _progress_crate_shoved(game, driver, runner)
	_progress_flattened(game, victim)
	_progress_feed(game)
	_progress_round_survived(game)
	_progress_earned(game, earned)

	await _dispose(game)
	_done()


## A crate a runner breaks is theirs, and one a bot breaks is nobody's.
func _progress_crates_broken(
	game: BfhGame, runner: BfhPlayer, bot: BfhPlayer
) -> void:
	var progress := game.progress
	# A crate broken with a hammer.
	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		runner.hammer.cooldown = 0.0
		runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)

	# The same, by a bot: nobody is credited.
	var bots_crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(6.0, 0.5, 4.0))
	bots_crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		bot.hammer.cooldown = 0.0
		bot.hammer.swing(game, Vector3(6.0, 0.5, 2.0), forward, game.props, game.prop_damage, game.carry, &"b", mask)

	_check(
		progress.session_values(&"r").get_value(BfhStats.CRATES_BROKEN) == 1.0
		and not bots_crate.is_alive()
		and progress.session_values(&"b").get_value(BfhStats.CRATES_BROKEN) == 0.0,
		"a crate a runner breaks is theirs, and one a bot breaks is nobody's",
		"runner %.0f, bot %.0f" % [
			progress.session_values(&"r").get_value(BfhStats.CRATES_BROKEN),
			progress.session_values(&"b").get_value(BfhStats.CRATES_BROKEN),
		]
	)



## A crate shoved ahead of a bus is in its path, once; the driver breaks it.
func _progress_crate_shoved(
	game: BfhGame, driver: BfhPlayer, runner: BfhPlayer
) -> void:
	var progress := game.progress
	var mask := 0xFFFFFFF
	# A crate shoved ahead of the bus, put where the bus's impact rule looks (no driving).
	var body := driver.ridden
	var shoved := game.props.spawn(
		BfhContent.CRATE, &"world", body.global_transform * Vector3(0.0, -0.4, -6.0)
	)
	shoved.body().freeze = true
	await _step(game, 2)
	var from := body.global_transform * Vector3(0.0, -0.4, -8.2)
	runner.hammer.cooldown = 0.0
	runner.hammer.swing(
		game, from, (shoved.body().global_position - from).normalized(),
		game.props, game.prop_damage, game.carry, &"r", mask
	)
	shoved.body().global_position = body.global_transform * Vector3(0.0, -0.4, -3.0)
	var vehicle := game.vehicles.get_vehicle(game.ride.vehicle_id_of(&"d"))
	# Under the speed a crate breaks at, so it is struck and survives; then at speed, so
	# it goes. Struck twice and credited once.
	game._break_props_under(vehicle, 4.5, &"d")
	game._break_props_under(vehicle, 18.0, &"d")
	_check(
		progress.session_values(&"r").get_value(BfhStats.CRATES_INTO_PATH) == 1.0
		and progress.session_values(&"d").get_value(BfhStats.CRATES_BROKEN) == 1.0,
		"a crate a runner shoved and a bus then hit was put in its path — once — and the "
		+ "driver broke it",
		"runner %.0f in the way, driver %.0f broken" % [
			progress.session_values(&"r").get_value(BfhStats.CRATES_INTO_PATH),
			progress.session_values(&"d").get_value(BfhStats.CRATES_BROKEN),
		]
	)



## A runner run down is the driver's, and the seconds they stood are theirs.
func _progress_flattened(game: BfhGame, victim: BfhPlayer) -> void:
	var progress := game.progress
	# A runner flattened, and the seconds they had stood.
	var stood := game.round_elapsed
	game._bus_hit(victim, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	_check(
		progress.session_values(&"d").get_value(BfhStats.RUNNERS_FLATTENED) == 1.0
		and progress.session_values(&"v").get_value(BfhStats.SECONDS_SURVIVED) == floorf(stood),
		"a runner run down is the driver's, and the seconds they stood are theirs",
		"flattened %.0f, stood %.0f of %.1f s" % [
			progress.session_values(&"d").get_value(BfhStats.RUNNERS_FLATTENED),
			progress.session_values(&"v").get_value(BfhStats.SECONDS_SURVIVED),
			stood,
		]
	)



## Kills go through dot-stats' event feed.
func _progress_feed(game: BfhGame) -> void:
	var progress := game.progress
	_check(progress.feed != null and progress.feed.tracker == progress.stats,
		"kills go through dot-stats' event feed over the progress tracker")
	var was_reporting := progress.stats.report_to_backbone
	progress.stats.report_to_backbone = true
	_check(progress.feed.report_kill(&"d", &"v", "bus") and not progress.feed.report_kill(&"d", &"d", "bus"),
		"the feed files a flattening and refuses a suicide")
	progress.stats.report_to_backbone = was_reporting



## Standing when the clock runs out is a round survived.
func _progress_round_survived(game: BfhGame) -> void:
	var progress := game.progress
	# Ticked without awaiting physics: nothing here is about a body moving.
	var round_was := game.round_number
	for _i in range(int(10.5 * 60.0)):
		game.simulate(TICK)
		if game.round_number != round_was:
			break
	_check(
		progress.session_values(&"r").get_value(BfhStats.ROUNDS_SURVIVED) == 1.0
		and progress.session_values(&"v").get_value(BfhStats.ROUNDS_SURVIVED) == 0.0
		and progress.session_values(&"r").get_value(BfhStats.SECONDS_SURVIVED) >= 9.0,
		"standing when the clock ran out is a round survived, and being out is not",
		"runner %.0f round(s), %.0f s; the flattened one %.0f" % [
			progress.session_values(&"r").get_value(BfhStats.ROUNDS_SURVIVED),
			progress.session_values(&"r").get_value(BfhStats.SECONDS_SURVIVED),
			progress.session_values(&"v").get_value(BfhStats.ROUNDS_SURVIVED),
		]
	)



## The first achievements, for people and never the bot, and a leaver forgotten.
func _progress_earned(game: BfhGame, earned: Array) -> void:
	var progress := game.progress
	_check(
		earned.has("d:Road Rage") and earned.has("r:Traffic Control")
		and earned.has("r:Still Standing") and not earned.any(func(e: String) -> bool: return e.begins_with("b:")),
		"and each of those earned its first achievement, for the person and never the bot",
		str(earned)
	)
	_check(
		progress.is_unlocked(&"d", &"bfh.road_rage") and not progress.is_unlocked(&"d", &"bfh.rush_hour"),
		"the tracker holds the first tier and not the second"
	)

	game.remove_player(&"r")
	_check(
		not progress.stats.has_player(&"bfh-r") and progress.describe()["players"] == 2,
		"and a player who leaves is forgotten by the counters",
		str(progress.describe()["players"])
	)


# --- A player's settings
