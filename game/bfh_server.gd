extends Node

const BfhConfig := preload("bfh_config.gd")
const BfhGame := preload("bfh_game.gd")

## What a [DotServer] loads as its game scene. Never a client.

const CHANNEL := "bfh.server"

## The world this server is running. What the module will find in the registry.
var game: BfhGame = null


func _ready() -> void:
	var config := BfhConfig.new()

	# The family's `defaults < JSON < environment < argv` chain, on the server too. It is how an
	# operator sets `BFH_ROUND_SECONDS` or `--bfh-arena-radius` without editing anything, and the cvars
	# the module adds are the live half of the same numbers.
	var binder := BfhConfig.make_binder(config, "user://cfg/buses-from-hell.json")
	var loaded := binder.load_layers()

	if not loaded.ok:
		DotGameConfigBinder.fail_boot(get_tree(), loaded)
		return

	game = BfhGame.new()
	game.config_binder = binder
	game.name = "World"
	game.config = config
	# [b]The engine's rate, which the server has already set from `sv_tickrate`.[/b] Read rather than
	# chosen: this scene is loaded after the server has booted and executed its config, so the number
	# is already decided — and a game that picked its own would be a simulation running at one rate.
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)

	DotLog.info(CHANNEL, "the world is up", {
		"tick_rate": game.tick_rate,
		"bowl": "%.0f m" % config.arena_radius,
	})

	# [b]Not started here.[/b] `start()` lays the bowl out and puts the buses on it, and nothing is
	# listening yet: the module builds the bridge that answers `props.spawned`, so a bowl laid out now
	# is thirty-four crates no client is ever told about.
