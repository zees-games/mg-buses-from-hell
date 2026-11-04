extends "bfh_game_pilot.gd"

const BfhAmbience := preload("bfh_ambience.gd")
const BfhBowls := preload("bfh_bowls.gd")
const BfhContent := preload("bfh_content.gd")
const BfhReach := preload("bfh_reach.gd")
const BfhVote := preload("bfh_vote.gd")
const BfhProgress := preload("bfh_progress.gd")
const BfhSounds := preload("bfh_sounds.gd")
const BfhSpectate := preload("bfh_spectate.gd")

## The simulation. Headless, authoritative, and the only thing that decides anything.

const CHANNEL := "bfh.game"

const TEAM_DRIVERS := 1
const TEAM_RUNNERS := 2

## Where this world publishes itself, so a module can find it.
const SERVICE := &"bfh_game"

## Snapshots a second. Twenty, against a sixty-tick simulation.
const NET_SNAPSHOT_RATE := 20

## How far a position may be from the origin, in metres, on the wire.
const NET_WORLD_EXTENT := 256.0

## Somebody is in the world. The bridge answers this by making them an entity.
signal player_added(player_id: StringName)

## And is not any more.
signal player_removed(player_id: StringName)

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

## Somebody was run over or caught a barrel.
signal player_died(player_id: StringName, by: StringName)

## A barrel went off. The client draws it; this decides it.
signal barrel_exploded(at: Vector3, radius: float)

## Something in the bowl made a noise worth hearing: one of `BfhSounds.WORLD`, where it happened.
signal noise(id: StringName, at: Vector3)

## A bus touched a runner. [param lethal] is whether they are out, read AFTER the damage
## rather than predicted from the speed — a runner an admin has put in god mode is hit at
## a lethal speed and is not flattened.
signal run_over(player_id: StringName, by: StringName, lethal: bool)

## A hammer went round. [param instance_id] is the prop it landed on, 0 for a miss.
signal swung(player_id: StringName, instance_id: int, broke: bool)

## A bus drove into a prop, at speed or stuck on it. [param by] is its driver, or empty.
signal bus_struck(instance_id: int, by: StringName)

## Somebody earned an achievement. Authority only; see `BfhProgress`.
signal earned(player_id: StringName, title: String, points: int)

## Whether this instance decides anything. A client sets this false.
@export var authoritative: bool = true

@export_range(1, 240, 1) var tick_rate: int = 60

## Whether something else drives the tick.
@export var external_tick: bool = false

## Whether this world counts statistics and achievements. Authority only either way.
@export var track_progress: bool = true

## Whether this world publishes itself under [constant SERVICE].
@export var register_service: bool = true

var props: DotPropSpawner = null
var prop_damage: DotPropDamage = null
var carry: DotPropCarry = null
var combat: DotCombatManager = null
var match_node: DotMatch = null
var random: DotRandomManager = null

## Where a runner who is out looks. On every world: the authority decides, a connected
## client's world mirrors what it is told. See [BfhSpectate].
var spectate: BfhSpectate = null

## dot-player-controller's `mp_forceview`: whether a player may switch to third person (0), or is
## held in first (1) or third (2). Bound by the module (REPLICATED) and followed by a client through
## its link.
var view_rules: DotPlayerViewRules = DotPlayerViewRules.new()

## dot-player-controller's body rules, there for dot-team's block rules to feed. Players are never solid to each other here (no hull is built), so it changes nothing physical; `mp_solidplayers` is deliberately not bound.
var body_rules: DotPlayerBodyRules = DotPlayerBodyRules.new()

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

## dot-team's block rules (`!block`, `!noblock`, `mp_teamblock`), set by the server module or `DotGameClient.add_noblock`. They feed [member body_rules]'s `pair_fn`.
var block_rules: Object = null:
	set(value):
		if block_rules != null and block_rules.is_connected(&"changed", body_rules.refresh):
			block_rules.disconnect(&"changed", body_rules.refresh)
		block_rules = value
		if block_rules != null and block_rules.has_signal(&"changed"):
			block_rules.connect(&"changed", body_rules.refresh)

## Statistics and achievements. The authority's only; null on a connected client and
## when [member track_progress] is off. See [BfhProgress].
var progress: BfhProgress = null

## player id -> the tick their horn may next sound. See [method sound_horn].
var _horn_ready: Dictionary = {}

## player id -> team, for the sides that outlive a round.
var sides: Dictionary = {}

var round_number: int = 0

## Which of [code]BfhBowls[/code] the bowl is. The server's configured radius is
## [constant BfhBowls.DEFAULT].
var bowl_id: StringName = BfhBowls.DEFAULT

