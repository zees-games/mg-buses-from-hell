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

## Half a bus's body across, from the scene's 2.5 m collision box.
const BUS_HALF_WIDTH := 1.25

## The distance from the ramp's centreline to the nearest bus lane: half the ramp, half
## a bus (its body is 2.5 m across) and a metre and a half of air between them.
const BUS_RAMP_CLEAR := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH + 1.5

## Between two buses on the same side. What the old centred line used.
const BUS_LANE := 6.0

## The ramp foot, where a bus arrives on the floor.
func ramp_foot() -> Vector3:
	var run := RAMP_LENGTH * cos(deg_to_rad(RAMP_ANGLE))
	return Vector3(0.0, 0.5, -(radius - LEDGE_DEPTH) + run - RAMP_TUCK)

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

## What the district built, one `{at, radius, height, kind}` per building. Empty on the bowl.
func district_buildings() -> Array[Dictionary]:
	return _district_buildings

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

