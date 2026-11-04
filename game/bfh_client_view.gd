extends "bfh_client_round_end.gd"

const BfhAudio := preload("bfh_audio.gd")
const BfhBindings := preload("bfh_bindings.gd")
const BfhFx := preload("bfh_fx.gd")
const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhNetCommand := preload("net/bfh_net_command.gd")

const BfhConfig := preload("bfh_config.gd")
const BfhMapConfig := preload("bfh_map_config.gd")
const BfhSpectate := preload("bfh_spectate.gd")
const BfhViewmodel := preload("bfh_viewmodel.gd")

## One local player, a camera and a HUD over a [BfhGame] — offline, or against a server.

const CHANNEL := "bfh.client"

@export var config_file: String = "user://cfg/buses-from-hell.json"

## Play alone even when a link is available. `--offline`.
@export var force_offline: bool = false

## How many bot drivers the offline bowl gets. One bus is a game; two is a demonstration.
@export_range(0, 8, 1) var offline_bots: int = 1

var player: BfhPlayer = null
var camera: Camera3D = null

## The hammer in the local runner's hand, under [member camera].
var viewmodel: BfhViewmodel = null

## Keeps the screen covered, and the local body and the input still, until the bowl, the
## player and the camera are all in. See [member DotGameClient.gate].
var gate: DotLoadGate = null

## dot-game's client platform: the cover, settings and menu, console, Tab, M, the pointer and
## the input block. See [DotGameClient].
var platform: DotGameClient = null

## What this client hears. See [BfhAudio]. Null only if dot-audio refused its catalogue.
var audio: BfhAudio = null

## What this client draws that nothing simulates: a barrel going off. See [BfhFx]. Null
## only if dot-fx refused its catalogue.
var fx: BfhFx = null

## The player's console, the platform's.
var console: DotConsoleController = null

## Whether the camera was last put on somebody else's eyes. See [method _process].
var _spectating: bool = false

## Third person: the camera swept back from the eye by dot-core's probe, the own runner
## drawn. Presentation only; the server's `mp_forceview` decides whether the key may.
var third_person: bool = false
var _probe: DotCameraProbe = null
var _fade: DotCameraFade = null

## Behind the eye, in the view's axes (right, up, back); further back from over a bus.
const THIRD_PERSON_OFFSET := Vector3(0.45, 0.35, 2.8)
const THIRD_PERSON_BUS_OFFSET := Vector3(0.0, 0.8, 8.0)
## Metres over a seated driver's eye the sweep starts from: above the bus's roof, so the bus
## they are driving is not what stops it.
const BUS_PIVOT_RISE := 2.6

var net: DotNetManager = null
var bridge: BfhNetBridge = null
## Asks a server whether this player may edit it (sv_workbench_remote); null offline.
var workbench_remote: DotGameWorkbenchRemoteClient = null
## The tuning panel's host: F9 solo or hosting, the admin's remote panel on a server that allows it.
var workbench: DotGameWorkbench = null

var _offline: bool = true
var _sampler: DotFpsSampler = null

## Which session this client is, once the server has said. -1 until then, so nothing
## matches before it does.
var _watch_id: int = -1

func _pointer_ours() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

## The sampled command, on a connected client, once per tick the clock says has passed.
func _physics_process(delta: float) -> void:
	if _offline or net == null or not net.is_running() or bridge == null:
		return

	# The clock says how many ticks this frame is worth, which on a client whose engine
	# runs at the server's rate is almost always exactly one.
	var ticks := net.clock.advance(delta)

	# The clock has advanced; only the sampling waits, so the mouse does not pile up a turn
	# behind the cover and the server sees an idle body until it lifts.
	if _covered():
		return

	var move := _sampler.sample(delta) if _sampler != null else DotFpsCommand.new()

	# The keys that fly the free camera must not also walk the body that fell.
	if is_roaming():
		move = DotFpsCommand.new()
		_swinging = false

	if _swinging:
		move.buttons |= BfhNetCommand.BUTTON_SWING

	# [b]Each pass is its own tick.[/b] `advance` has already moved the clock by all of them, so
	# `input_tick()` is the LAST one on every pass: a frame worth two ticks sent the second twice and
	# the first never, the server repeated a stale command for the one it never got, and the.
	for i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), move)

