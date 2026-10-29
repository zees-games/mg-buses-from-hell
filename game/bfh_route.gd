extends RefCounted

## A route for a bot bus through a town: the streets between the buildings, found on a grid laid
## over the one obstacle description and pulled straight.

## Grid pitch in metres. A street leaves 0.8 m of open centre line at the default clearance, so
## a cell must be narrower than that or a street could fall between two columns of cells.
const CELL := 0.8

## How far (in cells) the nearest open cell is searched for when a point is inside a solid one.
const SEARCH := 8

var _grid := AStarGrid2D.new()
var _obstacles := PackedVector3Array()
var _radii := PackedFloat32Array()
var _slabs: Array[Rect2] = []
var _half := 0.0
var _origin := Vector2.ZERO
var _clearance := 0.0
var _size := 0


## Lays the grid over a bowl of [param radius] with [param obstacles] (axis and
## [param radii]) and [param slabs] (the ramp's and the deck's, in plan), for a
## bus kept [param clearance] off all of them. [param slabs] are the ramp's and the deck's footprints.
func build(radius: float, obstacles: PackedVector3Array, radii: PackedFloat32Array,
		slabs: Array[Rect2], clearance: float) -> void:
	_obstacles = obstacles
	_radii = radii
	_slabs = []
	for slab in slabs:
		_slabs.append(slab.grow(clearance))
	_clearance = clearance
	_half = radius
	_size = int(ceil(radius * 2.0 / CELL)) + 1
	_origin = Vector2(-radius, -radius)
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _size, _size)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()

	# The wall and the slab first, then every obstacle over its own bounding box only.
	for ix in range(_size):
		for iy in range(_size):
			var at := _centre(Vector2i(ix, iy))
			var solid := at.length() > radius - clearance
			for slab in _slabs:
				solid = solid or slab.has_point(at)
			if solid:
				_grid.set_point_solid(Vector2i(ix, iy), true)
	for i in range(_obstacles.size()):
		var reach := _radii[i] + clearance
		var lo := _cell_of(Vector2(_obstacles[i].x - reach, _obstacles[i].z - reach))
		var hi := _cell_of(Vector2(_obstacles[i].x + reach, _obstacles[i].z + reach))
		for ix in range(maxi(lo.x, 0), mini(hi.x, _size - 1) + 1):
			for iy in range(maxi(lo.y, 0), mini(hi.y, _size - 1) + 1):
				var at := _centre(Vector2i(ix, iy))
				if at.distance_to(Vector2(_obstacles[i].x, _obstacles[i].z)) < reach:
					_grid.set_point_solid(Vector2i(ix, iy), true)


## Waypoints from [param from] to [param to], not including [param from], or empty when the
## straight line between them is already clear (or no way was found: the caller drives at
## the target and the stuck rule is what is left, as before).
func plan(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _size == 0 or _clear(Vector2(from.x, from.z), Vector2(to.x, to.z)):
		return out

	var a := _open_near(_cell_of(Vector2(from.x, from.z)))
	var b := _open_near(_cell_of(Vector2(to.x, to.z)))
	if a.x < 0 or b.x < 0:
		return out
	var cells := _grid.get_id_path(a, b)
	if cells.is_empty():
		return out

	# Pulled straight: from each anchor, the furthest cell it can see.
	var points: Array[Vector2] = []
	for cell in cells:
		points.append(_centre(cell))
	var anchor := Vector2(from.x, from.z)
	var i := 0
	while i < points.size():
		var furthest := i
		for j in range(points.size() - 1, i - 1, -1):
			if _clear(anchor, points[j]):
				furthest = j
				break
		out.append(Vector3(points[furthest].x, to.y, points[furthest].y))
		anchor = points[furthest]
		i = furthest + 1
	return out


## Whether a bus's centre can go in a straight line from [param a] to [param b] without coming
## within the clearance of anything. The same test the grid was built from, applied to the
## segment, so a pulled route never cuts a corner the cells refused.
func _clear(a: Vector2, b: Vector2) -> bool:
	# A little less than the grid's, so a route along a street's open centre line is not
	# thrown out by the one cell of rounding that put it there.
	var slack := _clearance - 0.15
	for slab in _slabs:
		if _segment_hits_rect(a, b, slab.grow(-0.15)):
			return false
	var wall := _half - slack
	if _farthest_from_origin(a, b) > wall:
		return false
	for i in range(_obstacles.size()):
		var c := Vector2(_obstacles[i].x, _obstacles[i].z)
		var closest := Geometry2D.get_closest_point_to_segment(c, a, b)
		if closest.distance_to(c) < _radii[i] + slack:
			return false
	return true


func _farthest_from_origin(a: Vector2, b: Vector2) -> float:
	# The farthest the segment gets from the middle is an end of it (a disc is convex).
	return maxf(a.length(), b.length())


func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for k in range(4):
		if Geometry2D.segment_intersects_segment(a, b, corners[k], corners[(k + 1) % 4]) != null:
			return true
	return false


func _cell_of(at: Vector2) -> Vector2i:
	return Vector2i(int(floor((at.x - _origin.x) / CELL)), int(floor((at.y - _origin.y) / CELL)))


func _centre(cell: Vector2i) -> Vector2:
	return _origin + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## The open cell nearest [param cell] by ring, or (-1, -1).
func _open_near(cell: Vector2i) -> Vector2i:
	var here := Vector2i(clampi(cell.x, 0, _size - 1), clampi(cell.y, 0, _size - 1))
	if not _grid.is_point_solid(here):
		return here
	for ring in range(1, SEARCH + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var c := here + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= _size or c.y >= _size or _grid.is_point_solid(c):
					continue
				var d := float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)
