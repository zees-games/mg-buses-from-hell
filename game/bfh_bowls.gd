extends RefCounted

const BfhDistricts := preload("bfh_districts.gd")

## The bowls a round can be played in: this game's maps, for the players' vote.

const DEFAULT := &"bfh_bowl"

## The small bowl's radius: the tank farm's minimum, so both clusters stand and the
## scaffold and colonnade (45 m minimum) are left out, which the arena logs.
const SMALL_RADIUS := 40.0

## The big bowl's radius.
const BIG_RADIUS := 54.0

## The largest radius a Workshop bowl document may ask for.
const WORKSHOP_MAX_RADIUS := 70.0


## Every bowl, in the order a ballot lists them when nothing else orders it: each a
## [code]{id, name, radius, ambient}[/code] (`ambient` is the bed's `{level, lively}`) and, for a district, [code]district[/code] (what the
## arena builds on that floor).
static func all(config: Object) -> Array[Dictionary]:
	var shipped := float(config.get("arena_radius")) if config != null else 46.0
	var out: Array[Dictionary] = [
		{"id": DEFAULT, "name": "The Bowl", "radius": shipped, "ambient": {"level": 1.0, "lively": true}},
		{"id": &"bfh_small_bowl", "name": "The Small Bowl", "radius": SMALL_RADIUS, "ambient": {"level": 0.8, "lively": false}},
		{"id": &"bfh_big_bowl", "name": "The Big Bowl", "radius": BIG_RADIUS, "ambient": {"level": 1.2, "lively": true}},
	]

	# The districts: each a town on the same floor, with its own radius (see BfhDistricts).
	# `district` is what the arena builds; the bowls' is empty.
	for town in BfhDistricts.LIST:
		out.append({"id": town["id"], "name": town["name"], "radius": float(town["radius"]),
			"district": String(town["id"]), "ambient": {"level": 1.0, "lively": true}})
	return out


## The bowls this server offers: [method all] narrowed by `bowl_ids`. A list that names
## nothing this game has offers them all, as an unknown layout name builds the default.
static func allowed(config: Object) -> Array[Dictionary]:
	var every := all(config)
	var wanted: PackedStringArray = config.get("bowl_ids") if config != null else PackedStringArray()

	if wanted.is_empty():
		return every

	var out: Array[Dictionary] = []

	for bowl in every:
		if wanted.has(String(bowl["id"])):
			out.append(bowl)

	return out if not out.is_empty() else every


## One bowl by id, or an empty dictionary.
static func by_id(config: Object, id: StringName) -> Dictionary:
	for bowl in all(config):
		if bowl["id"] == id:
			return bowl

	return {}