## The bowl the next round is played in, set by the players' vote ([code]game/bfh_vote.gd[/code])
## and used once. Empty keeps this one.
var next_bowl_id: StringName = &""

## The Workshop index a solo client points this at (`DotContentIndex.shared()`), so a
## subscribed bowl can be chosen. Null on a server, which plays only its own.
var workshop_index: DotContentIndex = null

## Simulated seconds since the round began. Never a wall clock.
var round_elapsed: float = 0.0

## What the server last said about the numbers a client cannot count for itself.
var remote_cover: int = -1

## And whether the server says there is somebody on each side.
var remote_playable: bool = false

## And the rounds each side has won, `TEAM_*` -> count, as the server's dot-match has them.
## Empty on the authority, which reads its own. See [method rounds_won].
var remote_rounds: Dictionary = {}

var _tick: int = 0

## Whether [method start] has laid the bowl out, after which somebody arriving is placed on
## arrival rather than left at the origin until the next round.
var _started: bool = false

## Every world object this game has an id for. See [DotEntityTable].
var entities := DotEntityTable.new()

## What a dead body does, and which death reactions the server allows: dot-player-char's
## `sv_ragdoll*` cvars, bound by the module (REPLICATED) and followed by a client through its
## link, because the client draws the bodies. Exaggerated by default: a bus throws what it hits, and
## the addon's plain drop would make that a limp fall (sv_ragdoll_exaggerate 0 turns it back).
var ragdoll_rules: DotPlayerRagdollRules = _throwing_rules()

## dot-props' `sv_toys*`, bound by the module (REPLICATED) and followed by a client.
var toy_rules: DotPropToyRules = DotPropToyRules.new()

## The bowl's toys (dot-props' loose ones: beach balls, barrels, a tyre), on a ring the arena works
## out from its build (`BfhArena.toy_placements`), so both ends place the same toys in the same
## order.
var toys: DotPropToyBox = null

## The bowl's toys are about to go (the arena is rebuilt), and are built: what the bridge
## releases and pairs their entities on.
signal toys_clearing()
signal toys_built()

## A toy made a sound, on whichever end draws it.
signal toy_sound(id: StringName, at: Vector3, strength: float)

## The collision bit a loose toy is on (layer 10): nothing else here uses it, and a person's
## motor (layer 1) never collides with it. Buses, crates and the bowl are all on layer 1.
const TOY_LAYER := 1 << 9
var _layout_seed: int = 0
var _bus_ids: Array[int] = []

## The scaffold's crates this round, by prop instance id. A crate of it is an ordinary
## crate in every other respect — it breaks, it is shoved, it counts as cover — and this
## list is only so the round, the suite and `describe` can tell which ones they are.
var scaffold_ids: Array[int] = []


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

## Puts somebody in the world. [param wanted_team] is a TEAM_* constant, or 0 to be placed.
func add_player(
	player_id: StringName,
	display_name: String,
	wanted_team: int = 0,
	samples_input: bool = false,
	bot: bool = false,
) -> BfhPlayer:
	if players.has(player_id):
		return players[player_id]

	var team := wanted_team if wanted_team != 0 else _side_for_new_player()

	var player := BfhPlayer.new()
	player.name = "Player_%s" % String(player_id)
	player.player_id = player_id
	player.display_name = display_name
	player.samples_input = samples_input
	player.is_bot = bot
	player.tick_rate = tick_rate
	# Before `add_child`, because `_ready` is what builds the controller and its tunables.
	player.config = config
	player.mass_kg = config.runner_mass
	player.carry = carry
	add_child(player)

	var opened := entities.open(
		DotEntity.KIND_PLAYER,
		player,
		&"",
		player_id,
		float(_tick) / float(maxi(tick_rate, 1))
	)

	if not opened.ok:
		# A refusal here means this player id is already an entity, which cannot happen -- `add_player`
		# returns early on a duplicate.
		DotLog.error(CHANNEL, "could not open an entity for a player", {
			"id": String(player_id), "why": opened.error.message,
		})

	player.entity_id = (opened.value as DotEntityHandle).id if opened.ok else 0

	var health := DotHealth.new()
	health.name = "Health"
	health.max_health = config.runner_health
	health.health = config.runner_health
	player.add_child(health)
	player.health = health
	combat.register_health(player.entity_id, health)

	health.died.connect(func(damage: DotDamage) -> void: _on_player_died(player, damage))

	players[player_id] = player
	sides[player_id] = team

	var joined := match_node.add_player(String(player_id), display_name, _tick, team)

	if not joined.ok:
		# Not fatal to the join -- they can still move and be seen -- but the round rule
		# cannot count them, which is a round decided without them. Said out loud because
		# the last time this was refused, nothing did.
		DotLog.error(CHANNEL, "dot-match refused a player's side", {
			"id": String(player_id), "team": team, "why": joined.error.message,
		})

	if team == TEAM_RUNNERS:
		_arm(player)

	# [b]Somebody arriving in the middle of a round is placed NOW, not at the next one.[/b]
	# `_place_players` only runs when a round is laid out, so a runner who joined a live server stood
	# where a `CharacterBody3D` starts — the centre of the bowl, on the ramp's line — until the round.
	if authoritative and _started:
		_place_one(player, team, random.stream(&"late_spawns"))

	DotLog.debug(CHANNEL, "player joined", {"id": String(player_id), "team": team})

	# Last, after the hammer and the health: the bridge answers this by building the
	# replicated entity and announcing the join, and an entity built over a half-made
	# player replicates the half.
	apply_pass_through()
	player_added.emit(player_id)

	# After the announcement, because seating fires `ride.entered` and the bridge answers
	# that by writing to the entity it has just built.
	if authoritative and team == TEAM_DRIVERS:
		_seat_in_an_empty_bus(player)

	return player


