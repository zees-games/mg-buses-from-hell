extends RefCounted

const BfhStats := preload("bfh_stats.gd")

## What a player can earn here, as a document rather than as code.

# No `CHANNEL`: a static document, validated by dot-achievements, which is where a
# refusal is reported.

const CAT_DRIVING := &"driving"
const CAT_RUNNING := &"running"
const CAT_THE_BOWL := &"the_bowl"


static func catalogue() -> DotAchievementCatalogue:
	var out: Array[DotAchievement] = []

	out.append(_sum(
		&"bfh.road_rage", "Road Rage", BfhStats.RUNNERS_FLATTENED, 1,
		"Run somebody down.", CAT_DRIVING, 5, &"bfh.flattening", 1
	))
	out.append(_sum(
		&"bfh.rush_hour", "Rush Hour", BfhStats.RUNNERS_FLATTENED, 25,
		"Run twenty-five people down.", CAT_DRIVING, 20, &"bfh.flattening", 2
	))

	out.append(_sum(
		&"bfh.still_standing", "Still Standing", BfhStats.ROUNDS_SURVIVED, 1,
		"Be on your feet when the clock runs out.", CAT_RUNNING, 10, &"bfh.surviving", 1
	))
	out.append(_sum(
		&"bfh.unflattenable", "Unflattenable", BfhStats.ROUNDS_SURVIVED, 10,
		"Outlast the buses ten times.", CAT_RUNNING, 30, &"bfh.surviving", 2
	))

	# Ten minutes on foot and alive, summed across rounds: a runner who survives nothing
	# but always lasts a while still gets there, which is the point of counting seconds
	# as well as rounds.
	out.append(_sum(
		&"bfh.marathon", "Marathon", BfhStats.SECONDS_SURVIVED, 600,
		"Spend ten minutes on your feet with a bus after you.", CAT_RUNNING, 20, &"", 0
	))

	out.append(_sum(
		&"bfh.demolition", "Demolition", BfhStats.CRATES_BROKEN, 50,
		"Break fifty crates.", CAT_THE_BOWL, 15, &"", 0
	))

	# Secret rather than hidden: the name is on the list from the start, so a runner knows
	# there is something to find, and what it is — a crate you moved, driven into by a bus
	# — is the lesson the game is trying to teach, which is better learnt than read.
	var traffic := _sum(
		&"bfh.traffic_control", "Traffic Control", BfhStats.CRATES_INTO_PATH, 1,
		"Put a crate in front of a bus.", CAT_THE_BOWL, 10, &"bfh.traffic", 1
	)
	traffic.secret = true
	out.append(traffic)
	out.append(_sum(
		&"bfh.roadworks", "Roadworks", BfhStats.CRATES_INTO_PATH, 10,
		"Put ten crates in front of a bus.", CAT_THE_BOWL, 25, &"bfh.traffic", 2
	))

	var catalogue := DotAchievementCatalogue.new()
	catalogue.achievements = out
	return catalogue


static func _sum(
	id: StringName,
	name: String,
	stat: StringName,
	target: float,
	description: String,
	category: StringName,
	points: int,
	series: StringName,
	tier: int,
) -> DotAchievement:
	var rules: Array[DotAchievementRule] = [
		DotAchievementRule.make(
			stat, target, DotAchievementRule.Op.AT_LEAST, DotAchievementRule.Merge.SUM
		)
	]
	var out := DotAchievement.make(id, name, rules)
	out.description = description
	out.category = category
	out.points = points
	out.series = series
	out.tier = tier
	return out
