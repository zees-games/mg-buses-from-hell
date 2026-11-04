extends "bfh_arena_layout.gd"
## How a bus or a bot moves round the bowl: steering, the ramp, the street route, scatter, toys, the scaffold and the climbs.

## [param target], moved aside if driving straight at it would go through a pillar.
func steer_around(from: Vector3, target: Vector3) -> Vector3:
	var nudged := _round_the_obstacles(from, _round_the_ramp(from, target))
	# Only when the nudge moved the aim: the line to an untouched target was already checked.
	if nudged.distance_squared_to(target) > 0.01:
		return _round_the_ramp(from, nudged)
	return nudged

## Whether a bot bus is routed along streets here rather than nudged round obstacles: a
## district's buildings are a maze of 7.6 m streets, which the nudge cannot thread. The plain
## bowls keep the nudge, because their narrow lanes are doors on purpose (see `LANE_THROUGH`).
func routes_through_streets() -> bool:
	return district != ""

## How far a bus's centre is kept off every obstacle, the wall and the slabs by
## [method street_route]: `BfhConfig.bot_route_clearance`, written here by the world before each
## bot steers. Changing it rebuilds the grid on the next route.
var route_clearance: float = 3.4:
	set(value):
		if not is_equal_approx(value, route_clearance):
			route_clearance = value
			_route = null

var _route: BfhRoute = null

## The waypoints a bus at [param from] follows to [param target] through the streets, not
## including where it is, or empty when the straight line is clear. See [BfhRoute].
func street_route(from: Vector3, target: Vector3) -> PackedVector3Array:
	if _route == null:
		_route = BfhRoute.new()
		var deck_front := -(radius - LEDGE_DEPTH)
		var slabs: Array[Rect2] = [
			Rect2(-RAMP_WIDTH * 0.5, deck_front, RAMP_WIDTH, ramp_foot().z - deck_front),
			Rect2(-LEDGE_WIDTH * 0.5, -radius, LEDGE_WIDTH, LEDGE_DEPTH),
		]
		_route.build(radius, _obstacles, _obstacle_radii, slabs, route_clearance)
	return _route.plan(from, target)

## The ramp, which is not a cylinder and is the one thing in the bowl a bus cannot come round on
## either side: its top end is the deck, so the only way past is round its foot.
func _round_the_ramp(from: Vector3, target: Vector3) -> Vector3:
	if _ramp == null:
		return target

	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var foot_z := ramp_foot().z
	var deck_front := -(radius - LEDGE_DEPTH)

	# Up there already: the deck is open floor.
	var on_deck := absf(from.x) < LEDGE_WIDTH * 0.5 and from.z < deck_front
	if on_deck:
		return target

	# A quarry on the ramp or the deck is reached from the bottom of it.
	var target_up := (
		(absf(target.x) < half and target.z < foot_z)
		or (absf(target.x) < LEDGE_WIDTH * 0.5 and target.z < deck_front)
	)
	if target_up:
		return _up_the_ramp(from, target, half, foot_z, deck_front)

	# Lined up at the bottom: the ramp is its road, not its obstacle.
	var in_lane := absf(from.x) < RAMP_WIDTH * 0.5 and from.z < foot_z + RAMP_APPROACH
	if in_lane:
		return target

	# Against the slab itself, not the slab widened by a bus.
	if not _crosses_ramp(from, target, RAMP_WIDTH * 0.5, deck_front, foot_z):
		return target

	var side := signf(from.x) if absf(from.x) > 0.01 else signf(target.x)
	if side == 0.0:
		side = 1.0

	return Vector3(side * (half + PILLAR_CLEARANCE), target.y, foot_z + PILLAR_CLEARANCE)

## Whether a bus at [param from] chasing [param target] has to go up the ramp to get
## there: the quarry is on the ramp or the deck and the bus is not on the deck yet.
func ramp_bound(from: Vector3, target: Vector3) -> bool:
	if _ramp == null:
		return false
	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var deck_front := -(radius - LEDGE_DEPTH)
	if absf(from.x) < LEDGE_WIDTH * 0.5 and from.z < deck_front:
		return false
	return (
		(absf(target.x) < half and target.z < ramp_foot().z)
		or (absf(target.x) < LEDGE_WIDTH * 0.5 and target.z < deck_front)
	)

