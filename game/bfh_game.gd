extends "bfh_game_flashlight.gd"

const BfhAmbience := preload("bfh_ambience.gd")

## The simulation. Headless, authoritative, and the only thing that decides anything.

## Where this world publishes itself, so a module can find it.
const SERVICE := &"bfh_game"

## Snapshots a second. Twenty, against a sixty-tick simulation.
const NET_SNAPSHOT_RATE := 20

## How far a position may be from the origin, in metres, on the wire.
const NET_WORLD_EXTENT := 256.0

## Every player changed sides. Round-numbered, because a client redraws its HUD from it.
signal sides_swapped(round_number: int)

## A round began. The bowl has been re-laid by the time this fires.
signal round_began(number: int)

## The bowl was rebuilt at a round's start, to the one the players voted for. Emitted after
## the last round's props are gone and before this round's are laid, so a bridge that tells
## its clients now has them rebuild before the first crate arrives.
signal bowl_changed(bowl_id: StringName)

## A round ended. [param winner] is one of the TEAM_* constants, or 0 for a draw.
signal round_over(number: int, winner: int)

## Somebody earned an achievement. Authority only; see `BfhProgress`.
signal earned(player_id: StringName, title: String, points: int)

## Whether something else drives the tick.
@export var external_tick: bool = false

## Whether this world counts statistics and achievements. Authority only either way.
@export var track_progress: bool = true

## Whether this world publishes itself under [constant SERVICE].
@export var register_service: bool = true

## dot-player-controller's `mp_forceview`: whether a player may switch to third person (0), or is
## held in first (1) or third (2). Bound by the module (REPLICATED) and followed by a client through
## its link.
var view_rules: DotPlayerViewRules = DotPlayerViewRules.new()

## The ambience cvars (`bfh_ambient*`): bound by the module (REPLICATED), followed by a client through its link.
var ambient_rules: DotAmbienceRules = BfhAmbience.make_rules()

## Binds [member config] to cvars, the cfg/ yml layers and the workbench; made by the server scene or the client.
var config_binder: DotGameConfigBinder = null

## The workbench's profile rows, made on first ask: the bridge's profile link must exist before the netcode seals, the workbench after.
var profile_runtime: DotProfileRuntime = null

func ensure_runtime() -> DotProfileRuntime:
	if profile_runtime == null:
		profile_runtime = DotProfileRuntime.new()
		profile_runtime.permit = func(actor: Variant, _flag: String) -> bool:
			return typeof(actor) == TYPE_STRING_NAME and actor == &"local"
	return profile_runtime

## The bowl the next round is played in, set by the players' vote ([code]game/bfh_vote.gd[/code])
## and used once. Empty keeps this one.
var next_bowl_id: StringName = &""

## The Workshop index a solo client points this at (`DotContentIndex.shared()`), so a
## subscribed bowl can be chosen. Null on a server, which plays only its own.
var workshop_index: DotContentIndex = null

var _layout_seed: int = 0

func _ready() -> void:
	if config == null:
		config = BfhConfig.new()

	var valid := config.validate()
	if not valid.ok:
		# FATAL is reserved in this family for "the process cannot continue", and a
		# configuration that contradicts itself is not that: the right answer is to
		# say so loudly and refuse to run a round, not to take the server down.
		DotLog.error(CHANNEL, "the configuration is not usable", {"why": valid.error.message})
		return

	_layout_seed = config.arena_seed

	if not body_rules.changed.is_connected(apply_pass_through):
		body_rules.changed.connect(apply_pass_through)
	body_rules.solid = false
	_apply_gravity()
	_build_random()
	_build_arena()
	_build_props()
	_build_vehicles()
	_build_combat()
	_build_match()
	_build_spectate()
	_build_progress()

	if register_service:
		DotRegistry.register(SERVICE, self)

	if authoritative:
		var _rotation_read := load_rotation()

	DotLog.info(CHANNEL, "world ready", config.describe())

func _exit_tree() -> void:
	# By instance, never by name. Unregistering the NAME from a world that lost the
	# race to register it takes the other world's entry out with it, and the symptom is
	# a module that cannot find a game that is sitting in the tree.
	if register_service:
		DotRegistry.unregister_instance(SERVICE, self)

