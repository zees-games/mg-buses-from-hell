extends RefCounted

## The districts: bowls whose floor is a town, laid out by hand to the shape of a kind of place.

## Clear floor kept between any two buildings (surface to surface), in metres. Past
## `BfhArena.LANE_THROUGH` (7.2), which is what the autopilot needs to take a street straight.
const STREET := 7.6

## Clear floor kept between a building and the wall, in metres.
const WALL_ROOM := 8.0

## Clear floor kept between a building and the scaffold, in metres: the scaffold is a place to
## be reached, and a gap under `BfhArena.BUS_GAP` beside it is a pocket a bus cannot get to.
const SCAFFOLD_ROOM := 6.0

## The road surface's width, in metres. Painted only; the floor is the same floor.
const ROAD_WIDTH := 7.0

const DOWNTOWN := &"bfh_downtown"
const HILL_TOWN := &"bfh_hill_town"
const SUBURB := &"bfh_suburb"

## The kinds of building, which are a look and a height, never a different collider.
const TOWER := "tower"
const HOUSE := "house"
const ISLAND := "island"

## Each district's name and radius, in the order a ballot lists them. The radius is the whole
## map's size: a district is placed in metres off the bowl's middle, not as a fraction of it,
## so it only means anything at its own radius.
const LIST := [
	{"id": DOWNTOWN, "name": "Downtown", "radius": 60.0},
	{"id": HILL_TOWN, "name": "Hill Town", "radius": 52.0},
	{"id": SUBURB, "name": "The Suburbs", "radius": 56.0},
]


static func knows(id: String) -> bool:
	for entry in LIST:
		if String(entry["id"]) == id:
			return true
	return false


## One district's `{id, name, radius}`, or an empty dictionary.
static func entry(id: String) -> Dictionary:
	for each in LIST:
		if String(each["id"]) == id:
			return each
	return {}


## What a district puts on the floor: `buildings`, each `{at: Vector3, radius, height, kind}`, and
## `roads`, each `{from: Vector3, to: Vector3, width, colour_id}` for a strip or `{at: Vector3,
## radius, colour_id}` for a disc (a roundabout's ring).
static func plan(id: String, radius: float, scaffold: Rect2, keep_out: Array[Rect2]) -> Dictionary:
	var out := {"buildings": [] as Array[Dictionary], "roads": [] as Array[Dictionary]}
	var ctx := {"radius": radius, "scaffold": scaffold, "keep_out": keep_out}

	match id:
		String(DOWNTOWN):
			_downtown(out, ctx)
		String(HILL_TOWN):
			_hill_town(out, ctx)
		String(SUBURB):
			_suburb(out, ctx)

	return out


# --- Downtown

## A grid: square-ish blocks on a 21 m pitch with an 8 m street between them, an avenue running down
## from the buses' ramp, and a ring street round the middle four blocks, marked in a lighter paint
## because it is the one-way loop a driver circles to come back at a runner.
static func _downtown(out: Dictionary, ctx: Dictionary) -> void:
	var pitch := 19.0
	var block := 5.6
	var z0 := 0.0
	var cols: Array[float] = [-1.5, -0.5, 0.5, 1.5, 2.5, -2.5]
	var rows: Array[float] = [0.0, 1.0, 2.0, 3.0]
	var radius: float = ctx["radius"]

	# Streets first, so a refused block leaves its street painted.
	for r: float in [-0.5, 0.5, 1.5, 2.5, 3.5]:
		var z := z0 + r * pitch
		_road(out, Vector3(-radius + 4.0, 0.0, z), Vector3(radius - 4.0, 0.0, z), ROAD_WIDTH, "road")
	for c: float in [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]:
		var x := c * pitch * 0.5 * 2.0 - 0.0
		x = (c - 0.0) * pitch
		x = c * pitch
		_road(out, Vector3(x, 0.0, -radius + 14.0), Vector3(x, 0.0, radius - 4.0), ROAD_WIDTH, "road")

	# The one-way loop: the ring of street round the middle four blocks, over the road.
	var loop_z0 := z0 - 0.5 * pitch
	var loop_z1 := z0 + 1.5 * pitch
	for pair in [
		[Vector3(-pitch, 0.0, loop_z0), Vector3(pitch, 0.0, loop_z0)],
		[Vector3(pitch, 0.0, loop_z0), Vector3(pitch, 0.0, loop_z1)],
		[Vector3(pitch, 0.0, loop_z1), Vector3(-pitch, 0.0, loop_z1)],
		[Vector3(-pitch, 0.0, loop_z1), Vector3(-pitch, 0.0, loop_z0)],
	]:
		_road(out, pair[0], pair[1], 1.6, "loop")

	var n := 0
	for row: float in rows:
		for col: float in cols:
			var at := Vector3(col * pitch, 0.0, z0 + row * pitch)
			# A little height variety by position, so the skyline is not a comb.
			var height := 6.5 + float((n * 5) % 3) * 0.9
			n += 1
			_building(out, ctx, at, block, height, TOWER)


