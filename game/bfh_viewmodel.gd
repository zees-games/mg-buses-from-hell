extends Node3D

const BfhHammer := preload("bfh_hammer.gd")

## The runner's own hammer, drawn in first person. A child of the local camera, built in code from
## primitives: no art to vendor, so nothing here can break in a delivered pack.

const SWING_TIME := 0.28
const REST := Vector3(-25.0, -12.0, 8.0)
const SWUNG := Vector3(-95.0, -4.0, 8.0)

var hammer: BfhHammer = null

## Swings started, for the suite.
var swings: int = 0

var _pivot: Node3D = null
var _t: float = -1.0


func _init() -> void:
	name = "Viewmodel"
	position = Vector3(0.34, -0.34, -0.5)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.rotation_degrees = REST

	var wood := _material(Color(0.55, 0.38, 0.2))
	var iron := _material(Color(0.32, 0.33, 0.36))
	_part(CylinderMesh.new(), Vector3(0.0, 0.2, 0.0), wood, 0.035, 0.5)
	var head := BoxMesh.new()
	head.size = Vector3(0.09, 0.09, 0.2)
	var head_node := MeshInstance3D.new()
	head_node.mesh = head
	head_node.material_override = iron
	head_node.position = Vector3(0.0, 0.46, 0.0)
	head_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(head_node)
	visible = false
	set_process(false)


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


func _part(mesh: Mesh, at: Vector3, mat: Material, radius: float, length: float) -> void:
	var cyl := mesh as CylinderMesh
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(node)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
