extends DotVoteRoundGame

## The players choose the next bowl: dot-vote's [DotVoteRoundGame] with Buses From Hell's names. Every round is a play and owes a
## ballot, opened [member open_after_sec] into it and applied at its end; the rest is dot-vote's settings
## (`user://cfg/buses_vote.json`, `game.yml` metadata `bowl_vote:`).

const CHANNEL := "buses.vote"

## The key in the running game's descriptor metadata an operator's overrides are read from, [code]metadata: bowl_vote:[/code].
const METADATA_KEY := "bowl_vote"

## The `map_kind`s of subscribed maps the ballot lists: `accepts.map_kinds` in `provides.json`,
## written out here because that file is not mounted with the game (`headless_workshop` holds
## the two equal).
const ACCEPTED_MAP_KINDS := ["arena"]

## What the vote command is called: `!vote 2` in chat, `vote 2` in a console.
const COMMAND_NAMES := {"vote": "vote"}


func _init() -> void:
	channel = CHANNEL
	metadata_key = METADATA_KEY
	command_names = COMMAND_NAMES
	noun = "bowl"
	config_path = "user://cfg/buses_vote.json"


func _default_kinds() -> PackedStringArray:
	return PackedStringArray(ACCEPTED_MAP_KINDS)


## A bowl is a radius built in code, so a subscribed pack's scene map has nothing to build here: it is listed, and refused when it wins
## (docs/not-yet.md).
func _apply(id: StringName) -> DotResult:
	if not _own_ids().has(id):
		return DotResult.fail(DotError.CODE_STATE, "'%s' is a Workshop map this game cannot play yet." % id)

	return super._apply(id)


## Before the first round there is nothing playing for a ballot to replace: the warmup.
func _ballot_may_open() -> bool:
	return director.current_id() != &""


## A round began in [param id]: the list is read again first, because an operator's `bowl_ids` or `arena_radius` changes what a
## server offers and nothing else would tell the ballot. Every round, whether or not the bowl changed.
func note_map(id: StringName) -> void:
	if director != null:
		refresh_maps()

	super.note_map(id)


## The ids of this game's own bowls.
func _own_ids() -> Array:
	var out: Array = []
	if maps_fn.is_valid():
		for pair: Variant in maps_fn.call():
			out.append(StringName(str((pair as Array)[0])))
	return out