## Puts a driver who arrived after the buses were placed into one nobody is driving.
func _seat_in_an_empty_bus(player: BfhPlayer) -> void:
	if ride == null or ride.is_riding(player.player_id):
		return

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive() or bus.driver() != &"":
			continue

		ride.enter(bus, player.player_id, player, &"driver")
		return


## Which side somebody new goes on.
func _side_for_new_player() -> int:
	var drivers := 0
	var runners := 0
	for id: StringName in sides:
		if int(sides[id]) == TEAM_DRIVERS:
			drivers += 1
		else:
			runners += 1

	if runners == 0:
		return TEAM_RUNNERS

	return TEAM_DRIVERS if drivers < config.driver_count else TEAM_RUNNERS


func remove_player(player_id: StringName) -> void:
	if not players.has(player_id):
		return

	var player: BfhPlayer = players[player_id]

	if ride != null and ride.is_riding(player_id):
		ride.exit(vehicles.get_vehicle(ride.vehicle_id_of(player_id)), player_id, true)

	# Before the node goes. dot-combat keyed a `DotHealth` on this entity and NOTHING in this game had
	# ever told it to let go -- so every player who had ever joined left a health record behind,
	# pointing at a node freed with them.
	if combat != null and is_instance_valid(combat) and player.entity_id != 0:
		combat.forget(player.entity_id)
		entities.close(player.entity_id, DotEntityTable.REASON_OWNER_LEFT)

	# And dot-match, which kept counting them as present: towards `min_players`, and on
	# the side they left from. Their scoreboard record stays, which is dot-match's own rule.
	if match_node != null:
		match_node.remove_player(String(player_id))

	players.erase(player_id)
	if block_rules != null:
		block_rules.call(&"forget", player_id)
	apply_pass_through()
	sides.erase(player_id)
	_horn_ready.erase(player_id)
	player.queue_free()

	# After the roster has dropped them: dot-spectate picks a new target for anybody who
	# was watching them from the participants, and before the erase that is the leaver.
	if spectate != null:
		spectate.on_leave(player_id)

	player_removed.emit(player_id)


## Hands a runner their hammer and listens to it.
func _arm(player: BfhPlayer) -> void:
	player.give_hammer(config)

	var id := player.player_id
	player.hammer.hit.connect(func(instance_id: int, at: Vector3, broke: bool) -> void:
		_on_hammer_hit(id, instance_id, at, broke))
	player.hammer.missed.connect(func(_at: Vector3) -> void:
		_on_hammer_missed(id))


func _on_hammer_hit(player_id: StringName, instance_id: int, at: Vector3, broke: bool) -> void:
	var player: BfhPlayer = players.get(player_id)

	if player != null:
		noise.emit(BfhSounds.HAMMER_SWING, player.eye_position())

	noise.emit(BfhSounds.HAMMER_HIT, at)

	# Moved rather than broken, and only if it CAN move: a block takes the blow and stays
	# exactly where it was, and a scrape from one would be a sound saying the opposite.
	var prop := props.get_prop(instance_id) if props != null else null
	if not broke and prop != null and prop.def != null and prop.def.id != BfhContent.BLOCK \
			and prop.body() != null:
		noise.emit(BfhSounds.CRATE_SHOVE, prop.body().global_position)

	swung.emit(player_id, instance_id, broke)


