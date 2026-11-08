extends "headless_run_client.gd"
## The flashlight: the bowl's mood sets it, a player switches it, the out and a config may not.

const BfhBindings := preload("../game/bfh_bindings.gd")
const BfhFlashlight := preload("../game/bfh_flashlight.gd")


func _test_the_flashlight() -> void:
	print("the flashlight: the bowl sets it, a player switches it, the out and a config may not")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var _driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var a := game.add_player(&"r1", "Ada", BfhGame.TEAM_RUNNERS)
	var b := game.add_player(&"r2", "Bo", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var cfg := game.flashlight_conf()
	var keys := BfhBindings.make()
	_check(cfg.key == "F" and game.flashlight_binder != null, "the key is F and the config has a binder", cfg.key)
	_check(str(keys.row_for_action(BfhBindings.FLASHLIGHT).get("default", "")) == "F" and keys.defaults_on("F").size() == 1,
		"the key is a bindings row, and nothing else defaults to F")
	_check(not BfhFlashlight.starts_on(cfg, "bfh_bowl"), "the lit bowl starts dark")
	_check(not BfhFlashlight.starts_on(cfg, "bfh_downtown"), "and so does a town in ruins")
	_check(BfhFlashlight.starts_on(cfg, "bfh_bowl", "outdoor_night"), "and a night mood would start lit")

	cfg.default_state = DotFlashlightConfig.START_ON
	a.flashlight_ready = false
	await _step(game, 2)
	_check(a.flashlight, "a config that starts lit lights the player")
	cfg.default_state = DotFlashlightConfig.START_OFF
	a.flashlight_ready = false
	await _step(game, 2)
	_check(not a.flashlight, "and one that starts dark does not")

	_check(game.toggle_flashlight(a.player_id) and a.flashlight, "the switch turns a light on")
	_check(game.toggle_flashlight(a.player_id) and not a.flashlight, "and the next press turns it off")

	b.health.alive = false
	_check(not game.toggle_flashlight(b.player_id) and not b.flashlight, "somebody who is down has no switch")

	cfg.enabled = false
	_check(not game.toggle_flashlight(a.player_id) and not a.flashlight, "a disabled config has no light")
	cfg.enabled = true
	cfg.default_state = DotFlashlightConfig.START_DARK
	await _dispose(game)
	_done()