## Whether a bus at [param from] is on the ramp or in the strip in front of its foot
## where a bus bound up it follows the centreline. See [method _up_the_ramp].
func lining_up(from: Vector3) -> bool:
	if _ramp == null:
		return false
	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var foot_z := ramp_foot().z
	var deck_front := -(radius - LEDGE_DEPTH)
	var on_ramp := (
		absf(from.x) < RAMP_WIDTH * 0.5 + 0.5 and from.z <= foot_z and from.z >= deck_front
		and from.y > ramp_surface_at(0.0, from.z) + 0.5
	)
	var in_front := absf(from.x) < half and from.z > foot_z \
		and from.z < foot_z + RAMP_LINE_UP + RAMP_STRIP_PAST
	return on_ramp or in_front

## The way up to a quarry on the ramp or the deck, from [param from] on the floor or the ramp: the
## ramp's centreline [constant RAMP_LOOKAHEAD] ahead of the bus while it is on the ramp or in front
## of its foot, the line-up point [constant RAMP_LINE_UP] in front of the foot otherwise, and the.
func _up_the_ramp(from: Vector3, target: Vector3, half: float, foot_z: float,
		deck_front: float) -> Vector3:
	if lining_up(from):
		var ahead := from.z - RAMP_LOOKAHEAD
		if ahead < deck_front:
			return target
		return Vector3(0.0, target.y, ahead)

	var approach := Vector3(0.0, target.y, foot_z + RAMP_LINE_UP)
	if _crosses_ramp(from, approach, RAMP_WIDTH * 0.5, deck_front, foot_z):
		var side := signf(from.x) if absf(from.x) > 0.01 else 1.0
		return Vector3(side * (half + PILLAR_CLEARANCE), target.y, foot_z + PILLAR_CLEARANCE)
	return approach

## Whether the segment [param from] to [param to] passes through the box [param half]
## either side of the ramp's centreline, between [param z_min] and [param z_max], in plan.
func _crosses_ramp(from: Vector3, to: Vector3, half: float, z_min: float, z_max: float) -> bool:
	# Clipped against the box one axis at a time; the classic slab test.
	var t0 := 0.0
	var t1 := 1.0
	var d := Vector2(to.x - from.x, to.z - from.z)
	var o := Vector2(from.x, from.z)
	var lo := Vector2(-half, z_min)
	var hi := Vector2(half, z_max)

	for axis in range(2):
		if absf(d[axis]) < 0.0001:
			if o[axis] < lo[axis] or o[axis] > hi[axis]:
				return false
			continue
		var a := (lo[axis] - o[axis]) / d[axis]
		var b := (hi[axis] - o[axis]) / d[axis]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			return false

	return true


## How far in front of the ramp's foot a bus lines up before driving up it.
const RAMP_APPROACH := 8.0

## How far up the ramp's centreline a bus on it aims. See [method _up_the_ramp].
const RAMP_LOOKAHEAD := 6.0

## How far in front of the foot a bus chasing somebody up the ramp lines up, and the
## depth of the strip in front of the foot where it follows the centreline.
const RAMP_LINE_UP := 11.0

## How far the line-up strip reaches past the line-up point.
const RAMP_STRIP_PAST := 3.0

## The nearest to the foot a bus turns round in front of it, in metres. See
## [method ramp_turn_point].
const RAMP_TURN_NEAREST := 5.0