func _on_hammer_missed(player_id: StringName) -> void:
	var player: BfhPlayer = players.get(player_id)

	if player != null:
		noise.emit(BfhSounds.HAMMER_SWING, player.eye_position())

	swung.emit(player_id, 0, false)


## A driver's horn. The swing button, for somebody whose only weapon is the bus.
func sound_horn(player: BfhPlayer) -> bool:
	if player == null or not player.riding or player.ridden == null \
			or not is_instance_valid(player.ridden):
		return false

	if int(_horn_ready.get(player.player_id, 0)) > _tick:
		return false

	var interval := config.bot_horn_seconds if player.is_bot else config.horn_seconds
	_horn_ready[player.player_id] = _tick + int(interval * float(maxi(tick_rate, 1)))
	noise.emit(BfhSounds.BUS_HORN, player.ridden.global_position)
	return true


## Flips a player between walking and driving. Called by the ride, never directly.
func _set_riding(
	player_id: StringName, value: bool, at: Vector3 = Vector3.ZERO,
	vehicle: DotVehicleInstance = null
) -> void:
	var player: BfhPlayer = players.get(player_id)
	if player == null:
		return

	player.set_riding(value)

	# Where the driver is DRAWN from now on, because their own position stops meaning
	# anything the moment they sit down. See [member BfhPlayer.ridden].
	if value and vehicle != null:
		player.ridden = vehicle.body()

	if not value and at != Vector3.ZERO:
		player.global_position = at
		player.controller.state.position = at


func team_of(player_id: StringName) -> int:
	return int(sides.get(player_id, 0))


## The side id dot-team's block rules compare ("" for none): drivers pass drivers and runners pass runners under `mp_teamblock 0`.
func team_of_side(player_id: Variant) -> Variant:
	var side := team_of(StringName(str(player_id)))
	return str(side) if side > 0 else ""


## Hands every controller the bodies it passes through under `block_rules`; the same call on every machine, or a client predicts a wall.
func apply_pass_through() -> void:
	var entries := {}
	for id: Variant in players:
		var who := players[id] as BfhPlayer
		if who != null and who.controller != null:
			entries[id] = {"body": who, "controller": who.controller}
	body_rules.apply_exceptions(entries)


## Puts the config's bus feel onto the catalogue's bus, for buses built from now on.
func refresh_bus_feel() -> void:
	var def := vehicles.catalogue.get_vehicle(BfhContent.BUS) if vehicles != null and vehicles.catalogue != null else null
	if def != null and def.tunables != null:
		BfhContent.apply_bus_feel(def.tunables, config)


func runners() -> Array[BfhPlayer]:
	return _players_on(TEAM_RUNNERS)


func drivers() -> Array[BfhPlayer]:
	return _players_on(TEAM_DRIVERS)


func _players_on(team: int) -> Array[BfhPlayer]:
	var out: Array[BfhPlayer] = []
	for id: StringName in players:
		if int(sides.get(id, 0)) == team:
			out.append(players[id])
	return out


func _is_alive(key: String) -> bool:
	var player: BfhPlayer = players.get(StringName(key))
	return player != null and player.health != null and player.health.alive


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


## Where one person stands at the top of a round, or on arriving during one.
func _place_one(player: BfhPlayer, team: int, stream: DotRandomStream) -> void:
	if team == TEAM_DRIVERS:
		player.global_position = arena.ledge_centre() + Vector3(0.0, 1.0, 0.0)
	else:
		player.global_position = arena.scatter_point(stream, 10.0, 1.2)

	player.controller.state.position = player.global_position
	player.controller.state.velocity = Vector3.ZERO


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

## Whether a player's client is still behind its loading cover: `func(player_key: StringName) -> bool`.
## The server module fills it from dot-game's roster; unset (offline, a suite, a bot) nobody is
## loading, so every offline suite is unchanged. A covered client froze itself and cannot see.
var loading_fn: Callable = Callable()


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


# --- Toys

func _build_toys() -> void:
	if toys != null:
		toys_clearing.emit()
		remove_child(toys)
		toys.queue_free()
		toys = null
	toys = DotPropToyBox.new()
	toys.name = "Toys"
	toys.authoritative = authoritative
	toys.rules = toy_rules
	toys.gravity = 20.0
	toys.kill_y = -30.0
	toys.loose_layer = TOY_LAYER
	toys.loose_mask = 1 | TOY_LAYER
	toys.solid_layer = 1
	toys.solid_mask = 1
	toys.footprint_layer = 0
	toys.aim_mask = 1 | TOY_LAYER
	add_child(toys)
	var built := toys.build(arena.toy_placements())
	if not built.ok:
		DotLog.warn(CHANNEL, "the bowl's toys would not build", {"why": built.error.message})
	var _sounds := toys.sound.connect(func(id: StringName, at: Vector3, strength: float) -> void: toy_sound.emit(id, at, strength))
	toys_built.emit()


