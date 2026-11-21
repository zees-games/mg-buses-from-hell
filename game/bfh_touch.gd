extends RefCounted

## The phone's controls: gs-mobile's overlay driving the client's [GSFpsTouchSampler]. The buttons a phone needs to
## drive and swing: the hammer (the horn in a bus), jump and the handbrake.
## The left half of the screen is the sampler's steer pad (up and down are throttle and brake, sideways is the wheel)
## and the right half looks; [GSMobileControls] draws the stick, forwards the fingers and holds the buttons.

const CHANNEL := "bfh.touch"

const FIRE := GSGameTouchLayout.FIRE
const JUMP := GSGameTouchLayout.JUMP
const HANDBRAKE := GSGameTouchLayout.HANDBRAKE

## gs-game's driving preset less what the steer pad covers (gas, brake, steering) and the buses lack; the hammer takes fire's home.
static func touch_layout() -> GSGameTouchLayout:
	var res := GSGameTouchLayout.build(GSGameTouchLayout.DRIVING, {
		&"gas": null, &"brake": null, &"use": null, &"respawn": null, &"camera": null, &"board": null, &"chat": null,
		FIRE: {"slot": &"primary", "label": "HIT"},
		HANDBRAKE: {"slot": &"outer", "label": "BRAKE"},
	})
	if not res.ok:
		push_error("mg-buses-from-hell touch layout refused: %s" % str(res.error))
		return GSGameTouchLayout.custom()
	return res.value


## The rows [method touch_layout] gives, with the command bit the overlay holds on the sampler for jump and the handbrake.
static func controls_layout() -> Array[Dictionary]:
	var rows := touch_layout().buttons()
	for row in rows:
		if row["id"] == JUMP:
			row["hold"] = GSFpsCommand.BUTTON_JUMP
		elif row["id"] == HANDBRAKE:
			row["hold"] = GSFpsCommand.BUTTON_CROUCH
	return rows


var controls: GSMobileControls = null
## gs-ui's buttons inside the overlay, for the shell's DPI fit.
var buttons: GSTouchButtons:
	get:
		return controls.buttons if controls != null else null

var _swing_fn: Callable = Callable()
var _client: Object = null


## Builds gs-mobile's overlay under [param parent] (a Control) over [param sampler]: the stick is the steer pad, the
## right half looks, jump and the handbrake hold their bits, the hammer goes to [param swing_fn] (takes `down: bool`).
## No crosshair is given, so auto-fire and aim assist have nothing to act on: this is not a shooter. [param client] fits
## the buttons to the phone's DPI.
func build(parent: Control, sampler: GSFpsSampler, swing_fn: Callable, client: Object = null) -> GSMobileControls:
	_swing_fn = swing_fn
	_client = client
	controls = GSMobileControls.new()
	controls.name = "TouchControls"
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.setup(sampler, controls_layout())
	controls.button_pressed.connect(_on_button.bind(true))
	controls.button_released.connect(_on_button.bind(false))
	parent.add_child(controls)
	_fit()
	return controls


## The active sampler changed (the player did): the overlay drives the new one.
func bind_sampler(sampler: GSFpsSampler) -> void:
	if controls == null or controls.sampler == sampler:
		return
	controls.setup(sampler, controls_layout())
	_fit()


## True while the overlay is up and forwards [param event] itself, or [param event] is the mouse the engine emulates
## from a touch, which would swing a second time.
func takes(event: InputEvent) -> bool:
	if controls == null or not controls.touch:
		return false
	return controls.takes(event) or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)


func active() -> bool:
	return controls != null and controls.touch


## Pauses the overlay under a menu, the chat, the console or the cover.
func sync(busy: bool) -> void:
	if controls != null and controls.paused != busy:
		controls.paused = busy


func _fit() -> void:
	if buttons != null and _client != null and _client.has_method(&"fit_touch_buttons"):
		_client.call(&"fit_touch_buttons", buttons, controls_layout())


func _on_button(id: StringName, down: bool) -> void:
	if id == FIRE and _swing_fn.is_valid():
		_swing_fn.call(down)


## A touch sampler where a phone is, the keyboard one otherwise; [param ignore_fn], when given, is asked with a screen
## position and keeps a finger off the stick.
static func make_sampler(tunables: GSFpsTunables, ignore_fn: Callable = Callable()) -> GSFpsSampler:
	var sampler: GSFpsSampler
	if GSPlatform.has_touch():
		var touch := GSFpsTouchSampler.new(tunables)
		if ignore_fn.is_valid():
			touch.ignore_fn = ignore_fn
		sampler = touch
	else:
		sampler = GSFpsSampler.new(tunables)
	GSFpsSampler.register_default_actions(sampler)
	return sampler
