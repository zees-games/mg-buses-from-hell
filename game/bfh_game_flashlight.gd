extends "bfh_game_roster.gd"

## The flashlight's rules in the simulation, split out of `bfh_game.gd` (which extends this): the server owns each player's on/off. No `class_name`.

const BfhFlashlight := preload("bfh_flashlight.gd")

## The flashlight config and binder, made on first use so a suite that builds a game by hand still has one; the bowl the lights were last set for.
var flashlight_config: DotFlashlightConfig = null
var flashlight_binder: DotGameConfigBinder = null
var _flashlight_bowl: String = ""


## The flashlight config, made on first use.
func flashlight_conf() -> DotFlashlightConfig:
	if flashlight_config == null:
		flashlight_config = BfhFlashlight.make_config()
		flashlight_binder = BfhFlashlight.make_binder(flashlight_config)
		DotLog.result("bfh.game", "flashlight config", flashlight_binder.load_layers())
	return flashlight_config


## A new bowl sets everybody's light by its mood (a lit bowl starts dark). Server side.
func _advance_flashlights() -> void:
	if not authoritative:
		return

	var cfg := flashlight_conf()
	var id := String(bowl_id)

	if id != _flashlight_bowl:
		_flashlight_bowl = id
		for p: BfhPlayer in players.values():
			p.flashlight_ready = false

	for key: StringName in players:
		var player: BfhPlayer = players[key]

		if not player.flashlight_ready:
			player.flashlight_ready = true
			player.flashlight = BfhFlashlight.starts_on(cfg, id)


## A living player in the round switches their light. Refused for somebody who is out, and where the config disallows it. Server side.
func toggle_flashlight(id: StringName) -> bool:
	var player: BfhPlayer = players.get(id)

	if player == null or player.health == null or not player.health.alive \
			or (spectate != null and spectate.is_spectating(id)) \
			or not DotFlashlightRules.allowed_on(flashlight_conf(), String(bowl_id)):
		return false

	player.flashlight = not player.flashlight
	return true
