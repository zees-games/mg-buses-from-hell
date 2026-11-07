extends DotGameCheckSuite

## The phone's on-screen buttons: the layout fits a phone, nothing overlaps, and a press reaches the swing or the sampler.

const BfhTouch := preload("../game/bfh_touch.gd")
const CHECKS := 12


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	print("mg-buses-from-hell: touch controls")
	var list := BfhTouch.touch_layout().buttons()
	var ids: Array = list.map(func(b: Dictionary) -> Variant: return b["id"])
	for want: StringName in [BfhTouch.FIRE, BfhTouch.JUMP, BfhTouch.HANDBRAKE]:
		_check(ids.has(want), "the layout has the %s button" % want)
	var probe := DotTouchButtons.new()
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

	var swings: Array = []
	var sampler := DotFpsTouchSampler.new(DotFpsTunables.new())
	var sampler_fn := func() -> Variant: return sampler
	var swing_fn := func(down: bool) -> void: swings.append(down)
	BfhTouch.route(BfhTouch.FIRE, true, sampler_fn, swing_fn)
	BfhTouch.route(BfhTouch.FIRE, false, sampler_fn, swing_fn)
	_check(swings == [true, false], "a press and a release of HIT reach the swing", str(swings))
	BfhTouch.route(BfhTouch.HANDBRAKE, true, sampler_fn, swing_fn)
	_check((sampler.sample(0.016).buttons & DotFpsCommand.BUTTON_CROUCH) != 0, "BRAKE holds the handbrake bit the bus reads")
	BfhTouch.route(BfhTouch.HANDBRAKE, false, sampler_fn, swing_fn)
	_check((sampler.sample(0.016).buttons & DotFpsCommand.BUTTON_CROUCH) == 0, "and releasing lets it go")
	_report_sections(1, 1, 1, CHECKS)
