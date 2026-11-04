extends "bfh_game_rotation.gd"
## Who is in the bowl: joining and leaving, sides, the hammer's reports, and the numbers `describe` gives.

const BfhContent := preload("bfh_content.gd")
const BfhProgress := preload("bfh_progress.gd")
const BfhSpectate := preload("bfh_spectate.gd")

@export_range(1, 240, 1) var tick_rate: int = 60

var carry: DotPropCarry = null

var _tick: int = 0

## Every world object this game has an id for. See [DotEntityTable].
var entities := DotEntityTable.new()

var match_node: DotMatch = null


## Whether [method start] has laid the bowl out, after which somebody arriving is placed on
## arrival rather than left at the origin until the next round.
var _started: bool = false

var random: DotRandomManager = null

## Somebody is in the world. The bridge answers this by making them an entity.
signal player_added(player_id: StringName)

## And is not any more.
signal player_removed(player_id: StringName)

## dot-team's block rules (`!block`, `!noblock`, `mp_teamblock`), set by the server module or `DotGameClient.add_noblock`. They feed [member body_rules]'s `pair_fn`.
var block_rules: Object = null:
	set(value):
		if block_rules != null and block_rules.is_connected(&"changed", body_rules.refresh):
			block_rules.disconnect(&"changed", body_rules.refresh)
		block_rules = value
		if block_rules != null and block_rules.has_signal(&"changed"):
			block_rules.connect(&"changed", body_rules.refresh)

var round_number: int = 0

## dot-player-controller's body rules, there for dot-team's block rules to feed. Players are never solid to each other here (no hull is built), so it changes nothing physical; `mp_solidplayers` is deliberately not bound.
var body_rules: DotPlayerBodyRules = DotPlayerBodyRules.new()

## The scaffold's crates this round, by prop instance id. A crate of it is an ordinary
## crate in every other respect — it breaks, it is shoved, it counts as cover — and this
## list is only so the round, the suite and `describe` can tell which ones they are.
var scaffold_ids: Array[int] = []

## A hammer went round. [param instance_id] is the prop it landed on, 0 for a miss.
signal swung(player_id: StringName, instance_id: int, broke: bool)

## Somebody was run over or caught a barrel.
signal player_died(player_id: StringName, by: StringName)

## Death reactions: dot-player-char's `sv_ragdoll*` cvars, bound by the module and followed by the client.
## Exaggerated by default so a bus throws what it hits; sv_ragdoll_exaggerate 0 turns it back.
var ragdoll_rules: DotPlayerRagdollRules = _throwing_rules()

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

## Where one person stands at the top of a round, or on arriving during one.
func _place_one(player: BfhPlayer, team: int, stream: DotRandomStream) -> void:
	if team == TEAM_DRIVERS:
		player.global_position = arena.ledge_centre() + Vector3(0.0, 1.0, 0.0)
	else:
		player.global_position = arena.scatter_point(stream, 10.0, 1.2)

	player.controller.state.position = player.global_position
	player.controller.state.velocity = Vector3.ZERO

## Where a runner who is out looks. On every world: the authority decides, a connected
## client's world mirrors what it is told. See [BfhSpectate].
var spectate: BfhSpectate = null

## Statistics and achievements. The authority's only; null on a connected client and
## when [member track_progress] is off. See [BfhProgress].
var progress: BfhProgress = null

## player id -> the tick their horn may next sound. See [method sound_horn].
var _horn_ready: Dictionary = {}

## What the server last said about the numbers a client cannot count for itself.
var remote_cover: int = -1

## And whether the server says there is somebody on each side.
var remote_playable: bool = false

## And the rounds each side has won, `TEAM_*` -> count, as the server's dot-match has them.
## Empty on the authority, which reads its own. See [method rounds_won].
var remote_rounds: Dictionary = {}

## Simulated seconds since the round began. Never a wall clock.
var round_elapsed: float = 0.0

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
