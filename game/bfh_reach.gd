extends RefCounted

## What a runner can get onto, as arithmetic over the movement they actually have.

## The family's margin, owned by the controller.
const CLIMB_MARGIN := DotFpsTunables.CLIMB_MARGIN

## How a climb is made. Each is held to a different number, which is why it is declared
## rather than inferred: a 0.4 m rise is a STEP if you walk into it and a JUMP if there is
## a gap in front of it, and only the map knows which it meant.
enum How {
	## Walked into. Held to `step_height`, with no gap.
	STEP,
	## Jumped onto from a run. Held to [method climb_limit] and [method jump_reach].
	JUMP,
	## Walked up a slope and over the lip at its top. Held to `max_slope_angle` for the
	## slope and to `step_height` for the lip.
	WALK,
	## Thrown by a barrel. Held to [constant CLIMB_MARGIN] of the throw's apex.
	THROW,
}


## One way up the bowl expects a runner to take, measured off the geometry.
class Climb:
	extends RefCounted

	var name: String = ""
	var how: int = How.JUMP
	## Metres gained, top face to top face.
	var rise: float = 0.0
	## Clear horizontal air between the two footprints; 0 when they touch or overlap.
	var gap: float = 0.0
	## Degrees, for a [constant How.WALK].
	var slope: float = 0.0
	## Metres of apex a [constant How.THROW] reaches. Filled by whoever declares it,
	## because it depends on where the runner stands.
	var lift: float = 0.0

	static func between(of_name: String, p_how: int, from_box: AABB, to_box: AABB) -> Climb:
		var climb := Climb.new()
		climb.name = of_name
		climb.how = p_how
		climb.rise = to_box.end.y - from_box.end.y
		climb.gap = maxf(
			_clear(from_box.position.x, from_box.end.x, to_box.position.x, to_box.end.x),
			_clear(from_box.position.z, from_box.end.z, to_box.position.z, to_box.end.z)
		)
		return climb

	## The larger axis, not the diagonal: two boxes offset on both axes are crossed by
	## jumping along whichever one separates them.
	static func _clear(a_min: float, a_max: float, b_min: float, b_max: float) -> float:
		if b_min >= a_max:
			return b_min - a_max
		if a_min >= b_max:
			return a_min - b_max
		return 0.0

	func describe() -> String:
		var kind: String = How.keys()[how].to_lower()
		match how:
			How.WALK:
				return "%s: walk, %.0f deg, lip %.2f" % [name, slope, rise]
			How.THROW:
				return "%s: throw, rise %.2f of %.2f" % [name, rise, lift]
		return "%s: %s, rise %.2f, gap %.2f" % [name, kind, rise, gap]


## The speed that carries a body [param height] metres up under [param gravity].
static func launch_speed(gravity: float, height: float) -> float:
	return sqrt(2.0 * gravity * maxf(height, 0.0))


## The highest top face a runner standing on flat ground jumps onto, in metres.
## [method DotFpsTunables.climb_limit] at [constant CLIMB_MARGIN].
static func climb_limit(t: DotFpsTunables) -> float:
	return t.climb_limit(CLIMB_MARGIN)


## The clear air a runner at full ground speed crosses in one jump, landing [param rise] metres
## higher than they left. [method DotFpsTunables.jump_reach] at `max_speed`.
static func jump_reach(t: DotFpsTunables, rise: float) -> float:
	return t.jump_reach(rise, t.max_speed)


## Why [param climb] is outside what [param t] can do, or "" when it is inside it.
static func refusal(climb: Climb, t: DotFpsTunables) -> String:
	match climb.how:
		How.STEP:
			if climb.gap > 0.0:
				return "a step with %.2f m of air in front of it" % climb.gap
			if climb.rise > t.step_height:
				return "rise %.2f over a %.2f step" % [climb.rise, t.step_height]
		How.JUMP:
			var limit := climb_limit(t)
			if climb.rise > limit:
				return "rise %.2f over a %.2f climb limit" % [climb.rise, limit]
			var reach := jump_reach(t, climb.rise)
			if climb.gap > reach:
				return "gap %.2f over a %.2f reach at that rise" % [climb.gap, reach]
		How.WALK:
			if climb.slope > t.max_slope_angle:
				return "slope %.1f over %.1f" % [climb.slope, t.max_slope_angle]
			if climb.rise > t.step_height:
				return "lip %.2f over a %.2f step" % [climb.rise, t.step_height]
		How.THROW:
			if climb.rise > climb.lift * CLIMB_MARGIN:
				return "rise %.2f over %.2f of a %.2f throw" % [
					climb.rise, climb.lift * CLIMB_MARGIN, climb.lift
				]
	return ""
