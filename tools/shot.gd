extends Node

const BfhContent := preload("../game/bfh_content.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhVote := preload("../game/bfh_vote.gd")

## Renders the game from the local player's eyes and exits. The check no assertion makes.

func _ready() -> void:
	_run.call_deferred()

var _o_seconds := 3.0
var _o_out := "res://screenshots/bfh.png"
var _o_look_at_bus := false
var _o_look_at_stacks := false
var _o_look_at_lane := false
var _o_look_at_hook := false
var _o_look_at_west_lane := false
var _o_look_at_tanks := false
var _o_look_at_yard := ""
var _o_look_at_scaffold := false
var _o_look_at_ramp := false
var _o_on_deck := false
var _o_plan := false
var _o_show_chat := false
var _o_beacon := false
var _o_blind := false
var _o_settings := false
var _o_maps := false
var _o_watch := ""
var _o_blast := false
var _o_crate_break := false
var _o_scoreboard := false
var _o_ballot := false
var _o_cover := false
var _o_swing := false
var _o_killcam := false
var _o_bowl_id := ""
var _o_action: Array = []
var _o_killcam_seconds := 0.0
var _o_elapsed := 0.0


func _run() -> void:
	_parse_args()
	_shot_maps_fixture()
	var client: Node = load("res://game/bfh.tscn").instantiate()
	add_child(client)

	if _o_cover:
		await _shot_cover(client)
		return
	_shot_bowl(client)
	_shot_chat(client)
	_shot_deck(client)
	await _shot_wait()
	await _shot_swing(client)

	if not _o_action.is_empty():
		await _stage_action(client, _o_action[0], _o_action[1], _o_out)
		get_tree().quit(0)
		return

	await _shot_marks(client)
	await _shot_maps_menu(client)
	await _shot_settings(client)
	await _shot_watch(client)
	await _shot_beacon(client)
	await _shot_stacks(client)
	await _shot_lane(client)
	await _shot_hook(client)
	await _shot_west(client)
	await _shot_tanks(client)
	await _shot_yard(client)
	await _shot_scaffold(client)
	await _shot_ramp(client)
	await _shot_bus(client)
	await _shot_blast(client)
	await _shot_scoreboard(client)
	await _shot_killcam(client)
	await _shot_plan(client)
	await _shot_ballot(client)

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(_o_out))
	print("wrote ", _o_out, " after %.1f s" % _o_elapsed)
	await DotShotSeq.new().record(get_tree(), ProjectSettings.globalize_path(_o_out))

	var world: BfhGame = client.get("game")
	if world != null:
		for line in world.describe_lines():
			print(line)

	get_tree().quit(0)


func _parse_args() -> void:
	var user_args := OS.get_cmdline_user_args()
	var action_at := user_args.find("--action")
	if action_at >= 0 and action_at + 2 < user_args.size():
		_o_action = [StringName(user_args[action_at + 1]), String(user_args[action_at + 2])]
	for arg in user_args:
		if arg.begins_with("--seconds="):
			_o_seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			_o_out = arg.substr(6)
		elif arg == "--touch":
			DotPlatform.touch_override = 1
		elif arg == "--swing":
			_o_swing = true
		elif arg == "--bus":
			_o_look_at_bus = true
		elif arg == "--stacks":
			_o_look_at_stacks = true
		elif arg == "--lane":
			_o_look_at_lane = true
		elif arg == "--hook":
			_o_look_at_hook = true
		elif arg == "--west-lane":
			_o_look_at_west_lane = true
		elif arg == "--tanks":
			_o_look_at_tanks = true
		elif arg == "--yard":
			_o_look_at_yard = "peak"
		elif arg.begins_with("--yard="):
			_o_look_at_yard = arg.substr(7)
		elif arg == "--scaffold":
			_o_look_at_scaffold = true
		elif arg == "--ramp":
			_o_look_at_ramp = true
		elif arg == "--plan":
			_o_plan = true
		elif arg == "--deck":
			_o_on_deck = true
		elif arg == "--chat":
			_o_show_chat = true
		elif arg == "--beacon":
			_o_beacon = true
		elif arg == "--blind":
			_o_blind = true
		elif arg == "--settings":
			_o_settings = true
		elif arg == "--maps":
			_o_maps = true
		elif arg == "--blast":
			_o_blast = true
		elif arg == "--crate":
			_o_crate_break = true
		elif arg == "--scoreboard":
			_o_scoreboard = true
		elif arg == "--ballot":
			_o_ballot = true
		elif arg == "--view=cover":
			_o_cover = true
		elif arg == "--view=killcam":
			_o_killcam = true
		elif arg.begins_with("--bowl="):
			_o_bowl_id = arg.substr(7)
		elif arg.begins_with("--watch="):
			_o_watch = arg.substr(8)



