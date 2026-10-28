extends CanvasLayer

const BfhGame := preload("bfh_game.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhArena := preload("bfh_arena.gd")
const BfhBindings := preload("bfh_bindings.gd")

## Health, the clock, and how much cover is left. Four numbers and a crosshair.
##
## [b]How much cover is left is the one number that is not obvious, and it is the most
## important of the four.[/b] Health tells a runner how many mistakes they have left
## and the clock tells them how long they have to survive; neither tells them whether
## surviving is still possible. The crate count does: a bowl down to its last few
## blocks is a bowl where standing still stops working, and a player who can see that
## number drop starts moving before it is too late rather than after.

# No `const CHANNEL`. This draws four numbers from state somebody else owns and has
# nothing an operator would act on; the round, the deaths and the bowl are logged by
# [BfhGame], which is where the decisions are. A channel declared and never used is a file
# that meant to say something and does not.

var game: BfhGame = null
var player: BfhPlayer = null

## The clock with the status line under it: dot-ui's [DotScoreStrip], clock alone (this
## game's two sides keep their rounds-won on the scoreboard, not on the HUD).
var strip: DotScoreStrip = null
## Health: dot-ui's [DotVitals], bar and number on one plate, red at a quarter.
var vitals: DotVitals = null
var _cover: Label = null
var _crosshair: DotCrosshair = null
var _root: Control = null

## An administrator's `blind`, over the world and under the four numbers.
##
## [b]Under the numbers, on purpose.[/b] A blind takes the bowl away, not the player's
## bearings: the clock, their health and the cover count still say that the round is going
## on and that they are in it, which is what makes it read as "an admin did this" rather
## than as a client that stopped drawing. The chat box is its own layer above this one.
##
## Black rather than white. A white screen at full brightness is a thing a player can be
## hurt by in a dark room, and taking the picture away is the whole of the point.
var blind_overlay: ColorRect = null

## Seconds a blind takes to come down and to lift. Short, so it is unmistakably on, and
## not instant, so it reads as something done to the screen rather than a frame dropped.
const BLIND_FADE_SEC := 0.25

const BLIND_COLOUR := Color(0.01, 0.01, 0.015)

## Seconds left at which the clock turns red.
const LOW_CLOCK_SEC := 10.0


## This game's accent over whichever theme the player picked in the menu (its highlight and
## the plates' edge). The plates, the words and their outline are the theme's, dark by default,
## so a light or high-contrast theme can change them. Static so a render tool can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := DotHudPiece.THEME_TYPE
	t.set_color(&"plate_edge", type, Color(BfhArena.SAND, 0.3))
	t.set_color(&"highlight", type, BfhArena.SAND)
	t.set_color(&"good", type, BfhArena.PILLAR_COLOUR)
	return t


## The Escape menu, whose theme this HUD follows (dot-menu's `follow_hud`): the menu sets the
## theme on the HUD's root now and at every theme change, and applies the player's HUD size.
## Christian's first play test (2026-10-11) asked for a darker HUD a player can restyle in
## the menu. Duck-typed and called by name, for a client shell older than dot-menu 7.
var _menu: Object = null


func follow_menu(menu: Object) -> void:
	_menu = menu
	_follow()


func _follow() -> void:
	if _root != null and _menu != null and _menu.has_method(&"follow_hud"):
		_menu.call(&"follow_hud", _root, piece_theme())


func bind(p_game: BfhGame, p_player: BfhPlayer) -> void:
	game = p_game
	player = p_player
	_build()


func _build() -> void:
	# [b]A full-rect Control between the CanvasLayer and the labels, and the first
	# render is why.[/b] A CanvasLayer is not a Control and does not lay its children
	# out, so anchors on a Label parented straight to one resolve against nothing:
	# every label landed in the top-left corner stacked on top of the others, and the
	# only one visible was the clock, clipped in half by the edge of the screen. It
	# reads as the HUD being half-written rather than as four labels in one place.
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# First, so every label added below draws over it. See [member blind_overlay].
	blind_overlay = ColorRect.new()
	blind_overlay.name = "Blind"
	blind_overlay.color = BLIND_COLOUR
	blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_overlay.modulate.a = 0.0
	blind_overlay.visible = false
	_root.add_child(blind_overlay)

	var font_size := 22

	# The glance pieces read their colours from the theme on the type DotHudPiece; set on
	# the root, every piece under it inherits them. See [method piece_theme].
	_root.theme = piece_theme()
	_follow()

	# The clock, and the status line ("waiting for both sides", whose eyes you are watching
	# through, "blinded by an admin") as the line under it. Full width, because the strip
	# centres itself on its own middle and the watching line is long.
	strip = DotScoreStrip.new()
	strip.name = "Clock"
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 16.0
	strip.offset_bottom = 96.0
	_root.add_child(strip)

	# Bottom left, under the chat box, which starts 120 pixels off the bottom
	# (`BfhClientChat`): the plate is 56 tall and ends 26 off it.
	vitals = DotVitals.new()
	vitals.name = "Vitals"
	vitals.bar_end = 220.0
	vitals.fill_colour = BfhArena.PILLAR_COLOUR
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24.0
	vitals.offset_right = 24.0 + 340.0
	vitals.offset_top = -82.0
	vitals.offset_bottom = -26.0
	_root.add_child(vitals)

	_cover = _label(font_size)
	_cover.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cover.offset_left = -330.0
	_cover.offset_right = -30.0
	_cover.offset_top = -76.0
	_cover.offset_bottom = -30.0
	_cover.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# A dot rather than a cross: the hammer has a reach of two metres and no spread,
	# so what a player needs is "the point I will hit", not a spread indicator.
	var dot := DotCrosshair.new()
	dot.name = "Crosshair"
	dot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dot.length = 0.0
	dot.base_gap = 0.0
	dot.top_arm = false
	dot.dynamic = false
	dot.outline = false
	dot.dot_radius = 3.0
	dot.colour = Color(1.0, 1.0, 1.0, 0.75)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DotAddonApi.build_level("dot_ui") >= 14:
		dot.set(&"alive_source", func() -> bool: return player == null or game == null or game.spectate == null or not game.spectate.is_spectating(player.player_id))
	_root.add_child(dot)
	_crosshair = dot


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	# An outline rather than a panel behind it. A HUD over a sand-coloured bowl in
	# bright light is unreadable in white and unreadable in black; an outline is
	# readable over both and costs nothing.
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


func _process(delta: float) -> void:
	present_blind(delta)

	if game == null or game.config == null:
		return

	var left := maxf(game.config.round_seconds - game.round_elapsed, 0.0)
	# Red for the last ten seconds: the runners are nearly through it.
	strip.show_clock(DotScoreStrip.clock_text(left), left <= LOW_CLOCK_SEC, _status_line())

	if player != null and player.health != null:
		# Red at a quarter (DotVitals.low_fraction), which is one bus bump from gone.
		vitals.show_vitals(player.health.health, player.health.max_health)

	_cover.text = "%d cover   %d alive" % [game.crates_left(), game.alive_runners()]


## Fades [member blind_overlay] toward whether this HUD's player is blinded.
##
## Read off [member player] rather than pushed by anybody, because the flag arrives in a
## snapshot on a connected client and is set directly offline, and a HUD that had to be
## told would need telling from two places. Public so a check can step it.
##
## [b]Sized to the viewport every frame it shows, not trusted to its anchors.[/b] The root
## it sits in is full-rect under a [CanvasLayer], which today IS the viewport — but a blind
## that left a strip of the bowl showing would be a blind a player can still play through,
## and one line here costs less than finding that out from a picture.
func present_blind(delta: float) -> void:
	if blind_overlay == null:
		return

	var want := 1.0 if player != null and player.blinded else 0.0
	blind_overlay.modulate.a = move_toward(
		blind_overlay.modulate.a, want, maxf(delta, 0.0) / BLIND_FADE_SEC
	)
	blind_overlay.visible = blind_overlay.modulate.a > 0.0

	if blind_overlay.visible and blind_overlay.is_inside_tree():
		var inverse := blind_overlay.get_parent_control().get_global_transform().affine_inverse()
		blind_overlay.position = inverse * Vector2.ZERO
		blind_overlay.size = inverse.basis_xform(blind_overlay.get_viewport_rect().size)


## The rectangle the blind covers, in viewport pixels. For a check.
func blind_rect() -> Rect2:
	if blind_overlay == null:
		return Rect2()

	return blind_overlay.get_global_rect()


func _status_line() -> String:
	# First, because a black screen with no reason on it reads as the client broken. The
	# line is drawn over the blind; see [member blind_overlay].
	if player != null and player.blinded:
		return "blinded by an admin"
	if not game.sides_are_playable():
		return "waiting for both sides"
	if player != null and player.riding:
		return "driving"
	if player != null and player.health != null and not player.health.alive:
		return watching_line(game, player)
	return ""


## What a runner who is out is told about the camera they are looking through.
##
## [b]Who, and how to change it, on one line.[/b] A camera that moved to somebody else's
## eyes with nothing on screen saying whose reads as the client having lost track of the
## player, and the three controls are the kind nobody finds by pressing keys at random.
## Static and public so the suite reads the words a player would.
static func watching_line(p_game: BfhGame, own: BfhPlayer) -> String:
	if p_game == null or own == null or p_game.spectate == null \
			or not p_game.spectate.is_spectating(own.player_id):
		return "down — next round"

	var roam_key: String = BfhBindings.key_name(BfhBindings.ROAM)

	if p_game.spectate.is_roaming(own.player_id):
		return "down — free camera (WASD · space/ctrl: up/down · shift: fast · %s: back to the players)" % roam_key

	var target := p_game.spectate.target_of(own.player_id)
	var who: BfhPlayer = p_game.players.get(target)
	var name := who.display_name if who != null else "nobody"

	if who != null and p_game.team_of(target) == BfhGame.TEAM_DRIVERS:
		name = "%s's bus" % name

	match p_game.spectate.mode_of(own.player_id):
		DotSpectatorView.Mode.DEATH_CAM:
			return "down — run over by %s" % name
		DotSpectatorView.Mode.FREEZE_CAM:
			return "down — %s, from the cab" % name
		DotSpectatorView.Mode.FIXED:
			return "down — next round"

	var roam_hint := (" · %s: free camera" % roam_key) if p_game.spectate.can_roam(own.player_id) else ""
	return "down — watching %s   (click: next · right-click: back · space: view%s)" % [name, roam_hint]
