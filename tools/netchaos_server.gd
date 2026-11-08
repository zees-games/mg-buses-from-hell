extends DotGameNetchaosServer

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")

## Buses From Hell's side of `tools/netchaos.sh` (dot-game's DotGameNetchaosServer): the world and the module, no warmup or intermission.
## The module fills empty driving seats with its own bots (bot_quota), so the roster holds those too.

var _game: BfhGame = null


func _boot_world() -> void:
	if not (await boot_server()).ok:
		return
	var config := BfhConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.round_seconds = 600.0
	_game = BfhGame.new()
	_game.name = "World"
	_game.config = config
	_game.config_binder = BfhConfig.make_binder(config)
	_game.tick_rate = Engine.physics_ticks_per_second
	add_child(_game)
	await get_tree().process_frame
	(load("res://game/bfh_module.gd") as GDScript).set("punishments_file", "%s/punishments.json" % data_dir)
	var loaded: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	if not loaded.ok:
		printerr("netchaos server: ", loaded.error)
		return
	module = server.modules.get_module("buses")
	if solid != "":
		var cv: DotConVar = server.console.find_cvar("mp_solidplayers")
		if cv != null:
			cv.force_set(solid)


func _players() -> Array:
	return _game.players.values() if _game != null else []