## Everybody against the toys after they moved: a walk into a ball sends it on. Buses and crates
## meet them in the solver; a person, whose motor never sees them, through this. Server side.
func _advance_toys(delta: float) -> void:
	if toys == null or toys.count() == 0:
		return
	for id: StringName in players:
		var player: BfhPlayer = players[id]
		if player.riding or (player.health != null and not player.health.alive):
			continue
		var state := player.controller.state
		var tunables := player.controller.tunables
		var radius := tunables.radius if tunables != null else 0.35
		var height := lerpf(tunables.stand_height, tunables.crouch_height, state.crouch_fraction) if tunables != null else 1.8
		var _pushed := toys.push_from(state.position, state.velocity, radius, height)
	toys.advance(delta)


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


## A bus that touched somebody, and what that costs them.
func _check_bus_impacts(delta: float) -> void:
	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			continue

		var body := bus.body()
		if body == null:
			continue

		var bus_velocity := bus.velocity()
		var driver_id := driver_of(instance_id)
		var roof := _roof_of(body)

		for id: StringName in players:
			var player: BfhPlayer = players[id]

			if player.riding or player.health == null or not player.health.alive:
				continue
			if int(sides.get(id, 0)) == TEAM_DRIVERS:
				continue

			var offset := player.global_position - body.global_position
			# A crude bound rather than a physics contact: the bus is a 2.5 x 2.6 x 9 box and this is the
			# sphere around it. Deliberately generous, because a miss that should have been a hit is the
			# complaint this game would actually get, and a hit is checked against closing speed anyway.
			if offset.length() > 4.2:
				continue

			# [b]And nothing above the roof, which the sphere cannot tell.[/b] A sphere round a box that is
			# wider than it is tall reaches over the top of it: a runner standing three crates up, with a bus
			# driving past the foot of the stack, was 3.2 m from its centre and killed — by a vehicle whose.
			if player.global_position.y > roof + BUS_ROOF_MARGIN:
				continue

			# [b]Along the offset, not against it.[/b] `offset` runs from the bus to the player, so a bus
			# moving toward them has a POSITIVE component along it.
			var closing := (bus_velocity - player.controller.state.velocity).dot(
				offset.normalized()
			)

			if closing < 1.0:
				continue

			_bus_hit(player, driver_id, closing, offset)

		_break_props_under(bus, bus_velocity.length(), driver_id)
		_unstick(bus, driver_id, delta)
		_upright(bus, delta)


## The top of a bus's hull in world height, from its own collider.
func _roof_of(body: Node3D) -> float:
	var hull := body.get_node_or_null(^"Collision") as CollisionShape3D
	if hull == null or not (hull.shape is BoxShape3D):
		return body.global_position.y + 3.0
	var top := hull.position + Vector3(0.0, (hull.shape as BoxShape3D).size.y * 0.5, 0.0)
	return (body.global_transform * top).y


## How far above the roof a runner's feet can be and still be hit: a bus bouncing on
## its springs, and a runner a few centimetres off the crate they are running across.
const BUS_ROOF_MARGIN := 0.25


## Whether [param player] is behind a loading cover and so may not be hurt. Only the two
## hazards (a bus, a barrel's blast) ask; an admin's slay or slap goes straight to dot-combat.
func is_loading(player: BfhPlayer) -> bool:
	return loading_fn.is_valid() and bool(loading_fn.call(player.player_id))


func _bus_hit(player: BfhPlayer, by: StringName, closing: float, offset: Vector3) -> void:
	# Before the damage, the knock and the sound: a hit that did not happen leaves no trace.
	if is_loading(player):
		return

	var lethal := closing >= config.bus_lethal_speed
	var amount := config.runner_health * 2.0 if lethal else closing * config.bus_bump_damage

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	var damage := DotDamage.make(attacker, player.entity_id, amount, null)
	damage.point = player.global_position
	damage.direction = offset.normalized()
	# What killed them, for how the body falls (`decide_death`): a bus throws it.
	damage.context = {"why": KILLED_BY_BUS}
	combat.apply_damage(damage)

	# Whether it put them down, from the health rather than from `lethal`: a runner in an
	# admin's god mode is hit at a killing speed and is not out, and a sound or a statistic
	# that said otherwise would be describing a different game from the one on screen.
	var down := player.health != null and not player.health.alive
	run_over.emit(player.player_id, by, down)
	noise.emit(BfhSounds.RUNNER_DOWN if down else BfhSounds.RUNNER_HIT, player.global_position)

	# Knocked away whether or not it killed them, because a bus that passes through
	# somebody standing still and leaves them standing still is the one thing in this
	# game that would look broken from every angle.
	player.controller.state.velocity += offset.normalized() * closing * 0.6



