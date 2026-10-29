extends Node

## The third-person camera and the spectator's chase camera flown round the bowl in the real offline
## game (dot-core's DotCameraCheck: never inside, armed by the unprotected camera being in or behind
## the level on some frames), `mp_forceview` through the view key's path, and with `--render` both.

const BfhClient := preload("../game/bfh_client.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")

var _client: Node = null
var _render := false
var _failed := false


func _ready() -> void:
	_render = OS.get_cmdline_user_args().has("--render")
	_client = load("res://game/bfh.tscn").instantiate()
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	await _seconds(3.0)
	var game: BfhGame = _client.get("game")
	_fly(game)
	_views_rule(game)
	if _render:
		await _views(game)
	print("all passed" if not _failed else "FAILED")
	get_tree().quit(1 if _failed else 0)


func _fly(game: BfhGame) -> void:
	# The rim, the stacks, the ledge, the colonnade and the ramp: every place a runner backs
	# into something, and where buses start.
	var space := _client.get_viewport().world_3d.direct_space_state
	var places: Array[Vector3] = []
	var arena = game.arena
	for point in arena.colonnade_points():
		places.append(point)
	for local in arena.pillar_layout():
		places.append(arena.stack_point(local))
	places.append(arena.ledge_centre())
	places.append(arena.ramp_foot())
	for i in 8:
		var angle := TAU * float(i) / 8.0
		places.append(Vector3(sin(angle), 0.0, cos(angle)) * (arena.radius - 2.0))
	var pivots: Array[Vector3] = []
	for at in places:
		for side in [Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0), Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
			var probe: Vector3 = at + side
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 6.0, probe + Vector3.DOWN * 6.0, 1))
			if hit.is_empty():
				continue
			var eye: Vector3 = (hit["position"] as Vector3) + Vector3.UP * BfhPlayer.EYE_HEIGHT
			if not DotCameraProbe.is_inside(space, eye, 0.3, 1):
				pivots.append(eye)
	var world := _client.get_viewport().world_3d
	var cases := {"third_person": BfhClient.THIRD_PERSON_OFFSET, "chase": Vector3(0.0, 0.8, 3.5)}
	for name in cases:
		var total := {}
		for pivot in pivots:
			total = DotCameraCheck.add(total, DotCameraCheck.fly(world, DotCameraCheck.orbit_path(pivot), cases[name], 1))
		_check(DotCameraCheck.passed(total), "%s round %d places in the bowl: %s" % [name, pivots.size(), DotCameraCheck.summary(total)])


func _views_rule(game: BfhGame) -> void:
	_client.set("third_person", false)
	_client.call("toggle_view")
	_check(bool(_client.get("third_person")), "the view key goes to third person")
	game.view_rules.force_view = DotPlayerViewRules.FIRST_ONLY
	_client.call("toggle_view")
	_check(not bool(game.view_rules.resolve(_client.get("third_person"))), "mp_forceview 1 holds first person")
	game.view_rules.force_view = DotPlayerViewRules.ANY
	_client.set("third_person", false)


func _views(game: BfhGame) -> void:
	DirAccess.make_dir_recursive_absolute("screenshots/cameras")
	await _seconds(0.5)
	await _shot("buses_view_first")
	_client.call("toggle_view")
	await _seconds(0.6)
	await _shot("buses_view_third")
	_client.call("toggle_view")
	await _seconds(0.3)
	var me: BfhPlayer = _client.get("player")
	var camera: Camera3D = _client.get("camera")
	var other: BfhPlayer = null
	for id in game.players:
		var p: BfhPlayer = game.players[id]
		if p != me and not p.riding:
			other = p
			break
	if other == null:
		return
	var fade: DotCameraFade = _client.get("_fade")
	var figures: Callable = fade.bodies_fn
	fade.bodies_fn = Callable()
	await _held_at_lens(me, other, camera, "buses_walk_in_before")
	fade.bodies_fn = figures
	await _held_at_lens(me, other, camera, "buses_walk_in_after")


func _held_at_lens(me: BfhPlayer, other: BfhPlayer, camera: Camera3D, file: String) -> void:
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	for i in 20:
		other.controller.teleport(me.controller.state.position + ahead * 0.35, rad_to_deg(atan2(ahead.x, ahead.z)))
		other.global_position = other.controller.state.position
		await get_tree().process_frame
	await _shot(file)


func _shot(file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "screenshots/cameras/%s.png" % file
	var _saved := get_viewport().get_texture().get_image().save_png(path)
	print("  wrote %s" % path)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed = true


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
