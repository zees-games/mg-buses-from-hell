extends RefCounted

## Every per-player number this game counts, declared once.

# No `CHANNEL`: a schema of ids. The tracker that records against it is dot-stats', and
# logs there; `BfhProgress` logs what it decides.

## A runner a bus killed, credited to its driver.
const RUNNERS_FLATTENED := &"bfh.runners_flattened"

## Rounds a runner was still standing at the end of.
const ROUNDS_SURVIVED := &"bfh.rounds_survived"

## Crates a player broke, by any means they have: a hammer on foot, a bus at the wheel.
const CRATES_BROKEN := &"bfh.crates_broken"

## Crates a runner's hammer moved that a bus then drove into.
const CRATES_INTO_PATH := &"bfh.crates_into_path"

## Seconds a runner spent standing, summed: from the top of a round, or from joining it,
## to the end of it or to being put down.
const SECONDS_SURVIVED := &"bfh.seconds_survived"


## Every id above, in declaration order. Written out, because a constant is not
## enumerable in GDScript.
static func ids() -> Array[StringName]:
	return [
		RUNNERS_FLATTENED, ROUNDS_SURVIVED, CRATES_BROKEN, CRATES_INTO_PATH, SECONDS_SURVIVED,
	]


## The schema a [DotStatsTracker] is given.
static func schema() -> DotStatsSchema:
	var schema := DotStatsSchema.new()

	_counter(schema, RUNNERS_FLATTENED, "Runners flattened", "runners")
	_counter(schema, ROUNDS_SURVIVED, "Rounds survived", "rounds")
	_counter(schema, CRATES_BROKEN, "Crates broken", "crates")
	_counter(schema, CRATES_INTO_PATH, "Crates put in a bus's path", "crates")
	_counter(schema, SECONDS_SURVIVED, "Time survived", "s")

	return schema


static func _counter(schema: DotStatsSchema, id: StringName, display: String, unit: String) -> void:
	var def := schema.define(id, DotStatsDef.Kind.COUNTER, display)
	def.unit = unit
	def.decimals = 0
	def.publish = true