## Puts this world's physics space on the gravity the game was tuned for.
func _apply_gravity() -> void:
	var world := get_world_3d()

	if world == null:
		DotLog.warn(CHANNEL, "no world to set gravity on", {})
		return

	PhysicsServer3D.area_set_param(
		world.space, PhysicsServer3D.AREA_PARAM_GRAVITY, config.gravity
	)

func _build_random() -> void:
	random = DotRandomManager.new()
	random.name = "Random"
	# [b]Off, and the addon's own comment says why.[/b] A registry name is global to the process, so
	# the last manager to register wins — and two worlds in one process is not exotic here: it is a
	# server and a client in one editor session, and it is what the suite does in every section.
	random.register_as_service = false
	add_child(random)
	random.setup()
	random.reseed(_layout_seed)

func _build_arena() -> void:
	arena = BfhArena.new()
	arena.name = "Arena"
	# The layout's two choices, before the build that reads them. A client's are its own
	# defaults until the HELLO says what the server built (see the bridge).
	arena.hook_layout = config.hook_layout
	arena.courtyard_west_lane = config.courtyard_west_lane
	add_child(arena)
	# Every build, the server's and a client's rebuild on HELLO alike.
	var _toys := arena.built.connect(_build_toys)
	arena.build(config.arena_radius)

func _build_props() -> void:
	props = DotPropSpawner.new()
	props.name = "Props"
	props.catalogue = BfhContent.props(config)
	props.limits = DotPropLimits.new()
	# The bowl's furniture is spawned by the world rather than by a player, so the per-player budget
	# and the cooldown are not what is being defended against here — the world cap is, and it has to be
	# above what a round lays out or the last few crates silently never appear.
	props.limits.spawn_interval = 0.0
	props.limits.per_player_budget = 400
	props.limits.world_budget = 400
	props.limits.clean_up_on_leave = false
	props.authoritative = authoritative
	add_child(props)

	prop_damage = DotPropDamage.new()
	prop_damage.name = "PropDamage"
	prop_damage.authoritative = authoritative
	props.add_child(prop_damage)
	prop_damage.exploded.connect(_on_prop_exploded)
	prop_damage.broken.connect(_on_prop_broken)

	carry = DotPropCarry.new()
	carry.name = "PropCarry"
	props.add_child(carry)

func _build_vehicles() -> void:
	vehicles = DotVehicleSpawner.new()
	vehicles.name = "Vehicles"
	vehicles.catalogue = BfhContent.vehicles(config)
	vehicles.authoritative = authoritative
	# The buses are put out by the world at the top of a round, not requested by players, so the limits
	# that exist to stop somebody spamming a spawn key are the wrong shape here.
	vehicles.spawn_interval = 0.0
	vehicles.per_player_budget = 16
	vehicles.world_budget = 16
	add_child(vehicles)

	# [b]The SPAWNER'S ride, not a second one.[/b] `DotVehicleSpawner` builds one in its own `_init`
	# and uses it for three things: evacuating a vehicle that is destroyed with people in it, answering
	# `vehicle_of_rider`, and reporting how many riders there are.
	ride = vehicles.ride
	ride.carry_rider_nodes = false
	ride.on_seated = func(rider_id: StringName, v: DotVehicleInstance, _s: DotVehicleSeat) -> void:
		_set_riding(rider_id, true, Vector3.ZERO, v)
	ride.on_unseated = func(
		rider_id: StringName, _v: DotVehicleInstance, _s: DotVehicleSeat, at: Vector3
	) -> void:
		_set_riding(rider_id, false, at)

func _build_combat() -> void:
	combat = DotCombatManager.new()
	combat.name = "Combat"
	combat.is_authority = authoritative

	# [b]Said out loud, because the inherited default says the opposite of what this game does.[/b]
	# [DotDamageRules] defaults `friendly_fire` to false, and a reader who found that here would
	# conclude that a runner cannot hurt another runner.
	var rules := DotDamageRules.new()
	rules.friendly_fire = true
	combat.rules = rules

	add_child(combat)

## The intermission is the pause plus the killcam the clients play inside it, so the server never waits on one.
func apply_intermission(rules: DotMatchRules = null) -> void:
	var target: DotMatchRules = rules if rules != null else (match_node.rules if match_node != null else null)
	if target == null:
		return
	var pause := config.intermission_seconds
	target.intermission_sec = pause + (config.killcam_seconds if pause > 0.0 else 0.0)

