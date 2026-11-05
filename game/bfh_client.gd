extends "bfh_client_view.gd"

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

	# Layered on the CLIENT too: otherwise every command-line flag does nothing offline.
	var binder := BfhConfig.make_binder(config, config_file)
	var loaded := binder.load_layers()

	if not loaded.ok:
		DotGameConfigBinder.fail_boot(get_tree(), loaded)
		return

	link = platform.link as Node
	_offline = platform.offline

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.config_binder = binder
	game.authoritative = _offline
	# A connected client's world is not what a module looks up; sharing a process would fight over the name.
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
	_sampler = BfhTouch.make_sampler(BfhPlayer.tunables_for(config), _touch_ignores)

	_build_hud()
	_build_touch()
	_build_chat()
	_build_audio()
	_build_fx()
	_build_settings()
	_build_scoreboard()
	_build_killcam()

	if _offline:
		_start_offline()
	else:
		# [b]Here, in `_ready`, which runs INSIDE `DotClientLink._load_scene`.[/b] The link adds this
		# scene and tells the server it has loaded on the next line, so the netcode is up before the
		# server has been told there is anybody to send to — which is the order that leaves nothing to be.
		var netted := _build_netcode()
		DotLog.result(CHANNEL, "the netcode", netted)
		if netted.ok and link != null:
			_start_remote_workbench()

## The load gate is [member DotGameClient.gate]: covered, and the local body and the input still,
## until the bowl stands, the local player exists and its camera is current.

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

# --- Offline

func _start_offline() -> void:
	# A driver and a runner, because a round needs both sides and there is one person here. What the
	# bot is for is having a bus on the floor to run away from, which is the thing worth looking at.
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

# --- Connected

func _build_netcode() -> DotResult:
	# The server's sv_ragdoll* set: this end draws the bodies.
	if link != null:
		var _bodies := game.ragdoll_rules.follow_cvars(link)
		# And sv_toys*: a client hides the toys a server took away.
		var _toys := game.toy_rules.follow_cvars(link)
		# The server's mp_forceview: this end places its own camera.
		var _view := game.view_rules.follow_cvars(link)
		var _ambient := game.ambient_rules.follow_cvars(link)
		# mp_forcecamera, mp_freeroam, mp_freeroam_speed: whether the free camera is offered,
		# and how fast it flies.
		if game.spectate != null and game.spectate.manager != null:
			var _roam := game.spectate.manager.rules.follow_cvars(link)

	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	# Empty: a stale `user://dot_net.json` would silently change the tick rate.
	net.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = game.tick_rate
	config.snapshot_rate = BfhGame.NET_SNAPSHOT_RATE
	config.enable_prediction = true
	# Off on a client: rewinding is what a server does to resolve somebody's shot, and a
	# client resolves nobody's.
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 0
	# From the game: two files holding this number can disagree about the range.
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
	# Before the seal and in the server's order (after the bridge), or the actions stay local.
	DotLog.result(CHANNEL, "avatar action message", DotGameAvatarActionMessage.register(net))
	# The server's order again (after the avatar frame): the remote workbench's frame.
	workbench_remote = DotGameWorkbenchRemoteClient.attach(net)
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.blast_received.connect(_on_blast)
	# Where a refusal (gagged, too fast) is drawn; undrawn it looks like broken chat.
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
	if workbench_remote != null:
		workbench_remote.ask()
	if bridge != null:
		bridge.ask_ready()

func _on_hello(session_id: int) -> void:
	_watch_id = session_id
	_adopt(game.players.get(BfhNetBridge.player_key(session_id)))
	# The HELLO carried the server's bowl, built just now; the player is what is left to wait for.
	gate.release(&"map")

## A player arrived or changed. The one we are waiting for might be us.
func _on_roster_changed(session_id: int) -> void:
	if session_id == _watch_id and player == null:
		_adopt(game.players.get(BfhNetBridge.player_key(session_id)))

## The figure an avatar action plays on: that peer's player, or the local one offline.
func _avatar_figure(peer_id: int) -> Object:
	var who: BfhPlayer = null
	if bridge != null and peer_id != 0:
		who = game.players.get(BfhNetBridge.player_key(bridge.player_for_peer(peer_id)), null)
	if who == null and player != null and (net == null or peer_id == net.local_peer_id):
		who = player
	return who.figure.person if who != null and who.figure != null else null

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

	if DotPlatform.has_touch() and player.sampler != null and not player.sampler is DotFpsTouchSampler:
		player.sampler = BfhTouch.make_sampler(player.sampler.tunables, _touch_ignores)
		_suspend_input(platform.is_input_blocked() if platform != null else false)

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

	# The camera goes up into the cab. [member BfhPlayer.EYE_HEIGHT] is where a person's eyes are when
	# they are standing on the sand; a driver's are above the wheel, and a camera left at standing
	# height while the bus carries the body means driving with your chin on the bonnet.
	if camera != null:
		camera.position = Vector3(0.0, BfhPlayer.EYE_HEIGHT + (0.9 if seated else 0.0), 0.0)

