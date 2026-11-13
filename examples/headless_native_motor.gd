extends DotGameCheckSuite

const BfhConfig := preload("../game/bfh_config.gd")
const BfhPlayer := preload("../game/bfh_player.gd")

## A player's motor in dot-sim ([member DotFpsMotor.native_tick], on by default since dot-player-controller API 27) moves
## exactly as the script motor does: the same seeded inputs with this game's movement tunables, on a floor, ramp, step,
## wall and pillar, give the same bytes every tick, for the whole tick in one call and for its two halves. A web client
## runs the script while a native server and native clients run the library, so they must agree without a correction.
## Hit registration and lag compensation are not touched. With no library the native half is skipped;
## [code]DOT_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 3
const CHECKS := 7
const TICKS := 2400

var _entered := 0
var _finished := 0
var _rate := 60


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_rate = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	_run.call_deferred()


func _run() -> void:
	print("Buses from Hell native motor")
	print("")
	_entered += 1
	print("the motor is native by default, and the library is there")
	_check(DotFpsMotor.native_tick, "DotFpsMotor.native_tick is on without the game turning it on")
	_check(DotFpsMotor.native_full, "DotFpsMotor.native_full is on without the game turning it on")
	var loaded := DotFpsPhysicsBody.native_full_available()
	if not loaded:
		print("  dot-sim's motor module is not loaded: the native half is skipped")
		_check(OS.get_environment("DOT_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (DOT_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, SECTIONS - 2, 3)
		return
	_check(true, "the library has the whole tick")
	print("  dot-sim: native motor_tick=full")
	_finished += 1

	_build_world()
	var stream := _stream(7, TICKS)

	_entered += 1
	print("the whole tick in one native call against the script (%d Hz)" % _rate)
	var before := DotFpsPhysicsBody.native_ticks
	var script_run: Array[PackedByteArray] = await _replay(0, stream)
	var full_run: Array[PackedByteArray] = await _replay(2, stream)
	var native_calls := DotFpsPhysicsBody.native_ticks - before
	_check(native_calls > TICKS / 2, "most ticks ran in dot-sim", "%d native calls in %d ticks" % [native_calls, TICKS])
	var first := _first_difference(script_run, full_run)
	_check(first < 0, "every tick's state is the same bytes", "first differs at tick %d" % first)
	_check(_spread(script_run) > 20.0, "the run went somewhere (not a body stood still)", "%.1f m" % _spread(script_run))
	_finished += 1

	_entered += 1
	print("the tick's two halves native against the script")
	first = _first_difference(script_run, await _replay(1, stream))
	_check(first < 0, "every tick's state is the same bytes", "first differs at tick %d" % first)
	_finished += 1

	DotFpsMotor.native_tick = true
	DotFpsMotor.native_full = true
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## The controller as the game's player builds it.
func _make_controller() -> DotFpsController:
	var controller := DotFpsController.new()
	controller.tunables = BfhPlayer.tunables_for(BfhConfig.new())
	controller.admin_abilities = true
	return controller


## A floor, a ramp, a step, a wall and a pillar: ground, slope, step-up, slide and corner.
func _build_world() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Vector3.ZERO)
	_box(Vector3(6, 0.6, -8), Vector3(6, 0.4, 8), Vector3(deg_to_rad(18), 0, 0))
	_box(Vector3(-6, 0.15, -6), Vector3(4, 0.3, 4), Vector3.ZERO)
	_box(Vector3(0, 1.5, -18), Vector3(30, 3, 1), Vector3.ZERO)
	_box(Vector3(-3, 1.5, -10), Vector3(1, 3, 1), Vector3(0, deg_to_rad(30), 0))


func _box(at: Vector3, size: Vector3, rotation: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.rotation = rotation
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## Seeded inputs that change every few ticks: any move, sprint, crouch, jump, and a turning view.
func _stream(seed: int, ticks: int) -> Array[DotFpsCommand]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[DotFpsCommand] = []
	var move := Vector2.ZERO
	var buttons := 0
	var yaw := 0.0
	for tick in range(ticks):
		if tick % 8 == 0 or rng.randf() < 0.06:
			move = Vector2(rng.randi_range(-1, 1), -1.0 if rng.randf() < 0.6 else float(rng.randi_range(-1, 1)))
			buttons = 0
			if rng.randf() < 0.5:
				buttons |= DotFpsCommand.BUTTON_SPRINT
			if rng.randf() < 0.15:
				buttons |= DotFpsCommand.BUTTON_CROUCH
			if rng.randf() < 0.2:
				buttons |= DotFpsCommand.BUTTON_JUMP
		yaw = wrapf(yaw + rng.randf_range(-0.15, 0.15), -PI, PI)
		var c := DotFpsCommand.new()
		c.move = move
		c.buttons = buttons
		c.yaw = yaw
		out.append(c)
	return out


## [param way] 0 all script, 1 the native halves, 2 the whole tick native: each tick's state as bytes.
func _replay(way: int, stream: Array[DotFpsCommand]) -> Array[PackedByteArray]:
	DotFpsMotor.native_tick = way > 0
	DotFpsMotor.native_full = way == 2
	var controller := _make_controller()
	controller.tick_rate = _rate
	controller.drive = DotFpsController.Drive.EXTERNAL
	var host := CharacterBody3D.new()
	host.position = Vector3(0, 0.05, 4)
	add_child(host)
	host.add_child(controller)
	controller.teleport(host.position, 0.0, 0.0)
	await get_tree().physics_frame
	var delta := 1.0 / float(_rate)
	var out: Array[PackedByteArray] = []
	for tick in range(stream.size()):
		var c := DotFpsCommand.new()
		c.move = stream[tick].move
		c.buttons = stream[tick].buttons
		c.yaw = stream[tick].yaw
		controller.apply_command(c)
		controller.simulate_tick(tick, delta)
		var s := controller.state
		out.append(var_to_bytes([
			s.position, s.velocity, s.mode, s.ground_normal, s.ground_id, s.crouch_fraction, s.sprinting, s.stamina,
			s.modifiers, s.ground_ticks, s.time_since_jump, s.time_since_grounded, s.time_since_jump_pressed,
			s.slide_time, s.slide_cooldown_left, s.airborne_time, s.previous_buttons,
		]))
	host.queue_free()
	await get_tree().process_frame
	return out


func _first_difference(a: Array[PackedByteArray], b: Array[PackedByteArray]) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i in range(a.size()):
		if a[i] != b[i]:
			return i
	return -1


## The farthest the body got from its start, in metres.
func _spread(run: Array[PackedByteArray]) -> float:
	if run.is_empty():
		return 0.0
	var start: Vector3 = (bytes_to_var(run[0]) as Array)[0]
	var far := 0.0
	for b in run:
		far = maxf(far, ((bytes_to_var(b) as Array)[0] as Vector3).distance_to(start))
	return far
