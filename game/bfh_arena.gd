extends Node3D

const BfhConfig := preload("bfh_config.gd")
const BfhContent := preload("bfh_content.gd")
const BfhReach := preload("bfh_reach.gd")
const BfhTextures := preload("bfh_textures.gd")
const BfhDistricts := preload("bfh_districts.gd")
const BfhRoute := preload("bfh_route.gd")

## The bowl: a round sand floor, a wall around it, and a ledge the drivers look from.

const CHANNEL := "bfh.arena"

## Metres of wall above the floor. Tall enough that a bus cannot launch over it.
const WALL_HEIGHT := 9.0

const WALL_THICKNESS := 2.0

## Segments in the ring. 48 reads as round at this radius and costs 48 boxes.
const WALL_SEGMENTS := 48

## Where the drivers start, above the floor at the north edge.
const LEDGE_HEIGHT := 7.0
const LEDGE_DEPTH := 14.0
const LEDGE_WIDTH := 22.0

## The drive down onto the floor.
const RAMP_LENGTH := 26.0
const RAMP_ANGLE := 18.0
const RAMP_THICKNESS := 0.8
const RAMP_WIDTH := 5.0

## How far the ramp's top end runs in under the deck.
const RAMP_TUCK := 0.3

## THE STACKS: the permanent half of the bowl.
const PILLAR_RADIUS := 1.2

## Taller than the bus, so it meets the hull rather than a wheel ray.
const PILLAR_HEIGHT := 5.4

## Stack-local metres: [code]x[/code] runs along the lane, [code]z[/code] across it. The two rows
## sit at +/- 4.6, so the lane is 6.8 m of clear floor between the pillar faces -- comfortable for a
## three-metre bus at speed and not comfortable at all for a driver who arrives at it crooked.
const PILLAR_LAYOUT: Array[Vector2] = [
	Vector2(-13.0, -4.6),
	Vector2(-4.5, -4.6),
	Vector2(4.0, -4.6),
	Vector2(12.5, -4.6),
	Vector2(-8.5, 4.6),
	Vector2(0.0, 4.6),
	Vector2(8.5, 4.6),
	# The dog-leg. Offset rather than centred, so the lane closes to one side instead
	# of plugging: there is a way out at speed and it is not the one you are pointing at.
	Vector2(17.0, 1.6),

	# --- The hook, past the dog-leg
	Vector2(22.5, -6.2),
	Vector2(27.5, 0.0),
	Vector2(23.0, 6.6),

	# A third row makes the rows between it and the old south row a second lane, and turns the west end
	# into a fork: the old lane ends at the dog-leg and the hook; this one ends at the hook's south
	# pillar, offset in it the way the dog-leg is offset in the first, and past it is the open.
	Vector2(-4.5, 14.6),
	Vector2(4.0, 14.6),
]

## The first of the hook's three pillars in [constant PILLAR_LAYOUT].
const HOOK_FIRST := 8

## The hook's three pillars, stack-local, by name: what [code]BfhConfig.hook_layout[/code] chooses
## between. Each replaces [constant PILLAR_LAYOUT]'s [code]HOOK_FIRST[/code] to [code]HOOK_FIRST +
## 2[/code] in that order (north, middle, south).
const HOOK_LAYOUTS := {
	"tight": [Vector2(22.5, -6.2), Vector2(27.5, 0.0), Vector2(23.0, 6.6)],
	"wide": [Vector2(22.5, -6.2), Vector2(30.3, 0.0), Vector2(23.0, 6.6)],
}

## The hook a map gets when nothing says otherwise. [constant PILLAR_LAYOUT] carries it.
const HOOK_DEFAULT := "tight"

## Set before [method build]: which of [constant HOOK_LAYOUTS] the hook is. Layout data rather than
## a constant so an operator can choose it, and it reaches a client in the HELLO, because the map is
## this function run on both ends. An unknown name builds the default and says so.
var hook_layout: String = HOOK_DEFAULT


## The stacks' lanes, as the stack-local [code]z[/code] of each centre line: the first
## lane between the two original rows, and the second between the old south row and the
## third ([constant PILLAR_LAYOUT]).
const STACK_LANES: Array[float] = [0.0, 9.6]

## Stack-local [code]x[/code] where the lanes' rows end and the dog-legs begin. A pillar
## west of this is a side of a lane; one east of it that stands across a lane's centre
## line is what stops the lane running clean through.
const STACK_LANE_END := 14.0

## Which way the lane points. Deliberately not aligned with anything: the ramp arrives
## on the bowl's north-south axis, and a lane square to it would be a corridor a driver
## can line up on from the moment they land.
const STACK_YAW := 25.0

