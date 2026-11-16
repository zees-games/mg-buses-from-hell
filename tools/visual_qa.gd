extends DotGameVisualQaCapture

## Buses from Hell's visual QA capture (docs/testing.md, "Visual QA"; the loop is dot-game's docs/visual-qa.md).
## Each item is recorded frame by frame at --fps in three views (f first person, t behind-right, o in front):
##   person_<letter>  the six runners (a b c e f k) and the driver on foot (j), BfhFigure; f is a runner 2.5 m in front.
##   hammer           f is the runner's own BfhViewmodel at the eye; t and o draw a runner holding and swinging it.
##   bus              the bus standing, driving and turning; f is the cab eye the game spectates a driver from.
##   crate, barrel    on a turntable; the barrel also goes off (BfhBlast) where it stood.
##   bowl             the default map built in code, orbited from above; f stands on the sand by the wall.

const BfhFigure := preload("../game/bfh_figure.gd")
const BfhViewmodel := preload("../game/bfh_viewmodel.gd")
const BfhSpectate := preload("../game/bfh_spectate.gd")
const BfhArena := preload("../game/bfh_arena.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhBlast := preload("../fx/bfh_blast.gd")
const BfhConfig := preload("../game/bfh_config.gd")

## Your own body draws only in the outside views; the view model only in the first-person one.
const BODY_LAYER := 1 << 18
const VIEW_LAYER := 1 << 19
const ALL_LAYERS := 0xFFFFF
const BODY_HEIGHT := 1.8
const PERSON_CLIPS: PackedStringArray = ["idle", "walk", "run", "jump"]
const HAMMER_CLIPS: PackedStringArray = ["idle", "swing", "walk_swing"]
const BUS_CLIPS: PackedStringArray = ["idle", "drive", "turn"]
## Ground speed per clip (metres a second): a runner's run about 6.5, a walk about half; the bus at cruising speed.
const SPEED := {"idle": 0.0, "walk": 3.0, "run": 6.5, "jump": 3.0, "walk_swing": 3.0, "drive": 12.0, "turn": 9.0}
const SECONDS := {"idle": 2.0, "walk": 2.4, "run": 2.0, "jump": 1.6, "swing": 1.6, "walk_swing": 2.0,
	"drive": 3.0, "turn": 3.0, "turntable": 2.0, "blast": 1.5, "orbit": 4.0}
## Seconds between swings in a swing clip: a swing is BfhViewmodel.SWING_TIME, so this leaves a beat at rest between.
const SWING_EVERY := 0.6
## bone_pop limit in a swing clip: a real hammer blow turns the forearm well over 90 deg in 1/15 s.
const STRIKE_POP_DEG := 130.0
## The turning bus's steering lock, radians, and the radius of the circle it drives.
const TURN_STEER := 0.45
const TURN_RADIUS := 14.0

## The grid floor's side, metres: wide enough for the bus's drive and turn.
const FLOOR_M := 120.0

var _holder := Node3D.new()
var _figure: BfhFigure = null
var _model: BfhViewmodel = null
var _bus: VehicleBody3D = null
var _prop: Node3D = null
var _prop_model: Node3D = null
var _blast: BfhBlast = null
var _arena: Node3D = null
var _pivot: Node3D = null
var _kind := ""
var _swings := 0
var _prop_height := 1.0
var _prop_away := 2.5


func _items() -> PackedStringArray:
	var items := PackedStringArray()
	for path in BfhFigure.RUNNER_ATLASES:
		items.append("person_" + _letter(path))
	items.append("person_" + _letter(BfhFigure.DRIVER_ATLAS))
	items.append_array(["hammer", "bus", "crate", "barrel", "bowl"])
	return items


func _clips(item: String) -> PackedStringArray:
	if item.begins_with("person_"):
		return PERSON_CLIPS
	match item:
		"hammer": return HAMMER_CLIPS
		"bus": return BUS_CLIPS
		"barrel": return PackedStringArray(["turntable", "blast"])
		"bowl": return PackedStringArray(["orbit"])
	return PackedStringArray(["turntable"])


func _seconds(_item: String, clip: String) -> float:
	return float(SECONDS.get(clip, 2.0))


func _warmup_frames(_item: String, _clip: String) -> int:
	return 4


func _build() -> void:
	var _stage := build_stage()
	_widen_floor(FLOOR_M)
	first_person.cull_mask = ALL_LAYERS & ~BODY_LAYER
	root.add_child(_holder)


## The addon's floor is 40 m; the bus's drive and turn cover more than that. Grows the grid floor to
## [param size] metres a side, one grid square a metre as before.
func _widen_floor(size: float) -> void:
	for child in stage.get_children():
		var floor_mesh := child as MeshInstance3D
		if floor_mesh == null or not (floor_mesh.mesh is PlaneMesh):
			continue
		(floor_mesh.mesh as PlaneMesh).size = Vector2(size, size)
		var grid := floor_mesh.material_override as StandardMaterial3D
		if grid != null:
			grid.uv1_scale = Vector3(size, size, 1.0)
		return
	push_error("visual_qa: the stage has no plane floor to widen")


## Where the bus body rests on its wheels: the wheel's mount less the sprung length at rest and the
## radius, with the sag its suspension takes under the game's gravity.
func _ride_height() -> float:
	var wheels: Array[VehicleWheel3D] = []
	for child in _bus.get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
	if wheels.is_empty():
		push_error("visual_qa: the bus has no wheels")
		return 0.0
	var wheel := wheels[0]
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var stiffness := BfhConfig.new().bus_suspension_stiffness
	var sag := gravity / (wheels.size() * stiffness)
	return -(wheel.position.y - (wheel.wheel_rest_length - sag) - wheel.wheel_radius)


func _letter(path: String) -> String:
	return path.get_file().get_basename().trim_prefix("texture-")


func _atlas_of(letter: String) -> String:
	for path in BfhFigure.RUNNER_ATLASES:
		if _letter(path) == letter:
			return path
	return BfhFigure.DRIVER_ATLAS if _letter(BfhFigure.DRIVER_ATLAS) == letter else ""


func _stage(item: String, clip: String) -> DotResult:
	_clear()
	views.behind_offset = Vector3(1.6, 1.6, 3.2)
	views.behind_look_height = 1.0
	views.opponent_offset = Vector3(0.4, 1.6, -4.0)
	views.opponent_look_height = 1.3
	_swings = 0
	if item.begins_with("person_"):
		var atlas := _atlas_of(item.trim_prefix("person_"))
		if atlas == "":
			return DotResult.fail(DotError.CODE_INVALID, "no atlas for %s" % item)
		_kind = "person"
		_stand(atlas)
	elif item == "hammer":
		_kind = "hammer"
		# From the hammer-hand side the swing reads in profile.
		views.behind_offset = Vector3(2.4, 1.5, 2.2)
		views.opponent_offset = Vector3(2.6, 1.4, -2.6)
		views.opponent_look_height = 1.2
		_stand(BfhFigure.RUNNER_ATLASES[0])
		if _figure.has_method("hold_hammer"):
			_figure.call("hold_hammer", true)
		_model = BfhViewmodel.new()
		first_person.add_child(_model)
		_model.show_for(true)
		_model.set_process(false)
		var _tagged := DotGameVisualQaViews.tag_layers(_model, VIEW_LAYER)
	elif item == "bus":
		_kind = "bus"
		var scene := load(BfhContent.BUS_SCENE) as PackedScene
		if scene == null:
			return DotResult.fail(DotError.CODE_INVALID, "the bus scene would not load: %s" % BfhContent.BUS_SCENE)
		_bus = scene.instantiate() as VehicleBody3D
		_bus.freeze = true
		_holder.add_child(_bus)
		views.behind_offset = Vector3(6.0, 4.5, 11.0)
		views.behind_look_height = 1.6
		views.opponent_offset = Vector3(4.0, 3.0, -11.0)
		views.opponent_look_height = 1.6
	elif item == "crate" or item == "barrel":
		_kind = "prop"
		var path := BfhContent.CRATE_SCENE if item == "crate" else BfhContent.BARREL_SCENE
		var scene := load(path) as PackedScene
		if scene == null:
			return DotResult.fail(DotError.CODE_INVALID, "%s would not load" % path)
		_prop = Node3D.new()
		_holder.add_child(_prop)
		var body := scene.instantiate() as RigidBody3D
		body.freeze = true
		_prop_model = body
		_prop.add_child(body)
		var height := BfhContent.CRATE_SIZE if item == "crate" else BfhContent.BARREL_HEIGHT
		body.position.y = height * 0.5
		_frame_prop(Vector3(1.0, height, 1.0) if item == "crate" else Vector3(0.86, height, 0.86))
		if clip == "blast":
			body.visible = false
			_blast = BfhBlast.new()
			_prop.add_child(_blast)
			_blast.position.y = height * 0.5
			_blast.set_process(false)
			_blast.configure(BfhContent.BARREL_BLAST_RADIUS)
			var reach := BfhContent.BARREL_BLAST_RADIUS
			views.behind_offset = Vector3(reach * 0.8, reach * 0.6, reach * 1.6)
			views.behind_look_height = 1.0
			views.opponent_offset = Vector3(reach * 0.3, reach * 0.5, -reach * 1.6)
			views.opponent_look_height = 1.0
	elif item == "bowl":
		_kind = "bowl"
		_arena = BfhArena.new()
		_holder.add_child(_arena)
		_arena.call("build", BfhBowls.SMALL_RADIUS)
		_pivot = Node3D.new()
		_holder.add_child(_pivot)
		views.behind_offset = Vector3(0.0, 38.0, 62.0)
		views.behind_look_height = 0.0
		views.opponent_offset = Vector3(20.0, 12.0, -30.0)
		views.opponent_look_height = 2.0
	else:
		return DotResult.fail(DotError.CODE_INVALID, "no item %s" % item)
	return DotResult.success(clip)


func _stand(atlas: String) -> void:
	_figure = BfhFigure.new()
	_figure.name = "Figure"
	_holder.add_child(_figure)
	_figure.build(BODY_HEIGHT, atlas)
	# Driven a frame at a time below, as a client's frame would.
	_figure.person.auto_animate = false


## Cameras that fit the prop: every term scales with its size.
func _frame_prop(size: Vector3) -> void:
	var reach := maxf(size.y, maxf(size.x, size.z))
	var away := reach * 2.2
	_prop_height = size.y
	_prop_away = away
	views.behind_offset = Vector3(away * 0.45, size.y * 0.7 + reach * 0.3, away)
	views.behind_look_height = size.y * 0.5
	views.opponent_offset = Vector3(away * 0.15, size.y * 0.6 + reach * 0.3, -away)
	views.opponent_look_height = size.y * 0.5


func _clear() -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.free()
	if _model != null and is_instance_valid(_model):
		first_person.remove_child(_model)
		_model.free()
	_model = null
	_figure = null
	_bus = null
	_prop = null
	_prop_model = null
	_blast = null
	_arena = null
	_pivot = null


func _subject(_item: String) -> Node3D:
	match _kind:
		"bus": return _bus
		"prop": return _prop
		"bowl": return _pivot
	return _figure


func _drive(_item: String, clip: String, t: float, _frame: int) -> void:
	var step := 1.0 / float(fps)
	match _kind:
		"prop":
			if clip == "blast":
				_blast.age = 0.0
				_blast.advance(t)
			else:
				_prop_model.rotation.y = TAU * t / float(SECONDS["turntable"])
			return
		"bowl":
			_pivot.rotation.y = TAU * t / float(SECONDS["orbit"])
			return
		"bus":
			_drive_bus(clip, t)
			return
	var speed := float(SPEED.get(clip, 0.0))
	var airborne := false
	var vertical := 0.0
	var height := 0.0
	if clip == "jump":
		# A 0.6 s hop at the start, again at 1.0 s.
		var phase := fmod(t, 1.0) / 0.6
		airborne = phase < 1.0
		vertical = 4.0 * (1.0 - 2.0 * phase) if airborne else 0.0
		height = 2.4 * phase * (1.0 - phase) if airborne else 0.0
	var length := float(SECONDS.get(clip, 2.0))
	_figure.global_position = Vector3(0.0, height, -speed * t + speed * length * 0.5)
	_figure.face(0.0)
	_figure.person.set_motion({"on_floor": not airborne, "vertical": vertical, "crouched": false,
		"sprinting": clip == "run", "aim": 0.0, "velocity": Vector3(0.0, 0.0, -speed)})
	if _kind == "hammer" and clip != "idle":
		var due := int(floor((t - 0.2) / SWING_EVERY)) + 1 if t >= 0.2 else 0
		while _swings < due:
			_swings += 1
			_model.swing()
			if _figure.has_method("swing"):
				_figure.call("swing")
	_figure.person.animate(speed, step)
	if _model != null:
		_model.set_process(false)
		_model._process(step)


## The bus is frozen and moved by hand; the wheels are drawn from draw_roll and draw_steering, as a client's are.
func _drive_bus(clip: String, t: float) -> void:
	var speed := float(SPEED.get(clip, 0.0))
	var length := float(SECONDS.get(clip, 2.0))
	if clip == "turn":
		# Round a circle of TURN_RADIUS to the left, centred off the bus's left side.
		var angle := speed * (t - length * 0.5) / TURN_RADIUS
		var centre := Vector3(-TURN_RADIUS, 0.0, 0.0)
		_bus.global_transform = Transform3D(Basis(Vector3.UP, angle),
			centre + Vector3(TURN_RADIUS * cos(angle), _ride_height(), -TURN_RADIUS * sin(angle)))
		_bus.call("draw_steering", TURN_STEER)
	else:
		_bus.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, _ride_height(), -speed * t + speed * length * 0.5))
		_bus.call("draw_steering", 0.0)
	_bus.call("draw_roll", speed)


