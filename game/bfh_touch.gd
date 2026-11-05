extends RefCounted

## The on-screen buttons a phone needs to drive and swing: the hammer (the horn in a bus), jump and the handbrake.
## The left half of the screen is [DotFpsTouchSampler]'s steer pad (up and down are throttle and brake, sideways is
## the wheel) and the right half looks; [member buttons] tells it where a button is.

const CHANNEL := "bfh.touch"

const FIRE := DotGameTouchLayout.FIRE
const JUMP := DotGameTouchLayout.JUMP
const HANDBRAKE := DotGameTouchLayout.HANDBRAKE

## dot-game's driving preset less what the steer pad covers (gas, brake, steering) and the buses lack; the hammer takes fire's home.
static func touch_layout() -> DotGameTouchLayout:
	var res := DotGameTouchLayout.build(DotGameTouchLayout.DRIVING, {
		&"gas": null, &"brake": null, &"use": null, &"respawn": null, &"camera": null, &"board": null, &"chat": null,
		FIRE: {"slot": &"primary", "label": "HIT"},
		HANDBRAKE: {"slot": &"outer", "label": "BRAKE"},
	})
	if not res.ok:
		push_error("mg-buses-from-hell touch layout refused: %s" % str(res.error))
		return DotGameTouchLayout.custom()
	return res.value

var buttons: DotTouchButtons = null


## Builds the buttons under [param parent]: jump and the handbrake go to the sampler (read through the callable, the
## active one changes when the player does), the swing to [param swing_fn], which takes `down: bool`. [param client] fits them.
func build(parent: Control, sampler_fn: Callable, swing_fn: Callable, client: Object = null) -> DotTouchButtons:
	buttons = DotTouchButtons.new()
	buttons.name = "TouchButtons"
	buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_layout().apply(buttons, client)
	parent.add_child(buttons)
	buttons.button_down.connect(func(id: StringName) -> void: route(id, true, sampler_fn, swing_fn))
	buttons.button_up.connect(func(id: StringName) -> void: route(id, false, sampler_fn, swing_fn))
	return buttons


static func route(id: StringName, down: bool, sampler_fn: Callable, swing_fn: Callable) -> void:
	if id == FIRE:
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