## A fixture bowl pack in the shared content index, for `--maps`.
func _shot_maps_fixture() -> void:
	# `--maps`: a fixture bowl pack in the shared DotContentIndex, as the solo shell leaves one
	# after a subscribed pack mounts, and the M menu opened on it.
	if _o_maps:
		var dir := "user://ws_shot_bfh/"
		DirAccess.make_dir_recursive_absolute(dir)
		var file := FileAccess.open(dir + "pit.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"radius": 50.0}))
		file.close()
		var index := DotContentIndex.shared()
		index.set_session(DotContentIndex.SESSION_SOLO)
		var _added := index.add_pack({
			"content_id": "fixture/bowls", "version": "1.0.0", "prefix": dir,
			"session": DotContentIndex.SESSION_SOLO, "source": &"subscription",
			"provides": {"schema": 1, "title": "Hilltop Pack", "kinds": ["map"], "entries": [
				{"kind": "map", "id": "fixture_pit", "name": "Fixture Pit", "scene": "pit.json", "map_kind": "arena"},
			]},
		})


## `--view=cover`: the loading cover, before it lifts.
func _shot_cover(client: Node) -> void:
	# --view=cover: the loading cover dot-game's DotGameClient puts up first, before it lifts.
	if _o_cover:
		for _i in 2:
			await RenderingServer.frame_post_draw
		var platform: DotGameClient = client.get("platform")
		print("cover %s" % ("lifted" if platform.is_shown() else "up"))
		var cover_path := ProjectSettings.globalize_path(_o_out)
		DirAccess.make_dir_recursive_absolute(cover_path.get_base_dir())
		print("saved %s: %s" % [_o_out, error_string(get_viewport().get_texture().get_image().save_png(cover_path))])
		get_tree().quit(0)
		return


## `--bowl=`: play in one of the ballot's bowls.
func _shot_bowl(client: Node) -> void:
	# `--bowl=bfh_downtown`: play in one of the ballot's bowls (BfhBowls ids), through the
	# map menu's own door, so the round that begins is laid out on that floor.
	if _o_bowl_id != "":
		var world_for_bowl: BfhGame = client.get("game")
		if world_for_bowl != null:
			print("bowl change: ", world_for_bowl.change_bowl_now(StringName(_o_bowl_id)).ok)


## `--chat`: the chat box with something in it.
func _shot_chat(client: Node) -> void:
	# The chat box, with something in it. A box drawn empty says nothing about whether a
	# line would be readable over a sand-coloured bowl in bright light, which is the only
	# question a picture of it can answer.
	if _o_show_chat:
		var chat: Node = client.get("chat")

		if chat != null and chat.get("window") != null:
			var window = chat.get("window")
			window.add_said("Driver", "coming round the stacks", Color(0.55, 0.82, 0.95))
			window.add_said("Ada", "north ramp, north ramp", Color(0.88, 0.90, 0.94))
			window.add_text("Bus driver 1 was run over by nobody", Color(0.98, 0.72, 0.35))


## `--deck`: the runner on the deck, and a camera at the ramp's foot.
func _shot_deck(client: Node) -> void:
	var world_for_deck: BfhGame = client.get("game")
	var runner_for_deck: Node3D = client.get("player")
	if _o_on_deck and world_for_deck != null and world_for_deck.arena != null and runner_for_deck != null:
		var stand := world_for_deck.arena.ledge_centre()
		stand.y = world_for_deck.arena.deck_top() + 0.05
		runner_for_deck.global_position = stand
		runner_for_deck.get("controller").get("state").set("position", stand)
		var foot := world_for_deck.arena.ramp_foot()
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = foot + Vector3(-14.0, 17.0, 16.0)
		cam.look_at(foot + Vector3(0.0, 0.0, 4.0), Vector3.UP)
		cam.current = true


## Spend the requested seconds drawing.
func _shot_wait() -> void:
	# --view=killcam spends --seconds after the round ends, not before.
	_o_killcam_seconds = _o_seconds
	if _o_killcam:
		_o_seconds = 4.0
	_o_elapsed = 0.0
	while _o_elapsed < _o_seconds:
		_o_elapsed += get_process_delta_time()
		await get_tree().process_frame


## `--swing`: the hammer a third of the way through its swing.
func _shot_swing(client: Node) -> void:
	# --swing: the hand's hammer a third of the way through its swing.
	if _o_swing and client.get("viewmodel") != null:
		client.get("viewmodel").call("swing")
		var into := 0.0
		while into < 0.1:
			into += get_process_delta_time()
			await get_tree().process_frame


## `--beacon` and `--blind`: an administrator's marks.
func _shot_marks(client: Node) -> void:
	# An administrator's marks, set the way the handlers set them and then given a few frames to draw.
	var world_for_marks: BfhGame = client.get("game")
	var local_player: Node3D = client.get("player")
	if (_o_beacon or _o_blind) and world_for_marks != null:
		for id in world_for_marks.players:
			var someone: Node = world_for_marks.players[id]
			if _o_beacon:
				someone.set("beacon", true)
			if _o_blind and someone == local_player:
				someone.set("blinded", true)
		var settle := 0.0
		while settle < 0.6:
			settle += get_process_delta_time()
			await get_tree().process_frame


## `--maps`: the M menu opened on the fixture bowl.
func _shot_maps_menu(client: Node) -> void:
	if _o_maps and client.get("settings") != null:
		await get_tree().create_timer(0.5).timeout
		var menu: Variant = client.get("settings").get("menu")
		menu.call(&"open_maps")
		var picker: Variant = menu.get("picker")
		var world_for_maps: BfhGame = client.get("game")
		if picker != null and world_for_maps != null:
			var rows := world_for_maps.bowl_rows(DotContentIndex.shared())
			for i in range(rows.size()):
				if str(rows[i]["id"]) == "fixture_pit":
					picker.call(&"turn", 99)
					picker.call(&"turn", i - rows.size() + 1)
		await get_tree().create_timer(0.3).timeout


## `--settings`: the screen Escape opens.
func _shot_settings(client: Node) -> void:
	# The settings screen, over the bowl, the way Escape opens it.
	if _o_settings and client.get("settings") != null:
		client.get("settings").call("open")
		var shown := 0.0
		while shown < 0.3:
			shown += get_process_delta_time()
			await get_tree().process_frame


## `--watch=`: run down, then where the camera goes.
func _shot_watch(client: Node) -> void:
	var world_for_marks: BfhGame = client.get("game")
	var local_player: Node3D = client.get("player")
	# Run down, and then where the camera goes: `--watch=death` is the death camera, `cab` the freeze
	# on the bus's cab, `follow` the first person it hands over to and `chase` the view behind them.
	if _o_watch != "" and world_for_marks != null and local_player != null \
			and not world_for_marks.drivers().is_empty():
		var buddy: Node3D = world_for_marks.add_player(
			&"buddy", "Bea", BfhGame.TEAM_RUNNERS, false, true
		)
		buddy.set("global_position", local_player.global_position + Vector3(3.0, 0.0, 6.0))
		buddy.get("controller").get("state").set("position", buddy.global_position)
		var killer: StringName = world_for_marks.drivers()[0].player_id
		world_for_marks.call("_bus_hit", local_player, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		var wait := {"death": 0.4, "cab": 1.8, "follow": 3.6, "chase": 3.6}.get(_o_watch, 0.4) as float
		var waited := 0.0
		var asked := false
		while waited < wait + (0.6 if _o_watch == "chase" else 0.0):
			waited += get_process_delta_time()
			if _o_watch == "chase" and not asked and waited >= wait:
				asked = true
				var _v: Variant = world_for_marks.spectate.request(&"local", 2)
			await get_tree().process_frame
		print("watching: ", world_for_marks.spectate.describe_view(&"local"))


## `--beacon`: a camera behind the runner.
func _shot_beacon(client: Node) -> void:
	var local_player: Node3D = client.get("player")
	if _o_beacon and not _o_look_at_bus and local_player != null:
		var cam := Camera3D.new()
		add_child(cam)
		var behind := local_player.global_basis.z.normalized()
		cam.global_position = local_player.global_position + behind * 8.0 + Vector3(0.0, 4.0, 0.0)
		cam.look_at(local_player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--stacks`: over the stacks, looking down the lane.
func _shot_stacks(client: Node) -> void:
	# Stand over the stacks and look down the lane: a random spawn shows them only by luck.
	var world_for_stacks: BfhGame = client.get("game")
	if _o_look_at_stacks and world_for_stacks != null and world_for_stacks.arena != null:
		var pillars := world_for_stacks.arena.pillars()
		if not pillars.is_empty():
			var middle := Vector3.ZERO
			for pillar in pillars:
				middle += pillar
			middle /= float(pillars.size())

			var cam := Camera3D.new()
			add_child(cam)
			# Low and off the end of the lane: can a route be read at eye height.
			cam.global_position = middle + Vector3(-26.0, 11.0, -22.0)
			cam.look_at(middle + Vector3(0.0, 2.0, 0.0), Vector3.UP)
			cam.current = true
			await get_tree().process_frame


## `--lane`: the stacks' second lane from its west mouth.
func _shot_lane(client: Node) -> void:
	# Or stand in the stacks' second lane's west mouth, at a runner's eyes, and look down
	# it: the question is whether it reads as a second way through, with the hook's south
	# pillar across its far end and the scaffold past that, rather than as more columns.
	var world_for_lane: BfhGame = client.get("game")
	if _o_look_at_lane and world_for_lane != null and world_for_lane.arena != null \
			and not world_for_lane.arena.pillars().is_empty():
		var arena = world_for_lane.arena
		var lane_z: float = arena.STACK_LANES[1]
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = arena.stack_point(Vector2(-14.0, lane_z)) + Vector3(0.0, 1.7, 0.0)
		cam.look_at(arena.stack_point(Vector2(arena.STACK_LANE_END, lane_z)) + Vector3(0.0, 1.4, 0.0),
			Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--hook`: outside the hook's south-middle gap.
func _shot_hook(client: Node) -> void:
	# Or stand outside the hook at a runner's eyes, square to its south-middle gap, and
	# look in: whether its two gaps read as ways a bus comes through or as slots between
	# columns. Pass --bfh-hook-layout=wide to see the other hook (`BfhArena.HOOK_LAYOUTS`).
	var world_for_hook: BfhGame = client.get("game")
	if _o_look_at_hook and world_for_hook != null and world_for_hook.arena != null \
			and not world_for_hook.arena.pillars().is_empty():
		var arena = world_for_hook.arena
		var p: PackedVector3Array = arena.pillars()
		var h: int = arena.HOOK_FIRST
		var centroid: Vector3 = (p[h] + p[h + 1] + p[h + 2]) / 3.0
		var mouth: Vector3 = (p[h + 1] + p[h + 2]) * 0.5
		var away: Vector3 = mouth - centroid
		away.y = 0.0
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = mouth + away.normalized() * 11.0 + Vector3(0.0, 3.2, 0.0)
		cam.look_at(centroid + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--west-lane`: outside the courtyard's west lane.
func _shot_west(client: Node) -> void:
	var world_for_west: BfhGame = client.get("game")
	if _o_look_at_west_lane and world_for_west != null and world_for_west.arena != null \
			and not world_for_west.arena.tanks().is_empty():
		var arena = world_for_west.arena
		var middle: Vector3 = arena.yard_middle(0)
		var mouth: Vector3 = arena.yard_lane_middle(0, 3)
		var away: Vector3 = mouth - middle
		away.y = 0.0
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = mouth + away.normalized() * 9.0 + Vector3(0.0, 2.2, 0.0)
		cam.look_at(middle + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--tanks`: the tank farm's lane mouth at a runner's height.
func _shot_tanks(client: Node) -> void:
	# The mouth of one of the tank farm's lanes at a runner's height, the view the farm was designed
	# around: do the tanks hide a bus, or read as bollards.
	var world_for_tanks: BfhGame = client.get("game")
	if _o_look_at_tanks and world_for_tanks != null and world_for_tanks.arena != null:
		var farm := world_for_tanks.arena.tanks()
		if not farm.is_empty():
			# The first courtyard's middle, not every tank's: since the back yard the
			# farm is two rooms, and the centroid of all six is a point in neither.
			var middle := world_for_tanks.arena.yard_middle(0)

			var cam := Camera3D.new()
			add_child(cam)
			# Off the north-west mouth, clear of the RAMP (x = 0), which a camera can end up inside.
			cam.global_position = middle + Vector3(-19.0, 4.5, -14.0)
			cam.look_at(middle + Vector3(1.0, 2.5, 0.0), Vector3.UP)
			cam.current = true
			await get_tree().process_frame


## `--yard`: the tank farm's back yard.
func _shot_yard(client: Node) -> void:
	# The tank farm's back yard. `--yard` (or `=peak`) is the scaffold's peak looking north down the
	# covered way; `--yard=courtyard` stands in the first courtyard and looks through the shared lane.
	var world_for_yard: BfhGame = client.get("game")
	if _o_look_at_yard != "" and world_for_yard != null and world_for_yard.arena != null \
			and world_for_yard.arena.tanks().size() > 4:
		var arena = world_for_yard.arena
		var yard: Vector3 = arena.yard_middle(1)
		var cam := Camera3D.new()
		add_child(cam)
		if _o_look_at_yard == "courtyard":
			var court: Vector3 = arena.yard_middle(0)
			var away := (court - yard).normalized()
			cam.global_position = court + away * 3.0 + Vector3(0.0, 1.6, 0.0)
			cam.look_at(yard + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		elif arena.has_scaffold():
			var top: AABB = arena.scaffold_steps()[arena.scaffold_peak()]
			var eye := top.get_center() + Vector3(0.0, top.size.y * 0.5 + 1.6, 0.0)
			cam.global_position = eye
			cam.look_at(yard + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--scaffold`: off the scaffold's low end, looking up.
func _shot_scaffold(client: Node) -> void:
	# Off the scaffold's low end, a little above a runner's eyes, looking up it: three steps should
	# read as a way UP, and the top as higher than a bus.
	var world_for_scaffold: BfhGame = client.get("game")
	if _o_look_at_scaffold and world_for_scaffold != null and world_for_scaffold.arena != null \
			and world_for_scaffold.arena.has_scaffold():
		var box := world_for_scaffold.arena.scaffold_footprint()
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = box.position + Vector3(-3.5, 2.4, box.size.z + 5.0)
		cam.look_at(box.get_center() + Vector3(0.5, 0.2, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--ramp`: the ramp from its side.
func _shot_ramp(client: Node) -> void:
	# Or stand in the bowl west of the ramp and look along it to the ledge: the ramp was
	# built backwards for nine days and a picture of it from the side is the one view
	# where that is obvious at a glance.
	var world_for_ramp: BfhGame = client.get("game")
	if _o_look_at_ramp and world_for_ramp != null and world_for_ramp.arena != null:
		var foot := world_for_ramp.arena.ramp_foot()
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = foot + Vector3(-13.0, 4.5, 1.0)
		cam.look_at(foot + Vector3(0.0, 3.5, -15.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame


## `--bus`: stand off and look at the bus.
func _shot_bus(client: Node) -> void:
	# Optionally stand off and look at the bus instead of out of the player's eyes.
	# The one thing a first-person camera cannot show is the vehicle chasing it.
	var world_for_view: BfhGame = client.get("game")
	if _o_look_at_bus and world_for_view != null and not world_for_view._bus_ids.is_empty():
		var bus := world_for_view.vehicles.get_vehicle(world_for_view._bus_ids[0])
		if bus != null and bus.is_alive():
			var cam := Camera3D.new()
			add_child(cam)
			cam.global_position = bus.position() + Vector3(7.0, 4.5, 7.0)
			cam.look_at(bus.position(), Vector3.UP)
			cam.current = true
			await get_tree().process_frame


## `--blast` and `--crate`: a barrel going off and a crate breaking ahead of the runner.
func _shot_blast(client: Node) -> void:
	# A barrel going off twelve metres in front of the local runner, drawn by the client's own effects
	# from the world's `barrel_exploded` — the path a connected client takes from a BLAST.
	var world_for_blast: BfhGame = client.get("game")
	var eye_for_blast: Camera3D = client.get("camera")
	if _o_blast and world_for_blast != null and eye_for_blast != null:
		var ahead := -eye_for_blast.global_basis.z
		ahead.y = 0.0
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
		var at := eye_for_blast.global_position + ahead * 12.0
		at.y = 0.0
		var barrel := world_for_blast.props.spawn(BfhContent.BARREL, &"world",
			at + Vector3(0.0, BfhContent.BARREL_HEIGHT * 0.5 + 0.05, 0.0))
		await get_tree().process_frame
		world_for_blast.prop_damage.break_now(barrel.instance_id, &"local")
		var burning := 0.0
		while burning < 0.2:
			burning += get_process_delta_time()
			await get_tree().process_frame
		var fx: Node = client.get("fx")
		print("fx: ", fx.call("describe") if fx != null else "none")
		var drawn: Node3D = fx.get("last_blast") if fx != null else null
		if drawn != null:
			print("blast at %s, radius %.2f, ring drawn to %.2f m" % [
				str(drawn.global_position), float(drawn.get("radius")), float(drawn.call("drawn_reach"))])

	# A crate breaking five metres ahead: splinters from dot-fx's break effect.
	if _o_crate_break and world_for_blast != null and eye_for_blast != null:
		var fwd := -eye_for_blast.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var spot := eye_for_blast.global_position + fwd * 5.0
		spot.y = 0.0
		var crate := world_for_blast.props.spawn(BfhContent.CRATE, &"world", spot + Vector3(0.0, 0.6, 0.0))
		await get_tree().process_frame
		world_for_blast.prop_damage.break_now(crate.instance_id, &"local")
		var splintering := 0.0
		while splintering < 0.18:
			splintering += get_process_delta_time()
			await get_tree().process_frame


## `--scoreboard`: real match state, then Tab held.
func _shot_scoreboard(client: Node) -> void:
	# The scoreboard from real match state: three more runners, a round the buses win
	# (which puts it up on its own), then the next round with one runner out and Tab held.
	var world_for_board: BfhGame = client.get("game")
	if _o_scoreboard and world_for_board != null:
		for name in ["Ada", "Bea", "Cy"]:
			var _r := world_for_board.add_player(StringName(name.to_lower()), name,
				BfhGame.TEAM_RUNNERS, false, true)
		var waited_live := 0.0
		while not world_for_board.match_node.is_live() and waited_live < 20.0:
			waited_live += get_process_delta_time()
			await get_tree().process_frame
		var killer: StringName = world_for_board.drivers()[0].player_id
		for runner in world_for_board.runners():
			world_for_board.call("_bus_hit", runner, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		await get_tree().process_frame
		print("after the round: ", client.get("scoreboard").call("describe"))
		var round_one := world_for_board.round_number
		var waited_next := 0.0
		while world_for_board.round_number == round_one and waited_next < 20.0:
			waited_next += get_process_delta_time()
			await get_tree().process_frame
		await get_tree().process_frame
		var cy: Node = world_for_board.players.get(&"cy")
		if cy != null:
			world_for_board.call("_bus_hit", cy, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		tab.pressed = true
		client.get("scoreboard").call("handle_key", tab)
		var settle_board := 0.0
		while settle_board < 0.3:
			settle_board += get_process_delta_time()
			await get_tree().process_frame
		print("held: ", client.get("scoreboard").call("describe"))


## `--view=killcam`: the last runner flattened, the replay and the podium.
func _shot_killcam(client: Node) -> void:
	# The last runner flattened by a bus, the buses win: ~2 s later is the replay, ~7.5 the podium.
	var world_for_cam: BfhGame = client.get("game")
	if _o_killcam and world_for_cam != null:
		for name in ["Ada", "Bea"]:
			var _r := world_for_cam.add_player(StringName(name.to_lower()), name,
				BfhGame.TEAM_RUNNERS, false, true)
		var live := 0.0
		while not world_for_cam.match_node.is_live() and live < 20.0:
			live += get_process_delta_time()
			await get_tree().process_frame
		var lead := 0.0
		while lead < 3.0:
			lead += get_process_delta_time()
			await get_tree().process_frame
		var by: StringName = world_for_cam.drivers()[0].player_id
		for runner in world_for_cam.runners():
			world_for_cam.call("_bus_hit", runner, by, 30.0, Vector3(0.0, 0.0, 1.0))
		var after := 0.0
		while after < _o_killcam_seconds:
			after += get_process_delta_time()
			await get_tree().process_frame


## `--plan`: the whole bowl from straight above.
func _shot_plan(client: Node) -> void:
	# The whole bowl from straight above, north (the deck) at the top. The one view that shows where
	# everything is against everything else -- which is the question when choosing where a new piece of
	# the map goes, and the one a runner's-eye camera cannot answer.
	var world_for_plan: BfhGame = client.get("game")
	if _o_plan and world_for_plan != null and world_for_plan.arena != null:
		var cam := Camera3D.new()
		add_child(cam)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = world_for_plan.arena.radius * 2.1
		cam.global_position = Vector3(0.0, 80.0, 0.0)
		cam.look_at(Vector3.ZERO, Vector3.FORWARD)
		cam.far = 200.0
		cam.current = true
		await get_tree().process_frame


## `--ballot`: the bowl vote's ballot over the frame.
func _shot_ballot(client: Node) -> void:
	# The bowl vote's ballot over the frame, as the client shell draws it.
	var world_for_ballot: BfhGame = client.get("game")
	if _o_ballot and world_for_ballot != null:
		var list: Array = []
		for bowl in BfhBowls.allowed(world_for_ballot.config):
			list.append([bowl["id"], bowl["name"]])
		await _show_ballot(list, world_for_ballot.bowl_id)



## A real ballot from this game's vote: every bowl this server offers there is, four voters, three
## of whom have voted, drawn the way the client shell's notice overlay draws a `map_ballot` — a
## [DotBallotPanel] down the right-hand side.
func _show_ballot(list: Array, current: StringName) -> void:
	var names := {&"1": "you", &"2": "bo", &"3": "quiet_one", &"4": "ana"}
	var states: Array = []
	var vote: Node = BfhVote.new()
	vote.set("config_path", "")
	vote.set("bowls_fn", func() -> Array: return list)
	vote.set("voters_fn", func() -> Array: return names.keys())
	vote.set("people_fn", func(voter: StringName) -> Dictionary: return {"name": names.get(voter, "?"), "avatar": ""})
	vote.set("ballot_fn", func(state: Dictionary) -> void: states.append(state))
	add_child(vote)
	var _set: DotResult = vote.call("setup")
	vote.call("note_bowl", current)
	var director: DotVoteDirector = vote.get("director")
	var _opened := director.open_vote(DotVoteClock.REASON_MANUAL)
	var options := director.ballot.option_ids()
	var _a := director.cast_one(&"1", options[0])
	var _b := director.cast_one(&"2", options[1 % options.size()])
	var _c := director.cast_one(&"3", options[0])
	(vote.get("feed") as DotVoteBallotFeed).poll()

	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -376.0
	box.offset_right = -16.0
	box.offset_top = 110.0
	box.offset_bottom = -16.0
	layer.add_child(box)
	var panel := DotBallotPanel.new()
	panel.ui_theme = DotUiTheme.space()
	panel.local_voter = "1"
	box.add_child(panel)
	panel.show_state(states.back() if not states.is_empty() else {})

	var waited := 0.0
	while waited < 1.0:
		waited += get_process_delta_time()
		await get_tree().process_frame


## `--action <kind> <id>` (`--action emote dance`): the local runner, in third person, playing an
## avatar action through the client's own input path, from the front, early and later in the
## clip. Writes <out>_a.png and <out>_b.png.
func _stage_action(client: Node, kind: StringName, id: String, out: String) -> void:
	var me: Node3D = client.get("player")
	if me == null:
		print("action: no local player")
		return
	client.set("third_person", true)
	for _i in range(20):
		await get_tree().process_frame
	var figure: Object = client.call("_avatar_figure", 0)
	print("action %s/%s: figure=%s third_person=%s" % [kind, id, figure != null, client.get("third_person")])
	var entry := DotAvatarActions.defaults().find(kind, id)
	var input: Object = (client.get("platform") as DotGameClient).avatar_actions.input
	input.emit_signal(&"action_requested", entry)
	var yaw := deg_to_rad((me.get("controller") as DotFpsController).state.yaw)
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var feet: Vector3 = me.global_position
	var camera := Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.current = true
	for part in ["a", "b"]:
		for _i in range(12 if part == "a" else 30):
			await get_tree().process_frame
		camera.global_position = feet + ahead * 3.2 + Vector3.UP * 1.6
		camera.look_at(feet + Vector3.UP * 1.0, Vector3.UP)
		for _i in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := out.trim_suffix(".png") + "_%s.png" % part
		var _saved := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("wrote ", path, " action=", figure.get("action") if figure != null else "n/a")
