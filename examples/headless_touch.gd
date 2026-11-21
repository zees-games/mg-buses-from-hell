extends GSGameCheckSuite

## The phone's controls: the layout fits a phone, nothing overlaps, and gs-mobile's overlay drives the client's sampler: the stick, the look half, the swing and the handbrake.

const BfhTouch := preload("../game/bfh_touch.gd")
const BfhHud := preload("../game/bfh_hud.gd")
const BfhSettings := preload("../game/bfh_settings.gd")
const CHECKS := 22


func _ready() -> void:
	GSLog.set_level(GSLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	print("mg-buses-from-hell: touch controls")
	var list := BfhTouch.touch_layout().buttons()
	var ids: Array = list.map(func(b: Dictionary) -> Variant: return b["id"])
	for want: StringName in [BfhTouch.FIRE, BfhTouch.JUMP, BfhTouch.HANDBRAKE]:
		_check(ids.has(want), "the layout has the %s button" % want)
	var probe := GSTouchButtons.new()
	var m := probe.margin
	probe.free()
	for size: Vector2 in [Vector2(667, 375), Vector2(844, 390), Vector2(932, 430)]:
		var clear := true
		var inside := true
		for i in list.size():
			var a: Vector2 = size - Vector2(m, m) - (list[i]["offset"] as Vector2)
			var ra: float = list[i]["radius"]
			inside = inside and a.x - ra >= size.x * 0.5 and a.y - ra >= 0.0 and a.x + ra <= size.x and a.y + ra <= size.y
			for j in range(i + 1, list.size()):
				var b: Vector2 = size - Vector2(m, m) - (list[j]["offset"] as Vector2)
				clear = clear and a.distance_to(b) >= ra + float(list[j]["radius"])
		_check(inside, "every button sits in the right half at %dx%d" % [size.x, size.y])
		_check(clear, "and no two overlap at %dx%d" % [size.x, size.y])

	await _overlay()
	await _hud_clear_of_menu()
	_report_sections(1, 1, 1, CHECKS)


## The top-right HUD label stays clear of the Menu button at the corner this game's spec puts it in (gs-menu's default is the
## top right, which sat on the label), and the button stays on screen.
func _hud_clear_of_menu() -> void:
	# A headless window is 64 px square, so the HUD lays out in a phone-sized viewport of its own.
	var view := Vector2(844, 390)
	var frame := SubViewport.new()
	frame.size = Vector2i(view)
	add_child(frame)
	var hud := BfhHud.new()
	frame.add_child(hud)
	hud.bind(null, null)
	await get_tree().process_frame
	await get_tree().process_frame
	var corner := BfhSettings.spec_for().menu_button_corner
	var size := Vector2(96.0, 52.0)
	var inset := 14.0
	var right := corner == &"top_right" or corner == &"bottom_right"
	var bottom := corner == &"bottom_right" or corner == &"bottom_left"
	var menu := Rect2(Vector2(view.x - inset - size.x if right else inset, view.y - inset - size.y if bottom else inset), size)
	var label := hud.corner_label_rect()
	_check(label.size.x > 0.0 and Rect2(Vector2.ZERO, view).encloses(menu) and not label.intersects(menu),
		"the top-right label does not sit under the Menu button", "%s vs %s" % [label, menu])
	frame.free()


func _overlay() -> void:
	GSPlatform.touch_override = 1
	# The real HUD is a CanvasLayer with a Control host inside it; the overlay anchors to the Control.
	var layer := CanvasLayer.new()
	add_child(layer)
	var host := Control.new()
	host.size = Vector2(844, 390)
	layer.add_child(host)
	var sampler := GSFpsTouchSampler.new(GSFpsTunables.new())
	var swings: Array = []
	var touch := BfhTouch.new()
	var controls := touch.build(host, sampler, func(down: bool) -> void: swings.append(down))
	controls.size = host.size
	await get_tree().process_frame
	_check(controls.touch and controls.sampler == sampler and touch.buttons != null, "the overlay is built and drives the client's own sampler")
	_check(not controls.crosshair_fn.is_valid() and not controls.effective.autofire, "no crosshair and no auto-fire: this is a hammer, not a gun")

	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	var fake := InputEventMouseMotion.new()
	fake.device = InputEvent.DEVICE_ID_EMULATION
	_check(touch.takes(tap) and touch.takes(fake), "it takes touches and the mouse emulated from them")

	# The steer pad: a finger down in the left zone and dragged up is throttle.
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	var vw := get_viewport().get_visible_rect().size.x
	down.position = Vector2(vw * 0.1, 300)
	get_viewport().push_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(vw * 0.1, 240)
	drag.relative = Vector2(0, -60)
	get_viewport().push_input(drag)
	_check(sampler.sample(0.016).move.y > 0.1, "a finger on the left half drags the stick forward", str(sampler.sample(0.016).move))
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = drag.position
	get_viewport().push_input(up)

	# The buttons: HIT reaches the swing, BRAKE holds the bit the bus reads.
	_press(touch.buttons.centre_of(BfhTouch.FIRE), 1, true)
	_check(swings == [true], "a press of HIT reaches the swing", str(swings))
	_press(touch.buttons.centre_of(BfhTouch.FIRE), 1, false)
	_check(swings == [true, false], "and its release too", str(swings))
	_press(touch.buttons.centre_of(BfhTouch.HANDBRAKE), 2, true)
	_check((sampler.sample(0.016).buttons & GSFpsCommand.BUTTON_CROUCH) != 0, "BRAKE holds the handbrake bit")
	_press(touch.buttons.centre_of(BfhTouch.HANDBRAKE), 2, false)
	_check((sampler.sample(0.016).buttons & GSFpsCommand.BUTTON_CROUCH) == 0, "and releasing lets it go")
	_press(touch.buttons.centre_of(BfhTouch.JUMP), 3, true)
	_check((sampler.sample(0.016).buttons & GSFpsCommand.BUTTON_JUMP) != 0, "JUMP holds the jump bit")
	_press(touch.buttons.centre_of(BfhTouch.JUMP), 3, false)

	touch.sync(true)
	_check(not controls.visible and not touch.active() and not touch.takes(tap), "a menu pauses it and lets the touch through")
	touch.sync(false)
	_check(touch.active(), "closing the menu brings it back")

	var other := GSFpsTouchSampler.new(GSFpsTunables.new())
	touch.bind_sampler(other)
	_check(controls.sampler == other, "a new active sampler (the player changed) is the one it drives")
	layer.free()
	GSPlatform.touch_override = -1


func _press(at: Vector2, finger: int, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = finger
	e.pressed = pressed
	e.position = at
	get_viewport().push_input(e)
