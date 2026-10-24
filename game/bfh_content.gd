extends RefCounted

const BfhConfig := preload("bfh_config.gd")
const BfhPaths := preload("bfh_paths.gd")

## The two catalogues: what can be in the bowl, and what can be driven at it.
##
## [b]Three props and one vehicle, and the whole game is in their numbers.[/b] A crate
## is breakable by a hammer and by a bus and is something to stand on; a barrel is
## breakable by anything and takes whoever is near it with it; a block is neither and
## exists so there is somewhere a bus cannot follow. Every one of those is a field on
## [DotPropDef] rather than a script, which is what lets a server retune the game by
## editing JSON — and what lets the suite assert the design instead of the code.

## Where the three bodies live, as this game was authored.
##
## [b]Rebased where they are defined, so no use of them can forget to.[/b] A delivered
## pack mounts at `res://dot_cloud/<id>/<version>/`, so an absolute path to this game's OWN
## files resolves against the host project root — which holds another game's props, or
## nothing. Rebasing returns these unchanged in a build and the mounted path in a pack,
## which is one form that is right in both. They were `const`s rebased at every call site,
## which was correct and was also one new call site away from not being: `static var` is
## the only spelling that can hold the rebased value, because a `const` cannot call.
static var CRATE_SCENE := BfhPaths.rebase("res://props/bfh_crate.tscn")
static var BARREL_SCENE := BfhPaths.rebase("res://props/bfh_barrel.tscn")
static var BUS_SCENE := BfhPaths.rebase("res://props/bfh_bus.tscn")

## The props' collision sizes, in metres, as the scenes above build them.
##
## [b]A deliberate copy, and `headless_run` asserts it against the scenes.[/b] The map's
## climbs are measured off these — what a runner can get onto is a question about the
## collider, not the art — and reading them out of an instanced scene every time the map
## is asked would make the map depend on loading a prop.
const CRATE_SIZE := 1.0
const BARREL_HEIGHT := 1.19
const BARREL_RADIUS := 0.43

## A barrel's blast, and the reach of what it throws. Named because the map's barrel
## climb is measured against it and the def below is built from it.
const BARREL_BLAST_RADIUS := 6.5

const CRATE := &"crate"
const BARREL := &"barrel"
const BLOCK := &"block"
const BUS := &"bus"


## Everything that gets scattered in the bowl.
static func props(config: BfhConfig) -> DotPropCatalogue:
	var catalogue := DotPropCatalogue.new()

	var crate := DotPropDef.make(CRATE, CRATE_SCENE)
	crate.display_name = "Crate"
	crate.category = &"cover"
	crate.size = DotPropDef.Size.SMALL
	crate.mass = 30.0
	crate.rideable = true
	crate.max_health = 100.0
	# Three swings of a hammer at 34. Deliberately not two and not four: two is a crate
	# nobody can shelter behind and four is a crate nobody bothers with.
	# [b]Below the speed that kills a runner, and that ordering is the design.[/b] At
	# the lethal speed a bus was fast enough to run somebody over and not fast enough
	# to get through the crate they were hiding behind — so it climbed the crate
	# instead, high-centred on it with two wheels off the ground, and sat there for the
	# rest of the round. A bus at cruising speed has to go THROUGH the cover or the
	# cover is a bus trap rather than cover.
	crate.break_impact_speed = 5.0
	catalogue.add(crate)

	var barrel := DotPropDef.make(BARREL, BARREL_SCENE)
	barrel.display_name = "Barrel"
	barrel.category = &"hazard"
	barrel.size = DotPropDef.Size.SMALL
	barrel.mass = 45.0
	barrel.rideable = true
	# A third of a crate's health, because the point of a barrel is that everything
	# sets it off — a hammer, a bus, and another barrel.
	barrel.max_health = 34.0
	barrel.break_impact_speed = 6.0
	barrel.explode_radius = BARREL_BLAST_RADIUS
	barrel.explode_damage = 95.0
	barrel.explode_force = 900.0
	catalogue.add(barrel)

	# [b]The one thing in the bowl that is not a toy.[/b] A round where every piece of
	# cover can be removed is a round that ends the same way every time: the drivers
	# flatten the crates and then the runners have nowhere to be. A handful of blocks
	# that cannot be broken and cannot be pushed are what make the last thirty seconds
	# a game rather than a countdown.
	var block := DotPropDef.make(BLOCK, CRATE_SCENE)
	block.display_name = "Concrete block"
	block.category = &"cover"
	block.size = DotPropDef.Size.MEDIUM
	block.mass = 4000.0
	block.rideable = false
	block.max_health = 0.0
	block.break_impact_speed = 0.0
	block.can_grab = false
	catalogue.add(block)

	return catalogue


