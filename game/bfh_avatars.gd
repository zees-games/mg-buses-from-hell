extends RefCounted

## What a player looks like, as a dot-user-avatar document: the schema, the stock avatar a player
## without one of their own wears, and which skin a document asks for.

const SCHEMA_ID := &"bfh_people"

const SLOT_SKIN := &"skin"

## The skins, in [code]BfhFigure.RUNNER_ATLASES[/code] order. The letter is the kit's own.
const SKINS: Array[StringName] = [
	&"skin_a", &"skin_b", &"skin_c", &"skin_e", &"skin_f", &"skin_k",
]


## Built once per game; it is content, not state.
static func schema() -> DotAvatarSchema:
	var s := DotAvatarSchema.new()
	s.id = SCHEMA_ID
	s.version = 1

	var skin := DotAvatarSlot.new()
	skin.id = SLOT_SKIN
	skin.display_name = "Person"
	skin.required = true
	skin.default_part = SKINS[0]
	s.slots.append(skin)

	for id in SKINS:
		var part := DotAvatarPart.new()
		part.id = id
		part.slot = SLOT_SKIN
		part.display_name = "Person %s" % String(id).trim_prefix("skin_").to_upper()
		# Free and shipped in the pack: nobody has to own a face.
		part.free = true
		part.colour_channels = 0
		s.parts.append(part)

	return s


## The avatar a player with none of their own wears: the skin their id hashes to.
static func stock_avatar(player_id: StringName) -> DotAvatar:
	var avatar := DotAvatar.make(SCHEMA_ID)
	avatar.set_part(SLOT_SKIN, SKINS[stock_index(player_id)])
	return avatar


static func stock_index(player_id: StringName) -> int:
	return int(hash(String(player_id)) & 0x7fffffff) % SKINS.size()


## Which of [constant SKINS] a document asks for, or -1 for none this game has.
static func skin_index(avatar: DotAvatar) -> int:
	if avatar == null or avatar.schema_id != SCHEMA_ID:
		return -1

	return SKINS.find(avatar.part_in(SLOT_SKIN))


## A member's site avatar as one of this game's runners: their top's skin, when this game
## ships it. See `DotPlatformIdentity.avatar_translate_fn`. Null for a skin this game does
## not draw and for a document that is not the site's: the member is their stock runner.
static func from_site(foreign: DotAvatar) -> DotAvatar:
	var top := _site_skin(foreign, &"top")
	var skin := StringName("skin_%s" % top)

	if top == "" or not SKINS.has(skin):
		return null

	var avatar := DotAvatar.make(SCHEMA_ID)
	avatar.set_part(SLOT_SKIN, skin)
	return avatar


## The letter of the site's skin in [param slot] of its `builtin` document, or "".
static func _site_skin(foreign: DotAvatar, slot: StringName) -> String:
	if foreign == null or foreign.schema_id != &"builtin":
		return ""

	# [b]The site files a part as `<slot>.<option>`[/b] (`top.skin-k`; its GodotPartId), so
	# the slot's own prefix comes off first. A bare `skin-k` is still read: checking only
	# the bare form refused every real site avatar, and every member wore a stock look.
	var part := String(foreign.part_in(slot)).trim_prefix(String(slot) + ".")

	if part.length() != 6 or not part.begins_with("skin-"):
		return ""

	var letter := part.substr(5, 1)
	return letter if letter >= "a" and letter <= "r" else ""