func _process(delta: float) -> void:
	third_person = game.view_rules.resolve(third_person)
	var _shown := present_frame(net, game, player, delta, -1.0, third_person)
	if killcam != null:
		killcam.frame()

	# Before the early return, so an effect is retired on time even before there is a
	# camera; culled from where the camera was last frame, which is one frame's error.
	if fx != null:
		if camera != null:
			fx.present(delta, camera.global_position, -camera.global_basis.z)
		else:
			fx.present(delta, Vector3.ZERO)

	if camera == null or player == null:
		return

	_present_viewmodel()

	# Somebody else's eyes, while this player is out. After the frame's interpolation, so
	# the camera is where this frame draws whoever it is on.
	if is_roaming():
		_drive_free_camera()
		_spectating = true
		if audio != null:
			audio.present(delta, camera.global_position)
		return

	_roam_seeded = false

	if present_spectator_camera(game, player, camera):
		_spectating = true
		if audio != null:
			audio.present(delta, camera.global_position)
		return

	if _spectating:
		# Back into their own head: the view the seat or the sand gives them, which the lines below then
		# move every frame. Without it the camera keeps the last spectator transform's LOCAL offset and a
		# new round starts with the view floating wherever the last target was.
		_spectating = false
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(
			0.0, BfhPlayer.EYE_HEIGHT + (0.9 if player.riding else 0.0), 0.0
		))

	# Drawn every FRAME from the controller's own interpolated view, not once per tick.
	var state := player.controller.state
	camera.rotation = Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0)

	# [b]And the position, which the angles above never needed.[/b] The camera hangs off the player's
	# node and the node only moves on a tick, so a camera left there advances in steps while everybody
	# it is looking at is now interpolated every frame — a runner watching another runner alongside.
	if not player.riding:
		camera.global_position = player.controller.render_state().position \
			+ Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)

	_place_third_person(delta)

	if audio != null:
		audio.present(delta, camera.global_position)

func _present_viewmodel() -> void:
	if viewmodel == null:
		return
	if viewmodel.hammer != player.hammer:
		viewmodel.bind(player.hammer)
	var out := is_roaming() or (game.spectate != null and game.spectate.is_spectating(player.player_id))
	viewmodel.show_for(BfhViewmodel.wanted(
		player.hammer, player.health == null or player.health.alive, player.riding, out, third_person))

## Moves the camera from the eye to behind it in third person, swept by dot-core's
## [DotCameraProbe] so a wall, a bowl's rim or a bus between stops it short; from over the
## roof when driving, so the bus being driven is not what stops it.
func _place_third_person(delta: float) -> void:
	if not third_person:
		if _probe != null:
			_probe.reset()
		if _fade != null:
			_fade.focus = null
		return
	if _probe == null:
		_probe = DotCameraProbe.new(camera.get_world_3d(), 1)
		_probe.add_excluded_object(player.get_rid())
	var pivot := camera.global_position + (Vector3.UP * BUS_PIVOT_RISE if player.riding else Vector3.ZERO)
	var offset := THIRD_PERSON_BUS_OFFSET if player.riding else THIRD_PERSON_OFFSET
	camera.global_position = _probe.resolve(pivot, pivot + camera.global_basis * offset, delta)
	if _fade != null:
		_fade.focus = player

## The view key: the other view if the server's `mp_forceview` allows it.
func toggle_view() -> void:
	var wanted := game.view_rules.toggled(third_person)
	if wanted == third_person:
		var menu: Object = settings.menu if settings != null else null
		if menu != null and game.view_rules.refusal() != "" and menu.has_method(&"toast"):
			menu.call(&"toast", game.view_rules.refusal())
		return
	third_person = wanted

## Everybody else, for the camera fade.
func _other_players() -> Array:
	var out: Array = []
	if game == null:
		return out
	for id in game.players:
		var other: Node3D = game.players[id]
		if other != player and is_instance_valid(other):
			out.append(other)
	return out

## Puts [param eye] where a runner who is out is looking. Returns whether it did.
static func present_spectator_camera(p_game: BfhGame, own: BfhPlayer, eye: Camera3D) -> bool:
	if p_game == null or own == null or eye == null or p_game.spectate == null:
		return false

	if not p_game.spectate.is_spectating(own.player_id):
		return false

	# The chase and death cameras pulled out of the bowl by dot-spectate, given the level.
	var manager: DotSpectatorManager = p_game.spectate.manager
	if manager != null and manager.camera_world == null:
		manager.camera_world = eye.get_world_3d()
		manager.camera_mask = 1

	var view := p_game.spectate.camera_for(own.player_id)

	# Identity is dot-spectate's "no pose to give", which is a target that has not been drawn
	# yet. The last frame's transform is a better picture than the world's origin.
	if view == Transform3D.IDENTITY:
		return true

	eye.global_transform = view
	return true

