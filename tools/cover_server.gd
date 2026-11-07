extends DotCoverServer

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")

## A headless dedicated bowl for tools/render_cover.gd to join: the boot examples/dedicated.gd does
## (DotServer, the world, the module), left running.

var game: BfhGame = null


func _max_players() -> int:
	return 4


func _boot(dir: String) -> void:
	var world_config := BfhConfig.new()
	world_config.warmup_seconds = 0.0
	game = BfhGame.new()
	game.name = "World"
	game.config = world_config
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)
	await get_tree().process_frame

	(load("res://game/bfh_module.gd") as GDScript).set("punishments_file", "%s/punishments.json" % dir)
	var loaded: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	print("cover_server: module loaded=%s port=%d" % [loaded.ok, port])
