extends Node

const BfhAudio := preload("bfh_audio.gd")
const BfhBindings := preload("bfh_bindings.gd")
const BfhClientChat := preload("bfh_client_chat.gd")
const BfhFx := preload("bfh_fx.gd")
const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhNetCommand := preload("net/bfh_net_command.gd")

const BfhConfig := preload("bfh_config.gd")
const BfhGame := preload("bfh_game.gd")
const BfhKillcam := preload("bfh_killcam.gd")
const BfhHud := preload("bfh_hud.gd")
const BfhMapConfig := preload("bfh_map_config.gd")
const BfhScoreboard := preload("bfh_scoreboard.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhSettings := preload("bfh_settings.gd")
const BfhSpectate := preload("bfh_spectate.gd")

## One local player, a camera and a HUD over a [BfhGame] — offline, or against a server.
##
## [b]One client for both, and the offline half is not a demo mode.[/b] It is the same
## world class with `authoritative` true and nothing else different: the same bowl, the
## same bot bus, the same rules. What changes is where the answers come from, and the
## whole of that difference is [BfhNetBridge]. A separate "single player" build would be a
## second game to keep in step, and the family has watched two copies of one thing drift
## more than once.
##
## [b]Which half runs is decided by whether there is a link in the registry.[/b] A
## dot-server client publishes a [DotClientLink] under `dot_client_link` before the game
## scene loads; no link means nobody connected us to anything, and the honest answer to
## that is a playable bowl rather than an error. `--offline` forces it.

const CHANNEL := "bfh.client"

@export var config_file: String = "user://cfg/buses-from-hell.json"

## Play alone even when a link is available. `--offline`.
@export var force_offline: bool = false

## How many bot drivers the offline bowl gets. One bus is a game; two is a demonstration.
@export_range(0, 8, 1) var offline_bots: int = 1

var game: BfhGame = null
var player: BfhPlayer = null
var camera: Camera3D = null
var hud: BfhHud = null

## Keeps the screen covered, and the local body and the input still, until the bowl, the
## player and the camera are all in. See [member DotGameClient.gate].
var gate: DotLoadGate = null

## dot-game's client platform: the cover, settings and menu, console, Tab, M, the pointer and
## the input block. See [DotGameClient].
var platform: DotGameClient = null

## The score and the sides: held on Tab, and up on its own between rounds. See [BfhScoreboard].
var scoreboard: BfhScoreboard = null

## The chat box and the microphone. Built in both halves: offline it echoes what you type.
var chat: BfhClientChat = null

## What this client hears. See [BfhAudio]. Null only if dot-audio refused its catalogue.
var audio: BfhAudio = null

## What this client draws that nothing simulates: a barrel going off. See [BfhFx]. Null
## only if dot-fx refused its catalogue.
var fx: BfhFx = null

## The player's own settings and the screen that changes them. See [BfhSettings].
var settings: BfhSettings = null

## Records every frame and replays the round's last moment, then the reveal ([BfhKillcam]).
var killcam: BfhKillcam = null
var winner_reveal: DotWinnerReveal = null

## The player's console, the platform's.
var console: DotConsoleController = null

## Whether the camera was last put on somebody else's eyes. See [method _process].
var _spectating: bool = false

## Third person: the camera swept back from the eye by dot-core's probe, the own runner
## drawn. Presentation only; the server's `mp_forceview` decides whether the key may.
var third_person: bool = false
var _probe: DotCameraProbe = null
var _fade: DotCameraFade = null

## Behind the eye, in the view's axes (right, up, back); further back from over a bus.
const THIRD_PERSON_OFFSET := Vector3(0.45, 0.35, 2.8)
const THIRD_PERSON_BUS_OFFSET := Vector3(0.0, 0.8, 8.0)
## Metres over a seated driver's eye the sweep starts from: above the bus's roof, so the bus
## they are driving is not what stops it.
const BUS_PIVOT_RISE := 2.6

var net: DotNetManager = null
var bridge: BfhNetBridge = null
var link: Node = null

var _offline: bool = true
var _sampler: DotFpsSampler = null

## Which session this client is, once the server has said. -1 until then, so nothing
## matches before it does.
var _watch_id: int = -1


func _ready() -> void:
	# First, before anything can be drawn: the bowl, the player and the camera arrive after
	# this node is in the tree. The platform puts the loading cover up, held until the player
	# exists and the camera is current, and finds the link.
	platform = DotGameClient.new()
	platform.name = "Platform"
	platform.force_offline = force_offline
	platform.spawned_fn = func() -> bool: return player != null
	platform.scoreboard_action = BfhBindings.SCOREBOARD
	add_child(platform)
	gate = platform.gate
	gate.hold(&"map", "Loading the bowl")

	var config := BfhConfig.new()

	# [b]`load_layered` on the CLIENT too, and another game in this family records what
	# happens without it.[/b] The family's `defaults < JSON < env < argv` chain is a
	# convention, and a client that quietly skipped it was one where every command-line
	# flag worked against a dedicated server and did nothing at all offline.
	var loaded := config.load_layered(config_file)

	if not loaded.ok:
		DotLog.warn(CHANNEL, "falling back to defaults", {"why": loaded.error.message})

	link = platform.link as Node
	_offline = platform.offline

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = _offline
	# A connected client's world is not what a module looks up, and registering it would
	# mean a client and a server sharing a process fight over the name — which is what
	# every section of this game's own suite does.
	game.register_service = _offline
	game.tick_rate = int(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)
	)
	# Before the world is added: a world that ticks itself must not run in front of a picture.
	game.hold_clock = _covered
	add_child(game)
	_hold_for_bowls()
	_build_ragdolls()

	# The sampler lives HERE and not on the player, because on a connected client the
	# local player does not exist yet: they arrive in a JOIN, several frames after the
	# keyboard does.
	_sampler = DotFpsSampler.new(BfhPlayer.tunables_for(config))
	DotFpsSampler.register_default_actions(_sampler)

	_build_hud()
	_build_chat()
	_build_audio()
	_build_fx()
	_build_settings()
	_build_scoreboard()
	_build_killcam()

	if _offline:
		_start_offline()
	else:
		# [b]Here, in `_ready`, which runs INSIDE `DotClientLink._load_scene`.[/b] The link
		# adds this scene and tells the server it has loaded on the next line, so the
		# netcode is up before the server has been told there is anybody to send to —
		# which is the order that leaves nothing to be missed. Measured against a real
		# server in a second process: the join completes and the first snapshot arrives
		# with the bowl already replicated.
		DotLog.result(CHANNEL, "the netcode", _build_netcode())


