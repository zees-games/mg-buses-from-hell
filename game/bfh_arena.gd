extends "bfh_arena_routes.gd"
## The bowl built in code: light, floor, wall, ledge, ramp, stacks, tanks, towns, colonnade and the pillars.

## Every build, after the bowl is up: what the world builds the toys on.
signal built()

func build(p_radius: float) -> void:
	radius = maxf(p_radius, 8.0)

	# [b]Cleared first, because building is also REBUILDING.[/b] A client is told the server's radius
	# in the HELLO and rebuilds its bowl to match — the map here is one number, run through this
	# function on both ends — and a second call that only added would leave a 46 m wall.
	_clear()

	_build_light()
	_build_floor()
	_build_wall()
	_build_ledge()
	# The scaffold's place is known before a district is planned round it.
	_place_scaffold()
	if BfhDistricts.knows(district):
		# A district replaces the stacks, the tank farm and the colonnade with a town; the
		# ramp, the scaffold and the start lanes are the same in every map.
		_build_district()
		_stack_count = 0
		_tank_end = 0
	else:
		_build_stacks()
		# Counted here rather than inside `_build_stacks`, which returns early on a bowl too
		# small for them: the tanks are appended to the same array and the split between the
		# two views has to be right whether or not the stacks went in.
		_stack_count = _obstacles.size()
		_build_tanks()
		_tank_end = _obstacles.size()
		_build_colonnade()
	_toy_spots = _find_toy_spots()

	DotLog.info(
		CHANNEL,
		"arena built",
		{
			"radius": "%.0f m" % radius,
			"segments": WALL_SEGMENTS,
			"pillars": _stack_count,
			"tanks": _tank_end - _stack_count,
			"colonnade": _obstacles.size() - _tank_end,
			"scaffold": "%d crates" % scaffold_cells().size(),
			"tightest gap": "%.1f m" % narrowest_gap(),
			"district": district if district != "" else "the bowl",
			"hook": hook_layout,
			"courtyard west lane": "%.2f m" % courtyard_west_lane,
		}
	)

	# [b]The layout is an operator's to choose now, so the gap rule is said where it is broken.[/b]
	# `headless_run` holds the shipped layout to BUS_GAP; a hook or a west lane set from a JSON file or
	# the environment is not run through the suite, and a pair of drums closer than a bus is a.
	if minf(narrowest_gap(), scaffold_clearance()) < BUS_GAP:
		DotLog.warn(
			CHANNEL,
			"a gap on this map is too tight for a bus",
			{"tightest": "%.2f m" % narrowest_gap(), "scaffold": "%.2f m" % scaffold_clearance(),
				"bus needs": "%.2f m" % BUS_GAP,
				"hook_layout": hook_layout, "courtyard_west_lane": courtyard_west_lane},
		)

	built.emit()

## Everything a previous [method build] put here.
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	_floor_body = null
	_ramp = null
	_has_scaffold = false
	_obstacles = PackedVector3Array()
	_obstacle_radii = PackedFloat32Array()
	_route = null
	_stack_count = 0
	_tank_end = 0
	_district_buildings = []

## The bowl's palette: a sunny sand bowl in the family's pastels (game-fatal-contact's built-in maps), one
## colour per kind of thing so a runner can call a place out ("behind the blue tanks", "up the
## lavender ramp").
const SAND := Color(0.90, 0.74, 0.50)
const WALL_COLOUR := Color(0.98, 0.72, 0.70)
const LEDGE_COLOUR := Color(0.80, 0.70, 1.00)
const RAMP_COLOUR := Color(0.86, 0.80, 1.00)
const TANK_COLOUR := Color(0.62, 0.82, 1.00)
const TANK_BAND := Color(0.40, 0.62, 0.92)
const PILLAR_COLOUR := Color(0.58, 0.92, 0.78)
const PILLAR_CAP := Color(0.36, 0.74, 0.62)

## The sun and the sky, as a dot-lighting document.
const DAYLIGHT := {
	"sun": {
		"pitch_src": -42.0,
		"yaw_src": -42.0,
		"colour": [1.0, 0.93, 0.80],
		"brightness": 380.0,
		"spread_degrees": 1.0,
		"ambient_colour": [0.74, 0.78, 0.92],
	},
	"fog": {
		"enabled": true,
		"colour": [0.84, 0.90, 1.0],
		"start": 3150.0,
		"end": 21000.0,
		"max_density": 0.2,
	},
	"sky_top": [0.30, 0.56, 0.96],
}

