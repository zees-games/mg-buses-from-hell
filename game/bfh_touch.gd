extends RefCounted

## The on-screen buttons a phone needs to drive and swing: the hammer (the horn in a bus), jump and the handbrake.
## The left half of the screen is [DotFpsTouchSampler]'s steer pad (up and down are throttle and brake, sideways is
## the wheel) and the right half looks; [member buttons] tells it where a button is.

const CHANNEL := "bfh.touch"

const SWING := &"swing"
const JUMP := &"jump"
const BRAKE := &"brake"

## Offsets are from the bottom-right corner towards the middle; small enough for a 375 px tall screen.
static func layout() -> Array[Dictionary]:
	return [
		{"id": SWING, "label": "HIT", "offset": Vector2(80, 84), "radius": 44.0},
		{"id": JUMP, "label": "JUMP", "offset": Vector2(80, 172), "radius": 32.0},
		{"id": BRAKE, "label": "BRAKE", "offset": Vector2(190, 60), "radius": 34.0},
	]

var buttons: DotTouchButtons = null


## Builds the buttons under [param parent]: jump and the handbrake go to the sampler (read through the callable, the
## active one changes when the player does), the swing to [param swing_fn], which takes `down: bool`.
func build(parent: Control, sampler_fn: Callable, swing_fn: Callable) -> DotTouchButtons:
	buttons = DotTouchButtons.new()
	buttons.name = "TouchButtons"
	buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.set_buttons(layout())
	parent.add_child(buttons)
	buttons.button_down.connect(func(id: StringName) -> void: route(id, true, sampler_fn, swing_fn))
	buttons.button_up.connect(func(id: StringName) -> void: route(id, false, sampler_fn, swing_fn))
	return buttons


static func route(id: StringName, down: bool, sampler_fn: Callable, swing_fn: Callable) -> void:
	if id == SWING:
		swing_fn.call(down)
		return
	var sampler: Variant = sampler_fn.call()
	if sampler != null and sampler.has_method(&"hold"):
		var bit := DotFpsCommand.BUTTON_JUMP if id == JUMP else DotFpsCommand.BUTTON_CROUCH
		sampler.call(&"hold", bit, down)


## A touch sampler where a phone is, the keyboard one otherwise; [param ignore_fn] is asked with a screen position
## and keeps a button's finger off the stick.
static func make_sampler(tunables: DotFpsTunables, ignore_fn: Callable) -> DotFpsSampler:
	var sampler: DotFpsSampler
	if DotPlatform.has_touch():
		var touch := DotFpsTouchSampler.new(tunables)
		touch.ignore_fn = ignore_fn
		sampler = touch
	else:
		sampler = DotFpsSampler.new(tunables)
	DotFpsSampler.register_default_actions(sampler)
	return sampler