func _build_match() -> void:
	match_node = DotMatch.new()
	match_node.name = "Match"
	match_node.register_service = false

	var match_config := DotMatchConfig.new()
	match_config.tick_rate = tick_rate
	match_config.auto_start = false
	match_config.log_transitions = false
	match_node.config = match_config

	var rules := DotRulesElimination.make(config.round_seconds)
	apply_intermission(rules)
	rules.warmup_sec = config.warmup_seconds
	rules.countdown_sec = 0.0
	rules.rounds_to_win = 99
	# [b]One.[/b] dot-match defaults to two because a deathmatch with one player in it is not a match;
	# a round here with one runner and no drivers is a legitimate, if dull, thing for a nearly-empty
	# server to be doing, and the alternative is a server that sits in warmup for ever.
	rules.min_players = 1
	# [b]The rule asks the game who is alive, and that is the seam dot-match is built around.[/b] Being
	# alive is a `DotHealth`, which lives in dot-combat, which dot-match deliberately does not depend
	# on.
	rules.alive_fn = _is_alive
	match_node.rules = rules

	add_child(match_node)

	match_node.round_started.connect(_on_round_started)
	match_node.round_ended.connect(_on_round_ended)

	# So a client's world kept dot-match's default pair, "Red" and "Blue" — nothing read them until the
	# scoreboard asked for a side's name — and so would a server with `track_progress` off or whose
	# tracker failed to attach, with dot-match's balancing and its one-ahead cap back on, which is the.
	var teams: Array[DotTeam] = [
		DotTeam.make(TEAM_DRIVERS, "Drivers", Color(0.92, 0.74, 0.17)),
		DotTeam.make(TEAM_RUNNERS, "Runners", Color(0.35, 0.62, 0.88)),
	]
	match_node.teams.teams = teams
	# [b]And re-indexed, because assigning the list does not.[/b] dot-match fills in its standard pair
	# when it is added to the tree and indexes it on first lookup, and `teams.team(id)` goes on
	# answering from that index: the ids agree (1 and 2), so every rule worked, and the first thing to.
	match_node.teams.reindex()
	# Off: this game balances itself, because the sides are not interchangeable. Two drivers against
	# six runners is the design rather than an imbalance, and a balancer that did not know that would
	# move four people into the buses every round and there are two seats.
	match_node.teams.force_balance = false
	match_node.teams.allow_choice = true
	# [b]And off in the second place dot-match balances, which `force_balance` does not reach.[/b]
	# `max_difference` defaults to 1 and REFUSES any join that puts a side more than one ahead — so on
	# a shipped server the second driver and every runner past the drivers' count plus one were on no.
	match_node.teams.max_difference = 0

## Where a runner who is out looks. See [BfhSpectate]. Not fatal: a world with no
## spectator camera is the world this game had until it existed.
func _build_spectate() -> void:
	spectate = BfhSpectate.new()
	spectate.name = "Spectate"
	add_child(spectate)

	var built: DotResult = spectate.setup_world(self, authoritative, tick_rate)

	if not built.ok:
		DotLog.warn(CHANNEL, "spectating is off", {"why": built.error.message})
		remove_child(spectate)
		spectate.free()
		spectate = null

## Statistics and achievements, on the authority. See [BfhProgress].
func _build_progress() -> void:
	if not authoritative or not track_progress:
		return

	progress = BfhProgress.new()
	progress.name = "Progress"
	add_child(progress)

	var attached: DotResult = progress.attach(self)

	if not attached.ok:
		DotLog.warn(CHANNEL, "progress is off", {"why": attached.error.message})
		remove_child(progress)
		progress.free()
		progress = null
		return

	progress.unlocked.connect(func(player_id: StringName, achievement: DotAchievement) -> void:
		earned.emit(player_id, achievement.display_name, achievement.points)
	)

# --- Players

# --- The round

func start() -> void:
	if not authoritative:
		return

	# [b]The bowl is laid out here and not only on `round_started`, and that is the difference between
	# an empty server and a broken-looking one.[/b] dot-match runs a warmup before the first round, so
	# a world that only furnished itself when a round began sat for the whole warmup as a bare disc.
	_clear_bowl()
	_lay_out_bowl()
	_place_players()
	_place_buses()
	_started = true

	match_node.start(_tick)

