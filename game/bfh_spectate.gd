extends DotSpectatorHost

const BfhPlayer := preload("bfh_player.gd")

## Where a runner who has been run down looks until the next round: [DotSpectatorHost] with this game's numbers and a bus's cab for a driver's eyes.

const CHANNEL := "bfh.spectate"

## What a spectator can ask for. Also the wire format of `BfhEvents.Ask.WATCH`.
const ASK_NEXT := 0
const ASK_PREVIOUS := 1
const ASK_VIEW := 2
## The free-camera key: into one, or back onto a player. The fourth value of the two bits.
const ASK_ROAM := 3

## Where a driver's view is, in their bus's own frame: over the cab roof, behind the container its forks carry out front.
const CAB_EYE := Vector3(0.0, 3.8, -1.2)

## And pitched down the road rather than at the horizon, which is where the runners are.
const CAB_PITCH_DEG := -14.0

## Seconds of death camera: from where they fell, looking at the bus that did it.
const DEATH_CAM_SEC := 1.0

## Seconds of freeze camera: from the cab of the bus that did it.
const FREEZE_CAM_SEC := 2.0

var _world: Node3D = null


func _init() -> void:
	death_cam_seconds = DEATH_CAM_SEC
	freeze_cam_seconds = FREEZE_CAM_SEC
	# Far enough back that a runner is a figure in a scene and a bus, nine metres in front of its own cab, is behind the camera's subject.
	chase_distance = 7.0
	chase_height = 2.5
	history_seconds = 0.0
	eye_height = BfhPlayer.EYE_HEIGHT
	guard_roam = true


## Builds the manager. [param is_authority] false builds a mirror.
func setup_world(world: Node3D, is_authority: bool, rate: int) -> DotResult:
	_world = world
	authoritative = is_authority
	tick_rate = rate

	var built := setup()
	if not built.ok:
		return built.wrap("spectating")

	# INFO because it is the policy an admin is asked about.
	if authoritative:
		DotLog.info(CHANNEL, "spectating is set up", {
			"watch_anybody": manager.rules.force_camera == 0,
			"roaming": manager.rules.allow_roaming,
			"death_cam_ticks": manager.rules.death_cam_ticks,
			"freeze_cam_ticks": manager.rules.freeze_cam_ticks,
		})

	return DotResult.success(self)


func _channel() -> String:
	return CHANNEL


func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	r.force_camera = 0
	r.allow_while_alive = false
	r.allow_while_dead = true
	r.allow_unassigned = true
	# allow_roaming stays at the family default and follows `mp_freeroam`; hardcoding it here would be overwritten when the module binds the cvar.
	r.cycle_includes_dead = false
	r.auto_retarget = true
	r.delay_ticks = 0
	return r


func _players() -> Dictionary:
	return _world.get("players") as Dictionary if _world != null else {}


## Every player, sorted by key so "next" is stable.
func _participants() -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = _players().keys()
	ids.sort()
	for id: Variant in ids:
		out.append(String(id))
	return out


func _is_alive(key: String) -> bool:
	var player: BfhPlayer = _players().get(StringName(key))
	return player != null and (player.health == null or player.health.alive)


func _team_of(key: String) -> int:
	return int((_world.get("sides") as Dictionary).get(StringName(key), 0)) if _world != null else 0


func _pose_of(key: String) -> Transform3D:
	return pose_of(key)


## Where somebody's eyes are: a runner's, or a driver's bus's cab.
func pose_of(key: String) -> Transform3D:
	var player: BfhPlayer = _players().get(StringName(key))

	if player == null or player.controller == null:
		return Transform3D.IDENTITY

	if player.riding and player.ridden != null and is_instance_valid(player.ridden):
		var bus := player.ridden.global_transform
		var yaw := atan2(-bus.basis.z.x, -bus.basis.z.z)
		var cab := Basis.from_euler(Vector3(deg_to_rad(CAB_PITCH_DEG), yaw, 0.0))
		return Transform3D(cab, bus * CAB_EYE)

	var state := player.controller.state
	return eye_pose(state.position, state.pitch, state.yaw)