func _grounded(_item: String, clip: String, t: float) -> bool:
	return not (clip == "jump" and fmod(t, 1.0) < 0.6)


func _before_draw(_item: String, _clip: String, _frame: int) -> void:
	if _figure != null:
		var _tagged := DotGameVisualQaViews.tag_layers(_figure, BODY_LAYER)


## The hammer: the runner's own eye with the view model on it. The bus: the cab eye the game spectates a driver from.
## A person or prop: a runner's eye in front, looking at it. The bowl: standing on the sand by the wall, looking in.
func _place_first_person(_item: String) -> void:
	match _kind:
		"hammer":
			first_person.global_position = _figure.global_position + Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)
			first_person.rotation = Vector3.ZERO
			return
		"bus":
			var cab := Basis.from_euler(Vector3(deg_to_rad(BfhSpectate.CAB_PITCH_DEG), _bus.global_rotation.y, 0.0))
			first_person.global_transform = Transform3D(cab, _bus.global_transform * BfhSpectate.CAB_EYE)
			return
		"bowl":
			first_person.global_position = Vector3(0.0, BfhPlayer.EYE_HEIGHT, BfhBowls.SMALL_RADIUS - 4.0)
			first_person.look_at(Vector3(0.0, 2.0, 0.0))
			return
	var subject := _subject("")
	var height := BODY_HEIGHT if _kind == "person" else _prop_height
	var away := 2.5 if _kind == "person" else _prop_away
	var eye := BfhPlayer.EYE_HEIGHT if _kind == "person" else clampf(height * 1.4, 0.1, BfhPlayer.EYE_HEIGHT)
	if _blast != null:
		away = BfhContent.BARREL_BLAST_RADIUS * 1.6
		eye = BfhPlayer.EYE_HEIGHT
	first_person.global_position = subject.global_position + Vector3(0.0, eye, -away)
	first_person.look_at(subject.global_position + Vector3(0.0, height * 0.5, 0.0))


