extends Node
## The client's round-end presentation: the killcam, then the winners' reveal, then the board.
## Split from [code]bfh_client.gd[/code] (which extends this) so that file stays a size the gate allows.

const BfhClientChat := preload("bfh_client_chat.gd")
const BfhGame := preload("bfh_game.gd")
const BfhKillcam := preload("bfh_killcam.gd")
const BfhHud := preload("bfh_hud.gd")
const BfhScoreboard := preload("bfh_scoreboard.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhSettings := preload("bfh_settings.gd")

var game: BfhGame = null
var hud: BfhHud = null
## The score and the sides: held on Tab, and up on its own between rounds. See [BfhScoreboard].
var scoreboard: BfhScoreboard = null
## The chat box and the microphone. Built in both halves: offline it echoes what you type.
var chat: BfhClientChat = null
## The player's own settings and the screen that changes them. See [BfhSettings].
var settings: BfhSettings = null
## Records every frame and replays the round's last moment, then the reveal ([BfhKillcam]).
var killcam: BfhKillcam = null
## Where the dead lie: dot-player-char's ragdolls under the game's (the server's) rules.
var ragdolls: DotPlayerRagdolls = null
var link: Node = null
var winner_reveal: DotWinnerReveal = null


## The server's `mp_killcam_time`; -1 until it has said, so the config's number stands.
var _killcam_sec: float = -1.0
var _round_ending: bool = false
var _round_end_number: int = 0
var _round_end_winner: int = 0
var _hud_was_visible: bool = true


func _build_killcam() -> void:
	killcam = BfhKillcam.new()
	killcam.name = "RoundKillcam"
	killcam.players_fn = func() -> Array: return game.players.values() if game != null else []
	killcam.player_for_fn = func(key: StringName) -> Variant: return game.players.get(key) if game != null else null
	killcam.driver_fn = func(p: BfhPlayer) -> bool: return game.team_of(p.player_id) == BfhGame.TEAM_DRIVERS
	killcam.seconds_fn = func() -> float: return _killcam_sec if _killcam_sec >= 0.0 else game.config.killcam_seconds
	killcam.hide_while_playing = [hud, chat.window if chat != null else null, ragdolls]
	killcam.over.connect(func(_skipped: bool) -> void: _reveal_round())
	add_child(killcam)
	winner_reveal = DotWinnerReveal.new()
	winner_reveal.name = "WinnerReveal"
	winner_reveal.skip_actions = BfhKillcam.SKIP_ACTIONS
	winner_reveal.hold_seconds = 4.0
	winner_reveal.finished.connect(_on_reveal_finished)
	add_child(winner_reveal)
	if scoreboard != null:
		scoreboard.hold_after_round = true
	game.player_died.connect(_note_death)
	game.round_over.connect(_begin_round_end)
	game.round_began.connect(func(_number: int) -> void: _end_round_presentation())
	if link != null and link.has_method(&"replicated_cvar"):
		_on_killcam_cvar("mp_killcam_time", String(link.call(&"replicated_cvar", "mp_killcam_time", "")))
		if link.has_signal(&"replicated_cvar_changed"):
			link.connect(&"replicated_cvar_changed", _on_killcam_cvar)


## `mp_killcam_time`, from the server's replicated cvar.
func _on_killcam_cvar(cvar_name: String, value: String) -> void:
	if cvar_name == "mp_killcam_time" and value.strip_edges().is_valid_float():
		_killcam_sec = clampf(value.to_float(), 0.0, 30.0)


## A death is the round's last moment if nothing follows it. A bus puts the runner in its
## driver's eyes; anything else (a blast) in the runner's own.
func _note_death(victim: StringName, by: StringName) -> void:
	if killcam == null:
		return
	var who: BfhPlayer = game.players.get(victim)
	var name_of := who.display_name if who != null else String(victim)
	if by != &"" and by != victim and game.players.has(by):
		killcam.note_moment(by, "ran over", name_of)
	else:
		killcam.note_moment(victim, "caught in a blast")


func _begin_round_end(number: int, winner: int) -> void:
	_round_end_number = number
	_round_end_winner = winner
	_round_ending = true
	# Only the buses end a round on a death; a clock that runs out has nothing worth replaying.
	if winner == BfhGame.TEAM_DRIVERS:
		var _playing := killcam.round_ended()
	else:
		_reveal_round()


## The winning side's best three on a podium, after the killcam and before the board.
func _reveal_round() -> void:
	if not _round_ending:
		return
	var winner := _round_end_winner
	var entries: Array = []
	if winner == BfhGame.TEAM_DRIVERS or winner == BfhGame.TEAM_RUNNERS:
		for row: Dictionary in BfhScoreboard.rows_for(game, winner).slice(0, 3):
			entries.append({"name": row[&"name"], "score": row[&"status"],
				"colour": BfhScoreboard.side_colour(game, winner)})
	if entries.is_empty():
		_open_round_board()
		return
	winner_reveal.reduced_motion = settings != null and settings.settings != null and settings.settings.get_bool(&"reduce_motion", false)
	var shown := winner_reveal.present(entries, {"title": "ROUND %d" % _round_end_number,
		"subtitle": "The buses win" if winner == BfhGame.TEAM_DRIVERS else "The runners win", "hint": "Jump to skip"})
	if not shown.ok:
		_open_round_board()
		return
	if hud != null:
		_hud_was_visible = hud.visible
		hud.visible = false


func _on_reveal_finished(_skipped: bool) -> void:
	if hud != null and not killcam.is_playing():
		hud.visible = _hud_was_visible
	if _round_ending:
		_open_round_board()


func _open_round_board() -> void:
	if scoreboard != null:
		scoreboard.release_after_round()


## A new round: whatever is still up goes, so it never covers the start.
func _end_round_presentation() -> void:
	_round_ending = false
	if killcam != null:
		killcam.skip()
	if winner_reveal != null:
		winner_reveal.skip()
