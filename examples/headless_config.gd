extends Node

## BfhConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const BfhConfig := preload("../game/bfh_config.gd")
const ROOT := "user://bfh_cfgtest"
const GAME := "mg-buses-from-hell"
const CHECKS := 29

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
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("mg-buses-from-hell: config binder")
	var config := BfhConfig.new()
	var binder := BfhConfig.make_binder(config)
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["round_seconds", "hammer_damage", "bus_mass", "bus_engine_force", "bus_steering_falloff", "horn_seconds", "bot_horn_range", "bus_pinned_seconds", "bot_ramp_speed", "crate_count", "gravity"]:
		_check(keys.has(k), "%s is exposed" % k)

	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("bfh_crate_count", "7")
	_check(config.crate_count == 7 and binder.source_of("crate_count") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("crate_count: 7"), "the diff names the edit")
	var schema_path := "user://bfh_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)

	var bad := FileAccess.open("user://bfh_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := BfhConfig.make_binder(BfhConfig.new(), "user://bfh_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://bfh_config_bad.json")

	_layers()
	_templates(binder)

	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	for set: DotProfileSet in binder.profile_sets():
		wb.add_set(set, set.rel_path)
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var listed := PackedStringArray()
	for kind: String in wb.api.kinds():
		var got: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "get", "kind": kind, "id": binder.profile_id})
		if got.ok:
			listed.append_array(PackedStringArray((got.value as Dictionary).get("values", {}).keys()))
	var missing := PackedStringArray()
	for k in keys:
		if not listed.has(k):
			missing.append(k)
	_check(missing.is_empty() and binder.profile_sets().size() == 3, "the workbench lists all %d keys over %d files" % [keys.size(), binder.profile_sets().size()], ",".join(missing))
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "config_round", "id": binder.profile_id, "key": "round_seconds", "value": 90.0})
	_check(res.ok and config.round_seconds == 90.0, "a workbench edit reaches the live config")
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/mg-buses-from-hell/config_round/game.yml", "")
	_check(text.contains("round_seconds: 90"), "the export holds the edit in the cfg layout")

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


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := BfhConfig.new()
	var binder := BfhConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	print("PROBE ok=%s round=%s round_src=%s mass=%s mass_src=%s cvar=%s dmg=%s dmg_src=%s grav=%s grav_src=%s" % [
		loaded.ok, config.round_seconds, binder.source_of("round_seconds"), config.bus_mass, binder.source_of("bus_mass"),
		console.find_cvar("bfh_bus_mass").get_string(), config.hammer_damage, binder.source_of("hammer_damage"),
		config.gravity, binder.source_of("gravity")])
	get_tree().quit(0)


func _write(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _child() -> String:
	var out: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", "--bfh-hammer-damage=7.5", "--bfh-gravity=15.0"], out, true)
	return "".join(PackedStringArray(out))


## A value set in a cfg file, the environment and argv each reaches the live config, and later layers win.
func _layers() -> void:
	_write("game/%s/config_round/game.yml" % GAME, "round_seconds: 222.0\n")
	_write("game/%s/config_buses/game.yml" % GAME, "bus_mass: 9000.0\n")
	OS.set_environment("BFH_BUS_MASS", "4000.0")
	var text := _child()
	_check(text.contains("PROBE ok=true"), "the layers load strictly in a fresh process", text.right(300))
	_check(text.contains("round=222") and text.contains("round_src=yml"), "a cfg file reaches the live config")
	_check(text.contains("mass=4000") and text.contains("mass_src=env") and text.contains("cvar=4000"), "the environment beats a second file and reaches the cvar")
	_check(text.contains("dmg=7.5") and text.contains("dmg_src=argv"), "argv alone reaches the config")
	_check(text.contains("grav=15") and text.contains("grav_src=argv"), "a second argv flag reaches it too")
	OS.unset_environment("BFH_BUS_MASS")
	_write("game/%s/config_round/game.yml" % GAME, "bus_mass: 9000.0\n")
	_check(_child().contains("PROBE ok=false"), "strict: a key in the wrong file is refused")
	for f in ["config_round", "config_buses"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("game/%s/%s/game.yml" % [GAME, f])))


## The shipped cfg files hold every key, in step with BfhConfig, and change nothing as they are.
func _templates(binder: DotGameConfigBinder) -> void:
	var files := binder.template_files()
	_check(files.size() == 3, "three shipped cfg files", str(files.size()))
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/dot_game/qa/dot_game_cfg_templates.gd)", ",".join(stale))