## Everything a frame draws that a tick does not, in this order: the netcode's interpolation, then
## every player's body, then every beacon. Returns how many bodies are shown. Static so the net
## suite drives exactly this and not a copy of it.
static func present_frame(
	p_net: DotNetManager, p_game: BfhGame, own: BfhPlayer, delta: float, alpha: float = -1.0,
	own_seen: bool = false
) -> int:
	var networked := p_net != null and p_net.is_running()

	if networked:
		p_net.interpolate_frame(alpha)

	# Your own runner is drawn at the clock's render alpha, not the engine's fraction: the clock
	# stretches and shrinks its ticks while it settles on the server, so a physics frame now and then
	# runs no tick or two, and drawn at the engine's fraction the eye stood still on one frame and.
	if own != null and own.controller != null:
		own.controller.set(&"render_clock", p_net.clock if networked else null)

	if p_game == null:
		return 0

	var shown := 0

	for id: StringName in p_game.players:
		var body: BfhPlayer = p_game.players[id]

		if body == null or not is_instance_valid(body):
			continue

		# Your own runner is drawn when the camera is behind you ([param own_seen]).
		if body.present_body(body == own and not own_seen, p_game.team_of(id) == BfhGame.TEAM_DRIVERS):
			shown += 1

		# Every player's beacon, this client's own included — somebody who has been
		# beaconed sees their ring and hears their ping too. After the interpolation, so a
		# ring is placed where this frame draws them rather than where the last one did.
		body.present_beacon(delta, body == own)

	return shown

## Whether the mouse button is down this frame. Read by [method _physics_process].
var _swinging: bool = false

func _unhandled_input(event: InputEvent) -> void:
	# Tab, M and a click taking the pointer back are the platform's (DotGameClient).
	if event.is_action_pressed("ui_cancel"):
		# Opens the settings when the menu left this Escape alone, because a released pointer with nothing
		# on screen to click was a key that did half a job. A second Escape never reaches here: dot-ui's
		# stack sits deeper in the tree, sees it first, and closes the screen.
		if settings != null:
			settings.open()
		return

	# Nothing below acts while the cover is up: no swing, jump or look.
	if _covered():
		return

	# A runner who is out: the mouse and the jump key are the spectator's, and nothing
	# below — a swing, a turn — means anything for somebody who is not in the round.
	if player != null and game.spectate != null and game.spectate.is_spectating(player.player_id):
		if InputMap.has_action(BfhBindings.ROAM) and event.is_action_pressed(BfhBindings.ROAM):
			toggle_roam()
			return

		# A free camera turns on the mouse, and the clicks and the jump key belong to it:
		# next, back and the view change mean nothing without a target.
		if is_roaming():
			if event is InputEventMouseMotion and _pointer_ours():
				_roam_mouse(event as InputEventMouseMotion)
			return

		var ask := spectator_ask(event)
		if ask >= 0:
			_ask_to_watch(ask)
		return

	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and InputMap.has_action(BfhBindings.VIEW) and event.is_action(BfhBindings.VIEW):
		toggle_view()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton

		if button.button_index == MOUSE_BUTTON_LEFT:
			_swinging = button.pressed

			# Offline there is no command to carry the button: the world is right here and
			# the swing is resolved against it directly. Connected, the flag above rides
			# the next command and the SERVER swings.
			if _offline and button.pressed:
				_swing_locally()
			elif button.pressed and viewmodel != null and player != null and not player.riding:
				# Connected the server resolves the swing; the hand swings on the press.
				viewmodel.swing()

	if player == null:
		return

	# EVERY event, not only motion: the sampler latches button presses, which is how a wheel
	# tick (press and release in one pair) reaches a command as one jump. Its `suspended`
	# flag already gates this while a menu or chat is up, as it does Space.
	if _pointer_ours():
		if _offline and player.sampler != null:
			player.sampler.handle_event(event)
		elif _sampler != null:
			_sampler.handle_event(event)

## Which spectator request an input event is, or -1. Left click is next, right click is
## back, and the jump key changes between their eyes and behind them.
static func spectator_ask(event: InputEvent) -> int:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return BfhSpectate.ASK_NEXT
			MOUSE_BUTTON_RIGHT:
				return BfhSpectate.ASK_PREVIOUS
			MOUSE_BUTTON_MIDDLE:
				return BfhSpectate.ASK_VIEW

	# The jump key, as bound ([BfhBindings]); Space where nothing put the action on the map.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event.is_action(&"dot_fps_jump") if InputMap.has_action(&"dot_fps_jump")
				else (event as InputEventKey).physical_keycode == KEY_SPACE):
		return BfhSpectate.ASK_VIEW

	return -1

## Offline the world answers; connected, the server does, and a refusal comes back as a
## notice like every other one.
func _ask_to_watch(ask: int) -> void:
	if audio != null:
		audio.click()

	if _offline:
		var answered: DotResult = game.spectate.request(player.player_id, ask)
		if not answered.ok and chat != null:
			chat.notice(answered.error.message)
	elif bridge != null:
		bridge.ask_watch(ask)