func _build_light() -> void:
	var holder := Node3D.new()
	holder.name = "Lighting"
	add_child(holder)
	var sun := DotLightRig.apply(holder, DotLightDocument.from_dictionary(DAYLIGHT), light_profile())
	if sun != null:
		sun.shadow_blur = 1.5
	for node in holder.get_children():
		if node is WorldEnvironment and (node as WorldEnvironment).environment.sky != null:
			var material := (node as WorldEnvironment).environment.sky.sky_material as ProceduralSkyMaterial
			if material != null:
				var top: Array = DAYLIGHT["sky_top"]
				material.sky_top_color = Color(float(top[0]), float(top[1]), float(top[2]))
				material.ground_bottom_color = material.sky_top_color

## What this machine draws of [constant DAYLIGHT]: dot-lighting's `painted()`.
static func light_profile() -> DotLightProfile:
	var p := DotLightProfile.painted()
	p.sun_shadows = true
	p.sky_below_horizon = true
	return p

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 2.0

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 2.0
	cylinder.radial_segments = 64
	mesh.mesh = cylinder
	mesh.position = Vector3(0.0, -1.0, 0.0)
	mesh.material_override = BfhTextures.surface(SAND)
	body.add_child(mesh)

	add_child(body)
	_floor_body = body

func _build_wall() -> void:
	var wall := Node3D.new()
	wall.name = "Wall"
	add_child(wall)

	var step := TAU / float(WALL_SEGMENTS)
	# The chord each segment has to span, plus a little, or the ring has gaps a bus
	# can be squeezed through at the corners. A segment sized to the RADIUS rather
	# than to the chord leaves exactly that gap and it only shows at speed.
	var chord := 2.0 * radius * sin(step * 0.5) + 0.4

	for i in range(WALL_SEGMENTS):
		var angle := step * float(i)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * (radius + WALL_THICKNESS * 0.5)
		_box(
			wall,
			"Wall%d" % i,
			at + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, chord),
			WALL_COLOUR,
			-angle,
		)

func _build_ledge() -> void:
	var ledge := Node3D.new()
	ledge.name = "Ledge"
	add_child(ledge)

	var z := -(radius - LEDGE_DEPTH * 0.5)

	_box(
		ledge,
		"Deck",
		Vector3(0.0, LEDGE_HEIGHT, z),
		Vector3(LEDGE_WIDTH, 1.0, LEDGE_DEPTH),
		LEDGE_COLOUR,
	)

	# The way down. A bus drives off the ledge onto the floor, which is the only route between the two
	# halves of the map and therefore the only place a runner can do anything about a driver at all.
	var rise := RAMP_LENGTH * 0.5 * sin(deg_to_rad(RAMP_ANGLE))
	var run := RAMP_LENGTH * 0.5 * cos(deg_to_rad(RAMP_ANGLE))
	var deck_front := z + LEDGE_DEPTH * 0.5

	var ramp := _box(
		ledge,
		"Ramp",
		# Pulled back under the deck by [constant RAMP_TUCK], so the two overlap instead
		# of meeting at a seam. A seam between two colliders is exactly the interior edge
		# a sliding body catches on, which dot-props documents from the other direction.
		Vector3(0.0, deck_top() - rise - RAMP_THICKNESS * 0.5, deck_front + run - RAMP_TUCK),
		# [b]Runner-wide, not vehicle-wide.[/b] At 0.6 of the deck it was thirteen metres across, which is
		# a road: the bot drove up it on the way to anybody standing near the north edge, beached itself
		# on the lip at the top, and spent the round being recovered by the stuck rule.
		Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH),
		RAMP_COLOUR,
	)
	# [b]Positive, and for the game's first nine days it was negative.[/b] A rotation about +X by -18
	# degrees LIFTS the +Z end, so the ramp was built rising out of the floor under the deck and ending
	# 7.8 m up in the middle of the bowl: a ski jump pointing away from the ledge it was meant to.
	ramp.rotation = Vector3(deg_to_rad(RAMP_ANGLE), 0.0, 0.0)
	_segment_collider(ramp, RAMP_SEGMENTS)
	_ramp = ramp

## How many boxes the ramp's collider is built from. The mesh stays one piece.
const RAMP_SEGMENTS := 8