## The load gate is [member DotGameClient.gate]: covered, and the local body and the input
## still, until the bowl stands, the local player exists and its camera is current.
##
## [b]Covered also means the round does not run.[/b] Offline the world ticks itself, so the bot
## bus, the round clock and the barrels would all act on the runner in front of a picture;
## [member BfhGame.hold_clock] steps only the bodies then, which settle onto the sand under the
## cover with their input off. Connected, the server owns the round; what is left to hold is
## this end's sampling and keys, which wait on [method _covered]. The vendored art is loaded
## exactly as before: the gate only waits for it.


## The bowl is rebuilt (a vote's bowl, a server's radius in the HELLO): covered from the build
## until the end of that frame, by which time the round has laid its props on it. The first
## hold (from [method _build_gate]) is released when the first layout is in.
func _hold_for_bowls() -> void:
	platform.map_config_keys = BfhMapConfig.client_keys()
	platform.map_config_game = BfhMapConfig.GAME_ID
	platform.map_config_get_fn = func(key: String) -> Variant: return BfhMapConfig.client_get(game, key)
	platform.map_config_set_fn = func(key: String, value: Variant) -> bool: return BfhMapConfig.client_set(game, key, value)
	game.arena.built.connect(func() -> void:
		if gate == null:
			return
		gate.hold(&"map", "Loading the bowl")
		gate.release.call_deferred(&"map")
		platform.map_changed(String(game.bowl_id)))


## True while the load gate covers the screen: no input, no prediction sampling, no round clock.
func _covered() -> bool:
	return gate != null and not gate.is_open()


# --- Dead bodies -----------------------------------------------------------

## Where the dead lie: dot-player-char's ragdolls under the game's (the server's) rules.
var ragdolls: DotPlayerRagdolls = null


## [b]From the world's `player_died`, in both halves[/b]: offline the world is the authority and
## says so itself; connected, the bridge re-emits it from DEATH after putting the server's fall
## on the player.
func _build_ragdolls() -> void:
	ragdolls = DotPlayerRagdolls.new()
	ragdolls.name = "Ragdolls"
	ragdolls.rules = game.ragdoll_rules
	ragdolls.sound_fn = _ragdoll_sound
	add_child(ragdolls)
	game.player_died.connect(_on_player_down)
	game.round_began.connect(_on_round_for_bodies)


func _on_round_for_bodies(_number: int) -> void:
	ragdolls.clear()


func _on_player_down(id: StringName, _by: StringName) -> void:
	_fall(game.players.get(id))


func _ragdoll_sound(id: StringName, at: Vector3, volume: float) -> void:
	if audio != null and audio.audio != null:
		var _played := audio.audio.play_at(id, at, clampf(volume, 0.3, 1.0))


## [param who]'s body falls the way the server picked ([member BfhPlayer.death]), copied from the
## figure this client draws; the figure stays hidden while they are dead
## ([method BfhPlayer.present_body]). Nobody's figure, nothing: a player this client never drew.
func _fall(who: BfhPlayer) -> void:
	if who == null or ragdolls == null or who.figure == null or not who.figure.is_inside_tree():
		return
	var velocity := who.controller.state.velocity if who.controller != null else Vector3.ZERO
	var _body := ragdolls.spawn(who.figure, who.death if who.death != null else DotPlayerDeath.new(), velocity)


# --- Offline ---------------------------------------------------------------