## Where the cluster sits, as a fraction of the bowl radius, so a smaller bowl gets the
## stacks in proportion. The pillar spacing itself does NOT scale -- it is sized to a
## bus, and a bus is the same size in every bowl.
const STACK_CENTRE := Vector2(-0.36, 0.14)

## Below this the lanes would not fit inside the floor and the stacks are left out.
const STACK_MIN_RADIUS := 36.0

## THE TANK FARM: the east half, and a different question from the stacks.
const TANK_HEIGHT := 6.8

## Tank-local metres and the radius of each, as [code]x, z, radius[/code].
const TANK_LAYOUT: Array[Vector3] = [
	Vector3(-9.0, -6.0, 4.4),
	Vector3(6.5, -8.0, 3.0),
	Vector3(10.5, 3.5, 3.8),
	Vector3(-5.0, 7.0, 2.6),

	# Two more drums close a second courtyard between the first and the scaffold: two rooms joined by
	# the courtyard's widest lane, and a covered way from the middle of the farm to the foot of the
	# height.
	Vector3(-1.5, 17.5, 2.6),
	Vector3(11.5, 15.0, 2.2),
]

## The courtyard's west lane, as the clear floor between its two drums (the 4.4 m tank 0 and the 2.6
## m tank 3), by default.
const COURTYARD_WEST_LANE := 7.6

const COURTYARD_WEST_LANE_NARROW := 6.6

## The tanks either side of the courtyard's west lane, in [constant TANK_LAYOUT]. Tank 0
## is the one [member courtyard_west_lane] moves.
const WEST_LANE_TANKS := Vector2i(0, 3)

## Set before [method build]: the courtyard's west lane, in metres of clear floor. Layout
## data for the reason [member hook_layout] is, and sent in the HELLO with it.
var courtyard_west_lane: float = COURTYARD_WEST_LANE


## [constant TANK_LAYOUT] with tank 0 placed for a west lane of [param west_lane] metres:
## moved along the line from tank 3 through its constant position. A negative
## [param west_lane] leaves the constant as it is.
static func layout_with_west_lane(west_lane: float) -> Array[Vector3]:
	var layout: Array[Vector3] = TANK_LAYOUT.duplicate()
	if west_lane < 0.0:
		return layout
	var moved := TANK_LAYOUT[WEST_LANE_TANKS.x]
	var fixed := TANK_LAYOUT[WEST_LANE_TANKS.y]
	var out := Vector2(moved.x - fixed.x, moved.y - fixed.y).normalized()
	var at := Vector2(fixed.x, fixed.y) + out * (fixed.z + moved.z + west_lane)
	layout[WEST_LANE_TANKS.x] = Vector3(at.x, at.y, moved.z)
	return layout


## [constant TANK_LAYOUT] as this arena builds it. See [member courtyard_west_lane].
func tank_layout() -> Array[Vector3]:
	return layout_with_west_lane(courtyard_west_lane)


## The farm's open floors, each as the tanks round it in order, so that neighbours in the list are
## the two sides of a lane. Indices into [constant TANK_LAYOUT].
const TANK_YARDS: Array[Array] = [
	[0, 1, 2, 3],
	[3, 2, 5, 4],
]

## Where the farm sits, as a fraction of the bowl radius -- like the stacks, and for the
## same reason: a smaller bowl gets it in proportion while the spacing inside it stays
## sized to a bus.
const TANK_CENTRE := Vector2(0.467, -0.152)

## Below this the farm is left out, and [b]it is not the same number as the stacks' nor about
## fitting inside the wall.[/b] Both clusters are placed as a fraction of the radius, so a smaller
## bowl brings them TOWARDS each other while the gap a bus needs stays an absolute width.
const TANK_MIN_RADIUS := 40.0

## [b]The quarter of the bowl the buses come out into had nothing in it.[/b] The stacks hold the
## west, the farm the east, the scaffold the south-east, and the north-west -- thirty metres of sand
## between the stacks' west mouths, the wall and the deck's west end -- was where a runner.

## Clear floor between each pillar's face and the wall: the walk. The second lane's width.
const COLONNADE_WALK := 7.6

## Pillar centre to pillar centre, along the arc's chord: 8.0 m of clear floor between
## faces, past [constant LANE_THROUGH].
const COLONNADE_SPACING := 10.4

const COLONNADE_PILLARS := 4

## Where the first pillar stands, in degrees round the bowl from +X towards +Z: 236 is
## north-west, with 8.6 m of floor between it and the deck's west corner. The rest step
## towards the stacks.
const COLONNADE_FIRST := 236.0