## Replaces [param body]'s one box collider with [param count] along its local Z, in the
## same plane and overlapping by [constant SEGMENT_OVERLAP] so there is no gap to find.
func _segment_collider(body: StaticBody3D, count: int) -> void:
	var whole := body.get_child(0) as CollisionShape3D
	var size := (whole.shape as BoxShape3D).size
	var step := size.z / float(count)

	var piece := BoxShape3D.new()
	piece.size = Vector3(size.x, size.y, step + SEGMENT_OVERLAP)
	whole.shape = piece
	whole.position = Vector3(0.0, 0.0, -size.z * 0.5 + step * 0.5)

	for i in range(1, count):
		var more := CollisionShape3D.new()
		more.shape = piece
		more.position = Vector3(0.0, 0.0, -size.z * 0.5 + step * (float(i) + 0.5))
		body.add_child(more)

const SEGMENT_OVERLAP := 0.1

## The stacks, and the one list they all come out of.
func _build_stacks() -> void:
	if radius < STACK_MIN_RADIUS:
		# Said rather than skipped silently: a bowl configured small enough to lose a
		# whole feature of the map should say which feature and why, or the next person
		# to set `arena_radius` low is debugging a map that looks half-built.
		DotLog.info(
			CHANNEL,
			"stacks left out, bowl too small",
			{"radius": "%.0f m" % radius, "needs": "%.0f m" % STACK_MIN_RADIUS},
		)
		return

	var stacks := Node3D.new()
	stacks.name = "Stacks"
	add_child(stacks)

	if not HOOK_LAYOUTS.has(hook_layout):
		DotLog.warn(CHANNEL, "no hook by that name; building the default",
			{"hook_layout": hook_layout, "default": HOOK_DEFAULT, "known": HOOK_LAYOUTS.keys()})
	var layout := pillar_layout()
	for i in range(layout.size()):
		var at := stack_point(layout[i])
		_add_obstacle(at, PILLAR_RADIUS)
		_build_pillar(stacks, "Pillar%d" % i, at)

## The tank farm, out of the one list its meshes, colliders and steering all come from.
func _build_tanks() -> void:
	if radius < TANK_MIN_RADIUS:
		# Said rather than skipped silently, for the reason the stacks say it: a bowl
		# small enough to lose a whole half of the map should name the half and the
		# number, or it reads as a map that was never finished.
		DotLog.info(
			CHANNEL,
			"tank farm left out, bowl too small",
			{"radius": "%.0f m" % radius, "needs": "%.0f m" % TANK_MIN_RADIUS},
		)
		return

	var farm := Node3D.new()
	farm.name = "Tanks"
	add_child(farm)

	var centre := Vector2(TANK_CENTRE.x * radius, TANK_CENTRE.y * radius)

	var layout := tank_layout()
	for i in range(layout.size()):
		var local := layout[i]
		var at := Vector3(centre.x + local.x, 0.0, centre.y + local.y)

		_add_obstacle(at, local.z)
		_build_tank(farm, "Tank%d" % i, at, local.z)

## The district: roads painted on the floor, and every building through
## [method _add_obstacle] like every other cylinder, so steering, the scatter, the toys and
## the gap rule see them with no change. See [BfhDistricts].
func _build_district() -> void:
	var scaffold := Rect2()
	if _has_scaffold:
		var box := scaffold_footprint()
		scaffold = Rect2(box.position.x, box.position.z, box.size.x, box.size.z)

	# The buses' start lanes, whatever the count, so no building stands in front of a bus. The
	# ramp and the deck are in the north strip; the lanes run from there to the middle.
	var south := LEDGE_DEPTH + 6.0 + 24.0 + 4.0
	var keep: Array[Rect2] = [Rect2(-17.0, -radius, 34.0, south)]

	var plan := BfhDistricts.plan(district, radius, scaffold, keep)
	var town := Node3D.new()
	town.name = "District"
	add_child(town)

	var roads := Node3D.new()
	roads.name = "Roads"
	town.add_child(roads)
	for road: Dictionary in plan["roads"]:
		_draw_road(roads, road)

	var index := 0
	for building: Dictionary in plan["buildings"]:
		_add_obstacle(building["at"], float(building["radius"]))
		_district_buildings.append(building)
		_build_building(town, "Building%d" % index, building)
		index += 1

const ROAD_COLOUR := Color(0.46, 0.45, 0.52)
const LOOP_COLOUR := Color(0.95, 0.88, 0.55)
const TOWER_COLOUR := Color(0.64, 0.74, 0.96)
const TOWER_CAP := Color(0.42, 0.52, 0.80)
const HOUSE_COLOUR := Color(0.98, 0.70, 0.56)
const HOUSE_ROOF := Color(0.78, 0.42, 0.40)
const ISLAND_COLOUR := Color(0.58, 0.92, 0.78)