func _start_offline() -> void:
	# A driver and a runner, because a round needs both sides and there is one person
	# here. What the bot is for is having a bus on the floor to run away from, which is
	# the thing worth looking at.
	# Named from dot-bot's pool, as a server's are.
	var roster := DotBotRoster.new()
	var taken: Array = ["You"]
	for i in range(offline_bots):
		var bot_name := roster.next_name(taken)
		taken.append(bot_name)
		var _bot := game.add_player(
			StringName("bot%d" % i), bot_name, BfhGame.TEAM_DRIVERS,
			false, true
		)

	# How well they drive: `bot_difficulty` and every `bot_*` at the console, or
	# `-- --bot_difficulty <preset>` at launch; the settings a server binds as cvars.
	var skill := DotBotSettings.of(game)
	var args := OS.get_cmdline_user_args()
	var at := args.find("--bot_difficulty")
	if at >= 0 and at + 1 < args.size():
		DotLog.result(CHANNEL, "bot difficulty from the command line", skill.set_difficulty(args[at + 1]))
	if console != null:
		var local := DotConsoleLocal.new()
		console.add_source(local)
		var _bound := skill.bind_console(local)

	_adopt(game.add_player(&"local", "You", BfhGame.TEAM_RUNNERS, true))
	game.start()
	gate.release(&"map")

	# An achievement, told the way a connected client is told one: as a notice. There is
	# no server to send it, so the world's own signal is the whole path.
	game.earned.connect(func(player_id: StringName, title: String, points: int) -> void:
		if player == null or player_id != player.player_id:
			return
		if chat != null:
			chat.notice("Achievement unlocked: %s (+%d)" % [title, points])
		if audio != null:
			audio.notice()
	)

	# No bridge: the box still opens and still echoes, because a chat box that does nothing
	# at all reads as broken rather than as absent.
	DotLog.result(CHANNEL, "chat, offline", chat.attach(null))


# --- Connected -------------------------------------------------------------

func _build_netcode() -> DotResult:
	# The server's sv_ragdoll* set: this end draws the bodies.
	if link != null:
		var _bodies := game.ragdoll_rules.follow_cvars(link)
		# And sv_toys*: a client hides the toys a server took away.
		var _toys := game.toy_rules.follow_cvars(link)
		# The server's mp_forceview: this end places its own camera.
		var _view := game.view_rules.follow_cvars(link)
		# mp_forcecamera, mp_freeroam, mp_freeroam_speed: whether the free camera is offered,
		# and how fast it flies.
		if game.spectate != null and game.spectate.manager != null:
			var _roam := game.spectate.manager.rules.follow_cvars(link)

	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	# [b]Empty, and it is not tidiness.[/b] The manager reads a JSON file by default, so a
	# client with a stale `user://dot_net.json` runs at a tick rate the game did not
	# choose and nothing says so.
	net.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = game.tick_rate
	config.snapshot_rate = BfhGame.NET_SNAPSHOT_RATE
	config.enable_prediction = true
	# Off on a client: rewinding is what a server does to resolve somebody's shot, and a
	# client resolves nobody's.
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	# From the game, not written here. Two files holding this number is how another game
	# in this family ended up decoding positions against a range the server never used.
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	net.config = config
	add_child(net)

	var started := net.setup()

	if not started.ok:
		return started

	bridge = BfhNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)

	var attached := bridge.attach(game, net)

	if not attached.ok:
		return attached

	# Under the link, and NAMED the same as the server's — the name is the routing.
	bridge.open_link(link)
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.blast_received.connect(_on_blast)
	# [b]Where a refusal is drawn.[/b] The server answers a gagged or too-fast line with a
	# notice to that one player, and a notice nothing draws is the server explaining itself
	# to nobody — which is indistinguishable from chat being broken.
	bridge.notice_received.connect(func(text: String) -> void:
		if chat != null:
			chat.notice(text)
		if audio != null:
			audio.notice()
	)
	bridge.seat_changed.connect(_on_seat_changed)

	# The one thing that writes an RTT sample. dot-net never touches a transport, so
	# nothing in it can; without this the clock's input lead omits the flight time and
	# past about 30 ms every command arrives after its tick and is discarded as late.
	if link != null and link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float:
			return float(maxi(0, int(link.call("ping_ms"))))

	DotLog.result(CHANNEL, "chat and voice", chat.attach(bridge))

	# READY, and not one byte before the scene exists. dot-server's signon finishes and
	# THEN the client builds this; anything the server sent in between landed on a node
	# that did not exist and was lost, one "Node not found" per call.
	if link != null and link.has_method("is_playing") and bool(link.call("is_playing")):
		_say_ready()
	elif link != null and link.has_signal("spawned"):
		link.connect("spawned", _say_ready, CONNECT_ONE_SHOT)

	return net.start()


func _say_ready() -> void:
	if bridge != null:
		bridge.ask_ready()


func _on_hello(session_id: int) -> void:
	_watch_id = session_id
	_adopt(game.players.get(BfhNetBridge.player_key(session_id)))
	# The HELLO carried the server's bowl, built just now; the player is what is left to wait for.
	gate.release(&"map")


