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
	_game.player_added.connect(_protect)
	var bots: DotConVar = server.console.find_cvar("bfh_bots")
	if bots != null:
		bots.force_set("0")
	if solid != "":
		var cv: DotConVar = server.console.find_cvar("mp_solidplayers")
		if cv != null:
			cv.force_set(solid)


## The pilot cannot be run over. The bots drive at the only runner, and with no intermission the round that its death ends starts again
## within 90 ms, so the client never sees it dead: it sees a live player put 60 m away, a respawn teleport that read as a prediction
## error of that size. A bus still shoves it (`_bus_hit` knocks a runner in god mode too), a server-side impulse the client cannot predict (0.7 m at the end of a clean run), so the rig drives no bots (`bfh_bots 0`): the pilot runs alone and what is judged is its own prediction.
func _protect(player_id: StringName) -> void:
	var player = _game.players.get(player_id)
	if player != null and not player.is_bot and player.health != null:
		player.health.invulnerable = true


func _players() -> Array:
	return _game.players.values() if _game != null else []