## A road, flat on the floor and never solid: a strip between two points or a disc. Painted a hair
## above the sand so it does not shimmer against it, and thin enough that nothing drives over a lip.
func _draw_road(parent: Node3D, road: Dictionary) -> void:
	var colour := LOOP_COLOUR if road["colour_id"] == "loop" else ROAD_COLOUR
	var mesh := MeshInstance3D.new()

	if road.has("at"):
		var disc := CylinderMesh.new()
		disc.top_radius = float(road["radius"])
		disc.bottom_radius = float(road["radius"])
		disc.height = 0.05
		disc.radial_segments = 40
		mesh.mesh = disc
		mesh.position = road["at"] + Vector3(0.0, 0.03, 0.0)
	else:
		var ends := _clip_to_floor(road["from"], road["to"], float(road["width"]) * 0.5)
		if ends.is_empty():
			mesh.free()
			return
		var from: Vector3 = ends[0]
		var to: Vector3 = ends[1]
		var length := from.distance_to(to)
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.05, float(road["width"]))
		mesh.mesh = box
		var lift := 0.045 if road["colour_id"] == "loop" else 0.025
		mesh.position = (from + to) * 0.5 + Vector3(0.0, lift, 0.0)
		mesh.rotation.y = -atan2(to.z - from.z, to.x - from.x)

	mesh.material_override = BfhTextures.surface(colour)
	parent.add_child(mesh)

## A road's two ends, pulled in to where a strip of half-width [param half] still lies on the
## floor, so a street that meets the wall stops at it instead of running out over the sky.
## Empty when none of it is on the floor.
func _clip_to_floor(from: Vector3, to: Vector3, half: float) -> Array[Vector3]:
	var limit := radius - half - 0.3
	var d := to - from
	var a := d.x * d.x + d.z * d.z
	if a < 0.0001:
		return []
	var b := 2.0 * (from.x * d.x + from.z * d.z)
	var c := from.x * from.x + from.z * from.z - limit * limit
	var disc := b * b - 4.0 * a * c
	if disc <= 0.0:
		return []
	var root := sqrt(disc)
	var t0 := maxf((-b - root) / (2.0 * a), 0.0)
	var t1 := minf((-b + root) / (2.0 * a), 1.0)
	if t1 <= t0:
		return []
	return [from + d * t0, from + d * t1]