# --- Hill town

## A road that winds: one long S-bend across the bowl and a switchback arc that doubles back
## beneath it, with small houses stepping along both sides, alternately, so the way is never a
## straight line and the view round each bend is a wall of house.
static func _hill_town(out: Dictionary, ctx: Dictionary) -> void:
	var bend: Array[Vector3] = []
	for i in range(0, 91):
		var x := -44.0 + float(i)
		bend.append(Vector3(x, 0.0, 14.0 + 11.0 * sin(x / 12.0)))

	var arc: Array[Vector3] = []
	for i in range(0, 61):
		var a := deg_to_rad(5.0 + float(i) * 2.5)
		arc.append(Vector3(cos(a) * 38.0, 0.0, sin(a) * 38.0 - 2.0))

	# The lower switchback: a second, tighter S under the first, so a bus coming off the
	# top has to wind down it.
	var low: Array[Vector3] = []
	for i in range(0, 71):
		var z := -6.0 + float(i) * 0.8
		low.append(Vector3(-30.0 + 7.0 * sin(z / 8.0), 0.0, z))

	_road_line(out, bend)
	_road_line(out, arc)
	_along(out, ctx, bend, 13.4, 0.0, true, 2.8)
	_along(out, ctx, arc, 13.4, 5.0, true, 2.8)
	_fill(out, ctx, 13.0, 2.8)


# --- The suburbs