func _break_props_under(bus: DotVehicleInstance, speed: float, by: StringName) -> void:
	if speed < 4.0 or prop_damage == null:
		return

	var body := bus.body()
	var into_bus := body.global_transform.affine_inverse()

	for prop in props.all_props():
		if not prop.is_alive():
			continue

		var prop_body := prop.body()
		if prop_body == null:
			continue

		var local := into_bus * prop_body.global_position

		if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
			continue

		# Vertically too, or a bus passing under a ledge takes out whatever is standing
		# on top of it.
		if absf(local.y) > 2.5:
			continue

		# Before the impact, which may break it: whoever put this crate here is credited
		# with the bus finding it, whether or not it survives the finding.
		bus_struck.emit(prop.instance_id, by)
		prop_damage.impact(prop.instance_id, speed, by)


## Instance ids that have hopped in this stuck spell; forgotten once the bus moves.
var _bus_hopped: Dictionary = {}


## Instance id -> `{at, held}`: where a bus asking for throttle was last clear of, and for how long.
var _bus_pinned: Dictionary = {}


## A bus that is throttling and going nowhere, and what to do about it.
func _unstick(bus: DotVehicleInstance, by: StringName, delta: float) -> void:
	var asking := bus.command != null and absf(bus.command.throttle) > 0.3
	var moving := bus.speed() > 1.0

	# [b]Rocking in place is not moving.[/b] The back-off reverses and goes forward again, and each
	# lurch passes 1 m/s and restarts the clock below, so a bus wedged among crates in a street
	# shuffled within three metres for 20 s without ever being caught (hill town).
	var pin: Dictionary = _bus_pinned.get(bus.instance_id, {})
	var here := bus.position()
	if pin.is_empty() or not asking or here.distance_to(pin["at"]) > config.bus_pinned_radius:
		pin = {"at": here, "held": 0.0}
	else:
		pin["held"] = float(pin["held"]) + delta
	_bus_pinned[bus.instance_id] = pin
	var pinned := float(pin["held"]) >= config.bus_pinned_seconds
	if pinned:
		moving = false

	if not asking or moving:
		_bus_stuck.erase(bus.instance_id)
		_bus_hopped.erase(bus.instance_id)
		return

	var held := float(_bus_stuck.get(bus.instance_id, 0.0)) + delta
	if pinned:
		held = maxf(held, config.bus_stuck_reset_seconds)
	_bus_stuck[bus.instance_id] = held

	if held < config.bus_stuck_break_seconds:
		return

	# Whatever is under it, at any speed. This is the one place the closing-speed rule
	# is deliberately not applied: the bus is not hitting the crate, it is sitting on it.
	if prop_damage != null:
		var into_bus := bus.body().global_transform.affine_inverse()
		for prop in props.all_props():
			if not prop.is_alive() or prop.body() == null:
				continue
			var local := into_bus * prop.body().global_position
			if absf(local.x) > BUS_HALF_WIDTH or absf(local.z) > BUS_HALF_LENGTH:
				continue
			if absf(local.y) > 2.5:
				continue
			bus_struck.emit(prop.instance_id, by)
			prop_damage.break_now(prop.instance_id, by)

	# [b]Before the start line, a short hop back the way it came.[/b] A bus sitting on a concrete block
	# (it cannot be broken or pushed, so the rule above has nothing to remove) is high-centred in both
	# directions, and the back-off rocking cannot lift it.
	var hop_at := minf(config.bus_stuck_hop_seconds, config.bus_stuck_reset_seconds * 0.5)
	if held >= hop_at and not _bus_hopped.has(bus.instance_id):
		_bus_hopped[bus.instance_id] = true
		var behind := bus.body().global_basis.z
		behind.y = 0.0
		if behind.length() > 0.01 and bus.body().global_basis.y.y > 0.5:
			var hop_body := bus.body()
			hop_body.linear_velocity = Vector3.ZERO
			hop_body.angular_velocity = Vector3.ZERO
			hop_body.global_position += behind.normalized() * config.bus_stuck_hop_metres + Vector3.UP * 0.4
			DotLog.debug(CHANNEL, "a stuck bus hopped back", {"stuck_for": held})
			return

	if held < config.bus_stuck_reset_seconds:
		return

	var index := maxi(_bus_ids.find(bus.instance_id), 0)
	var at := arena.bus_start(index, maxi(_bus_ids.size(), 1))
	var facing := Vector3(-at.x, 0.0, -at.z)

	var body := bus.body()
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01 else Basis.IDENTITY,
		at,
	)

	_bus_stuck.erase(bus.instance_id)
	_bus_pinned.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was put back on its start line", {"stuck_for": held})