## A swing clip's forearm turns faster than a walk's: its bone_pop limit is a blow's. Props and the bus: the art on the floor.
func _checks(_item: String, clip: String, rows: Array[Dictionary]) -> Array[Dictionary]:
	if _kind == "hammer" and clip != "idle":
		for row: Dictionary in rows:
			if row["check"] == "bone_pop" and not row.get("skip", false):
				row["pass"] = float(row["value"]) <= STRIKE_POP_DEG
				row["limit"] = STRIKE_POP_DEG
				row["note"] = "%s (a hammer blow)" % row.get("note", "")
	if _kind == "prop" and _blast == null:
		var box := _bounds(_prop_model)
		rows.append({"check": "prop_floor_m", "pass": absf(box.position.y) <= 0.03, "value": snappedf(box.position.y, 0.001),
			"limit": 0.03, "note": "the art's lowest point above (+) or under (-) the floor"})
	if _kind == "bus":
		# Measured with the wheels unturned: a turned wheel's box reaches past its round tyre.
		var turned := {}
		for mesh in _bus.find_children("wheel*", "MeshInstance3D", true, false):
			turned[mesh] = mesh.rotation
			mesh.rotation = Vector3.ZERO
		var box := _bounds(_bus)
		for mesh: Node3D in turned:
			mesh.rotation = turned[mesh]
		var lowest := box.position.y
		rows.append({"check": "bus_floor_m", "pass": absf(lowest) <= 0.05, "value": snappedf(lowest, 0.001),
			"limit": 0.05, "note": "the art's lowest point (the tyres) above (+) or under (-) the floor"})
	return rows


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var local := m.global_transform * m.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box