func _on_round_started(number: int) -> void:
	round_number = number
	round_elapsed = 0.0

	if config.reseed_each_round:
		# Derived from the configured seed and the round number rather than from a clock, so a server and
		# a replay of it lay the same round out. `hash` would do; this is one multiply and is stable
		# across engine versions, which `hash` on a built-in is not promised to be.
		_layout_seed = config.arena_seed + number * 7919
		random.reseed(_layout_seed)

	_clear_bowl()
	_change_bowl()
	# The toys home before anything is scattered round them.
	if toys != null and authoritative:
		toys.reset()
	_lay_out_bowl()
	_place_players()
	_place_buses()

	# A round is everybody's new body, so nobody who was out is watching any more.
	if spectate != null:
		spectate.on_round_began()

	round_began.emit(number)
	DotLog.info(CHANNEL, "round began", {"number": number, "seed": _layout_seed})

func _on_round_ended(number: int, winner: int, _outcome: int) -> void:
	round_over.emit(number, winner)
	DotLog.info(CHANNEL, "round over", {"number": number, "winner": winner})

	if config.rounds_before_swap > 0 and number % config.rounds_before_swap == 0:
		_swap_sides()

## Swaps every player's side.
func _swap_sides() -> void:
	# [b]Not when nobody driving is a person.[/b] Bots only drive, and the module removes a bot that
	# finds itself on foot, so swapping a server whose seats are all bots put every person in a bus and
	# left nobody to run: the next round never started.
	var person_driving := false
	for driver in drivers():
		if not driver.is_bot:
			person_driving = true
			break

	if not person_driving:
		DotLog.debug(CHANNEL, "sides not swapped: nobody driving is a person", {"round": round_number})
		return

	for id: StringName in sides:
		var was := int(sides[id])
		var now := TEAM_RUNNERS if was == TEAM_DRIVERS else TEAM_DRIVERS
		sides[id] = now

		# [b]dot-match as well, because its elimination rule is what decides the round and it reads teams
		# off its own scoreboard.[/b] Flipping `sides` alone left the rule on the old sides for the rest
		# of the server's life: the drivers ran the new runners down and every such round was.
		var switched := match_node.switch_team(String(id), now, _tick)
		if not switched.ok:
			DotLog.error(CHANNEL, "dot-match refused a side swap", {
				"id": String(id), "team": now, "why": switched.error.message,
			})

		var player: BfhPlayer = players[id]
		if now == TEAM_RUNNERS and player.hammer == null:
			_arm(player)
		elif now == TEAM_DRIVERS:
			player.hammer = null

	sides_swapped.emit(round_number)
	DotLog.info(CHANNEL, "sides swapped", {"round": round_number})

func _clear_bowl() -> void:
	for prop in props.all_props():
		props.remove(prop.instance_id, DotPropSpawner.REASON_CLEANUP)

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null:
			continue

		# [b]Riders out before the bus goes, and nothing else does this for us.[/b] `DotVehicleRide` is a
		# RefCounted holding its own rider index and it does not watch the spawner — so a bus removed
		# underneath somebody leaves the ride still believing they are aboard, and every later `enter` is.
		for rider_id: StringName in bus.occupants.values():
			ride.exit(bus, rider_id, true)

		vehicles.remove(instance_id)

	_bus_ids.clear()
	# Keyed by instance ids that are gone now, and never read again: a slow leak of two
	# entries a round for the life of the server rather than a behaviour, but a leak.
	_bus_stuck.clear()
	_bus_back_forward.clear()
	_bus_hopped.clear()
	_bus_inverted.clear()
	_bus_backing.clear()
	_bus_turning.clear()
	_bus_turn_rest.clear()
	_bus_pinned.clear()

## The map menu's change: [param id] now, not after this round. The next bowl is set and a
## fresh round begins in it (dot-match's `begin_round_now`: the round called off has no
## winner); with no match running yet it is simply built. Authority only.
func change_bowl_now(id: StringName) -> DotResult:
	if not authoritative:
		return DotResult.fail(DotError.CODE_STATE, "Only the server changes the bowl.")
	if not BfhBowls.allowed(config).any(func(b: Dictionary) -> bool: return b["id"] == id) \
			and not workshop_bowls(workshop_index).any(func(b: Dictionary) -> bool: return b["id"] == id):
		return DotResult.fail(DotError.CODE_INVALID, "There is no bowl called '%s' here." % id)
	next_bowl_id = id
	if match_node == null or not match_node.begin_round_now(_tick):
		_change_bowl()
	DotLog.info(CHANNEL, "bowl changed from the map menu", {"bowl": String(id)})
	return DotResult.success(id)