# --- What the world reports

## The world ticked. Runs the death camera's hand-overs and moves anybody whose target
## went away. A mirror's is a no-op inside dot-spectate.
func tick(tick_number: int) -> void:
	advance(tick_number)


## Somebody is out. The chain starts: where they fell, then who did it, then somebody.
func on_death(player_id: StringName, at: Vector3, by: StringName, tick_number: int) -> void:
	if manager == null or not authoritative:
		return

	death(String(player_id), at, String(by), tick_number)

	# DEBUG: a transition. "My camera went somewhere odd when I was run over" is answered by
	# who it was put on.
	DotLog.debug(CHANNEL, "a runner who is out is watching", {
		"player": String(player_id), "killer": String(by), "view": describe_view(player_id),
	})


## A round began: everybody has a new body, so nobody is watching.
func on_round_began() -> void:
	if manager == null or not authoritative:
		return

	for key in manager.viewers():
		spawned(key)


## Somebody left. Call AFTER the world has dropped them, so a spectator who was watching
## them is moved to somebody who is still there — dot-spectate chooses the replacement from
## the participants, and a world that reported first would have it pick the leaver.
func on_leave(player_id: StringName) -> void:
	left(String(player_id))


# --- What a spectator asks

## A click, on the authority. [param ask] is one of the ASK_* constants.
func request(player_id: StringName, ask: int) -> DotResult:
	if manager == null:
		return DotResult.fail(DotError.CODE_STATE, "Spectating is not set up.")
	if not authoritative:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "A client asks the server; it does not decide.")

	var key := String(player_id)

	match ask:
		ASK_NEXT:
			return manager.next_target(key)
		ASK_PREVIOUS:
			return manager.previous_target(key)
		ASK_VIEW:
			var view := manager.view(key)
			if not view.follows_target() or view.is_timed():
				return DotResult.fail(
					DotError.CODE_STATE, "There is nobody to change the view of yet."
				)
			var wanted := (
				DotSpectatorView.Mode.CHASE if view.mode == DotSpectatorView.Mode.FIRST_PERSON
				else DotSpectatorView.Mode.FIRST_PERSON
			)
			return manager.set_mode(key, wanted)

		ASK_ROAM:
			return toggle_roam(key)

	return DotResult.fail(DotError.CODE_INVALID, "Unknown spectator request %d." % ask)


## Who they are looking at: the target, or on a death camera the killer it looks at.
func target_of(player_id: StringName) -> StringName:
	if not is_spectating(player_id):
		return &""

	var view := manager.view(String(player_id))

	if view.mode == DotSpectatorView.Mode.DEATH_CAM:
		return StringName(view.killer)

	return StringName(view.target)


## A mirror is told its own view. [param target] is who [method target_of] would answer.
func adopt(player_id: StringName, mode: int, target: StringName) -> void:
	if manager == null or authoritative:
		return

	var key := String(player_id)
	var view := manager.view(key)
	var was_watching := view.is_watching()

	if mode <= 0 or mode >= DotSpectatorView.Mode.size():
		if was_watching:
			manager.stop(key)
		return

	if not was_watching:
		var player: BfhPlayer = _players().get(player_id)
		if player != null and player.controller != null:
			view.death_position = player.controller.state.position

	var as_mode := mode as DotSpectatorView.Mode
	var wire := {"m": mode, "t": "", "k": "", "u": -1}

	if as_mode == DotSpectatorView.Mode.DEATH_CAM:
		wire["k"] = String(target)
	elif as_mode == DotSpectatorView.Mode.FREEZE_CAM:
		wire["k"] = String(target)
		wire["t"] = String(target)
	else:
		wire["t"] = String(target)

	manager.apply_wire({"k": key, "v": wire})


func describe_view(player_id: StringName) -> String:
	if not is_spectating(player_id):
		return "playing"

	return "%s %s" % [
		DotSpectatorView.Mode.keys()[mode_of(player_id)], String(target_of(player_id))
	]