## A player arrived or changed. The one we are waiting for might be us.
##
## [b]Connected before anything can create a player rather than only checked on HELLO.[/b]
## HELLO and JOIN are both reliable and ordered, so HELLO does arrive first — but "the
## ordering happens to save us" is exactly the reasoning that put this bug in another game
## here, and a check that costs nothing is cheaper than depending on it.
func _on_roster_changed(session_id: int) -> void:
	if session_id == _watch_id and player == null:
		_adopt(game.players.get(BfhNetBridge.player_key(session_id)))


## Ours. Camera on it, HUD bound to it.
func _adopt(candidate: BfhPlayer) -> void:
	if candidate == null or player == candidate:
		return

	player = candidate
	if gate != null:
		gate.freeze(player)
	_build_camera()
	if platform != null:
		_suspend_input(platform.is_input_blocked())

	if settings != null:
		settings.bind_camera(camera)
		# Offline the player samples for themselves, from their controller's own tunables.
		if player.sampler != null:
			settings.bind_look(player.sampler.tunables)

	if hud != null:
		hud.bind(game, player)


func _on_seat_changed(session_id: int, seated: bool) -> void:
	if player == null or session_id != _watch_id:
		return

	# The camera goes up into the cab. [member BfhPlayer.EYE_HEIGHT] is where a person's
	# eyes are when they are standing on the sand; a driver's are above the wheel, and a
	# camera left at standing height while the bus carries the body means driving with
	# your chin on the bonnet.
	if camera != null:
		camera.position = Vector3(0.0, BfhPlayer.EYE_HEIGHT + (0.9 if seated else 0.0), 0.0)


func _on_blast(at: Vector3, radius: float) -> void:
	# The picture is [BfhFx]'s, from the world's `barrel_exploded` that the bridge re-emits,
	# so the same path draws it offline. The log line is what tells somebody reading a
	# client's records that the barrel they saw was one the server decided about, rather
	# than one their own copy imagined.
	DotLog.debug(CHANNEL, "a barrel went off", {"at": str(at), "radius": radius})


# --- The frame -------------------------------------------------------------

func _build_camera() -> void:
	if camera != null or player == null:
		return

	camera = Camera3D.new()
	camera.name = "Eye"
	camera.fov = 90.0
	camera.current = true
	player.add_child(camera)
	camera.position = Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)

	# Other runners and drivers: hidden when one is at the lens, faded in third person when
	# one stands between the camera and you.
	_fade = DotCameraFade.new()
	_fade.name = "Fade"
	_fade.bodies_fn = _other_players
	camera.add_child(_fade)
	third_person = game.view_rules.resolve(third_person)


func _build_hud() -> void:
	hud = BfhHud.new()
	hud.name = "Hud"
	add_child(hud)


## After the world, because it listens to the world's round signals from the start: a
## round that ends before anybody has pressed Tab still puts the score up. After the
## settings, because it draws on the menu's board.
func _build_scoreboard() -> void:
	scoreboard = BfhScoreboard.new()
	scoreboard.name = "Scoreboard"
	add_child(scoreboard)
	# The platform feeds the menu's board and holds it on the Tab row; this draws on it.
	var board: DotMenuScoreboard = platform.board as DotMenuScoreboard
	scoreboard.bind(game, func() -> BfhPlayer: return player, board, link if not _offline else null)


## The player's settings, applied to everything that reads them. See [BfhSettings].
##
## After the audio and the sampler, because both are bound here and a binding applies at
## once. The camera arrives with the player and is bound in [method _adopt].
func _build_settings() -> void:
	settings = BfhSettings.new()
	settings.name = "Settings"
	add_child(settings)
	platform.settings = settings
	# Not handed over: BfhHud is a CanvasLayer, so it follows the menu itself, below.
	platform.chat = chat
	platform.look_position_fn = _look_position
	platform.board_snapshot_fn = func() -> Dictionary:
		return scoreboard.snapshot() if scoreboard != null else {}
	_wire_maps()
	DotLog.result(CHANNEL, "the platform", platform.setup())
	# Walking is off while the cover is up, a menu is open or a line is typed: the sampler polls
	# the keyboard, and a player dragging a volume slider with the arrow keys would otherwise
	# walk into the bus they had stopped to turn up (and a driver steer with the letters of the
	# word they are typing).
	platform.input_blocked_changed.connect(_suspend_input)
	_suspend_input(platform.is_input_blocked())

	settings = platform.settings as BfhSettings
	console = platform.console as DotConsoleController
	if settings == null:
		return

	if _sampler != null:
		settings.bind_look(_sampler.tunables)

	if audio != null:
		settings.bind_audio(audio.audio)

	if fx != null and fx.fx != null:
		settings.bind_fx(fx.fx)

	if settings.menu != null:
		# The HUD in the menu's theme and at the player's HUD size, live.
		if hud != null:
			hud.follow_menu(settings.menu)