## Below this it is left out. The pillars keep their distance from the wall and their spacing, so on
## a smaller bowl the arc swings in towards the deck's corner and the stacks' west end; measured by
## [method colonnade_clearance], which `headless_run` asks at this radius.
const COLONNADE_MIN_RADIUS := 45.0

var radius: float = 46.0

## Which of [code]BfhDistricts[/code] the floor is, by id; empty (or an id this build does not know)
## is the bowl with its stacks, tank farm and colonnade. Layout, not a cvar, for the reason [member
## hook_layout] is not one: it travels in the HELLO and a client builds the server's.
var district: String = ""

## What the district placed: each `{at, radius, height, kind}`, in the order the obstacles
## were appended after the first obstacle this build made. A view for the drawing and the
## suite; the one description of what is solid is still [code]_obstacles[/code].
var _district_buildings: Array[Dictionary] = []

## Set before [method build]. The layers every piece of the world goes on.
var world_layer: int = 1
var world_mask: int = 1

var _floor_body: StaticBody3D = null

## The ramp's body, for the steering and for measuring its lip.
var _ramp: StaticBody3D = null

## Every round obstacle on the floor, and how wide each one is.
var _obstacles: PackedVector3Array = PackedVector3Array()
var _obstacle_radii: PackedFloat32Array = PackedFloat32Array()

## How many of [member _obstacles] are stack pillars. The rest are tanks.
var _stack_count: int = 0

## Where the tanks end in [member _obstacles]. The colonnade's pillars follow.
var _tank_end: int = 0


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


## Where a runner may be put: anywhere on the floor, inside a margin.
func runner_area_radius() -> float:
	return radius - 6.0


## Metres above the deck surface a bus is dropped from.
const BUS_DROP := 2.0

## The middle of the driver ledge, which is where a bus is put.
func ledge_centre() -> Vector3:
	return Vector3(0.0, deck_top() + BUS_DROP, -(radius - LEDGE_DEPTH * 0.5))


## The walking surface of the driver ledge.
func deck_top() -> float:
	return LEDGE_HEIGHT + 0.5


## Where the [param index]th of [param count] buses starts, on the floor.
func bus_start(index: int, count: int) -> Vector3:
	var _count := maxi(count, 1)
	var side := 1.0 if index % 2 == 0 else -1.0
	var x := side * (BUS_RAMP_CLEAR + BUS_LANE * float(index / 2))
	return Vector3(x, 1.4, -(radius - LEDGE_DEPTH - 6.0))


## The distance from the ramp's centreline to the nearest bus lane: half the ramp, half
## a bus (its body is 2.5 m across) and a metre and a half of air between them.
const BUS_RAMP_CLEAR := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH + 1.5

## Between two buses on the same side. What the old centred line used.
const BUS_LANE := 6.0


## The ramp foot, where a bus arrives on the floor.
func ramp_foot() -> Vector3:
	var run := RAMP_LENGTH * cos(deg_to_rad(RAMP_ANGLE))
	return Vector3(0.0, 0.5, -(radius - LEDGE_DEPTH) + run - RAMP_TUCK)


## The bowl's palette: a sunny sand bowl in the family's pastels (game-arena's built-in maps), one
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


## [constant PILLAR_LAYOUT] as this arena builds it: the hook from [member hook_layout].
## Everything else in the stacks is the constant.
func pillar_layout() -> Array[Vector2]:
	return layout_with_hook(hook_layout)


## [constant PILLAR_LAYOUT] with the hook named [param hook] (one of
## [constant HOOK_LAYOUTS]; anything else is the default).
static func layout_with_hook(hook: String) -> Array[Vector2]:
	var layout: Array[Vector2] = PILLAR_LAYOUT.duplicate()
	var points: Array = HOOK_LAYOUTS.get(hook, HOOK_LAYOUTS[HOOK_DEFAULT])
	for i in range(points.size()):
		layout[HOOK_FIRST + i] = points[i]
	return layout


## The clear floor in the named hook's two narrow gaps: [code]x[/code] south-middle (the third
## pillar to the middle), [code]y[/code] middle-north (the middle to the first), as `headless_run`
## names them.
static func hook_gaps(hook: String) -> Vector2:
	var layout := layout_with_hook(hook)
	var middle := layout[HOOK_FIRST + 1]
	return Vector2(
		layout[HOOK_FIRST + 2].distance_to(middle) - 2.0 * PILLAR_RADIUS,
		middle.distance_to(layout[HOOK_FIRST]) - 2.0 * PILLAR_RADIUS,
	)