## The clear floor round [param at], in metres: to the nearest obstacle's surface, the
## ramp's slab, the deck's face or the wall, whichever is closest.
func floor_clear_at(at: Vector3) -> float:
	var nearest := radius - Vector2(at.x, at.z).length()
	for i in range(_obstacles.size()):
		var axis := Vector2(at.x - _obstacles[i].x, at.z - _obstacles[i].z).length()
		nearest = minf(nearest, axis - _obstacle_radii[i])
	var deck_z := -(radius - LEDGE_DEPTH)
	if _ramp != null:
		nearest = minf(nearest,
			_to_box(at, -RAMP_WIDTH * 0.5, RAMP_WIDTH * 0.5, deck_z, ramp_foot().z))
	return minf(nearest, _to_box(at, -LEDGE_WIDTH * 0.5, LEDGE_WIDTH * 0.5, -radius, deck_z))

## Where a bus that faces away from the ramp turns round to go up it: the point on the centreline,
## between [constant RAMP_TURN_NEAREST] and [constant RAMP_LINE_UP] in front of the foot, with the
## most clear floor round it.
func ramp_turn_point() -> Vector3:
	var foot_z := ramp_foot().z
	var best := Vector3(0.0, 0.5, foot_z + RAMP_LINE_UP)
	var most := -INF
	var out := RAMP_TURN_NEAREST
	while out <= RAMP_LINE_UP + 0.001:
		var at := Vector3(0.0, 0.5, foot_z + out)
		var clear := floor_clear_at(at)
		if clear > most + 0.001:
			most = clear
			best = at
		out += 0.5
	return best

func _round_the_obstacles(from: Vector3, target: Vector3) -> Vector3:
	if _obstacles.is_empty():
		return target

	var line := target - from
	line.y = 0.0

	var distance := line.length()
	if distance < 0.5:
		return target

	var forward := line / distance
	# Right-hand normal in Godot's frame.
	var right := Vector3(-forward.z, 0.0, forward.x)

	var blocking := -1
	var nearest := INF
	var offset := 0.0

	for i in range(_obstacles.size()):
		var to_pillar := _obstacles[i] - from
		to_pillar.y = 0.0

		var along := to_pillar.dot(forward)
		# Behind the bus, or past where it is going: not in the way.
		if along <= 0.0 or along > distance:
			continue

		if absf(to_pillar.dot(right)) > _clearance(i):
			continue

		if along < nearest:
			nearest = along
			blocking = i
			offset = to_pillar.dot(right)

	if blocking < 0:
		return target

	# Pass on the far side from the pillar's own offset: a pillar sitting left of the
	# line is one to go right of. Dead ahead is the one case with no answer in the
	# geometry, so it picks a side rather than splitting the difference and hitting it.
	var away := -signf(offset) if absf(offset) > 0.05 else 1.0

	# Two staggered rows are never that; the hook past the dog-leg is three pillars in a triangle, and
	# the waypoint beside one of them is inside the next.
	var preferred := _beside(blocking, right, away)
	var other := _beside(blocking, right, -away)

	if _room_at(other, blocking) > _room_at(preferred, blocking) + 0.01:
		preferred = other

	return Vector3(preferred.x, target.y, preferred.z)

## The waypoint one bus-width to [param away] of obstacle [param blocking].
func _beside(blocking: int, right: Vector3, away: float) -> Vector3:
	return _obstacles[blocking] + right * away * _clearance(blocking)

## How far from obstacle [param index]'s axis a bus has to pass to miss it.
func _clearance(index: int) -> float:
	return _obstacle_radii[index] + steer_clearance

## How far past an obstacle's surface the steering keeps a bot bus: [constant PILLAR_CLEARANCE]
## unless `BfhConfig.bot_steer_clearance` says otherwise, which the world writes here before each
## bot steers.
var steer_clearance: float = PILLAR_CLEARANCE

## How much room there is at [param at], to the nearest obstacle that is not [param blocking].
func _room_at(at: Vector3, blocking: int) -> float:
	var room := INF

	for i in range(_obstacles.size()):
		if i == blocking:
			continue

		room = minf(
			room,
			Vector2(at.x - _obstacles[i].x, at.z - _obstacles[i].z).length()
				- _obstacle_radii[i],
		)

	return room