## M: the bowl list (dot-menu's map menu). Solo a choice changes the bowl here at once;
## connected the server decides, by the owner's `sv_map_menu_flag`, and anybody without it
## gets a vote instead (dot-vote's map menu, wired in [BfhModule]). By name, so a client shell
## older than the map menu still runs the game without it.
func _wire_maps() -> void:
	if game != null:
		game.workshop_index = DotContentIndex.shared()
	platform.maps_rows_fn = func() -> Array: return game.bowl_rows(game.workshop_index) if game != null else []
	platform.maps_change_fn = func(id: StringName) -> DotResult: return game.change_bowl_now(id)
	platform.maps_title = "Change bowl"
	platform.maps_noun = "bowls"


func _suspend_input(value: bool) -> void:
	if _sampler != null:
		_sampler.suspended = value
	if player != null and player.sampler != null:
		player.sampler.suspended = value


## What this client hears, listening to its own world. See [BfhAudio].
##
## Not fatal: a client whose audio was refused is a silent client, which is what this game
## was for its first eleven days, and a WARN is what says so.
func _build_audio() -> void:
	audio = BfhAudio.new()
	audio.name = "Audio"
	add_child(audio)

	var built: DotResult = audio.setup(game, func() -> BfhPlayer: return player)

	if not built.ok:
		DotLog.warn(CHANNEL, "no audio", {"why": built.error.message})
		remove_child(audio)
		audio.free()
		audio = null


## What this client draws, listening to its own world. See [BfhFx].
##
## Not fatal, for the reason the audio is not: a client that draws no blast still hears it
## and is still thrown by it, and a WARN says why the picture is missing.
func _build_fx() -> void:
	fx = BfhFx.new()
	fx.name = "Fx"
	add_child(fx)

	var built: DotResult = fx.setup(game)

	if not built.ok:
		DotLog.warn(CHANNEL, "no effects", {"why": built.error.message})
		remove_child(fx)
		fx.free()
		fx = null


## The chat box, before the netcode and before any player exists.
##
## [b]Built in both halves and attached to the bridge afterwards.[/b] A box that only
## appeared on a server would be a box nobody could test offline, and a box built after the
## first line arrived would miss it — the backlog a joining player is sent is the first
## thing the server says.
func _build_chat() -> void:
	chat = BfhClientChat.new()
	chat.name = "Chat"
	add_child(chat)


# --- The end of a round: killcam, winner reveal, board -------------------------

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


## Whether the pointer is the game's: captured. A menu frees it and the platform takes it back.
func _pointer_ours() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The sampled command, on a connected client, once per tick the clock says has passed.
##
## [b]Offline this does nothing and the world ticks itself.[/b] The player samples inside
## [method BfhPlayer.simulate] there, which is the shape a single process wants; a
## connected client cannot use it, because its local player has to be simulated by the
## PREDICTOR from the same command that was sent, and a second sample would predict
## something different from what the server was told.
func _physics_process(delta: float) -> void:
	if _offline or net == null or not net.is_running() or bridge == null:
		return

	# The clock says how many ticks this frame is worth, which on a client whose engine
	# runs at the server's rate is almost always exactly one.
	var ticks := net.clock.advance(delta)

	# The clock has advanced; only the sampling waits, so the mouse does not pile up a turn
	# behind the cover and the server sees an idle body until it lifts.
	if _covered():
		return

	var move := _sampler.sample(delta) if _sampler != null else DotFpsCommand.new()

	# The keys that fly the free camera must not also walk the body that fell.
	if is_roaming():
		move = DotFpsCommand.new()
		_swinging = false

	if _swinging:
		move.buttons |= BfhNetCommand.BUTTON_SWING

	# [b]Each pass is its own tick.[/b] `advance` has already moved the clock by all of
	# them, so `input_tick()` is the LAST one on every pass: a frame worth two ticks sent
	# the second twice and the first never, the server repeated a stale command for the
	# one it never got, and the predictor's replay stopped at the hole and drew the player
	# short of where they were -- after every hitch, and on every frame the display and
	# the tick rate do not line up. Arithmetic here rather than a new dot-net call,
	# because a pack has to run on whatever client shell the player already has.
	for i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), move)


