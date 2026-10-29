extends Node

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")

## A headless dedicated bowl for tools/render_cover.gd to join: the boot examples/dedicated.gd does
## (DotServer, the world, the module), left running.

var server: DotServer = null
var game: BfhGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _run() -> void:
	var dir := ProjectSettings.globalize_path("user://cover_server")
	DotPaths.remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)

	var config := DotServerConfig.new()
	config.autoexec_config = ""
	config.hostname = "cover test"
	config.max_players = 4
	config.hibernate_when_empty = false
	config.rcon_password = ""
	config.query_enabled = false
	config.port = int(_arg("--port", "27399"))
	config.admins_path = "%s/admins.json" % dir
	config.bans_path = "%s/bans.json" % dir
	config.audit_log_path = "%s/audit.jsonl" % dir
	config.stdin_console_enabled = false

	server = DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)
	for _i in 60:
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break

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
	print("cover_server: module loaded=%s port=%d" % [loaded.ok, config.port])
