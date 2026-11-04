extends "bfh_game_toys.gd"
## Which bowls this server plays: the maps.yml rotation mirror, the map menu's list and the Workshop's bowls.

const BfhBowls := preload("bfh_bowls.gd")
const BfhVote := preload("bfh_vote.gd")

## Which of [code]BfhBowls[/code] the bowl is. The server's configured radius is
## [constant BfhBowls.DEFAULT].
var bowl_id: StringName = BfhBowls.DEFAULT

## The server's maps.yml, or null when there is none (every bowl rotates, as it always did).
## dot-map's rotation file speaks DotMapDef; this game holds bowl records, so [member _defs]
## mirrors the ids and the file marks `in_rotation` on the mirror.
var rotation_file: DotMapRotationFile = null
var _defs: DotMapCatalogue = DotMapCatalogue.new()
var _rotation: DotMapRotation = DotMapRotation.of(_defs)

## Whether maps.yml names rotations, so that it decides which bowls rotate and in what order.
func has_rotation_file() -> bool:
	return rotation_file != null and rotation_file.has_rotations()

## Brings the mirror up to date with the bowls this server offers and lets the file mark who
## rotates. Without a file every bowl is in.
func apply_rotation() -> void:
	var offered: Array[StringName] = []

	for bowl in BfhBowls.allowed(config):
		offered.append(bowl["id"])

		if _defs.get_map(bowl["id"]) == null:
			var def := DotMapDef.new()
			def.id = bowl["id"]
			def.scene_path = "bfh:%s" % bowl["id"]
			def.display_name = str(bowl["name"])
			var _added := _defs.add(def)

	for def: DotMapDef in _defs.maps.duplicate():
		if not offered.has(def.id):
			var _gone := _defs.remove(def.id)

	if has_rotation_file():
		rotation_file.fallback_in = func(_def: DotMapDef) -> bool: return true
		var _applied := rotation_file.apply(_rotation)
		return

	_rotation.order = []

	for def: DotMapDef in _defs.maps:
		def.in_rotation = true

## Reads maps.yml (the `--config` directory first) and applies it. Called at boot and by
## `sv_map_rotation_file`. A file that is present and unreadable is an ERROR and changes nothing:
## rotating every bowl is a better failure than rotating none.
func load_rotation() -> DotResult:
	var stem := config.map_rotation_file
	var dir := DotMapRotationFile.config_dir_arg()
	var found := DotMapRotationFile.find(stem, dir)

	if found == "" and stem != "" and (dir != "" or stem != BfhConfig.new().map_rotation_file):
		# The default name being absent is an install with no maps.yml; a name or a directory
		# somebody chose that finds nothing is a typo they would otherwise never hear about.
		DotLog.warn(CHANNEL, "the map rotation file was not found; every bowl rotates", {
			"file": stem, "config_dir": dir,
		})

	var paths := PackedStringArray()

	if found != "":
		paths.append(found)

	var read := DotMapRotationFile.load_files(paths, "mg-buses-from-hell")

	if not read.ok:
		DotLog.error(CHANNEL, "the map rotation file could not be read; every bowl rotates", {
			"why": read.error.message,
		})
		rotation_file = null
		apply_rotation()
		return read

	rotation_file = read.value
	apply_rotation()

	if has_rotation_file():
		DotLog.info(CHANNEL, "the map rotation file", {
			"paths": ", ".join(rotation_file.sources), "active": rotation_file.active_name(),
		})

	return read

## `bfh_rotation <name>`: the live switch to another named rotation in the file.
func switch_rotation(rotation_name: String) -> DotResult:
	if not has_rotation_file():
		return DotResult.fail(DotError.CODE_STATE, "There is no maps.yml to switch rotations in.")

	apply_rotation()
	return rotation_file.switch(_rotation, rotation_name)

## Whether [param id] is in the active rotation. A bowl this server does not offer is not.
func in_rotation(id: StringName) -> bool:
	apply_rotation()
	var def := _defs.get_map(id)

	if def == null:
		return false

	return not has_rotation_file() or def.in_rotation

## What the ballot, a nomination and [method next_bowl] may offer: every offered bowl less the
## ones maps.yml leaves out, in the file's order. A bowl left out stays [i]playable[/i] (the map
## menu loads it). With no file, or a file that leaves nothing, every offered bowl.
func rotating_ids() -> Array[StringName]:
	apply_rotation()
	var every: Array[StringName] = []

	for bowl in BfhBowls.allowed(config):
		every.append(bowl["id"])

	if not has_rotation_file():
		return every

	var out: Array[StringName] = []

	for def: DotMapDef in _rotation.pool(0):
		if every.has(def.id):
			out.append(def.id)

	return out if not out.is_empty() else every

## The bowl after this one by the file's rotation (its mode, cooldown and written order, so a
## `cycle` walks in turn); the current one with no file. Never an out-of-rotation bowl. Does
## not change anything: [method _change_bowl] records the play.
func next_bowl() -> StringName:
	if not has_rotation_file():
		return bowl_id

	apply_rotation()

	if _rotation.seed_value == 0:
		_rotation.seed_value = maxi(1, config.arena_seed) if config.arena_seed != 0 else randi_range(1, 0x3fffffff)

	var chosen := _rotation.choose(0)

	if chosen != null and rotating_ids().has(chosen.id):
		return chosen.id

	return bowl_id

## maps.yml's `commands:` block (prefix and names), or empty with no file.
func rotation_commands() -> Dictionary:
	return rotation_file.commands() if rotation_file != null else {}

## Every bowl this server plays, as the map menu (M) lists them: `{id, name, detail, current}`, its
## size under the name. Solo the client's list, online the server's (the module hands it to dot-
## vote's map menu), so both say the same.
func bowl_rows(index: DotContentIndex = null) -> Array:
	var out: Array = []
	for bowl in BfhBowls.allowed(config):
		var rotates := in_rotation(bowl["id"])
		out.append({"id": String(bowl["id"]),
			"name": str(bowl["name"]) + ("" if rotates else " (not in rotation)"), "in_rotation": rotates,
			"detail": "%d m across" % int(round(float(bowl["radius"]) * 2.0)), "current": bowl["id"] == bowl_id})
	for bowl in workshop_bowls(index):
		out.append({"id": String(bowl["id"]), "name": str(bowl["name"]),
			"detail": "%d m across, Workshop" % int(round(float(bowl["radius"]) * 2.0)), "current": bowl["id"] == bowl_id})
	return out

## The bowls a subscribed pack adds, each `{id, name, radius}`. A pack's `map` entry of an accepted
## `map_kind` names, in `scene`, a bowl document: JSON `{"radius": metres}`, clamped to what the
## arena's gap rule has been built and checked for.
func workshop_bowls(index: DotContentIndex) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if index == null:
		return out
	for entry in index.entries(&"map"):
		if entry.id == "" or BfhBowls.by_id(config, StringName(entry.id)).size() > 0 \
				or not BfhVote.ACCEPTED_MAP_KINDS.has(str(entry.raw.get("map_kind", ""))):
			continue
		var path: String = entry.path("scene")
		if path == "" or not FileAccess.file_exists(path):
			continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (doc is Dictionary) or not (doc as Dictionary).get("radius") is float:
			continue
		var name: String = "%s [%s]" % [entry.name, entry.pack_title] if entry.pack_title != "" else entry.name
		out.append({"id": StringName(entry.id), "name": name,
			"radius": clampf(float((doc as Dictionary)["radius"]), BfhBowls.SMALL_RADIUS, BfhBowls.WORKSHOP_MAX_RADIUS)})
	return out