func _process(delta: float) -> void:
	third_person = game.view_rules.resolve(third_person)
	var _shown := present_frame(net, game, player, delta, -1.0, third_person)
	if killcam != null:
		killcam.frame()

	# Before the early return, so an effect is retired on time even before there is a
	# camera; culled from where the camera was last frame, which is one frame's error.
	if fx != null:
		if camera != null:
			fx.present(delta, camera.global_position, -camera.global_basis.z)
		else:
			fx.present(delta, Vector3.ZERO)

	if camera == null or player == null:
		return

	# Somebody else's eyes, while this player is out. After the frame's interpolation, so
	# the camera is where this frame draws whoever it is on.
	if is_roaming():
		_drive_free_camera()
		_spectating = true
		if audio != null:
			audio.present(delta, camera.global_position)
		return

	_roam_seeded = false

	if present_spectator_camera(game, player, camera):
		_spectating = true
		if audio != null:
			audio.present(delta, camera.global_position)
		return

	if _spectating:
		# Back into their own head: the view the seat or the sand gives them, which the lines
		# below then move every frame. Without it the camera keeps the last spectator
		# transform's LOCAL offset and a new round starts with the view floating wherever
		# the last target was.
		_spectating = false
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(
			0.0, BfhPlayer.EYE_HEIGHT + (0.9 if player.riding else 0.0), 0.0
		))

	# Drawn every FRAME from the controller's own interpolated view, not once per tick.
	# Another game in this family measured what the other way costs: a client stepping
	# physics at one rate and drawing at another advances the camera in bursts, which is a
	# 47% change in apparent speed several times a second and reads as "the game is
	# jittery" with every simulated number correct.
	var state := player.controller.state
	camera.rotation = Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0)

	# [b]And the position, which the angles above never needed.[/b] The camera hangs off the
	# player's node and the node only moves on a tick, so a camera left there advances in
	# steps while everybody it is looking at is now interpolated every frame — a runner
	# watching another runner alongside them sees the other one shudder, because it is the
	# VIEW that is stepping. `render_state` blends the last two ticks by the engine's physics
	# fraction, which the bridge makes a fraction through a tick by putting the engine on
	# the server's rate. Written globally rather than by moving the node, because the tick
	# writes the node and prediction reads it back. Not while riding: the controller is not
	# simulated in a bus, and a blend between two ticks that never happened drags the view
	# backwards.
	if not player.riding:
		camera.global_position = player.controller.render_state().position \
			+ Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)

	_place_third_person(delta)

	if audio != null:
		audio.present(delta, camera.global_position)


## Moves the camera from the eye to behind it in third person, swept by dot-core's
## [DotCameraProbe] so a wall, a bowl's rim or a bus between stops it short; from over the
## roof when driving, so the bus being driven is not what stops it.
func _place_third_person(delta: float) -> void:
	if not third_person:
		if _probe != null:
			_probe.reset()
		if _fade != null:
			_fade.focus = null
		return
	if _probe == null:
		_probe = DotCameraProbe.new(camera.get_world_3d(), 1)
		_probe.add_excluded_object(player.get_rid())
	var pivot := camera.global_position + (Vector3.UP * BUS_PIVOT_RISE if player.riding else Vector3.ZERO)
	var offset := THIRD_PERSON_BUS_OFFSET if player.riding else THIRD_PERSON_OFFSET
	camera.global_position = _probe.resolve(pivot, pivot + camera.global_basis * offset, delta)
	if _fade != null:
		_fade.focus = player


## The view key: the other view if the server's `mp_forceview` allows it.
func toggle_view() -> void:
	var wanted := game.view_rules.toggled(third_person)
	if wanted == third_person:
		var menu: Object = settings.menu if settings != null else null
		if menu != null and game.view_rules.refusal() != "" and menu.has_method(&"toast"):
			menu.call(&"toast", game.view_rules.refusal())
		return
	third_person = wanted


## Everybody else, for the camera fade.
func _other_players() -> Array:
	var out: Array = []
	if game == null:
		return out
	for id in game.players:
		var other: Node3D = game.players[id]
		if other != player and is_instance_valid(other):
			out.append(other)
	return out


## Puts [param eye] where a runner who is out is looking. Returns whether it did.
##
## [b]Static, so the net suite drives this and not a copy of it[/b] — the same reason
## [method present_frame] is. The answer is the world's spectator camera, which on a
## connected client is a mirror computing it from the view the server sent and the
## positions this frame is drawing; see [BfhSpectate].
static func present_spectator_camera(p_game: BfhGame, own: BfhPlayer, eye: Camera3D) -> bool:
	if p_game == null or own == null or eye == null or p_game.spectate == null:
		return false

	if not p_game.spectate.is_spectating(own.player_id):
		return false

	# The chase and death cameras pulled out of the bowl by dot-spectate, given the level.
	var manager: DotSpectatorManager = p_game.spectate.manager
	if manager != null and manager.camera_world == null:
		manager.camera_world = eye.get_world_3d()
		manager.camera_mask = 1

	var view := p_game.spectate.camera_for(own.player_id)

	# Identity is dot-spectate's "no pose to give", which is a target that has not been drawn
	# yet. The last frame's transform is a better picture than the world's origin.
	if view == Transform3D.IDENTITY:
		return true

	eye.global_transform = view
	return true


