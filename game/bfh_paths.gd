extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live.

## This game's content root: `res://` built in, the mount prefix delivered.
static func root() -> String:
	# The script is reached from an instance, not a self-preload: a script holding itself
	# is never freed at exit, and neither is anything it reaches.
	var here: Script = new().get_script()
	return here.resource_path.get_base_dir().get_base_dir()


## Moves one `res://` path onto [method root].
static func rebase(path: String) -> String:
	return rebase_onto(path, root())


## [method rebase], against a root given rather than discovered.
static func rebase_onto(path: String, here: String) -> String:
	if not path.begins_with("res://"):
		return path

	# [b]Idempotent, and the seventh form of this family's one delivery bug.[/b] The publisher REWRITES
	# every [code]res://[/code] string inside a [code].tscn[/code], a [code].tres[/code] and a
	# [code].import[/code] onto the mount prefix before it signs the pack — it has to, because a.
	if path.begins_with(here):
		return path

	return here.path_join(path.substr(6))