## A stack-local point ([code]x[/code] along the lanes, [code]z[/code] across them) on
## the floor of this bowl. The one transform the pillars, the lanes' checks and the
## cameras all go through.
func stack_point(local: Vector2) -> Vector3:
	var centre := Vector2(STACK_CENTRE.x * radius, STACK_CENTRE.y * radius)
	var yaw := deg_to_rad(STACK_YAW)
	return Vector3(
		centre.x + local.x * cos(yaw) - local.y * sin(yaw),
		0.0,
		centre.y + local.x * sin(yaw) + local.y * cos(yaw),
	)


## The clear floor across the [param lane]th of [constant STACK_LANES], in metres: twice
## the distance from its centre line to the nearest pillar face along it. Off the layout,
## because the spacing does not scale with the bowl.
static func stack_lane_width(lane: int) -> float:
	var half := INF
	for local in PILLAR_LAYOUT:
		if local.x < STACK_LANE_END:
			half = minf(half, absf(local.y - STACK_LANES[lane]) - PILLAR_RADIUS)
	return half * 2.0


## Whether a pillar past [constant STACK_LANE_END] stands across the [param lane]th
## lane, so that a driver on its fast line has to get out of it at the far end.
static func stack_lane_plugged(lane: int) -> bool:
	var half := stack_lane_width(lane) * 0.5 + PILLAR_RADIUS
	for local in PILLAR_LAYOUT:
		if local.x >= STACK_LANE_END and absf(local.y - STACK_LANES[lane]) < half:
			return true
	return false


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


## What the district built, one `{at, radius, height, kind}` per building. Empty on the bowl.
func district_buildings() -> Array[Dictionary]:
	return _district_buildings


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


## Where the colonnade's pillars stand, from the deck's end towards the stacks. Defined
## whether or not this bowl has the colonnade.
func colonnade_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	var arc := colonnade_arc_radius()
	var step := 2.0 * asin(COLONNADE_SPACING * 0.5 / arc)
	var first := deg_to_rad(COLONNADE_FIRST)
	for i in range(COLONNADE_PILLARS):
		var angle := first - step * float(i)
		out.append(Vector3(cos(angle), 0.0, sin(angle)) * arc)
	return out


## The radius of the circle the pillars' axes stand on.
func colonnade_arc_radius() -> float:
	return radius - COLONNADE_WALK - PILLAR_RADIUS


## A point on the middle of the walk, [param t] of the way from the deck's end (0) to the
## stacks' end (1), measured in pillar positions so 0.5 between pillars 1 and 2 of four.
func colonnade_walk_point(t: float) -> Vector3:
	var arc := colonnade_arc_radius()
	var step := 2.0 * asin(COLONNADE_SPACING * 0.5 / arc)
	var angle := deg_to_rad(COLONNADE_FIRST) - step * t * float(COLONNADE_PILLARS - 1)
	var middle := radius - COLONNADE_WALK * 0.5
	return Vector3(cos(angle), 0.0, sin(angle)) * middle


## Whether this bowl was built with the colonnade.
func has_colonnade() -> bool:
	return _obstacles.size() > _tank_end


## The pillars, deck end first. Empty on a bowl too small for it.
func colonnade() -> PackedVector3Array:
	return _obstacles.slice(_tank_end)


## The narrowest clear floor between a colonnade pillar and anything that is not the walk or a
## neighbour in the row: every other cylinder, the ramp's slab and the deck. The walk (to the wall)
## and the gaps in the row are fixed by construction and measured by their own checks.
func colonnade_clearance() -> float:
	if not has_colonnade():
		return INF
	var nearest := INF
	var deck_z := -(radius - LEDGE_DEPTH)
	var half_ramp := RAMP_WIDTH * 0.5
	var foot_z := ramp_foot().z
	for i in range(_tank_end, _obstacles.size()):
		var at := _obstacles[i]
		for j in range(_tank_end):
			var axis := Vector2(at.x - _obstacles[j].x, at.z - _obstacles[j].z).length()
			nearest = minf(nearest, axis - PILLAR_RADIUS - _obstacle_radii[j])
		nearest = minf(nearest, _to_box(at, -half_ramp, half_ramp, deck_z, foot_z) - PILLAR_RADIUS)
		nearest = minf(nearest,
			_to_box(at, -LEDGE_WIDTH * 0.5, LEDGE_WIDTH * 0.5, -radius, deck_z) - PILLAR_RADIUS)
	return nearest