## Everything a frame draws that a tick does not, in this order: the netcode's
## interpolation, then every player's body, then every beacon. Returns how many bodies are
## shown. Static so the net suite drives exactly this and not a copy of it.
##
## [b]The interpolation was never called in this game, and that is half of why nobody else
## was visible.[/b] `DotNetManager.interpolate_frame` is what blends two snapshots and hands
## the result to `BfhPlayerNet._net_interpolated` and `BfhPropNet._net_interpolated` — both
## written, documented, and reached by nothing. So every remote runner, every crate and both
## buses moved only when a snapshot landed, twenty times a second on a 60-tick server: the
## render-jitter class this family has now paid for in three games. The other half was that
## a remote runner had no body to move (see [BfhFigure]).
##
## [param alpha] is the fraction through the current tick; -1 derives it from the engine,
## which is what a real frame wants. A suite passes it explicitly, because a suite's frames
## are not an engine's.
static func present_frame(
	p_net: DotNetManager, p_game: BfhGame, own: BfhPlayer, delta: float, alpha: float = -1.0,
	own_seen: bool = false
) -> int:
	var networked := p_net != null and p_net.is_running()

	if networked:
		p_net.interpolate_frame(alpha)

	# Your own runner is drawn at the clock's render alpha, not the engine's fraction: the
	# clock stretches and shrinks its ticks while it settles on the server, so a physics frame
	# now and then runs no tick or two, and drawn at the engine's fraction the eye stood still
	# on one frame and moved double on the next. `DotFpsController.render_state` reads it from
	# `render_clock` (dot-player-controller); by name both ways, so a shell older than either
	# draws as before. Null offline, where every physics frame is one tick.
	if own != null and own.controller != null:
		own.controller.set(&"render_clock", p_net.clock if networked else null)

	if p_game == null:
		return 0

	var shown := 0

	for id: StringName in p_game.players:
		var body: BfhPlayer = p_game.players[id]

		if body == null or not is_instance_valid(body):
			continue

		# Your own runner is drawn when the camera is behind you ([param own_seen]).
		if body.present_body(body == own and not own_seen, p_game.team_of(id) == BfhGame.TEAM_DRIVERS):
			shown += 1

		# Every player's beacon, this client's own included — somebody who has been
		# beaconed sees their ring and hears their ping too. After the interpolation, so a
		# ring is placed where this frame draws them rather than where the last one did.
		body.present_beacon(delta, body == own)

	return shown


## Whether the mouse button is down this frame. Read by [method _physics_process].
##
## [b]A held state and not an event, because a hammer is held.[/b] An event queue is
## sampled per frame and a tick is not a frame: at 60 Hz on a 144 Hz screen, two frames in
## three carry no click at all, so a swing bound to the event would be dropped two times
## in three at exactly the moment somebody was leaning on the button.
var _swinging: bool = false


func _unhandled_input(event: InputEvent) -> void:
	# Tab, M and a click taking the pointer back are the platform's (DotGameClient).
	if event.is_action_pressed("ui_cancel"):
		# Opens the settings when the menu left this Escape alone, because a released pointer
		# with nothing on screen to click was a key that did half a job. A second Escape never
		# reaches here: dot-ui's stack sits deeper in the tree, sees it first, and closes the
		# screen.
		if settings != null:
			settings.open()
		return

	# Nothing below acts while the cover is up: no swing, jump or look.
	if _covered():
		return

	# A runner who is out: the mouse and the jump key are the spectator's, and nothing
	# below — a swing, a turn — means anything for somebody who is not in the round.
	if player != null and game.spectate != null and game.spectate.is_spectating(player.player_id):
		if InputMap.has_action(BfhBindings.ROAM) and event.is_action_pressed(BfhBindings.ROAM):
			toggle_roam()
			return

		# A free camera turns on the mouse, and the clicks and the jump key belong to it:
		# next, back and the view change mean nothing without a target.
		if is_roaming():
			if event is InputEventMouseMotion and _pointer_ours():
				_roam_mouse(event as InputEventMouseMotion)
			return

		var ask := spectator_ask(event)
		if ask >= 0:
			_ask_to_watch(ask)
		return

	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and InputMap.has_action(BfhBindings.VIEW) and event.is_action(BfhBindings.VIEW):
		toggle_view()
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton

		if button.button_index == MOUSE_BUTTON_LEFT:
			_swinging = button.pressed

			# Offline there is no command to carry the button: the world is right here and
			# the swing is resolved against it directly. Connected, the flag above rides
			# the next command and the SERVER swings.
			if _offline and button.pressed:
				_swing_locally()

	if player == null:
		return

	# EVERY event, not only motion: the sampler latches button presses, which is how a wheel
	# tick (press and release in one pair) reaches a command as one jump. Its `suspended`
	# flag already gates this while a menu or chat is up, as it does Space.
	if _pointer_ours():
		if _offline and player.sampler != null:
			player.sampler.handle_event(event)
		elif _sampler != null:
			_sampler.handle_event(event)


## Which spectator request an input event is, or -1. Left click is next, right click is
## back, and the jump key changes between their eyes and behind them.
static func spectator_ask(event: InputEvent) -> int:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return BfhSpectate.ASK_NEXT
			MOUSE_BUTTON_RIGHT:
				return BfhSpectate.ASK_PREVIOUS
			MOUSE_BUTTON_MIDDLE:
				return BfhSpectate.ASK_VIEW

	# The jump key, as bound ([BfhBindings]); Space where nothing put the action on the map.
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event.is_action(&"dot_fps_jump") if InputMap.has_action(&"dot_fps_jump")
				else (event as InputEventKey).physical_keycode == KEY_SPACE):
		return BfhSpectate.ASK_VIEW

	return -1


