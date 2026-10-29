extends VehicleBody3D

## The bus's own body: the art, and the four wheels that have to be seen turning.

const BfhArt := preload("bfh_art.gd")

const CHANNEL := "bfh.bus"

## Where the art lives under this body. The scene's own node name.
const ART_NODE := ^"Art"

## The Kenney model's wheel meshes, in its own naming. The front pair steers.
const ART_FRONT_WHEELS: Array[String] = ["wheel-front-left", "wheel-front-right"]
const ART_REAR_WHEELS: Array[String] = ["wheel-back-left", "wheel-back-right"]

var _art: Node3D = null
var _front: Array[MeshInstance3D] = []
var _rear: Array[MeshInstance3D] = []

## Radius of the wheel a player can SEE, in metres, which is not the simulated one.
var _art_wheel_radius: float = 0.47

## +1 when the art faces the way the vehicle drives, -1 when it is turned round.
var _art_sign: float = 1.0

## Radians of roll accumulated. Wrapped, because a float that grows for an hour loses the
## precision the rotation is drawn at.
var _roll: float = 0.0

## What a mirror was last told. Unused on the authority, which reads the wheels directly.
var _mirror_steering: float = 0.0
var _mirror_speed: float = 0.0
var _mirrored: bool = false


func _ready() -> void:
	_art = get_node_or_null(ART_NODE) as Node3D

	if _art == null:
		# `push_error`, not a log line: a bus with no art node is a scene somebody edited
		# wrongly, and the person who has to act is the one editing the file.
		push_error("BfhBus: no %s node under the body." % ART_NODE)
		return

	_art_sign = -1.0 if _art.transform.basis.z.dot(Vector3.BACK) < 0.0 else 1.0

	# The car kit's atlas, which is a different file from the survival kit's one of the
	# same name. Nothing happens in a build; see [BfhArt] for what happens in a pack.
	var repaired := BfhArt.paint(_art, BfhArt.CAR_ATLAS)

	if repaired > 0:
		DotLog.debug(CHANNEL, "the bus was repainted from the mount", {"materials": repaired})

	for name_of in ART_FRONT_WHEELS:
		var wheel := _find_mesh(_art, name_of)
		if wheel != null:
			_front.append(wheel)

	for name_of in ART_REAR_WHEELS:
		var wheel := _find_mesh(_art, name_of)
		if wheel != null:
			_rear.append(wheel)

	if _front.is_empty() and _rear.is_empty():
		push_error("BfhBus: the art has none of the wheel meshes this script drives.")
		return

	var sample: MeshInstance3D = _front[0] if not _front.is_empty() else _rear[0]

	if sample.mesh != null:
		# Half the mesh's height, through whatever scale the art is under. A wheel is a
		# cylinder lying on its side, so its own AABB's Y extent IS its diameter.
		_art_wheel_radius = maxf(
			sample.mesh.get_aabb().size.y * 0.5 * sample.global_transform.basis.get_scale().y,
			0.05
		)


## The model's wheels are direct children of the GLB's root, which is itself a child of
## the instanced scene — so this walks rather than indexing a path. A path would be a
## promise about somebody else's exporter.
func _find_mesh(under: Node, wanted: String) -> MeshInstance3D:
	if under.name == wanted:
		return under as MeshInstance3D

	for child in under.get_children():
		var found := _find_mesh(child, wanted)
		if found != null:
			return found

	return null


## Drawn per FRAME and not per tick, like every other visual in this family.
func _process(delta: float) -> void:
	if _front.is_empty() and _rear.is_empty():
		return

	var steering := _mirror_steering
	var speed := _mirror_speed

	if not _mirrored:
		steering = _steering_now()
		speed = _speed_now()

	_roll = wrapf(_roll + (speed / _art_wheel_radius) * delta * _art_sign, -TAU, TAU)

	for wheel in _front:
		# Yaw first and roll second, which is what Godot's default YXZ order gives:
		# the hub is steered, and the tyre spins about the axle the steering left it on.
		# The other order spins the wheel about the bus's axis and it wobbles.
		wheel.rotation = Vector3(_roll, steering * _art_sign, 0.0)

	for wheel in _rear:
		wheel.rotation = Vector3(_roll, 0.0, 0.0)


## The steering angle the simulation is actually using, in radians.
func _steering_now() -> float:
	for child in get_children():
		var wheel := child as VehicleWheel3D
		if wheel != null and wheel.use_as_steering:
			return wheel.steering
	return 0.0


## Forward speed in m/s, signed: a reversing bus turns its wheels backwards.
func _speed_now() -> float:
	return linear_velocity.dot(-global_basis.z)


## What a client is told, by [code]bfh_bus_net.gd[/code], once a snapshot has arrived.
func draw_steering(radians: float) -> void:
	_mirror_steering = radians
	_mirrored = true


func draw_roll(metres_per_second: float) -> void:
	_mirror_speed = metres_per_second
	_mirrored = true


func describe() -> Dictionary:
	return {
		"art": _art != null,
		"wheels_drawn": _front.size() + _rear.size(),
		"art_radius": "%.2f m" % _art_wheel_radius,
		"art_reversed": _art_sign < 0.0,
		"steering": "%.3f rad" % (_mirror_steering if _mirrored else _steering_now()),
		"speed": "%.1f m/s" % (_mirror_speed if _mirrored else _speed_now()),
		"mirrored": _mirrored,
	}
