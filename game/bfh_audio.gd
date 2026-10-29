extends Node

const BfhAmbience := preload("bfh_ambience.gd")
const BfhBowls := preload("bfh_bowls.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhSounds := preload("bfh_sounds.gd")

## What a client hears: the world's noises, the round's cues, and every bus's engine.

const CHANNEL := "bfh.audio"

## Engine pulses a second at a standstill and at the top speed.
const ENGINE_IDLE_HZ := 2.2
const ENGINE_TOP_HZ := 11.0

## The speed the engine's pulse rate and pitch top out at, in m/s. The shipped top speed.
const ENGINE_TOP_SPEED := 22.0

## How quickly the heard speed follows the drawn one. A mirrored bus is moved by
## interpolation and its speed is measured frame to frame, which is noisy on a frame that
## lands just after a snapshot; a pulse rate that jumped with it would stutter.
const ENGINE_SMOOTHING := 8.0

var audio: DotAudioManager = null

var _world: Node3D = null

## Who this client is, asked every time rather than held: on a connected client the local
## player arrives in a JOIN, frames after the world exists.
var _own: Callable = Callable()

## bus node instance id -> {"at": Vector3, "speed": float, "phase": float}.
var _engines: Dictionary = {}

## Runners' footsteps (sand, so dot-audio's grass set) and the bowl's wind, from dot-audio's
## stock. Drivers are in a bus and make the engine instead.
var steps: DotAudioFootsteps = null
var ambience: DotAudioAmbience = null

## Quiet moods under the bowl (dot-audio's stock set); the wind bed plays only when none loaded.
var ambient: DotAmbienceDirector = null


## Builds the manager and listens to [param world]. [param own] returns this client's
## player, or null before there is one.
func setup(world: Node3D, own: Callable = Callable()) -> DotResult:
	_world = world
	_own = own

	audio = DotAudioManager.new()
	audio.name = "Manager"
	audio.catalogue = BfhSounds.catalogue()
	audio.mixer = DotAudioMixer.new()
	# Not registered. A client and a server in one editor session, and the suite, are two
	# of these in one process, and a registry name is the last one's.
	audio.register_as_service = false
	# Two buses pulsing and a crowd of hammers is the busiest this game gets.
	audio.voices = 24
	# Measured toward the family's -17 LUFS (dot-audio docs/loudness.md): a 40 s stand-in round read
	# -25.4 LUFS integrated with the wind and the steps in (-20.1 before them, on a run with a crash in
	# it); -19.9 at +6, -18.1 and -19.1 at +8.
	audio.loudness_trim_db = 9.0
	add_child(audio)

	var built := audio.setup()
	if not built.ok:
		return built.wrap("the bowl's audio")

	# Only on a real sink, and only after setup: the manager decides whether there is a
	# device, and baking streams on a machine with nothing to play them on is a few
	# hundred milliseconds of arithmetic for nobody.
	var godot_sink := audio.sink as DotAudioSinkGodot
	if godot_sink != null:
		godot_sink.bank = DotAudioSynth.bank(audio.catalogue, BfhSounds.sound_recipes())
		DotLog.info(CHANNEL, "no audio files; synthesised stand-ins are in use", {
			"ids": BfhSounds.sound_recipes().size(), "dir": BfhSounds.sound_dir(),
		})

	steps = DotAudioFootsteps.new()
	steps.name = "Footsteps"
	steps.manager = audio
	steps.default_surface = &"sand"
	add_child(steps)
	ambience = DotAudioAmbience.new()
	ambience.name = "Ambience"
	ambience.manager = audio
	add_child(ambience)
	ambient = DotAmbienceDirector.new()
	ambient.name = "Ambient"
	ambient.manager = audio
	ambient.default_mood = BfhAmbience.DEFAULT_MOOD
	ambient.prefix_moods = BfhAmbience.PREFIX_MOODS
	ambient.rules = BfhAmbience.make_rules()
	ambient.beds = ambience
	add_child(ambient)
	var _moods := ambient.setup()
	ambient.follow_settings(null)
	ambient.map_lookup = func(id: StringName) -> Variant: return {"meta": BfhBowls.by_id(null, id)}
	# A walled bowl of sand in the open: the wind over its rim, unless a mood is playing.
	if ambient.has_moods():
		ambient.on_map(world.get("bowl_id"), {})
		if world.has_signal("bowl_changed"):
			world.connect("bowl_changed", func(id: StringName) -> void: ambient.on_map(id, {}))
	else:
		ambience.set_map_bed(&"amb_wind")

	world.connect("noise", _on_noise)
	world.connect("barrel_exploded", _on_blast)
	# The bowl's toys: a ball's bounce off a bus, a barrel's knock.
	if world.has_signal("toy_sound"):
		world.connect("toy_sound", _on_toy)
	world.connect("round_began", _on_round_began)
	world.connect("round_over", _on_round_over)
	world.connect("sides_swapped", _on_sides_swapped)

	return DotResult.success(self)


## Once a frame: where the listener is, and every driven bus's engine.
func present(delta: float, listener: Vector3) -> void:
	if audio == null or _world == null:
		return

	audio.listener_position = listener
	_present_engines(delta)
	if steps != null and _world.has_method("runners"):
		steps.keep(_world.call("runners"))


## A bus's engine, from the bus this client is drawing.
func _present_engines(delta: float) -> void:
	var seen := {}

	for id: StringName in (_world.get("players") as Dictionary):
		var driver: BfhPlayer = (_world.get("players") as Dictionary)[id]

		if driver == null or not driver.riding or driver.ridden == null \
				or not is_instance_valid(driver.ridden):
			continue

		var bus := driver.ridden
		var key := bus.get_instance_id()
		seen[key] = true

		var at := bus.global_position
		var engine: Dictionary = _engines.get(key, {"at": at, "speed": 0.0, "phase": 0.0})

		# Measured from the drawn position rather than read off the body: a client's bus is
		# a frozen mirror moved by interpolation and its `linear_velocity` is zero.
		var moved := Vector2(at.x - (engine["at"] as Vector3).x, at.z - (engine["at"] as Vector3).z)
		var drawn := moved.length() / delta if delta > 0.0 else 0.0
		var speed := lerpf(float(engine["speed"]), drawn, clampf(delta * ENGINE_SMOOTHING, 0.0, 1.0))

		var effort := clampf(speed / ENGINE_TOP_SPEED, 0.0, 1.0)
		var phase := float(engine["phase"]) + delta * lerpf(ENGINE_IDLE_HZ, ENGINE_TOP_HZ, effort)

		if phase >= 1.0:
			phase = fmod(phase, 1.0)
			audio.play_at(
				BfhSounds.BUS_ENGINE, at, lerpf(0.45, 1.0, effort), lerpf(0.7, 1.35, effort)
			)

		_engines[key] = {"at": at, "speed": speed, "phase": phase}

	# Buses that went — the round re-laid the bowl, a driver got out — are forgotten, or the
	# table keeps a row per bus the server has ever spawned.
	for key: Variant in _engines.keys():
		if not seen.has(key):
			_engines.erase(key)


## How fast this client hears a bus going, in m/s. For a check.
func engine_speed(bus: Node3D) -> float:
	var engine: Dictionary = _engines.get(bus.get_instance_id(), {})
	return float(engine.get("speed", 0.0))


# --- The world's signals

func _on_noise(id: StringName, at: Vector3) -> void:
	audio.play_at(id, at)


func _on_toy(id: StringName, at: Vector3, strength: float) -> void:
	audio.play_at(id, at, clampf(strength, 0.25, 1.0))


func _on_blast(at: Vector3, _radius: float) -> void:
	audio.play_at(BfhSounds.BARREL_BLAST, at)


func _on_round_began(_number: int) -> void:
	audio.play(BfhSounds.ROUND_START)


## Won or lost, by THIS client's side. See `BfhSounds.ROUND_WON`.
func _on_round_over(_number: int, winner: int) -> void:
	var mine := _own_side()
	audio.play(BfhSounds.ROUND_WON if winner != 0 and winner == mine else BfhSounds.ROUND_LOST)


func _on_sides_swapped(_number: int) -> void:
	audio.play(BfhSounds.SIDE_SWAP)


## A click on the interface: a spectator changing camera, a setting changed.
func click() -> void:
	if audio != null:
		audio.play(BfhSounds.UI_CLICK)


## The server said something to this player alone.
func notice() -> void:
	if audio != null:
		audio.play(BfhSounds.UI_NOTICE)


func _own_side() -> int:
	var own: BfhPlayer = _own.call() if _own.is_valid() else null

	if own == null or _world == null:
		return 0

	return int((_world.get("sides") as Dictionary).get(own.player_id, 0))


func describe() -> Dictionary:
	var out := audio.describe() if audio != null else {}
	out["engines"] = _engines.size()
	return out