## Offline the world answers; connected, the server does, and a refusal comes back as a
## notice like every other one.
func _ask_to_watch(ask: int) -> void:
	if audio != null:
		audio.click()

	if _offline:
		var answered: DotResult = game.spectate.request(player.player_id, ask)
		if not answered.ok and chat != null:
			chat.notice(answered.error.message)
	elif bridge != null:
		bridge.ask_watch(ask)


# --- The free camera -------------------------------------------------------

## The pose the free camera holds between frames, seeded from the camera as it was the frame
## the roam began, so the spectator starts where they were looking.
var _free_cam: DotSpectatorFreeCam = null
var _roam_seeded := false
var _roam_look := Vector2.ZERO


func is_roaming() -> bool:
	return player != null and game != null and game.spectate != null \
		and game.spectate.is_roaming(player.player_id)


## The free-camera key: into one from watching, back onto a player from one. Only for somebody
## already out; a stray press must not turn a runner into a spectator.
func toggle_roam() -> void:
	if player == null or game == null or game.spectate == null \
			or not game.spectate.is_spectating(player.player_id):
		return

	if not is_roaming() and not game.spectate.can_roam(player.player_id):
		if chat != null:
			chat.notice("Free camera is off on this server.")
		return

	if audio != null:
		audio.click()

	if _offline:
		var res: DotResult = game.spectate.request(player.player_id, BfhSpectate.ASK_ROAM)
		if not res.ok and chat != null:
			chat.notice(res.error.message)
	elif bridge != null:
		bridge.ask_watch(BfhSpectate.ASK_ROAM)


## The free camera, once a frame: WASD along the view, Space and Ctrl up and down, Shift fast,
## Alt slow, the mouse to look. Only the camera moves; the body stays where it fell.
##
## [b]The speed is the server's[/b] (`mp_freeroam_speed`, through the mirror's rules), so a
## client cannot fly faster than it was told to. The server holds only the mode.
func _drive_free_camera() -> void:
	if _free_cam == null:
		_free_cam = DotSpectatorFreeCam.new()

	_free_cam.rules = game.spectate.manager.rules

	if not _roam_seeded:
		# The camera still holds last frame's pose: where this spectator was looking.
		_free_cam.seed_from(camera.global_transform)
		_roam_seeded = true
		_roam_look = Vector2.ZERO

	_free_cam.look(_roam_look)
	_roam_look = Vector2.ZERO

	var move := Vector3.ZERO

	if not _covered() and (settings == null or _pointer_ours()):
		move = Vector3(
			Input.get_axis(&"dot_fps_left", &"dot_fps_right"),
			Input.get_axis(&"dot_fps_crouch", &"dot_fps_jump"),
			Input.get_axis(&"dot_fps_back", &"dot_fps_forward"))

	var shift := Input.is_physical_key_pressed(KEY_SHIFT)
	var alt := Input.is_physical_key_pressed(KEY_ALT)
	camera.global_transform = _free_cam.step(
		move, shift, alt and not shift, get_process_delta_time())


## Mouse motion while roaming, as radians for [method DotSpectatorFreeCam.look]: positive x
## turns left (mouse right is negative), positive y looks up (mouse down is negative).
func _roam_mouse(motion: InputEventMouseMotion) -> void:
	var sampler := _sampler if _sampler != null else player.sampler
	var degrees := 0.12
	var invert := 1.0

	if sampler != null and sampler.tunables != null:
		degrees = sampler.tunables.mouse_sensitivity
		invert = -1.0 if sampler.tunables.invert_look_y else 1.0

	_roam_look += Vector2(-motion.relative.x, -motion.relative.y * invert) * deg_to_rad(degrees)


func _swing_locally() -> void:
	if player == null or game == null:
		return

	# A driver's swing button is the horn. Connected, the button rides the command and the
	# server sounds it; offline the world is right here.
	if player.riding:
		game.sound_horn(player)
		return

	if player.hammer == null:
		return

	player.hammer.swing(
		game,
		player.eye_position(),
		player.aim_direction(),
		game.props,
		game.prop_damage,
		game.carry,
		player.player_id,
		0xFFFFFFF,
	)


func describe() -> Dictionary:
	var out := {
		"offline": _offline,
		"session": _watch_id,
		"player": player != null,
	}

	if bridge != null:
		out["bridge"] = bridge.describe()

	if chat != null:
		out["chat"] = chat.describe()

	if audio != null:
		out["audio"] = audio.describe()

	if fx != null:
		out["fx"] = fx.describe()

	if settings != null:
		out["settings"] = settings.describe()

	if player != null and game != null and game.spectate != null:
		out["watching"] = game.spectate.describe_view(player.player_id)

	if game != null:
		out["world"] = game.describe()

	return out


## Where a roster row's player stands, for dot-game's look-to-gag key (G, K).
func _look_position(row: Dictionary) -> Variant:
	if game == null:
		return null
	for who: BfhPlayer in game.players.values():
		if who != player and who.display_name == row["name"]:
			return who.global_position + Vector3.UP * 1.5
	return null