## Seconds a bus may lie on its roof before it is rolled back over.
const INVERTED_RIGHT_SEC := 2.0

## Instance id -> seconds this bus has been upside down.
var _bus_inverted: Dictionary = {}


## A bus that has rolled over, and why it is not left there.
func _upright(bus: DotVehicleInstance, delta: float) -> void:
	if not bus.is_inverted():
		_bus_inverted.erase(bus.instance_id)
		return

	var held := float(_bus_inverted.get(bus.instance_id, 0.0)) + delta
	_bus_inverted[bus.instance_id] = held

	if held < INVERTED_RIGHT_SEC:
		return

	var body := bus.body()

	if body == null:
		return

	# The heading, flattened. `global_basis.z` on an upside-down body still points the way
	# the bus was facing; what has to go is the roll and the pitch around it.
	var facing := -body.global_basis.z
	facing.y = 0.0

	var orientation := (
		Basis.looking_at(facing.normalized()) if facing.length() > 0.01
		else Basis.IDENTITY
	)

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		orientation, body.global_position + Vector3(0.0, 1.0, 0.0)
	)

	_bus_inverted.erase(bus.instance_id)
	DotLog.info(CHANNEL, "a bus was rolled back onto its wheels", {"upside_down_for": held})


## Who is driving the bus with this instance id, or an empty name.
func driver_of(instance_id: int) -> StringName:
	for id: StringName in players:
		if ride.vehicle_id_of(id) == instance_id:
			return id
	return &""


# --- Reacting

## A barrel went off. dot-props described the blast; this is what it does to people.
func _on_prop_exploded(
	at: Vector3, radius: float, damage_amount: float, force: float, by: StringName
) -> void:
	barrel_exploded.emit(at, radius)

	var attacker := 0
	if players.has(by):
		attacker = (players[by] as BfhPlayer).entity_id

	for id: StringName in players:
		var player: BfhPlayer = players[id]

		if player.health == null or not player.health.alive or player.riding or is_loading(player):
			continue

		var offset := player.global_position - at
		var distance := offset.length()

		if distance > radius:
			continue

		var falloff := 1.0 - (distance / radius)
		var damage := DotDamage.make(
			attacker, player.entity_id, damage_amount * falloff, null
		)
		damage.point = player.global_position
		damage.direction = offset.normalized() if distance > 0.01 else Vector3.UP
		damage.context = {"why": KILLED_BY_BARREL}
		combat.apply_damage(damage)

		# Thrown, and a barrel is the only thing in the game that throws a runner UPWARD — two metres from
		# the hammer's reach, past any jump, which is why a barrel is worth standing near as well as away
		# from. See docs/map.md, "What a runner can climb".
		var push := damage.direction * force * falloff * 0.004
		push.y = 0.0
		var state := player.controller.state
		state.velocity += push
		state.velocity.y = maxf(
			state.velocity.y, BfhReach.launch_speed(config.gravity, config.barrel_lift_height * falloff)
		)
		# [b]And off the ground, or none of that survives the tick.[/b] A velocity added to a runner the
		# motor still has as GROUND is snapped back onto the sand before it moves them — which is what
		# this did for nine days, and a barrel lifted people 7 cm.
		state.mode = DotFpsState.Mode.AIR
		state.time_since_grounded = 1000.0


## What a lethal hit was, on [member DotDamage.context] as `why`: run over, or thrown by a blast.
const KILLED_BY_BUS := &"bus"
const KILLED_BY_BARREL := &"barrel"


func _throwing_rules() -> DotPlayerRagdollRules:
	var rules := DotPlayerRagdollRules.new()
	rules.exaggerate = true
	return rules


## The fall a death gets: dot-player-char's reaction rule over the server's weights, seeded from the
## player and the tick.
func decide_death(player: BfhPlayer, damage: DotDamage) -> DotPlayerDeath:
	var why: StringName = damage.context.get("why", &"")
	var thrown := why == KILLED_BY_BUS or why == KILLED_BY_BARREL
	return DotPlayerDeath.decide(
		ragdoll_rules.reactions(), damage.is_headshot(), damage.amount, damage.direction,
		DotPlayerDeath.seed_of(player.entity_id, _tick), null,
		1.0 if thrown else 0.0, DotPlayerDeathReactions.POWER_LAUNCH if thrown else &""
	)


