extends Node

## The players choose the next bowl.
##
## [DotVoteDirector] over a [DotVoteListSource] of this server's bowls, and the only thing
## this file decides is WHEN: a ballot opens [member open_after_sec] into every bowl and is
## applied when the round ends, because the bowl is rebuilt only between rounds — the next
## round starts in whatever was chosen. The bowls are [code]BfhBowls[/code]: this game has
## no map files, its map is a radius, and a bowl is a name for one. Everything about the ballot itself (how many options, the
## counting method, the tie-break, rock the vote, nominations, cooldowns) is dot-vote's
## settings and none of it is restated here; [method _rules] only says which of them a
## one-bowl-per-round game wants by default.
##
## [b]`trigger` is MANUAL, not ROUND_END, and that is the point of this file.[/b] dot-vote's
## ROUND_END opens a ballot at a round's end and applies it at the NEXT round's end, which is
## right for a game that plays several rounds on a map and one round late here. Opening it
## during the round and applying it at the end (`apply: END_OF_ROUND`) puts the choice on
## the very next round.
##
## [b]Server side only.[/b] A client draws the ballot from the notice [member ballot_fn] sends
## (the client shell's [DotBallotPanel]), and never holds a director: a client that applied a
## result would be deciding what it plays.

const CHANNEL := "buses.vote"

## The key in the running game's descriptor metadata an operator's overrides are read from —
## [code]metadata: bowl_vote:[/code] in a delivered game's [code]game.yml[/code].
const METADATA_KEY := "bowl_vote"

## What the vote command is called: `!vote 2` in chat, `vote 2` in a console.
const COMMAND_NAMES := {"vote": "vote"}

## Seconds into a bowl before its ballot opens. 0 opens it the moment the bowl is built.
## Late enough that nobody is voting while the buses are coming, early enough that a short round still
## sees it close.
@export var open_after_sec: float = 20.0

## The file a server owner configures the vote in, keyed exactly as [DotVoteRules]. Layered:
## [code]_rules() < game.yml metadata bowl_vote: < this file < DOT_VOTE_* < --vote-*[/code].
## Empty skips the file. [code]{"enabled": false}[/code] turns the vote off and the rotation
## the server's own bowl stays.
@export var config_path: String = "user://cfg/buses_vote.json"

## [code]func() -> Array[/code] of [code][id, name][/code] pairs: every bowl a ballot may
## offer. The host's, because which bowls a server plays is the world's to say.
var bowls_fn: Callable = Callable()

## [code]func(id: StringName) -> DotResult[/code]: play this bowl next.
var apply_fn: Callable = Callable()

## [code]func() -> Array[/code] of voter ids (StringName): the people who may vote. Stand-ins
## are not voters — a ballot they could swing is not the players' choice.
var voters_fn: Callable = Callable()

## Says a line to everybody.
var announce_fn: Callable = Callable()

## Whether a voter is an admin, for dot-vote's admin bypasses.
var is_admin_fn: Callable = Callable()

## [code]func(state: Dictionary)[/code]: the ballot as a client draws it, sent when it changes.
var ballot_fn: Callable = Callable()

## [code]func(voter: StringName) -> Dictionary[/code]: a voter's name and avatar, for the ballot.
var people_fn: Callable = Callable()

var director: DotVoteDirector = null
var source: DotVoteListSource = null
var commands: DotVoteCommands = null
var feed: DotVoteBallotFeed = null

## Seconds since the bowl in play was built.
var _on_bowl_sec: float = 0.0

## Whether this bowl has had its ballot (or been refused one), so it opens once.
var _opened_this_bowl: bool = false