## The bowl the players voted for, built between one round's props going and the next's
## arriving. Once: [member next_bowl_id] is cleared whether or not it was used, and a bowl
## this server no longer offers (an operator narrowed `bowl_ids` since) is dropped.
func _change_bowl() -> void:
	var wanted := next_bowl_id
	next_bowl_id = &""

	if not authoritative:
		return

	# Nobody chose (no ballot, no votes): with a maps.yml the rotation decides, so the bowl a
	# round opens in is never one the file leaves out unless an admin or a vote asked for it.
	if wanted == &"" and has_rotation_file():
		wanted = next_bowl()

	if wanted == &"" or wanted == bowl_id:
		if has_rotation_file():
			_rotation.note_played(bowl_id)
		return

	var offered := false

	for bowl in BfhBowls.allowed(config):
		offered = offered or bowl["id"] == wanted

	var chosen := BfhBowls.by_id(config, wanted)

	if chosen.is_empty():
		for bowl in workshop_bowls(workshop_index):
			if bowl["id"] == wanted:
				chosen = bowl
				offered = true

	if not offered or chosen.is_empty():
		DotLog.warn(CHANNEL, "the voted bowl is not one this server offers; keeping this one",
			{"wanted": String(wanted), "keeping": String(bowl_id)})
		return

	bowl_id = wanted
	if has_rotation_file():
		_rotation.note_played(wanted)
	arena.district = String(chosen.get("district", ""))
	arena.build(float(chosen["radius"]))
	bowl_changed.emit(bowl_id)
	DotLog.info(CHANNEL, "the bowl changed", {"bowl": String(bowl_id), "radius": "%.0f m" % arena.radius})

func _lay_out_bowl() -> void:
	var stream := random.stream(&"bowl")

	if config.scatter_clears_bus_lanes:
		arena.keep_start_lanes(maxi(config.driver_count, 1), config.bus_lane_width, config.bus_lane_length)
	else:
		arena.start_lanes.clear()
	arena.scaffold_keep_out = config.scaffold_scatter_margin

	# The scaffold first, so nothing scattered is in its cells: the scatter keeps out of
	# its footprint, and a block that landed inside it — which one did, before the
	# keep-out — spread the whole staircase half a metre at the first step.
	scaffold_ids.clear()
	for at in arena.scaffold_spawn_points():
		var crate := props.spawn(BfhContent.CRATE, &"world", at)
		if crate != null:
			scaffold_ids.append(crate.instance_id)

	for _i in range(config.crate_count):
		props.spawn(BfhContent.CRATE, &"world", arena.scatter_point(stream, 8.0, 0.6))

	for _i in range(config.barrel_count):
		props.spawn(BfhContent.BARREL, &"world", arena.scatter_point(stream, 10.0, 0.8))

	# A sixth as many blocks as crates, and never fewer than three. The blocks are the
	# floor under the round: whatever the drivers break, this much cover remains.
	var blocks := maxi(config.crate_count / 6, 3)
	for _i in range(blocks):
		props.spawn(BfhContent.BLOCK, &"world", arena.scatter_point(stream, 12.0, 0.5))

func _place_players() -> void:
	var stream := random.stream(&"spawns")

	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if player.health != null:
			player.health.health = config.runner_health
			player.health.alive = true

		_place_one(player, int(sides.get(id, 0)), stream)
		player.set_riding(false)

func _place_buses() -> void:
	var seats := mini(config.driver_count, drivers().size())

	for i in range(maxi(seats, 1)):
		var at := arena.bus_start(i, maxi(seats, 1))

		# [b]Turned to face the bowl, and the default is 180 degrees wrong.[/b] `spawn` orients with
		# `Basis.IDENTITY` unless told otherwise, and identity faces -Z — which from a ledge at the north
		# edge is straight into the wall seven metres behind it.
		var facing := Vector3(-at.x, 0.0, -at.z)
		var orientation := (
			Basis.looking_at(facing.normalized()) if facing.length() > 0.01
			else Basis.IDENTITY
		)

		var bus := vehicles.spawn(BfhContent.BUS, at, &"world", orientation)

		if bus == null:
			DotLog.warn(CHANNEL, "a bus could not be spawned", {"index": i})
			continue

		_bus_ids.append(bus.instance_id)

		var seated := drivers()
		if i < seated.size():
			var driver := seated[i]
			# `on_seated` is what flips the player, not this call site: a rider can also be put down by the
			# ride itself — a destroyed bus, an admin removing one — and a game that only flipped the flag
			# where it seated somebody would leave them frozen in mid-air the one time it mattered.
			ride.enter(bus, driver.player_id, driver, &"driver")

