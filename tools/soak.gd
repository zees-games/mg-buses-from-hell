extends Node

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")

## Bot soak on the real game: N bot-driven buses chase idle runners in one bowl for M simulated
## minutes through dot-bot's DotBotSoak, fed by dot-spawn's DotSpawnWatch. A "map" here is a bowl id.
##
## [codeblock]
## ./game.sh soak [bowl] [minutes]
## godot --headless --path . res://tools/soak.tscn -- --map bfh_bowl --bots 4 --minutes 2
## [/codeblock]
##
## Takes the harness's own flags too (--soak-max-stuck-sec and the rest of DotBotSoakConfig).
## Writes .godot/test-logs/soak-<bowl>.json, prints the SOAK line, exits 1 when the run fails.
## The movers are the bot-driven buses; runners are idle people (there is no runner bot in play), so
## rounds end when the buses have run them down. Kills are off.

const DEFAULT_MAP := &"bfh_bowl"
const DEFAULT_MINUTES := 1.0
const DEFAULT_BOTS := 4
const RUNNERS := 3
const TICK_RATE := 64
## The buses are physics bodies the engine steps once per physics frame, so the sim ticks one frame at a time.
const STEPS_PER_FRAME := 1

var _game: BfhGame
var _rounds_over := 0
var _bots: Array[StringName] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback


func _run() -> void:
	var map_id := StringName(_arg("map", String(DEFAULT_MAP)))
	var cfg := DotBotSoakConfig.new()
	cfg.minutes = DEFAULT_MINUTES
	cfg.bots = DEFAULT_BOTS
	# The object count saws with each round's props and wrecks; a real leak keeps climbing.
	cfg.max_object_growth_pct = 40.0
	cfg.apply_cli()
	cfg.minutes = float(_arg("minutes", str(cfg.minutes)))
	cfg.bots = int(_arg("bots", str(cfg.bots)))

	var known := false
	for bowl in BfhBowls.all(BfhConfig.new()):
		known = known or StringName(bowl.get("id", &"")) == map_id
	if not known:
		_fail("no bowl %s" % map_id)
		return

	var config := BfhConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.driver_count = cfg.bots

	_game = BfhGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = TICK_RATE
	_game.authoritative = true
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	_game.round_over.connect(func(_n: int, _w: int) -> void: _rounds_over += 1)
	await get_tree().physics_frame
	await get_tree().physics_frame

	for i in range(cfg.bots):
		var id := StringName("d%d" % i)
		_game.add_player(id, "Driver %d" % i, BfhGame.TEAM_DRIVERS, false, true)
		_bots.append(id)
	for i in range(RUNNERS):
		_game.add_player(StringName("r%d" % i), "Runner %d" % i, BfhGame.TEAM_RUNNERS)
	_game.start()
	if map_id != BfhBowls.DEFAULT:
		_game.change_bowl_now(map_id)
	for _i in range(20):
		_game.simulate(1.0 / float(TICK_RATE))
		await get_tree().physics_frame

	var watch := DotSpawnWatch.new()
	watch.rules.enabled = true
	watch.rules.kill_y = -20.0

	var soak := DotBotSoak.new(cfg)
	soak.watch = watch
	soak.movers_fn = _movers
	soak.object_count_fn = func() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
	soak.step_fn = _game.simulate

	var delta := 1.0 / float(TICK_RATE)
	while not soak.is_done():
		soak.advance(delta)
		if soak.ticks % STEPS_PER_FRAME == 0:
			await get_tree().physics_frame

	var report := soak.finish()
	report["map"] = String(map_id)
	report["rounds"] = _game.round_number
	report["rounds_over"] = _rounds_over
	print(DotBotSoak.summary(report))
	print(DotBotSoak.report_line(report))
	var path := ProjectSettings.globalize_path("res://.godot/test-logs/soak-%s.json" % map_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if soak.write_report(report, path) != OK:
		push_error("could not write %s" % path)
	await _release_game()
	get_tree().quit(0 if report["ok"] else 1)


## Frees the game before quitting: a world still loaded at quit can abort the process.
func _release_game() -> void:
	_game.queue_free()
	for _i in range(3):
		await get_tree().process_frame


func _movers() -> Array:
	var out: Array = []
	var chasing := _game.alive_runners() > 0
	for id in _bots:
		if not _game.players.has(id):
			continue
		var instance_id := _game.ride.vehicle_id_of(id)
		var bus := _game.vehicles.get_vehicle(instance_id) if instance_id != 0 else null
		if bus == null or not bus.is_alive():
			continue
		out.append({"id": id, "position": bus.position(), "kind": &"bot", "has_goal": chasing})
		_trace_bus(id, bus)
	return out


## `--trace` prints each bus once a second: position, speed, the nearest runner, and the ramp plan.
func _trace_bus(id: StringName, bus: DotVehicleInstance) -> void:
	if not OS.get_cmdline_user_args().has("--trace"):
		return
	var sec := (Engine.get_physics_frames() - _first_frame) / TICK_RATE
	if _traced_sec.get(id, -1) == sec:
		return
	_traced_sec[id] = sec
	var q := _game._nearest_runner(bus.position())
	var plan: Dictionary = _game._bus_turning.get(bus.instance_id, {})
	var p := bus.position()
	print("TRACE t=%d %s pos=(%.1f,%.1f,y%.1f) v=%.1f route=%s quarry=%s plan=%s back=%s stuck=%.1f" % [
		sec, id, p.x, p.z, p.y, bus.speed(), str(_game._bus_routes.get(bus.instance_id, {}).get("path", PackedVector3Array()).slice(0, 3)),
		"-" if q == null else "(%.1f,%.1f,y%.1f)" % [q.global_position.x, q.global_position.z, q.global_position.y],
		plan.get("phase", "-") + ("R" if plan.get("reverse", false) else "F"),
		_game._bus_backing_off.get(bus.instance_id, 0.0) > 0.0, float(_game._bus_stuck.get(bus.instance_id, 0.0))])


var _traced_sec := {}
var _first_frame := Engine.get_physics_frames()


func _fail(why: String) -> void:
	printerr("SOAK setup failed: ", why)
	get_tree().quit(2)
