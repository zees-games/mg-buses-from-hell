extends RefCounted

const BfhConfig := preload("bfh_config.gd")
const BfhPaths := preload("bfh_paths.gd")

## The two catalogues: what can be in the bowl, and what can be driven at it.

## Where the three bodies live, as this game was authored.
static var CRATE_SCENE := BfhPaths.rebase("res://props/bfh_crate.tscn")
static var BARREL_SCENE := BfhPaths.rebase("res://props/bfh_barrel.tscn")
static var BUS_SCENE := BfhPaths.rebase("res://props/bfh_bus.tscn")

## The props' collision sizes, in metres, as the scenes above build them.
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
	# Three swings of a hammer at 34. Deliberately not two and not four: two is a crate nobody can
	# shelter behind and four is a crate nobody bothers with.
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

	# [b]The one thing in the bowl that is not a toy.[/b] A round where every piece of cover can be
	# removed is a round that ends the same way every time: the drivers flatten the crates and then the
	# runners have nowhere to be.
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
	# Newtons since dot-vehicle 4f4afaf (they were an impulse per step, and the bus stopped from 15 m/s
	# in 1.9 m on the foot brake and 4.5 m on the handbrake). 30 kN is 15 m/s², three quarters of this
	# bowl's gravity: 7.6 m from 15 m/s.
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