## Clear distance on the floor from [param at] to an axis-aligned rectangle.
static func _to_box(at: Vector3, x0: float, x1: float, z0: float, z1: float) -> float:
	var dx := maxf(maxf(x0 - at.x, at.x - x1), 0.0)
	var dz := maxf(maxf(z0 - at.z, at.z - z1), 0.0)
	return Vector2(dx, dz).length()


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


## Where the pillars stand, on the floor plane. Empty on a bowl too small for them.
func pillars() -> PackedVector3Array:
	return _obstacles.slice(0, _stack_count)


## Where the tanks stand, on the floor plane. Empty on a bowl too small for them.
func tanks() -> PackedVector3Array:
	return _obstacles.slice(_stack_count, _tank_end)


## The middle of the [param index]th of [constant TANK_YARDS] on the built map: the
## centroid of the tanks round it, on the floor. [constant Vector3.ZERO] with no farm.
func yard_middle(index: int) -> Vector3:
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for i: int in TANK_YARDS[index]:
		sum += farm[i]
	return Vector3(sum.x, 0.0, sum.z) / float(TANK_YARDS[index].size())


## The clear floor in each lane round the [param index]th yard, in order: element i is
## between its tank i and tank i + 1. Face to face, like [method narrowest_gap].
func yard_lanes(index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return out
	var yard: Array = TANK_YARDS[index]
	for i in range(yard.size()):
		var a: int = yard[i]
		var b: int = yard[(i + 1) % yard.size()]
		out.append(
			Vector2(farm[a].x - farm[b].x, farm[a].z - farm[b].z).length()
				- obstacle_radius(_stack_count + a) - obstacle_radius(_stack_count + b)
		)
	return out


## The midpoint of the lane between the [param index]th yard's tank [param i] and the
## next one round, at the middle of the clear floor rather than between the two axes.
func yard_lane_middle(index: int, i: int) -> Vector3:
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return Vector3.ZERO
	var yard: Array = TANK_YARDS[index]
	var a: int = yard[i % yard.size()]
	var b: int = yard[(i + 1) % yard.size()]
	var ra := obstacle_radius(_stack_count + a)
	var rb := obstacle_radius(_stack_count + b)
	var along := farm[b] - farm[a]
	along.y = 0.0
	var gap := along.length() - ra - rb
	return Vector3(farm[a].x, 0.0, farm[a].z) + along.normalized() * (ra + gap * 0.5)


## The clear floor a lane needs before the bot bus will drive straight through it, in metres:
## [constant PILLAR_CLEARANCE] each side of the line through its middle.
const LANE_THROUGH := 2.0 * PILLAR_CLEARANCE


## The lanes round the [param index]th yard the bot bus cannot drive through, as lane indices (see
## [method yard_lanes]): every lane narrower than [constant LANE_THROUGH].
func yard_refuges(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lanes := yard_lanes(index)
	for i in range(lanes.size()):
		if lanes[i] < LANE_THROUGH:
			out.append(i)
	return out


## Everything solid standing on the sand: the stacks, then the tank farm.
func obstacles() -> PackedVector3Array:
	return _obstacles


## How wide the [param index]th obstacle is, in metres.
func obstacle_radius(index: int) -> float:
	return _obstacle_radii[index] if index >= 0 and index < _obstacle_radii.size() else 0.0


## The least clear floor between any two obstacles on the built map, in metres. INF when there are
## fewer than two.
func narrowest_gap() -> float:
	var narrowest := INF

	for i in range(_obstacles.size()):
		for j in range(i + 1, _obstacles.size()):
			var axis := Vector2(
				_obstacles[i].x - _obstacles[j].x, _obstacles[i].z - _obstacles[j].z
			).length()
			narrowest = minf(narrowest, axis - _obstacle_radii[i] - _obstacle_radii[j])

	return narrowest


## The clear floor a bus needs between two obstacles, in metres.
const BUS_GAP := 2.0 * (PILLAR_CLEARANCE - PILLAR_RADIUS)


## The tightest gap between any two pillar axes, in metres. INF when there are none.
static func narrowest_pillar_gap() -> float:
	var narrowest := INF

	for i in range(PILLAR_LAYOUT.size()):
		for j in range(i + 1, PILLAR_LAYOUT.size()):
			narrowest = minf(narrowest, PILLAR_LAYOUT[i].distance_to(PILLAR_LAYOUT[j]))

	return narrowest


## How far from a pillar's axis a bus has to pass to miss it.
##
## Its radius, plus half a bus, plus enough that clearing one does not mean grazing it.
const PILLAR_CLEARANCE := 3.6


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


## Half a bus's body across, from the scene's 2.5 m collision box.
const BUS_HALF_WIDTH := 1.25

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