## One building: a cylinder collider and a look. A tower is a plain drum with a darker cap, a
## house a drum under a cone roof, a roundabout's island a low green drum.
func _build_building(parent: Node3D, node_name: String, building: Dictionary) -> void:
	var at: Vector3 = building["at"]
	var r := float(building["radius"])
	var h := float(building["height"])
	var kind := String(building["kind"])

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at + Vector3(0.0, h * 0.5, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var drum := CylinderMesh.new()
	drum.top_radius = r
	drum.bottom_radius = r
	drum.height = h
	drum.radial_segments = 28 if r > 4.0 else 16
	var mesh := MeshInstance3D.new()
	mesh.mesh = drum
	mesh.material_override = BfhTextures.surface(
		TOWER_COLOUR if kind == BfhDistricts.TOWER
		else (ISLAND_COLOUR if kind == BfhDistricts.ISLAND else HOUSE_COLOUR)
	)
	body.add_child(mesh)

	# Mesh only, like a pillar's capital: the only body that could touch the roof is a bus,
	# and a lip that catches a hull three metres up is a way to stop one nobody drew.
	if kind == BfhDistricts.HOUSE:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r * 1.25
		cone.height = 2.2
		cone.radial_segments = 16
		var roof := MeshInstance3D.new()
		roof.mesh = cone
		roof.position = Vector3(0.0, h * 0.5 + 1.1, 0.0)
		roof.material_override = BfhTextures.surface(HOUSE_ROOF)
		body.add_child(roof)
	elif kind == BfhDistricts.TOWER:
		var cap := CylinderMesh.new()
		cap.top_radius = r * 1.08
		cap.bottom_radius = r * 1.08
		cap.height = 0.7
		cap.radial_segments = 28
		var cap_mesh := MeshInstance3D.new()
		cap_mesh.mesh = cap
		cap_mesh.position = Vector3(0.0, h * 0.5 - 0.35, 0.0)
		cap_mesh.material_override = BfhTextures.surface(TOWER_CAP)
		body.add_child(cap_mesh)

	parent.add_child(body)

## The colonnade's pillars, through [method _add_obstacle] like every other cylinder,
## so the steering, the scatter keep-out and the gap rule see them with no change. See
## [constant COLONNADE_WALK].
func _build_colonnade() -> void:
	if radius < COLONNADE_MIN_RADIUS:
		DotLog.info(
			CHANNEL,
			"colonnade left out, bowl too small",
			{"radius": "%.0f m" % radius, "needs": "%.0f m" % COLONNADE_MIN_RADIUS},
		)
		return

	var row := Node3D.new()
	row.name = "Colonnade"
	add_child(row)

	var at := colonnade_points()
	for i in range(at.size()):
		_add_obstacle(at[i], PILLAR_RADIUS)
		_build_pillar(row, "Colonnade%d" % i, at[i])

func _build_tank(parent: Node3D, node_name: String, at: Vector3, tank_radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at + Vector3(0.0, TANK_HEIGHT * 0.5, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = tank_radius
	shape.height = TANK_HEIGHT

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	# More segments than a pillar because there is much more of it: 16 sides on a 1.2 m
	# column reads as round and 16 on a 4.4 m drum reads as a nut, which at this size is
	# the only thing on the floor that would look untextured rather than built.
	var drum := CylinderMesh.new()
	drum.top_radius = tank_radius
	drum.bottom_radius = tank_radius
	drum.height = TANK_HEIGHT
	drum.radial_segments = 28

	var mesh := MeshInstance3D.new()
	mesh.mesh = drum
	# Paler and cooler than the concrete of the stacks. A player has to be able to tell
	# at a glance which half of the bowl they are looking at, and the two features are
	# the same shape from above.
	mesh.material_override = BfhTextures.surface(TANK_COLOUR)
	body.add_child(mesh)

	# A band around the top and one around the waist, mesh only. A tank is a big smooth cylinder and
	# the grid alone gives a runner nothing to judge the distance to it by; two horizontal rings at
	# known heights do, and they read from across the bowl.
	for band in [Vector2(TANK_HEIGHT * 0.5 - 0.35, 0.7), Vector2(-TANK_HEIGHT * 0.12, 0.5)]:
		var ring := CylinderMesh.new()
		ring.top_radius = tank_radius * 1.04
		ring.bottom_radius = tank_radius * 1.04
		ring.height = band.y
		ring.radial_segments = 28

		var ring_mesh := MeshInstance3D.new()
		ring_mesh.mesh = ring
		ring_mesh.position = Vector3(0.0, band.x, 0.0)
		ring_mesh.material_override = BfhTextures.surface(TANK_BAND)
		body.add_child(ring_mesh)

	parent.add_child(body)

## One more thing on the floor a bus has to come round.
func _add_obstacle(at: Vector3, obstacle_radius: float) -> void:
	_obstacles.append(at)
	_obstacle_radii.append(obstacle_radius)

func _build_pillar(parent: Node3D, node_name: String, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at + Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = PILLAR_RADIUS
	shape.height = PILLAR_HEIGHT

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var column := CylinderMesh.new()
	column.top_radius = PILLAR_RADIUS
	column.bottom_radius = PILLAR_RADIUS
	column.height = PILLAR_HEIGHT
	column.radial_segments = 16

	var mesh := MeshInstance3D.new()
	mesh.mesh = column
	mesh.material_override = BfhTextures.surface(PILLAR_COLOUR)
	body.add_child(mesh)

	# [b]A capital, and it is mesh only.[/b] A bare cylinder against a bare disc gives a player nothing
	# to judge its height by until they are beside it, and height is the whole reason to run at one. A
	# wider band at the top reads at distance.
	var cap := CylinderMesh.new()
	cap.top_radius = PILLAR_RADIUS * 1.35
	cap.bottom_radius = PILLAR_RADIUS * 1.35
	cap.height = 0.45
	cap.radial_segments = 16

	var cap_mesh := MeshInstance3D.new()
	cap_mesh.mesh = cap
	cap_mesh.position = Vector3(0.0, PILLAR_HEIGHT * 0.5 - 0.22, 0.0)
	cap_mesh.material_override = BfhTextures.surface(PILLAR_CAP)
	body.add_child(cap_mesh)

	parent.add_child(body)
