extends Node3D

const BfhHammer := preload("bfh_hammer.gd")

## The runner's own hammer, drawn in first person. A child of the local camera, built in code from
## primitives: no art to vendor, so nothing here can break in a delivered pack.

const SWING_TIME := 0.28

## The pivot is the elbow; the forearm runs forward from it to the fist on the handle. REST and SWUNG
## are the forearm's turn (x is the chop: up at rest, down through the blow) and HAMMER_TILT the
## handle's in the fist, so the head leans forward at rest and comes down in front of the eye.
const REST := Vector3(15.0, -12.0, 8.0)
const SWUNG := Vector3(-40.0, -4.0, 8.0)
const HAMMER_TILT := Vector3(-40.0, 0.0, 0.0)

## Forearm length, elbow to the grip, metres.
const FOREARM := 0.34

const WOOD := Color(0.55, 0.38, 0.2)
const IRON := Color(0.32, 0.33, 0.36)
const SKIN := Color(0.87, 0.67, 0.52)
const SLEEVE := Color(0.24, 0.26, 0.3)

var hammer: BfhHammer = null

## Swings started, for the suite.
var swings: int = 0

var _pivot: Node3D = null
var _t: float = -1.0


func _init() -> void:
	name = "Viewmodel"
	# The elbow, below and behind the fist; the fist lands where the bare hammer's grip used to.
	position = Vector3(0.32, -0.38, -0.18)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.rotation_degrees = REST

	_box(_pivot, Vector3(0.075, 0.075, FOREARM), Vector3(0.0, 0.0, -FOREARM * 0.5), _material(SLEEVE), false)
	_box(_pivot, Vector3(0.09, 0.1, 0.1), Vector3(0.0, 0.0, -FOREARM), _material(SKIN), false)

	var head := build_hammer(_pivot, false)
	head.position = Vector3(0.0, 0.0, -FOREARM)
	head.rotation_degrees = HAMMER_TILT
	visible = false
	set_process(false)


## The hammer, built from primitives under [param parent]: the origin is the grip, the handle runs up
## +Y and the head's striking face points -Z. Life size (a 0.5 m handle); the third-person figure
## scales it. Returns the hammer's own node.
static func build_hammer(parent: Node3D, shadows: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Hammer"
	parent.add_child(root)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.035
	handle.bottom_radius = 0.035
	handle.height = 0.5
	_mesh(root, handle, Vector3(0.0, 0.2, 0.0), _material(WOOD), shadows)
	_box(root, Vector3(0.09, 0.09, 0.2), Vector3(0.0, 0.46, 0.0), _material(IRON), shadows)
	return root


func bind(p_hammer: BfhHammer) -> void:
	hammer = p_hammer
	if hammer != null:
		hammer.hit.connect(func(_id: int, _at: Vector3, _broke: bool) -> void: swing())
		hammer.missed.connect(func(_at: Vector3) -> void: swing())


## Whether a runner's frame shows the hammer: has one, alive, in their own eyes.
static func wanted(p_hammer: BfhHammer, alive: bool, riding: bool, spectating: bool, third_person: bool) -> bool:
	return p_hammer != null and alive and not riding and not spectating and not third_person


func show_for(on: bool) -> void:
	visible = on


## Starts a swing; a swing already under way is not restarted.
func swing() -> void:
	if _t >= 0.0:
		return
	_t = 0.0
	swings += 1
	set_process(true)


func swinging() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var k := clampf(_t / SWING_TIME, 0.0, 1.0)
	# Fast down, slower back.
	var w := k / 0.35 if k < 0.35 else 1.0 - (k - 0.35) / 0.65
	_pivot.rotation_degrees = REST.lerp(SWUNG, clampf(w, 0.0, 1.0))
	if k >= 1.0:
		_t = -1.0
		_pivot.rotation_degrees = REST
		set_process(false)


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, shadows: bool) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, at, mat, shadows)


static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material, shadows: bool) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
