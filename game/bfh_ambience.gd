extends RefCounted

## What the bowl's ambience is: the cvar defaults shared by the simulation (binds `bfh_ambient*`) and the client's director (plays them).

const PREFIX := "bfh"
## Under the engines and the hammers, with rare one-shots.
const LEVEL := 0.3
const RATE := 0.5
const DEFAULT_MOOD := &"industrial"

## By bowl id prefix; the bowls take the default, the three towns the ruins.
const PREFIX_MOODS := {
	"bfh_downtown": &"city_ruins", "bfh_hill_town": &"city_ruins", "bfh_suburb": &"city_ruins",
}


static func make_rules() -> DotAmbienceRules:
	var r := DotAmbienceRules.new()
	r.prefix = PREFIX
	r.volume = LEVEL
	r.frequency = RATE
	return r