## Builds the director. Fails when the rules do not validate, never because there are too few
## bowls: a server narrowed to one bowl (`bowl_ids`) simply never opens a ballot.
func setup() -> DotResult:
	source = DotVoteListSource.new()
	source.label = "bowls"
	source.apply_fn = func(id: StringName) -> DotResult:
		return apply_fn.call(id) if apply_fn.is_valid() else DotResult.success(id)
	refresh_bowls()

	director = DotVoteDirector.new()
	director.name = "VoteDirector"
	director.rules = configured_rules()
	director.source = source
	director.auto_apply = true
	# The host calls begin() whenever a bowl is built, which a vote's change is one cause of
	# and the first round another; both firing would put one play in the
	# history twice. See DotVoteDirector.begin_on_apply.
	director.begin_on_apply = false
	# The server's tick drives it, not the frame clock.
	director.self_advance = false
	director.round_based = true

	director.player_count_fn = func() -> int:
		return _voters().size()
	director.voters_fn = _voters
	director.is_admin_fn = func(voter: StringName) -> bool:
		return is_admin_fn.is_valid() and bool(is_admin_fn.call(voter))
	director.announce_fn = func(line: String) -> void:
		if announce_fn.is_valid():
			announce_fn.call(line)

	add_child(director)

	# [b]Rock the vote opens the ballot here, because MANUAL never does.[/b] Under MANUAL the
	# director hands every opening to its host, a rocked vote included: the clock expires
	# with reason rtv, the director does nothing, and `!rtv` answered "Rocked. 1 of 1." and
	# nothing happened. Connected after the director's own handler (its _ready runs first),
	# so the director has finished with the expiry before this asks for a ballot.
	director.clock.expired.connect(func(reason: StringName) -> void:
		if reason != DotVoteClock.REASON_RTV or director.is_voting():
			return

		_opened_this_bowl = true
		var opened := director.start_vote(DotVoteClock.REASON_RTV)

		if not opened.ok:
			DotLog.debug(CHANNEL, "the rocked vote could not open", {"why": opened.error.message})
	)

	director.vote_closed.connect(func(result: DotVoteResult) -> void:
		DotLog.info(CHANNEL, "the bowl vote closed", {"winner": String(result.winner_id), "votes": result.votes_cast})
	)

	feed = DotVoteBallotFeed.of(director, func(state: Dictionary) -> void:
		if ballot_fn.is_valid():
			ballot_fn.call(state)
	)
	feed.title = "Vote for the next bowl"
	feed.command = COMMAND_NAMES["vote"]
	feed.people_fn = func(voter: StringName) -> Dictionary:
		return people_fn.call(voter) if people_fn.is_valid() else {}

	return DotResult.success(self)


## [method _rules] under the server owner's layers. A layer that does not validate is refused
## whole, with the reason logged, and the defaults stand.
func configured_rules() -> DotVoteRules:
	var rules := _rules()
	var loaded := rules.layer_over_defaults(
		config_path, DotVoteGameSource.running_game_metadata(METADATA_KEY)
	)
	DotLog.result(CHANNEL, "the bowl vote's rules", loaded)
	return rules


## What a one-bowl-per-round game wants from dot-vote by default. Every line is a default an
## operator overrides in [member config_path].
func _rules() -> DotVoteRules:
	var rules := DotVoteRules.new()
	# See the class note: opened here, applied at the round's end.
	rules.trigger = DotVoteRules.Trigger.MANUAL
	rules.apply = DotVoteRules.Apply.END_OF_ROUND
	# A rocked vote changes the NEXT bowl too. Immediately would pull the bowl from under a
	# round in progress: a wall moving through the people standing beside it.
	rules.rtv_apply = DotVoteRules.Apply.END_OF_ROUND
	# No time limit: a bowl lasts one round, and dot-vote's 45-minute default would, on a
	# bowl somebody kept voting for, expire and change it under a round in progress.
	rules.duration_sec = 0.0
	# There is no clock to extend, and "this bowl again" is a fair thing to want when a
	# server has two.
	rules.include_extend = false
	# Rock the vote from the first second. dot-vote's two minutes keep a long map from being
	# rocked the moment it loads; here a bowl lasts one round, barely longer than that, and its own ballot opens
	# at open_after_sec anyway, so the delay would make `!rtv` a command that never works.
	rules.rtv_delay_sec = 0.0
	rules.include_current = true
	# Plays, not minutes: two bowls with a cooldown of five would offer nothing at all.
	rules.cooldown = 0
	rules.max_options = 5
	rules.vote_duration_sec = 25.0
	rules.method = DotVoteRules.Method.PLURALITY
	rules.tie_break = DotVoteRules.TieBreak.RANDOM
	return rules