# --- The tick

func _physics_process(delta: float) -> void:
	if not authoritative or match_node == null or external_tick:
		return
	simulate(delta)

## Asked every tick of a world that ticks itself: true while a cover is up (the client's load
## gate). Only the bodies are stepped then, so the bot bus, the toys, the impacts and the round
## clock do not act on anybody in front of a picture. Unset, never held.
var hold_clock: Callable = Callable()

## One simulated tick, counted by this world. What an offline client and the suite use.
func simulate(delta: float) -> void:
	_tick += 1

	if hold_clock.is_valid() and bool(hold_clock.call()):
		_step_bodies_only(delta)
		return

	_step(delta)

## A tick under a cover: the bodies move and settle, nothing else happens. A body the gate has
## frozen skips itself (see [method BfhPlayer.simulate]).
func _step_bodies_only(delta: float) -> void:
	for id: StringName in players:
		var player: BfhPlayer = players[id]
		player.simulate(_tick, delta)

## One simulated tick, numbered by the netcode. What the bridge uses.
func tick_once(tick: int) -> void:
	if match_node == null:
		return

	_tick = tick
	_step(delta_for_tick())

## The step both entry points share.
func _step(delta: float) -> void:
	round_elapsed += delta

	_advance_flashlights()

	for id: StringName in players:
		var player: BfhPlayer = players[id]
		player.input_off = spectate != null and spectate.is_roaming(id)
		player.simulate(_tick, delta)

	if authoritative:
		_advance_toys(delta)

	_drive_buses(delta)
	_check_bus_impacts(delta)

	# After the impacts, so a runner put down this tick has their death camera begin on
	# this tick rather than the next.
	if spectate != null:
		spectate.tick(_tick)

	# [b]A round with one side empty is not a round, and letting the clock run on one is an infinite
	# loop with a scoreboard.[/b] The elimination rule ends a round the moment a side has nobody alive,
	# and a side with nobody *at all* satisfies that on the first tick — so a server holding five.
	if not sides_are_playable():
		return

	match_node.tick(_tick)

## How long a round lasts, from now on: the config AND dot-match's rule.
func set_round_seconds(seconds: float) -> void:
	config.round_seconds = seconds

	if match_node != null and match_node.rules != null:
		match_node.rules.time_limit_sec = seconds

## The fixed step. One place, because three files were about to compute it.
func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))

## Adopts a tick rate, on a client being told what the server runs at.
func set_tick_rate(rate: int) -> bool:
	if rate <= 0 or rate == tick_rate:
		return false

	tick_rate = rate

	for id: StringName in players:
		(players[id] as BfhPlayer).tick_rate = rate

	if match_node != null and match_node.config != null:
		match_node.config.tick_rate = rate

	return true

## Whether there is somebody on each side. See [method simulate].
func sides_are_playable() -> bool:
	var has_driver := false
	var has_runner := false

	for id: StringName in sides:
		match int(sides[id]):
			TEAM_DRIVERS:
				has_driver = true
			TEAM_RUNNERS:
				has_runner = true

	if not authoritative:
		# A client knows the sides from JOIN and TEAM, but not whether the server has decided a round is
		# playable — and the answer is the whole of the HUD's "waiting for both sides" line, which is the
		# only thing telling somebody on an empty server that nothing is broken.
		return remote_playable

	return has_driver and has_runner

# --- Reacting

## Something dot-props broke. A crate is a sound; a barrel's sound is its blast, which
## [signal barrel_exploded] already carries, and a block cannot break.
func _on_prop_broken(prop: DotPropInstance, at: Vector3, _by: StringName) -> void:
	if prop != null and prop.def != null and prop.def.id == BfhContent.CRATE:
		noise.emit(BfhSounds.CRATE_BREAK, at)

# --- Reporting

