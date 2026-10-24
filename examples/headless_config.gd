extends Node

## BfhConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const BfhConfig := preload("../game/bfh_config.gd")
const CHECKS := 20

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _check(ok: bool, what: String, _detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _run() -> void:
	print("mg-buses-from-hell: config binder")
	var config := BfhConfig.new()
	var binder := DotGameConfigBinder.create(config, "mg-buses-from-hell", "bfh")
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["round_seconds", "hammer_damage", "bus_mass", "bus_engine_force", "bus_steering_falloff", "horn_seconds", "bot_horn_range", "bus_pinned_seconds", "bot_ramp_speed", "crate_count"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("bfh_hammer_damage", "7")
	_check(config.hammer_damage == 7.0 and binder.source_of("hammer_damage") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("hammer_damage: 7.0"), "the diff names the edit")
	var schema_path := "user://bfh_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)

	var bad := FileAccess.open("user://bfh_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := DotGameConfigBinder.create(BfhConfig.new(), "mg-buses-from-hell", "bfh", "user://bfh_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://bfh_config_bad.json")

	var shipped := "res://cfg/game/mg-buses-from-hell/config/game.yml"
	DirAccess.make_dir_recursive_absolute("res://cfg/game/mg-buses-from-hell/config")
	var yml := FileAccess.open(shipped, FileAccess.WRITE)
	yml.store_string("bus_mass: 3000.0\nhorn_seconds: 1.5\n")
	yml.close()
	var loaded := BfhConfig.new()
	var from_yml := DotGameConfigBinder.create(loaded, "mg-buses-from-hell", "bfh")
	from_yml.strict = true
	var got := from_yml.load_layers()
	_check(got.ok and loaded.bus_mass == 3000.0 and loaded.horn_seconds == 1.5 and from_yml.source_of("bus_mass") != "default",
		"an exported cfg/game/<game>/config/game.yml loads back as defaults", "" if got.ok else got.error.message)
	DirAccess.remove_absolute(shipped)
	DirAccess.remove_absolute("res://cfg/game/mg-buses-from-hell/config")

	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	wb.add_set(binder.profile_set(), "Game settings")
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var set: DotProfileSet = binder.profile_set()
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": set.rel_path, "id": binder.profile_id, "key": "bus_engine_force", "value": 30000.0})
	_check(res.ok and config.bus_engine_force == 30000.0, "a workbench edit reaches the live config")
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/mg-buses-from-hell/config/game.yml", "")
	_check(text.contains("bus_engine_force: 30000.0"), "the export holds the edit in the cfg layout")

	wb.free()
	console.free()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
