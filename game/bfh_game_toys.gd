extends "bfh_game_hazards.gd"
## The bowl's loose toys: built from the arena's ring, pushed by the people who walk into them.

## dot-props' `sv_toys*`, bound by the module (REPLICATED) and followed by a client.
var toy_rules: DotPropBodyRules = DotPropBodyRules.new()

## The bowl's toys (dot-props' loose ones: beach balls, barrels, a tyre), on a ring the arena works
## out from its build (`BfhArena.toy_placements`), so both ends place the same toys in the same
## order.
var toys: DotPropBodyBox = null

## The bowl's toys are about to go (the arena is rebuilt), and are built: what the bridge
## releases and pairs their entities on.
signal toys_clearing()
signal toys_built()

## A toy made a sound, on whichever end draws it.
signal toy_sound(id: StringName, at: Vector3, strength: float)

## The collision bit a loose toy is on (layer 10): nothing else here uses it, and a person's
## motor (layer 1) never collides with it. Buses, crates and the bowl are all on layer 1.
const TOY_LAYER := 1 << 9

func _build_toys() -> void:
	if toys != null:
		toys_clearing.emit()
		remove_child(toys)
		toys.queue_free()
		toys = null
	toys = DotPropBodyBox.new()
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
