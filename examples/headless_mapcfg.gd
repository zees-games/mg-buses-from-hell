extends DotGameCheckSuite

const BfhConfig := preload("../game/bfh_config.gd")
const BfhMapConfig := preload("../game/bfh_map_config.gd")

## A bowl gets its `cfg/` file's values and the next bowl gets the previous values back, on the server's cvars and on the client's hooks.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapcfg.tscn
## [/codeblock]
##
## The cvars start away from the file's values; the file is written for the run and removed after it.

const CHECKS := 10
const DIR := "res://cfg/server/game/mg-buses-from-hell/dot_map/map"
const FILE := "bfh_zz_mapcfg_check.yml"



class FakeWorld:
	extends RefCounted
	var config := BfhConfig.new()

	func set_round_seconds(seconds: float) -> void:
		config.round_seconds = seconds


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-buses-from-hell: per-bowl settings from cfg/game/mg-buses-from-hell/dot_map/map")
	if not ResourceLoader.exists("res://addons/dot_map/config/dot_map_config.gd"):
		print("SKIPPED: dot-map is not linked at addons/dot_map")
		get_tree().quit(0)
		return
	DotAddonConfig.game = BfhMapConfig.GAME_ID
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(DIR.path_join(FILE), FileAccess.WRITE)
	file.store_string("bfh_bus_top_speed: 50\nbfh_crates: 7\nbfh_exec: quit\n")
	file.close()

	var console := DotConsole.new()
	add_child(console)
	console.cvar("bfh_bus_top_speed", "34", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("bfh_crates", "40", "", DotConVar.FLAG_ARCHIVE)
	console.cvar("bfh_exec", "keep", "", DotConVar.FLAG_ARCHIVE)
	var cfg := BfhMapConfig.build(console)

	var got := cfg.apply("bfh_zz_mapcfg_check")
	_check(got.size() == 2, "the bowl applies its two whitelisted keys (%s)" % [got])
	_check(console.find_cvar("bfh_bus_top_speed").get_float() == 50.0, "bfh_bus_top_speed is 50 on that bowl")
	_check(console.find_cvar("bfh_crates").get_int() == 7, "bfh_crates is 7 on that bowl")
	_check(console.find_cvar("bfh_exec").get_string() == "keep", "a key outside the whitelist is untouched")

	cfg.apply("bfh_bowl")
	_check(console.find_cvar("bfh_bus_top_speed").get_float() == 34.0, "the next bowl has bfh_bus_top_speed back")
	_check(console.find_cvar("bfh_crates").get_int() == 40, "and bfh_crates")

	var world := FakeWorld.new()
	var before := world.config.bus_top_speed
	var client := DotGameMapConfig.new()
	client.game_id = BfhMapConfig.GAME_ID
	client.keys = BfhMapConfig.client_keys()
	client.get_fn = func(key: String) -> Variant: return BfhMapConfig.client_get(world, key)
	client.set_fn = func(key: String, value: Variant) -> bool: return BfhMapConfig.client_set(world, key, value)
	client.apply("bfh_zz_mapcfg_check")
	_check(is_equal_approx(world.config.bus_top_speed, 50.0), "the client's config takes the bowl's top speed")
	_check(world.config.crate_count == BfhConfig.new().crate_count, "the client holds no key it does not use")
	client.apply("bfh_bowl")
	_check(is_equal_approx(world.config.bus_top_speed, before), "the client's next bowl restores it")
	_check(not BfhMapConfig.client_set(world, "bfh_exec", "x"), "the client setter refuses an unknown key")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(FILE)))
	_report(CHECKS)
