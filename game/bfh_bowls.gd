extends RefCounted

const BfhDistricts := preload("bfh_districts.gd")

## The bowls a round can be played in: this game's maps, for the players' vote.
##
## [b]A bowl is a radius, not a file.[/b] The map here is [method BfhArena.build] run on both
## ends from one number (and the hook and the courtyard's west lane, which stay the
## operator's), so a bowl is a name and a radius. Every feature is placed as a fraction of
## the radius and spaced for a bus, so a different radius is a different map with the same
## rules: `headless_run` builds every bowl here and holds each to the gap rule, the same
## way it holds the minimum radii.
##
## [b]`bfh_bowl` is the operator's own[/b]: whatever `arena_radius` says (46 m shipped). The
## other two are the sizes the arena's own minimum radii already describe from either
## side: a small bowl below the scaffold's and the colonnade's minimum, where only the
## stacks and the tank farm stand and the bowl is open floor between them, and a big one
## where every feature is further apart and a bus has room to build speed.
##
## No `class_name`: this game is delivered as a pack (see docs/delivery.md).

const DEFAULT := &"bfh_bowl"

## The small bowl's radius: the tank farm's minimum, so both clusters stand and the
## scaffold and colonnade (45 m minimum) are left out, which the arena logs.
const SMALL_RADIUS := 40.0

## The big bowl's radius.
const BIG_RADIUS := 54.0

## The largest radius a Workshop bowl document may ask for.
const WORKSHOP_MAX_RADIUS := 70.0


## Every bowl, in the order a ballot lists them when nothing else orders it: each a
## [code]{id, name, radius}[/code] and, for a district, [code]district[/code] (what the
## arena builds on that floor).
static func all(config: Object) -> Array[Dictionary]:
	var shipped := float(config.get("arena_radius")) if config != null else 46.0
	var out: Array[Dictionary] = [
		{"id": DEFAULT, "name": "The Bowl", "radius": shipped},
		{"id": &"bfh_small_bowl", "name": "The Small Bowl", "radius": SMALL_RADIUS},
		{"id": &"bfh_big_bowl", "name": "The Big Bowl", "radius": BIG_RADIUS},
	]

	# The districts: each a town on the same floor, with its own radius (see BfhDistricts).
	# `district` is what the arena builds; the bowls' is empty.
	for town in BfhDistricts.LIST:
		out.append({"id": town["id"], "name": town["name"], "radius": float(town["radius"]),
			"district": String(town["id"])})
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