## A ring road with a roundabout where the cross street meets it at each end and one in the
## middle, houses in pairs along every street, and a cul-de-sac off the middle one to the
## south.
static func _suburb(out: Dictionary, ctx: Dictionary) -> void:
	var hubs: Array[Vector3] = [Vector3(-37.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(37.0, 0.0, 0.0)]
	var cul_de_sac := Vector3(0.0, 0.0, 36.0)

	var ring: Array[Vector3] = []
	for i in range(0, 73):
		var a := TAU * float(i) / 72.0
		ring.append(Vector3(cos(a) * 37.0, 0.0, sin(a) * 37.0))

	_road_line(out, ring)
	for hub in hubs:
		_disc(out, hub, 12.0, "road")
	_disc(out, cul_de_sac, 10.0, "road")
	_road(out, hubs[0], hubs[1], ROAD_WIDTH, "road")
	_road(out, hubs[1], hubs[2], ROAD_WIDTH, "road")
	_road(out, hubs[1], cul_de_sac, ROAD_WIDTH, "road")

	for hub in hubs:
		_building(out, ctx, hub, 4.5, 3.2, ISLAND)
	_building(out, ctx, cul_de_sac, 3.4, 3.0, ISLAND)

	_along(out, ctx, ring, 14.5, 4.0, true, 2.8)
	_along(out, ctx, [hubs[0], hubs[1]] as Array[Vector3], 14.5, 15.0, true, 2.8)
	_along(out, ctx, [hubs[1], hubs[2]] as Array[Vector3], 14.5, 15.0, true, 2.8)
	_along(out, ctx, [hubs[1], cul_de_sac] as Array[Vector3], 14.5, 15.0, true, 2.8)


# --- Placing

## Buildings along a polyline, every [param spacing] metres of its length starting
## [param skip] metres in, on both sides when [param both], otherwise alternating. Whatever
## would break the rules is skipped.
static func _along(out: Dictionary, ctx: Dictionary, line: Array[Vector3], spacing: float,
		skip: float, both: bool, house: float) -> void:
	var walked := 0.0
	var next := skip
	var n := 0
	var sizes := [house, house + 0.6, house + 0.2, house + 0.9]

	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var dir := (b - a) / seg
		var side := Vector3(-dir.z, 0.0, dir.x)

		while next <= walked + seg:
			var centre := a + dir * (next - walked)
			var r: float = house if both else float(sizes[n % sizes.size()])
			var off := ROAD_WIDTH * 0.5 + r + 0.5
			var kind := HOUSE
			var height := 4.2 + float((n * 3) % 3) * 0.7
			if both:
				_building(out, ctx, centre + side * off, r, height, kind)
				_building(out, ctx, centre - side * off, r, height, kind)
			else:
				var sign := 1.0 if n % 2 == 0 else -1.0
				_building(out, ctx, centre + side * off * sign, r, height, kind)
			n += 1
			next += spacing
		walked += seg


## Houses on the hillside between the roads: a staggered grid tried cell by cell, each
## refused by the same rules as any other building, so what survives is whatever fits. The
## stagger and a small deterministic wobble keep it from reading as a lattice.
static func _fill(out: Dictionary, ctx: Dictionary, pitch: float, house: float) -> void:
	var radius: float = ctx["radius"]
	var n := 0
	var rows := int(radius * 2.0 / pitch) + 1
	for j in range(rows):
		var z := -radius + float(j) * pitch
		for i in range(rows):
			var x := -radius + float(i) * pitch + (pitch * 0.5 if j % 2 == 1 else 0.0)
			var wobble := Vector3(float((n * 7) % 5) - 2.0, 0.0, float((n * 3) % 5) - 2.0) * 0.4
			_building(out, ctx, Vector3(x, 0.0, z) + wobble, house, 4.2 + float(n % 3) * 0.7, HOUSE)
			n += 1


## Adds one building unless it would crowd anything. Returns whether it went in.
static func _building(out: Dictionary, ctx: Dictionary, at: Vector3, r: float, height: float,
		kind: String) -> bool:
	var radius: float = ctx["radius"]

	if Vector2(at.x, at.z).length() + r > radius - WALL_ROOM:
		return false

	for other: Dictionary in out["buildings"]:
		var apart := Vector2(at.x - other["at"].x, at.z - other["at"].z).length()
		if apart - r - float(other["radius"]) < STREET:
			return false

	# Never on a street: a house on another road would paint the road under it.
	if kind != ISLAND and _on_a_road(out, at, r):
		return false

	var scaffold: Rect2 = ctx["scaffold"]
	if scaffold.size != Vector2.ZERO:
		var dx := maxf(maxf(scaffold.position.x - at.x, at.x - scaffold.end.x), 0.0)
		var dz := maxf(maxf(scaffold.position.y - at.z, at.z - scaffold.end.y), 0.0)
		if Vector2(dx, dz).length() - r < SCAFFOLD_ROOM:
			return false

	for zone: Rect2 in ctx["keep_out"]:
		if zone.grow(r).has_point(Vector2(at.x, at.z)):
			return false

	out["buildings"].append({"at": at, "radius": r, "height": height, "kind": kind})
	return true


## Whether a building of [param r] at [param at] would stand on a painted road: inside a strip's
## half width or a roundabout's disc. The lighter one-way paint is on top of a road and not one.
static func _on_a_road(out: Dictionary, at: Vector3, r: float) -> bool:
	var p := Vector2(at.x, at.z)

	for road: Dictionary in out["roads"]:
		if road["colour_id"] == "loop":
			continue
		if road.has("at"):
			if p.distance_to(Vector2(road["at"].x, road["at"].z)) < float(road["radius"]) + r - 0.5:
				return true
			continue
		var a := Vector2(road["from"].x, road["from"].z)
		var b := Vector2(road["to"].x, road["to"].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(road["width"]) * 0.5 + r - 0.5:
			return true

	return false


static func _road(out: Dictionary, from: Vector3, to: Vector3, width: float, colour_id: String) -> void:
	out["roads"].append({"from": from, "to": to, "width": width, "colour_id": colour_id})


static func _road_line(out: Dictionary, line: Array[Vector3]) -> void:
	for i in range(line.size() - 1):
		_road(out, line[i], line[i + 1], ROAD_WIDTH, "road")


static func _disc(out: Dictionary, at: Vector3, radius: float, colour_id: String) -> void:
	out["roads"].append({"at": at, "radius": radius, "colour_id": colour_id})