func _box(
	parent: Node3D,
	node_name: String,
	at: Vector3,
	size: Vector3,
	colour: Color,
	yaw: float = 0.0,
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.rotation = Vector3(0.0, yaw, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := BoxShape3D.new()
	shape.size = size

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = BfhTextures.surface(colour)
	body.add_child(mesh)

	parent.add_child(body)
	return body

## A point on the floor for something to be dropped at, from a seeded stream.
func scatter_point(stream: DotRandomStream, margin: float, height: float) -> Vector3:
	var usable := maxf(radius - margin, 1.0)

	for _attempt in range(32):
		var x := stream.next_range_f(-usable, usable)
		var z := stream.next_range_f(-usable, usable)
		if Vector2(x, z).length() > usable:
			continue
		if _inside_a_pillar(x, z) or _inside_the_scaffold(x, z) or _inside_a_start_lane(x, z, margin) or _on_a_toy(x, z):
			continue
		return Vector3(x, height, z)

	return Vector3(0.0, height, 0.0)

## Rectangles on the floor kept clear in front of the bus starts, as (centre x, centre z, half
## width, half length), each running from a start toward the bowl's middle. Set by the game
## from its config before it scatters; empty keeps nothing clear.
var start_lanes: Array[Vector4] = []

## Lanes from every start of [param count] buses, [param width] wide and [param length] long.
func keep_start_lanes(count: int, width: float, length: float) -> void:
	start_lanes.clear()
	if width <= 0.0 or length <= 0.0:
		return
	for i in range(maxi(count, 1)):
		var start := bus_start(i, count)
		# A start stands at negative z facing the middle (+z), so its lane runs from it toward
		# the middle and is mirrored for any start the other side of it.
		var forward := signf(-start.z) if start.z != 0.0 else 1.0
		start_lanes.append(Vector4(start.x, start.z + forward * length * 0.5, width * 0.5, length * 0.5))

## Whether a prop dropped at (x, z) with its own size margin would sit in a start lane.
func _inside_a_start_lane(x: float, z: float, margin: float) -> bool:
	# The scatter's margin is a distance from the rim; a prop's own half-size here is a
	# fraction of it, enough that a block's edge does not poke into the lane.
	var pad := clampf(margin * 0.1, 0.5, 1.5)
	for lane in start_lanes:
		if absf(x - lane.x) < lane.z + pad and absf(z - lane.y) < lane.w + pad:
			return true
	return false

## Metres of floor around a pillar that nothing is dropped into.
const PILLAR_KEEP_OUT := PILLAR_RADIUS + 2.2

## Metres of floor around ANY obstacle that nothing is dropped into, past its own radius.
const OBSTACLE_MARGIN := PILLAR_KEEP_OUT - PILLAR_RADIUS

# --- Toys

## Where the bowl's toys stand (dot-props' loose toys: beach balls, barrels, a tyre): a ring two
## thirds of the way out, clear of every pillar, tank and the scaffold. Not of the bus lanes: they
## are the game's per round and a client never sets them, and a bus ploughing a ball is the point.
var _toy_spots: Array[Vector3] = []

## The toys' ids, round the ring in this order.
const TOY_KINDS: Array[String] = ["beach_ball", "barrel", "beach_ball", "tyre", "beach_ball", "barrel"]

## How much room a toy spot keeps from an obstacle and from a scattered prop.
const TOY_ROOM := 2.0

func toy_placements() -> Array:
	var out: Array = []
	for i in range(_toy_spots.size()):
		var at := _toy_spots[i]
		out.append({"toy": TOY_KINDS[i % TOY_KINDS.size()], "at": [at.x, at.y, at.z], "yaw": float(i) * 37.0})
	return out

func _find_toy_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ring := runner_area_radius() * 0.62
	var steps := 36
	for k in range(steps):
		if out.size() >= TOY_KINDS.size():
			break
		var a := TAU * float(k) / float(steps)
		var x := cos(a) * ring
		var z := sin(a) * ring
		if _near_an_obstacle(x, z, TOY_ROOM) or _inside_the_scaffold(x, z):
			continue
		var crowded := false
		for o in out:
			if Vector2(o.x - x, o.z - z).length() < 6.0:
				crowded = true
		if not crowded:
			out.append(Vector3(x, 0.0, z))
	return out

func _near_an_obstacle(x: float, z: float, room: float) -> bool:
	for i in range(_obstacles.size()):
		var at := _obstacles[i]
		if Vector2(x - at.x, z - at.z).length() < _obstacle_radii[i] + room:
			return true
	return false

## Whether a prop dropped at (x, z) would land on a toy: the scatter keeps off them.
func _on_a_toy(x: float, z: float) -> bool:
	for at in _toy_spots:
		if Vector2(x - at.x, z - at.z).length() < TOY_ROOM:
			return true
	return false

func _inside_a_pillar(x: float, z: float) -> bool:
	for i in range(_obstacles.size()):
		var at := _obstacles[i]
		if Vector2(x - at.x, z - at.z).length() < _obstacle_radii[i] + OBSTACLE_MARGIN:
			return true
	return false

## THE SCAFFOLD: the only height in the bowl a runner can climb, and a bus can take away.

## Crates high, per column, along the scaffold's length. Two columns per step so a runner lands with
## a metre to run before the next face: measured, a jump from standing against a face clears a 1 m
## rise by 9 cm and misses one time in three.
const SCAFFOLD_STEPS: Array[int] = [1, 1, 2, 2, 3, 3, 2, 2, 1, 1]

## Columns across. Two, so the climb has room to be made at an angle and a crate knocked
## out of one row leaves the other.
const SCAFFOLD_ROWS := 2

## Where it stands, as a fraction of the bowl radius: the south-east, the one quarter of the floor
## with nothing in it. At 46 m its footprint is 6.2 m of clear floor from the nearest hook pillar
## and, since the back yard, 8.9 m from the nearest drum ([method scaffold_clearance]).
const SCAFFOLD_CENTRE := Vector2(0.43, 0.5)

## Below this it is left out: its position scales with the bowl and its size does not.
const SCAFFOLD_MIN_RADIUS := 45.0

## Air between neighbouring crates, and between a layer and the one it is dropped onto.
const SCAFFOLD_GAP := 0.02
const SCAFFOLD_DROP := 0.05

var _has_scaffold: bool = false
var _scaffold_origin: Vector3 = Vector3.ZERO

func _place_scaffold() -> void:
	if radius < SCAFFOLD_MIN_RADIUS:
		DotLog.info(CHANNEL, "bowl too small for the scaffold; left out", {
			"radius": "%.0f m" % radius, "needs": "%.0f m" % SCAFFOLD_MIN_RADIUS,
		})
		return

	var size := scaffold_size()
	var centre := SCAFFOLD_CENTRE * radius
	_scaffold_origin = Vector3(centre.x - size.x * 0.5, 0.0, centre.y - size.z * 0.5)
	_has_scaffold = true

## The scaffold's footprint and height, in metres.
func scaffold_size() -> Vector3:
	var pitch := BfhContent.CRATE_SIZE + SCAFFOLD_GAP
	var tallest := 0
	for h in SCAFFOLD_STEPS:
		tallest = maxi(tallest, h)
	return Vector3(
		pitch * SCAFFOLD_STEPS.size() - SCAFFOLD_GAP,
		BfhContent.CRATE_SIZE * tallest,
		pitch * SCAFFOLD_ROWS - SCAFFOLD_GAP,
	)

func has_scaffold() -> bool:
	return _has_scaffold

## Every crate of the scaffold as the box it occupies once settled, bottom layer first.
func scaffold_cells() -> Array[AABB]:
	var cells: Array[AABB] = []
	if not _has_scaffold:
		return cells

	var edge := BfhContent.CRATE_SIZE
	var pitch := edge + SCAFFOLD_GAP

	for level in range(3):
		for i in range(SCAFFOLD_STEPS.size()):
			if SCAFFOLD_STEPS[i] <= level:
				continue
			for row in range(SCAFFOLD_ROWS):
				cells.append(AABB(
					_scaffold_origin + Vector3(i * pitch, level * edge, row * pitch),
					Vector3(edge, edge, edge)
				))
	return cells

## Where to drop each crate of [method scaffold_cells] from: its centre, lifted
## [constant SCAFFOLD_DROP] per layer so every layer falls onto the one below.
func scaffold_spawn_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in scaffold_cells():
		var level := roundi(cell.position.y / BfhContent.CRATE_SIZE)
		points.append(cell.get_center() + Vector3(0.0, SCAFFOLD_DROP * float(level + 1), 0.0))
	return points

## The scaffold's steps as one box each, low to high: the surfaces a runner lands on.
func scaffold_steps() -> Array[AABB]:
	var steps: Array[AABB] = []
	if not _has_scaffold:
		return steps

	var pitch := BfhContent.CRATE_SIZE + SCAFFOLD_GAP
	var i := 0
	while i < SCAFFOLD_STEPS.size():
		var height := SCAFFOLD_STEPS[i]
		var j := i
		while j < SCAFFOLD_STEPS.size() and SCAFFOLD_STEPS[j] == height:
			j += 1
		steps.append(AABB(
			_scaffold_origin + Vector3(i * pitch, 0.0, 0.0),
			Vector3((j - i) * pitch - SCAFFOLD_GAP, height * BfhContent.CRATE_SIZE,
				scaffold_size().z)
		))
		i = j
	return steps

## The index into [method scaffold_steps] of the highest step: the one a runner climbs to.
func scaffold_peak() -> int:
	var steps := scaffold_steps()
	var best := 0
	for i in range(steps.size()):
		if steps[i].end.y > steps[best].end.y:
			best = i
	return best

func scaffold_footprint() -> AABB:
	return AABB(_scaffold_origin, scaffold_size()) if _has_scaffold else AABB()

## The least clear floor between the scaffold's footprint and any pillar or tank, in metres. INF
## with no scaffold.
func scaffold_clearance() -> float:
	if not _has_scaffold:
		return INF
	var footprint := scaffold_footprint()
	var nearest := INF
	for i in range(_obstacles.size()):
		var at := _obstacles[i]
		var dx := maxf(maxf(footprint.position.x - at.x, at.x - footprint.end.x), 0.0)
		var dz := maxf(maxf(footprint.position.z - at.z, at.z - footprint.end.z), 0.0)
		nearest = minf(nearest, Vector2(dx, dz).length() - _obstacle_radii[i])
	return nearest

## Metres round the scaffold the scatter keeps clear, set by the game from
## `BfhConfig.scaffold_scatter_margin` before it scatters. Never less than
## [constant OBSTACLE_MARGIN], which is what every obstacle keeps.
var scaffold_keep_out: float = OBSTACLE_MARGIN

func _inside_the_scaffold(x: float, z: float) -> bool:
	if not _has_scaffold:
		return false
	var box := scaffold_footprint().grow(maxf(scaffold_keep_out, OBSTACLE_MARGIN))
	return x > box.position.x and x < box.end.x and z > box.position.z and z < box.end.z

## The ramp's walking surface as a height at ([param x], [param z]), from the built body.
func ramp_surface_at(x: float, z: float) -> float:
	if _ramp == null:
		return 0.0
	var basis := _ramp.transform.basis.orthonormalized()
	var n := basis.y
	var p := _ramp.transform.origin + n * (RAMP_THICKNESS * 0.5)
	return p.y - (n.x * (x - p.x) + n.z * (z - p.z)) / n.y

## The ramp's pitch in degrees, from the built body.
func ramp_slope() -> float:
	if _ramp == null:
		return 0.0
	return rad_to_deg(acos(clampf(_ramp.transform.basis.orthonormalized().y.y, -1.0, 1.0)))

## The step at the top of the ramp onto the deck, in metres, and the step onto its foot.
func ramp_lips() -> Vector2:
	var deck_front := -(radius - LEDGE_DEPTH)
	return Vector2(
		maxf(ramp_surface_at(0.0, ramp_foot().z), 0.0),
		deck_top() - ramp_surface_at(0.0, deck_front),
	)

## Every way up this map expects a runner to take, each measured off what it climbs.
func climbs(config: BfhConfig) -> Array:
	var out: Array = []
	var sand := AABB(Vector3(-1000.0, -1.0, -1000.0), Vector3(2000.0, 1.0, 2000.0))
	var edge := BfhContent.CRATE_SIZE
	var crate := AABB(Vector3.ZERO, Vector3(edge, edge, edge))
	var barrel_d := BfhContent.BARREL_RADIUS * 2.0
	var beside := AABB(Vector3(edge, 0.0, 0.0), Vector3(barrel_d, BfhContent.BARREL_HEIGHT, barrel_d))
	var two := AABB(Vector3(edge, 0.0, 0.0), Vector3(edge, edge * 2.0, edge))

	out.append(BfhReach.Climb.between("a crate, from the sand", BfhReach.How.JUMP, sand, crate))
	out.append(BfhReach.Climb.between(
		"a concrete block, from the sand", BfhReach.How.JUMP, sand, crate))
	out.append(BfhReach.Climb.between(
		"a barrel, from a crate beside it", BfhReach.How.STEP, crate, beside))
	out.append(BfhReach.Climb.between(
		"a stack of two, from a crate beside it", BfhReach.How.JUMP, crate, two))

	# Thrown. The runner is as far from the barrel as the hammer lets them be and still
	# set it off: its reach to the barrel's face, from the feet, which is the farthest
	# and therefore the weakest throw anybody gets.
	var thrown := BfhReach.Climb.between(
		"a stack of two, from the sand, thrown by a barrel you hammered",
		BfhReach.How.THROW, sand, two)
	var flat := config.hammer_reach + BfhContent.BARREL_RADIUS
	var centre := Vector2(flat, BfhContent.BARREL_HEIGHT * 0.5).length()
	thrown.lift = config.barrel_lift_height * maxf(
		1.0 - centre / BfhContent.BARREL_BLAST_RADIUS, 0.0)
	out.append(thrown)

	if _ramp != null:
		var lips := ramp_lips()
		var up := BfhReach.Climb.new()
		up.name = "the ledge, up the ramp"
		up.how = BfhReach.How.WALK
		up.slope = ramp_slope()
		up.rise = maxf(lips.x, lips.y)
		out.append(up)

	# Up from each end to the peak: the west half from the west, the east half from the
	# east, and the peak from both sides.
	var steps := scaffold_steps()
	var peak := scaffold_peak()
	for i in range(steps.size()):
		if i <= peak:
			var from := sand if i == 0 else steps[i - 1]
			out.append(BfhReach.Climb.between(
				"the scaffold's step %d, from %s" % [i + 1, "the sand" if i == 0 else "the west"],
				BfhReach.How.JUMP, from, steps[i]))
		if i >= peak and steps.size() > 1:
			var last := steps.size() - 1
			if i == last and i == peak:
				continue
			var from := sand if i == last else steps[i + 1]
			out.append(BfhReach.Climb.between(
				"the scaffold's step %d, from %s" % [i + 1, "the sand" if i == last else "the east"],
				BfhReach.How.JUMP, from, steps[i]))

	return out

func describe() -> Dictionary:
	return {
		"radius": "%.0f m" % radius,
		"wall": "%.0f m" % WALL_HEIGHT,
		"ledge": str(ledge_centre()),
		"pillars": _stack_count,
		"tanks": _tank_end - _stack_count,
		"colonnade": _obstacles.size() - _tank_end,
		"scaffold": scaffold_cells().size(),
		"ramp": "%.0f deg, lips %s" % [ramp_slope(), str(ramp_lips())],
		"tightest gap": "%.1f m" % narrowest_gap(),
		"scaffold clearance": "%.1f m" % scaffold_clearance(),
		"hook": "%s, gaps %.2f / %.2f m" % [hook_layout, hook_gaps(hook_layout).x, hook_gaps(hook_layout).y],
		"courtyard west lane": "%.2f m" % courtyard_west_lane,
		"steer clearance": "%.1f m" % steer_clearance,
	}