# --- The free camera

## The pose the free camera holds between frames, seeded from the camera as it was the frame
## the roam began, so the spectator starts where they were looking.
var _free_cam: DotSpectatorFreeCam = null
var _roam_seeded := false
var _roam_look := Vector2.ZERO

func is_roaming() -> bool:
	return player != null and game != null and game.spectate != null \
		and game.spectate.is_roaming(player.player_id)

## The free-camera key: into one from watching, back onto a player from one. Only for somebody
## already out; a stray press must not turn a runner into a spectator.
func toggle_roam() -> void:
	if player == null or game == null or game.spectate == null \
			or not game.spectate.is_spectating(player.player_id):
		return

	if not is_roaming() and not game.spectate.can_roam(player.player_id):
		if chat != null:
			chat.notice("Free camera is off on this server.")
		return

	if audio != null:
		audio.click()

	if _offline:
		var res: DotResult = game.spectate.request(player.player_id, BfhSpectate.ASK_ROAM)
		if not res.ok and chat != null:
			chat.notice(res.error.message)
	elif bridge != null:
		bridge.ask_watch(BfhSpectate.ASK_ROAM)

## The free camera, once a frame: WASD along the view, Space and Ctrl up and down, Shift fast, Alt
## slow, the mouse to look. Only the camera moves; the body stays where it fell.
func _drive_free_camera() -> void:
	if _free_cam == null:
		_free_cam = DotSpectatorFreeCam.new()

	_free_cam.rules = game.spectate.manager.rules

	if not _roam_seeded:
		# The camera still holds last frame's pose: where this spectator was looking.
		_free_cam.seed_from(camera.global_transform)
		_roam_seeded = true
		_roam_look = Vector2.ZERO

	_free_cam.look(_roam_look)
	_roam_look = Vector2.ZERO

	var move := Vector3.ZERO

	if not _covered() and (settings == null or _pointer_ours()):
		move = Vector3(
			Input.get_axis(&"dot_fps_left", &"dot_fps_right"),
			Input.get_axis(&"dot_fps_crouch", &"dot_fps_jump"),
			Input.get_axis(&"dot_fps_back", &"dot_fps_forward"))

	var shift := Input.is_physical_key_pressed(KEY_SHIFT)
	var alt := Input.is_physical_key_pressed(KEY_ALT)
	camera.global_transform = _free_cam.step(
		move, shift, alt and not shift, get_process_delta_time())

## Mouse motion while roaming, as radians for [method DotSpectatorFreeCam.look]: positive x
## turns left (mouse right is negative), positive y looks up (mouse down is negative).
func _roam_mouse(motion: InputEventMouseMotion) -> void:
	var sampler := _sampler if _sampler != null else player.sampler
	var degrees := 0.12
	var invert := 1.0

	if sampler != null and sampler.tunables != null:
		degrees = sampler.tunables.mouse_sensitivity
		invert = -1.0 if sampler.tunables.invert_look_y else 1.0

	_roam_look += Vector2(-motion.relative.x, -motion.relative.y * invert) * deg_to_rad(degrees)

func _swing_locally() -> void:
	if player == null or game == null:
		return

	# A driver's swing button is the horn. Connected, the button rides the command and the
	# server sounds it; offline the world is right here.
	if player.riding:
		game.sound_horn(player)
		return

	if player.hammer == null:
		return

	player.hammer.swing(
		game,
		player.eye_position(),
		player.aim_direction(),
		game.props,
		game.prop_damage,
		game.carry,
		player.player_id,
		0xFFFFFFF,
	)

func describe() -> Dictionary:
	var out := {
		"offline": _offline,
		"session": _watch_id,
		"player": player != null,
	}

	if bridge != null:
		out["bridge"] = bridge.describe()

	if chat != null:
		out["chat"] = chat.describe()

	if audio != null:
		out["audio"] = audio.describe()

	if fx != null:
		out["fx"] = fx.describe()

	if settings != null:
		out["settings"] = settings.describe()

	if player != null and game != null and game.spectate != null:
		out["watching"] = game.spectate.describe_view(player.player_id)

	if game != null:
		out["world"] = game.describe()

	return out

## Where a roster row's player stands, for dot-game's look-to-gag key (G, K).
func _look_position(row: Dictionary) -> Variant:
	if game == null:
		return null
	for who: BfhPlayer in game.players.values():
		if who != player and who.display_name == row["name"]:
			return who.global_position + Vector3.UP * 1.5
	return null


## True while the load gate covers the screen: no input, no prediction sampling, no round clock.
func _covered() -> bool:
	return gate != null and not gate.is_open()