func _on_player_died(player: BfhPlayer, damage: DotDamage) -> void:
	# One dictionary read. This walked every player on the server comparing ints, which is the reverse
	# index [DotEntityTable] keeps so nobody has to -- and it ran on every death, which on this game is
	# a lot of them.
	var by := entities.key_for_id(damage.attacker)

	# How the body falls, picked once, here, and carried on DEATH to every client.
	if authoritative:
		player.death = decide_death(player, damage)

	player_died.emit(player.player_id, by)
	DotLog.debug(CHANNEL, "player died", {"id": String(player.player_id), "by": String(by)})

	if spectate != null:
		spectate.on_death(player.player_id, player.global_position, by, _tick)


## Something dot-props broke. A crate is a sound; a barrel's sound is its blast, which
## [signal barrel_exploded] already carries, and a block cannot break.
func _on_prop_broken(prop: DotPropInstance, at: Vector3, _by: StringName) -> void:
	if prop != null and prop.def != null and prop.def.id == BfhContent.CRATE:
		noise.emit(BfhSounds.CRATE_BREAK, at)


# --- Reporting

func alive_runners() -> int:
	var count := 0
	for player in runners():
		if player.health != null and player.health.alive:
			count += 1
	return count


## Rounds [param team] has won this match, which is what dot-match scores here.
func rounds_won(team: int) -> int:
	if not authoritative:
		return int(remote_rounds.get(team, 0))
	if match_node == null:
		return 0
	return int(match_node.rounds_won.get(team, 0))


func crates_left() -> int:
	if not authoritative and remote_cover >= 0:
		return remote_cover

	var count := 0
	for prop in props.all_props():
		if prop.is_alive() and prop.def != null and prop.def.id == BfhContent.CRATE:
			count += 1
	return count


## How many of the scaffold's crates are still there. Broken ones are gone; shoved ones
## still count, because a crate knocked off the top is still a crate somebody can climb.
func scaffold_standing() -> int:
	var count := 0
	for id in scaffold_ids:
		var prop := props.get_prop(id)
		if prop != null and prop.is_alive():
			count += 1
	return count


func describe() -> Dictionary:
	return {
		"round": round_number,
		"elapsed": "%.0f s" % round_elapsed,
		"players": players.size(),
		"runners_alive": alive_runners(),
		"crates": crates_left(),
		"scaffold": "%d of %d standing" % [scaffold_standing(), scaffold_ids.size()],
		"props": props.world_count() if props != null else 0,
		"buses": _bus_ids.size(),
		"gravity": "%.1f m/s2" % config.gravity,
		"bus_at": _bus_report(),
		"watching": spectate.manager.viewers().size() if spectate != null else 0,
		"counted": progress.describe()["players"] if progress != null else 0,
	}


## Where each bus is and how fast, for a console dump and a bug report.
func _bus_report() -> String:
	var parts := PackedStringArray()

	for instance_id in _bus_ids:
		var bus := vehicles.get_vehicle(instance_id)
		if bus == null or not bus.is_alive():
			parts.append("gone")
			continue

		var at := bus.position()

		# Wheels on the ground, because a vehicle with none is not a vehicle that is
		# broken — it is a vehicle that is airborne, and the two are the same picture.
		var grounded := 0
		var wheels := 0
		var body := bus.body()
		if body != null:
			for child in body.get_children():
				var wheel := child as VehicleWheel3D
				if wheel == null:
					continue
				wheels += 1
				if wheel.is_in_contact():
					grounded += 1

		var vb := body as VehicleBody3D
		var drive_line := ""
		if vb != null:
			drive_line = " engine=%.0f steer=%.2f thr=%.2f frz=%s slp=%s m=%.0f v=%s" % [
				vb.engine_force, vb.steering,
				bus.command.throttle if bus.command != null else 0.0,
				vb.freeze, vb.sleeping, vb.mass, str(vb.linear_velocity),
			]

		parts.append("(%.1f, %.1f, %.1f) %.1f m/s %d/%d wheels down" % [
			at.x, at.y, at.z, bus.speed(), grounded, wheels,
		] + drive_line + (" INVERTED" if bus.is_inverted() else ""))

	return ", ".join(parts) if not parts.is_empty() else "none"


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("buses-from-hell, round %d" % round_number)
	var facts := describe()
	for key: String in facts:
		lines.append("  %-16s %s" % [key, facts[key]])
	return lines
