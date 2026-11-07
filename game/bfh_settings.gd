extends DotMenuGameSettings

const BfhBindings := preload("bfh_bindings.gd")

## A player's own settings and the menu that changes them: how fast the view turns, how wide it is,
## how loud things are, the window, and the look of the menu itself.

const SCHEMA_VERSION := 1

## Where this game's own document lives. The shared account document is dot-settings'.
const SETTINGS_DIR := "user://buses_settings"

## The app's namespace. ACCOUNT settings are shared under dot-menu's `tmc_account`.
const APP_NAMESPACE := &"buses_from_hell"

## The field of view the camera had before this existed, and still the default.
const DEFAULT_FOV := 90

## Stock keys nothing here applies: the chat box has no switch. The interface bus is real
## here (the round's cues play on it) and so are the effects, which the client binds.
const NOT_APPLIED: Array[StringName] = [&"chat_window"]


func _init() -> void:
	super(spec_for())


## The game's settings as data: names, field of view, extra settings, keys and the help screen's goal and rules.
static func spec_for() -> DotMenuGameSpec:
	var s := DotMenuGameSpec.new()
	s.schema_version = SCHEMA_VERSION
	s.brand_name = "Buses from Hell"
	s.settings_dir = SETTINGS_DIR
	s.app_namespace = APP_NAMESPACE
	s.default_fov = DEFAULT_FOV
	s.reduce_motion_text = "The end-of-round announcement appears at once, with nothing sliding, rising or bursting."
	s.comfort_row_text = "The end-of-round announcement appears at once."
	s.ambient_text = "Quiet sounds under the bowl."
	s.not_applied = NOT_APPLIED
	s.bindings_maker = func() -> DotMenuBindings: return BfhBindings.make()
	s.help_about = "Two players drive buses; everybody else runs. Drivers win by flattening every runner before the clock runs out; runners win if anybody is still standing when it does."
	s.help_cards = [
		["Running", "Your hammer cannot hurt a bus. Use it to break and shove crates into cover and walls, and keep moving. Barrels explode when anything hits them, throwing runners into the air and crates across the bowl. Concrete blocks never move."],
		["Driving", "Steer with the movement keys and run the runners over. A crate breaks under one hit at speed, and the left mouse button sounds the horn. Sides swap every three rounds, so everybody gets a turn driving."],
	]
	s.help_sections = [["Mouse", [["Left", "Swing the hammer, or the horn in a bus; watch the next player while out"], ["Right", "Watch the one before while out"], ["Middle", "Their eyes or behind them, while out"]], &"keys"]]
	return s
