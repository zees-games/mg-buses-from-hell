extends RefCounted

## Per-map settings: dot-game's [DotGameMapConfig] over the tunables a bowl may change.
##
## `cfg/game/mg-buses-from-hell/dot_map/map/<bowl>.yml` (a glob such as `*.yml` covers them all), overridable from `cfg/server/...`. A key outside [constant KEYS] is logged and ignored, so a file can never run a command.

const GAME_ID := "mg-buses-from-hell"

## cvar -> its constraint. Add a cvar here to let a bowl's file set it.
const KEYS := {
	"bfh_round_seconds": {"type": "float", "min": 10.0, "max": 3600.0},
	"bfh_crates": {"type": "int", "min": 0, "max": 500},
	"bfh_barrels": {"type": "int", "min": 0, "max": 500},
	"bfh_drivers": {"type": "int", "min": 1, "max": 32},
	"bfh_bus_top_speed": {"type": "float", "min": 1.0, "max": 120.0},
	"bfh_bus_lethal_speed": {"type": "float", "min": 0.0, "max": 120.0},
	"bfh_bus_lane_width": {"type": "float", "min": 0.0, "max": 50.0},
	"bfh_scaffold_margin": {"type": "float", "min": 0.0, "max": 50.0},
	"bfh_bus_stuck_break": {"type": "float", "min": 0.1, "max": 60.0},
	"bfh_bus_stuck_reset": {"type": "float", "min": 0.1, "max": 120.0},
	"bfh_bus_mass": {"type": "float", "min": 500.0, "max": 20000.0},
	"bfh_bus_engine_force": {"type": "float", "min": 1000.0, "max": 200000.0},
	"bfh_bus_brake_force": {"type": "float", "min": 1000.0, "max": 200000.0},
	"bfh_bus_handbrake_grip": {"type": "float", "min": 0.02, "max": 1.0},
	"bfh_bus_steering_limit_deg": {"type": "float", "min": 5.0, "max": 60.0},
	"bfh_bus_steering_falloff": {"type": "float", "min": 0.0, "max": 1.0},
	"bfh_bus_friction_slip": {"type": "float", "min": 0.5, "max": 10.0},
	"bfh_horn_seconds": {"type": "float", "min": 0.0, "max": 10.0},
	"bfh_bot_horn_seconds": {"type": "float", "min": 0.0, "max": 60.0},
	"bfh_bot_ramp_speed": {"type": "float", "min": 2.0, "max": 30.0},
}

## The subset a client uses itself (offline play, prediction); the rest is the server's alone.
const CLIENT_KEYS := ["bfh_round_seconds", "bfh_bus_top_speed", "bfh_bus_lethal_speed"]


## The applier over [param console]'s cvars.
static func build(console: DotConsole) -> DotGameMapConfig:
	return DotGameMapConfig.for_console(GAME_ID, console, KEYS)


## The client's keys: [constant KEYS] restricted to [constant CLIENT_KEYS].
static func client_keys() -> Dictionary:
	var out := {}
	for key in CLIENT_KEYS:
		out[key] = KEYS[key]
	return out


## A client-side getter for [param world]'s config; null for a key the client does not hold.
static func client_get(world: Object, key: String) -> Variant:
	var cfg: Object = world.get("config")
	match key:
		"bfh_round_seconds": return str(cfg.get("round_seconds"))
		"bfh_bus_top_speed": return str(cfg.get("bus_top_speed"))
		"bfh_bus_lethal_speed": return str(cfg.get("bus_lethal_speed"))
	return null


## A client-side setter; false for a key the client does not hold.
static func client_set(world: Object, key: String, value: Variant) -> bool:
	var cfg: Object = world.get("config")
	var number := float(str(value))
	match key:
		"bfh_round_seconds":
			world.call("set_round_seconds", number)
		"bfh_bus_top_speed":
			cfg.set("bus_top_speed", number)
		"bfh_bus_lethal_speed":
			cfg.set("bus_lethal_speed", number)
		_:
			return false
	return true