func _on_blast(at: Vector3, radius: float) -> void:
	# The picture is [BfhFx]'s, from the world's `barrel_exploded` that the bridge re-emits, so the
	# same path draws it offline. The log line is what tells somebody reading a client's records that
	# the barrel they saw was one the server decided about, rather than one their own copy imagined.
	DotLog.debug(CHANNEL, "a barrel went off", {"at": str(at), "radius": radius})

# --- The frame

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

	viewmodel = BfhViewmodel.new()
	camera.add_child(viewmodel)
	viewmodel.bind(player.hammer)

func _build_hud() -> void:
	hud = BfhHud.new()
	hud.name = "Hud"
	add_child(hud)

## The phone's buttons over the HUD, on a touch device only.
func _build_touch() -> void:
	if not DotPlatform.has_touch() or hud == null:
		return
	_touch = BfhTouch.new()
	# BfhHud is a CanvasLayer; the buttons need a Control to anchor to.
	var host := Control.new()
	host.name = "TouchHost"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(host)
	_touch.build(host, _active_sampler, _set_swing, platform)


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
	# The starter set: the equipped list needs a credential the client does not hold (the server reads it).
	DotLog.result(CHANNEL, "avatar actions", platform.add_avatar_actions(net, _avatar_figure))
	_add_noblock_and_workbench()
	# Walking is off while the cover is up, a menu is open or a line is typed: the sampler polls the
	# keyboard, and a player dragging a volume slider with the arrow keys would otherwise walk into the
	# bus they had stopped to turn up (and a driver steer with the letters of the word they are.
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
		# The server's bfh_ambient* drive the quiet layer; the player's sliders multiply on top.
		if audio.ambient != null:
			audio.ambient.follow_settings(settings.settings, game.ambient_rules)

	if fx != null and fx.fx != null:
		settings.bind_fx(fx.fx)
		if fx.break_fx != null:
			fx.break_fx.follow(settings.settings)

	if settings.menu != null:
		# The HUD in the menu's theme and at the player's HUD size, live.
		if hud != null:
			hud.follow_menu(settings.menu)

## M: the bowl list (dot-menu's map menu). Solo a choice changes the bowl here at once; connected
## the server decides, by the owner's `sv_map_menu_flag`, and anybody without it gets a vote instead
## (dot-vote's map menu, wired in [BfhModule]).
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
func _build_chat() -> void:
	chat = BfhClientChat.new()
	chat.name = "Chat"
	add_child(chat)

# --- The end of a round: killcam, winner reveal, board

## Online: no local trust and no panel until the server names this player an admin (sv_workbench_remote). The sets are the game's own; the rows are the server's, through the bridge's profile link.
func _start_remote_workbench() -> void:
	if workbench_remote == null:
		return
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.remote_client = workbench_remote
	wb.remote_fn = func() -> bool: return true
	wb.config = {"enabled": false}
	if game.config_binder != null:
		for set: DotProfileSet in game.config_binder.profile_sets():
			wb.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	add_child(wb)
	var started := wb.start(game.ensure_runtime())
	DotLog.result(CHANNEL, "the remote workbench", started)
	if not started.ok:
		wb.queue_free()
		return
	workbench = wb
	platform.add_workbench(wb)

## dot-team's block rules followed from the server, or, solo, the F9 tuning panel over this process's own config.
func _add_noblock_and_workbench() -> void:
	if link != null:
		DotLog.result(CHANNEL, "noblock", platform.add_noblock(game, Callable(game, "team_of_side")))
		return
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.listen_host_fn = func() -> bool: return true
	workbench = wb
	wb.config = {"enabled": false}
	if game.config_binder != null:
		for set: DotProfileSet in game.config_binder.profile_sets():
			wb.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	add_child(wb)
	var started := wb.start()
	DotLog.result(CHANNEL, "the workbench", started)
	if started.ok and game.config_binder != null and wb.api != null:
		game.config_binder.attach(wb.api.runtime as DotProfileRuntime)
	platform.add_workbench(wb)

## Whether the pointer is the game's: captured. A menu frees it and the platform takes it back.
