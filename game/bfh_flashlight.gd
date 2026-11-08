extends RefCounted

## The flashlight's config and the server's start rule (the beam, the click and the replication helpers are dot-flashlight's).

const BfhAmbience := preload("bfh_ambience.gd")

const GAME_ID := "mg-buses-from-hell"

## The ambience moods whose rounds start with the light on. Every bowl is under open daylight and its moods are industrial or city ruins, so the light starts off; a bowl set at night would be added here.
const DARK_MOODS: PackedStringArray = ["interior_horror", "cave_tunnel", "outdoor_night"]


## A config with this game's defaults: F, off while the sky is lit, on in a dark mood.
static func make_config() -> DotFlashlightConfig:
	var cfg := DotFlashlightConfig.new()
	cfg.key = "F"
	cfg.dark_moods = DARK_MOODS
	return cfg


## The binder: `bfh_flashlight_<field>` cvars, `cfg/game/mg-buses-from-hell/flashlight/game.yml`, a workbench set.
static func make_binder(cfg: DotFlashlightConfig) -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(cfg, GAME_ID, "bfh_flashlight")
	b.profile_kind = "flashlight"
	return b


## The mood a bowl plays under: by id prefix, else the default.
static func mood_of(bowl_id: String) -> String:
	for prefix: String in BfhAmbience.PREFIX_MOODS:
		if bowl_id.begins_with(prefix):
			return String(BfhAmbience.PREFIX_MOODS[prefix])
	return String(BfhAmbience.DEFAULT_MOOD)


## Whether a player starts a round with the light on: the bowl's mood against the config's dark moods.
static func starts_on(cfg: DotFlashlightConfig, bowl_id: String, mood: String = "") -> bool:
	return DotFlashlightRules.start_on(cfg, bowl_id, 1.0, mood if mood != "" else mood_of(bowl_id))