## Reads the bowl list again: on boot, and at every round's start, because an operator's
## `bowl_ids` or `arena_radius` changes what a server offers and nothing else would tell the
## ballot.
func refresh_bowls() -> void:
	if source == null:
		return

	source.entries.clear()

	if not bowls_fn.is_valid():
		return

	for pair: Variant in bowls_fn.call():
		var row: Array = pair
		var _added := source.add(DotVoteChoice.of(StringName(str(row[0])), str(row[1])))


## A round began in [param id]: the director starts over on it and the ballot timer restarts.
## Every round, whether or not the bowl changed, because every round is a play and owes a
## ballot. Not at the warmup: no round, no ballot (see [method advance]).
func note_bowl(id: StringName) -> void:
	if director == null:
		return

	refresh_bowls()

	source.current = id
	director.begin(id)
	_on_bowl_sec = 0.0
	_opened_this_bowl = false


## The server woke from hibernation: the bowl ballot is owed again, from the top.
##
## The director restarts itself ([member DotVoteRules.wake_restart]); this is the half that is
## this game's — the seconds into the bowl at which the ballot opens.
func note_woke() -> void:
	_on_bowl_sec = 0.0
	_opened_this_bowl = false


## A round ended: a decided bowl is applied now, so the next round starts on it.
func note_round_end() -> void:
	if director != null:
		var _over := director.note_round_end()


## One tick.
func advance(delta: float) -> void:
	if director == null:
		return

	director.advance(delta)

	# [b]Before the warmup return, not after it.[/b] A ballot can be open in the warmup: a
	# rocked vote opens one, and so does a ballot the server's game vote made wait. Polled
	# only once a round had begun, it was open, counted and never drawn, so the only sign
	# of it was a line in chat.
	if feed != null:
		feed.poll()

	# Before the first round there is nothing playing for a ballot to replace: the warmup.
	if director.current_id() == &"":
		return

	# The ballot's own timer waits with the director's clock while the server hibernates
	# (DotGameModule hands the director the server's hibernation). Counted on, it ran past
	# open_after_sec over an empty room, the ballot was refused for want of voters, and the
	# first player in never got one on this bowl.
	if director.hibernating:
		return

	_on_bowl_sec += delta

	if _opened_this_bowl or _on_bowl_sec < open_after_sec:
		return

	_opened_this_bowl = true

	# Nothing to choose between: one bowl, or one bowl and itself.
	if source.entries.size() < 2:
		return

	var opened := director.start_vote(DotVoteClock.REASON_MANUAL)

	if not opened.ok:
		DotLog.debug(CHANNEL, "no bowl vote this round", {"why": opened.error.message})


func forget_voter(voter: StringName) -> void:
	if director != null:
		director.forget_voter(voter)


func is_voting() -> bool:
	return director != null and director.is_voting()


## dot-vote's commands on [param host]: `vote`, `rtv`, `nominate` and the operator's. Voters
## are the bare session id, the same spelling [member voters_fn] lists — dot-vote's default is
## `u<userid>`, and two spellings of one voter is a player who rocks the vote twice.
func install_commands(host: Object) -> DotResult:
	if director == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote to command.")

	commands = DotVoteCommands.new()
	commands.director = director
	commands.names = COMMAND_NAMES
	commands.voter_fn = func(ctx: Object) -> StringName:
		var session: Variant = ctx.get("session")

		if session is Object and (session as Object).get("userid") != null:
			return StringName(str((session as Object).get("userid")))

		return &"console"

	var bound := commands.bind(host)

	if feed != null:
		feed.command = commands.command_name("vote")

	return bound


func _voters() -> Array:
	return voters_fn.call() if voters_fn.is_valid() else []


func describe() -> Dictionary:
	return {
		"bowls": source.entries.size() if source != null else 0,
		"open_after_sec": open_after_sec,
		"on_bowl_sec": snappedf(_on_bowl_sec, 0.1),
		"director": director.describe() if director != null else {},
	}


func describe_lines() -> PackedStringArray:
	return director.describe_lines() if director != null else PackedStringArray()