## The bus feel numbers from the config onto [param tunables]; also run again on a live edit.
static func apply_bus_feel(tunables: DotVehicleTunables, config: BfhConfig) -> void:
	tunables.mass = config.bus_mass
	tunables.engine_force = config.bus_engine_force
	tunables.top_speed = config.bus_top_speed
	tunables.brake_force = config.bus_brake_force
	tunables.handbrake_force = config.bus_handbrake_force
	tunables.handbrake_grip_fraction = config.bus_handbrake_grip
	tunables.steering_limit_deg = config.bus_steering_limit_deg
	tunables.steering_rate_deg = config.bus_steering_rate_deg
	tunables.steering_speed_falloff = config.bus_steering_falloff
	tunables.friction_slip = config.bus_friction_slip
	tunables.suspension_stiffness = config.bus_suspension_stiffness
	tunables.suspension_travel = config.bus_suspension_travel
	tunables.centre_of_mass_drop = config.bus_centre_of_mass_drop
	tunables.max_exit_speed = config.bus_exit_speed


## The bus, and nothing else.
##
## [b]One vehicle on purpose.[/b] The reference this is built from has a school bus and
## a handful of cars, and the cars are the half that does not work: a car is small
## enough to be dodged reliably and fast enough to make dodging feel arbitrary, so a
## round with cars in it is decided by whoever happened to be looking the right way. A
## bus is slow to turn, impossible to miss, and telegraphs everything it is about to
## do — which is what makes running from one a decision instead of a coin toss.
static func vehicles(config: BfhConfig) -> DotVehicleCatalogue:
	var catalogue := DotVehicleCatalogue.new()

	var bus := DotVehicleDef.new()
	bus.id = BUS
	bus.display_name = "Bus"
	bus.category = &"vehicle"
	bus.scene_path = BUS_SCENE
	bus.kind = DotVehicleDef.Kind.WHEELED
	bus.max_health = 0.0

	var tunables := DotVehicleTunables.new()
	apply_bus_feel(tunables, config)
	# Newtons since dot-vehicle 4f4afaf (they were an impulse per step, and the bus stopped
	# from 15 m/s in 1.9 m on the foot brake and 4.5 m on the handbrake). 30 kN is 15 m/s²,
	# three quarters of this bowl's gravity: 7.6 m from 15 m/s. 22 kN, the old figure as a
	# force, made the bot's three-point turn under the deck settle between legs slowly enough
	# to give a runner up there a second and a half more (the deck chase in headless_run).
	# The handbrake is a person's Ctrl and stops in 6.3 m in a straight line. A person's S is
	# this foot brake until the bus has stopped and reverse after (`_drive_buses`), 7.5 m.
	# The rear tyres' grip while Ctrl is held, so a handbrake turn slides. Measured from 12 m/s
	# at full lock for a second (headless_run's "a handbrake turn"): at 1.0 (no change) the bus
	# turned 14 degrees and stopped dead, the handbrake only a brake; at 0.25 and 0.2 still
	# under the plain turn's 41; at 0.15 the back end steps out, 71 degrees with 7 m/s left;
	# at 0.1 it spins round. The change between 0.2 and 0.15 is a threshold, not a slope.
	# [b]Low, and it is the single most important number in the file.[/b] A bus that
	# turns as fast as it accelerates is a homing missile and there is no counterplay
	# to one; the whole of a runner's game is that a bus committed to a line cannot
	# take it back. Everything else here is feel.
	# [b]150, not the 45 a car uses, and 45 is what this shipped with.[/b] Stiffness has
	# to carry the mass above it: at 45 the springs on a 4.2 tonne bus bottomed out on
	# the first frame, the hull came to rest on the ground, and the body's own collider
	# dragged on the deck — so a bus with four wheels in contact and 26 kN of engine
	# force behind it sat perfectly still. Every number in the report read correctly
	# except the speed.
	# Dropped hard, because a 2.6 m tall box on a 2.5 m track rolls over on the first
	# hard turn otherwise — and a bus lying on its roof is a driver out of the round
	# through no decision anybody made.
	# [b]0.4, not 1.1, and the larger number is below the wheels.[/b] Godot's raycast
	# vehicle resolves its springs about the centre of mass; put that below the contact
	# plane and the springs push the body the wrong way about it. A drop is meant to
	# stop a tall box rolling over, not to move the pivot underground.
	bus.tunables = tunables

	var seat := DotVehicleSeat.new()
	seat.id = &"driver"
	seat.display_name = "Driver"
	seat.drives = true
	seat.attach_path = ^"Seat"
	seat.may_aim = true
	seat.may_fire = false
	seat.exit_offsets = [
		Vector3(-2.6, 0.6, 0.0),
		Vector3(2.6, 0.6, 0.0),
		Vector3(0.0, 3.2, 0.0),
	]
	bus.seats = [seat]

	catalogue.add(bus)
	return catalogue
