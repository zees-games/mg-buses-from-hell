extends DotGameCheckSuite

const BfhVote := preload("../game/bfh_vote.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhBowls := preload("../game/bfh_bowls.gd")
const BfhArena := preload("../game/bfh_arena.gd")

## What a subscribed map pack does to this game's lists, against a fixture [DotContentIndex] and
## never the process's shared one: a solo map is listed (ballot and map menu) as Name [Pack], an
## online session lists none, a map kind the game does not accept is left out, and the game's own.

const SECTIONS := 4
const MAP := &"fixture_hill"
const DIR := "user://ws_test_bfh/"

var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("mg-buses-from-hell - Workshop maps")
	_test_accepts()
	await _test_solo()
	_test_online()
	_test_ids()
	print("")
	_check(_completed == _entered and _entered == SECTIONS,
		"every section ran to its last line (%d of %d, %d expected)" % [_completed, _entered, SECTIONS])
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	get_tree().quit(1 if _failed > 0 or _completed != SECTIONS else 0)


func _index(session: StringName) -> DotContentIndex:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(DIR + "hill.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"radius": 90.0}))
	file.close()
	var index := DotContentIndex.new()
	index.set_session(session)
	var added := index.add_pack({
		"content_id": "fixture/hills", "version": "1.0.0", "prefix": DIR,
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Fixture Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": String(MAP), "name": "Fixture Hill", "scene": "hill.json", "map_kind": "arena"},
			{"kind": "map", "id": "fixture_run", "name": "Fixture Run", "scene": "hill.json", "map_kind": "surf"},
			{"kind": "map", "id": "bfh_bowl", "name": "Not The Bowl", "scene": "hill.json", "map_kind": "arena"},
			{"kind": "map", "id": "fixture_gone", "name": "Fixture Gone", "scene": "gone.json", "map_kind": "arena"},
		]},
	})
	_check(added.ok, "the fixture pack registers for %s" % session)
	return index


func _vote(index: DotContentIndex) -> BfhVote:
	var vote := BfhVote.new()
	vote.content_index = index
	vote.bowls_fn = func() -> Array: return [[&"bfh_bowl", "The Bowl"], [&"bfh_small_bowl", "The Small Bowl"]]
	vote.apply_fn = func(id: StringName) -> DotResult: return DotResult.success(id)
	add_child(vote)
	var built := vote.setup()
	_check(built.ok, "the vote builds", str(built.message) if not built.ok else "")
	return vote


func _labels(vote: BfhVote) -> PackedStringArray:
	var out := PackedStringArray()
	vote.source.before_ballot()
	for choice in vote.source.choices():
		out.append(choice.label())
	return out


func _names(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		out.append(str(row["name"]))
	return out


func _test_accepts() -> void:
	_entered += 1
	print("")
	print("what the game accepts")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://provides.json"))
	var accepts: Dictionary = (parsed as Dictionary).get("accepts", {})
	_check(accepts.get("kinds") == ["map"], "provides.json accepts maps only", str(accepts))
	_check(accepts.get("map_kinds") == Array(BfhVote.ACCEPTED_MAP_KINDS),
		"and the vote's list is the same as its map_kinds", str(accepts))
	_completed += 1


func _test_solo() -> void:
	_entered += 1
	print("")
	print("solo")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var vote := _vote(index)
	var labels := _labels(vote)
	_check(labels.has("Fixture Hill [Fixture Pack]"), "the vote lists the accepted map as Name [Pack]", str(labels))
	_check(not labels.has("Fixture Run [Fixture Pack]"), "and not the kind it does not accept")
	_check(labels.has("The Bowl") and labels.has("The Small Bowl"), "the game's own bowls stay", str(labels))
	_check(not labels.has("Not The Bowl [Fixture Pack]") and not labels.has("Not The Bowl"),
		"a pack map claiming a bowl's id does not replace it")
	var game := BfhGame.new()
	game.workshop_index = index
	var rows := game.bowl_rows(index)
	_check(not _names(rows).has("Fixture Gone [Fixture Pack]"), "a pack map with no document is not listed")
	var bowls := game.workshop_bowls(index)
	_check(bowls.size() == 1 and bowls[0]["id"] == MAP, "one playable Workshop bowl", str(bowls))
	_check(is_equal_approx(float(bowls[0]["radius"]), BfhBowls.WORKSHOP_MAX_RADIUS), "its radius is clamped to the largest the gap rule is checked for")
	game.authoritative = true
	game.arena = BfhArena.new()
	game.arena.build(game.config.arena_radius if game.config != null else 46.0)
	var chosen := game.change_bowl_now(MAP)
	_check(chosen.ok and game.bowl_id == MAP, "choosing it builds that bowl", str(chosen.message) if not chosen.ok else "")
	_check(is_equal_approx(game.arena.radius, BfhBowls.WORKSHOP_MAX_RADIUS), "at its radius")
	_check(_names(rows).has("Fixture Hill [Fixture Pack]"), "the solo map menu lists it as Name [Pack]", str(_names(rows)))
	_check(not _names(rows).has("Fixture Run [Fixture Pack]"), "and not the other kind")
	_check(game.bowl_rows().size() == rows.size() - 1, "without an index the menu is the game's own")
	vote.queue_free()
	# The arena was hand-made outside the tree, so game.free() does not reach its bodies.
	if is_instance_valid(game.arena) and game.arena.get_parent() == null:
		game.arena.free()
	game.free()
	_completed += 1


func _test_online() -> void:
	_entered += 1
	print("")
	print("online")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var vote := _vote(index)
	_check(_labels(vote).has("Fixture Hill [Fixture Pack]"), "listed while the index is solo")
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(not _labels(vote).has("Fixture Hill [Fixture Pack]"), "gone from the ballot when the session turns online")
	var game := BfhGame.new()
	_check(not _names(game.bowl_rows(index)).has("Fixture Hill [Fixture Pack]"), "and from the map menu")
	vote.queue_free()
	game.free()
	_completed += 1


func _test_ids() -> void:
	_entered += 1
	print("")
	print("the shared index")
	var vote := BfhVote.new()
	vote.bowls_fn = func() -> Array: return [[&"bfh_bowl", "The Bowl"]]
	add_child(vote)
	var built := vote.setup()
	_check(built.ok, "a vote with no fixture follows the process's shared index")
	_check(vote.source.content_index == DotContentIndex.shared(), "it is the registered one")
	vote.queue_free()
	_completed += 1
