extends RefCounted

const BfhGame := preload("../bfh_game.gd")
const BfhSounds := preload("../bfh_sounds.gd")

## The wire format for everything that is not a snapshot or an input.

enum Kind {
	## Who you are, how fast the server ticks, and how big the bowl is.
	HELLO,
	## A player is in the world: net id, name, side.
	JOIN,
	LEAVE,
	## A player changed sides. Every third round, everybody gets one.
	TEAM,
	## A crate, a barrel, a block or a bus now exists.
	PROP,
	## It is gone, and why — broken, driven over, or the round being re-laid.
	PROP_GONE,
	## Somebody got into or out of a bus.
	SEAT,
	## The round clock, the numbers a client cannot count for itself, and the score.
	CLOCK,
	## A round began or ended.
	ROUND,
	## Somebody was run over or caught a barrel.
	DEATH,
	## A barrel went off. The client draws it; the server decided it.
	BLAST,
	## Text for one player or for everybody.
	NOTICE,
	## One chat line, already routed, sanitised and addressed by [DotChatRouter].
	CHAT,
	## Something in the bowl made a noise: which one of `BfhSounds.WORLD`, and where.
	SOUND,
	## The bowl was rebuilt between rounds, to the one the players voted for: the same three
	## numbers the HELLO carries, so a client rebuilds exactly as it would on joining.
	BOWL,
	## The bowl's toys: their net ids in ring order (both ends place them from the arena's
	## build). After every build, and to a joiner after the HELLO.
	TOYS,
}

enum Ask {
	## I have built my world and can receive. Tell me everything in the bowl.
	READY,
	## I typed a line. The server decides what channel it lands on and who hears it.
	SAY,
	## I am out and watching: next, previous, or change the view. `BfhSpectate.ASK_*`.
	WATCH,
}

## Every decoder returns an `ok` beside its fields, and every caller checks it.
const NAME_BYTES := 64
const ID_BYTES := 64
const TEXT_BYTES := 256

## The most an avatar document may take in a JOIN. One slot is about eighty bytes; the rest
## is room for slots this game does not have yet, and a cap a hostile document cannot talk
## its way past.
const AVATAR_BYTES := 1024

## Where a body may be, in metres, on the wire.
const WORLD_EXTENT := BfhGame.NET_WORLD_EXTENT
const POS_BITS := 24

## The round clock, in seconds. Fifteen minutes is far past anything `round_seconds`
## allows, and the ninth bit is cheaper than the bug of a clock that wraps.
const CLOCK_MAX := 900.0
const CLOCK_BITS := 14


static func kind_name(kind: int) -> String:
	var names := Kind.keys()
	return String(names[kind]) if kind >= 0 and kind < names.size() else "?"


static func ask_name(ask: int) -> String:
	var names := Ask.keys()
	return String(names[ask]) if ask >= 0 and ask < names.size() else "?"


static func _w() -> DotNetWriter:
	return DotNetWriter.new()


# --- Hello

## What a client needs before it can build anything.
static func write_toys(map_id: StringName, net_ids: PackedInt64Array) -> PackedByteArray:
	var w := _w()
	w.write_string(String(map_id), ID_BYTES)
	w.write_varint(net_ids.size())
	for id in net_ids:
		w.write_varint(maxi(int(id), 0))
	return w.to_bytes()


static func read_toys(r: DotNetReader) -> Dictionary:
	var map_id := StringName(r.read_string(ID_BYTES))
	var count := r.read_varint()
	var ids := PackedInt64Array()
	if count < 0 or count > 256:
		return {"map_id": map_id, "ids": ids, "ok": false}
	for i in count:
		ids.append(r.read_varint())
	return {"map_id": map_id, "ids": ids, "ok": r.ok()}


static func write_hello(
	player_id: int,
	tick_rate: int,
	server_tick: int,
	arena_radius: float,
	round_seconds: float,
	hook_layout: String,
	courtyard_west_lane: float,
	district: String = ""
) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_uint(tick_rate, 9)
	w.write_varint(server_tick)
	w.write_float_range(arena_radius, 0.0, 512.0, 16)
	w.write_float_range(round_seconds, 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_string(hook_layout, LAYOUT_NAME_BYTES)
	w.write_float_range(courtyard_west_lane, 0.0, LAYOUT_MAX, LAYOUT_BITS)
	w.write_string(district, LAYOUT_NAME_BYTES)
	return w.to_bytes()


## The range and bits a layout length goes on the wire with: 1 mm steps up to 64 m. And
## the longest a layout's name may be.
const LAYOUT_MAX := 64.0
const LAYOUT_BITS := 16
const LAYOUT_NAME_BYTES := 32


## The map, as the HELLO's last three fields: what a client needs to rebuild the bowl when
## the server rebuilds its own between rounds.
static func write_bowl(arena_radius: float, hook_layout: String, courtyard_west_lane: float,
		district: String = "") -> PackedByteArray:
	var w := _w()
	w.write_float_range(arena_radius, 0.0, 512.0, 16)
	w.write_string(hook_layout, LAYOUT_NAME_BYTES)
	w.write_float_range(courtyard_west_lane, 0.0, LAYOUT_MAX, LAYOUT_BITS)
	w.write_string(district, LAYOUT_NAME_BYTES)
	return w.to_bytes()


static func read_bowl(r: DotNetReader) -> Dictionary:
	var arena_radius := r.read_float_range(0.0, 512.0, 16)
	var hook_layout := r.read_string(LAYOUT_NAME_BYTES)
	var courtyard_west_lane := r.read_float_range(0.0, LAYOUT_MAX, LAYOUT_BITS)
	var district := r.read_string(LAYOUT_NAME_BYTES)
	return {
		"arena_radius": arena_radius,
		"hook_layout": hook_layout,
		"courtyard_west_lane": courtyard_west_lane,
		"district": district,
		"ok": r.ok(),
	}


static func read_hello(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var tick_rate := r.read_uint(9)
	var server_tick := r.read_varint()
	var arena_radius := r.read_float_range(0.0, 512.0, 16)
	var round_seconds := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var hook_layout := r.read_string(LAYOUT_NAME_BYTES)
	var courtyard_west_lane := r.read_float_range(0.0, LAYOUT_MAX, LAYOUT_BITS)
	var district := r.read_string(LAYOUT_NAME_BYTES)
	return {
		"player_id": player_id,
		"tick_rate": tick_rate,
		"server_tick": server_tick,
		"arena_radius": arena_radius,
		"round_seconds": round_seconds,
		"hook_layout": hook_layout,
		"courtyard_west_lane": courtyard_west_lane,
		"district": district,
		"ok": r.ok(),
	}


# --- Players

## A join, or a change to who somebody is: their name, their side, their avatar.
static func write_join(
	player_id: int, net_id: int, display_name: String, team: int,
	avatar: DotAvatar = null
) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(net_id)
	w.write_string(display_name, NAME_BYTES)
	w.write_uint(clampi(team, 0, 3), 2)
	w.write_string(JSON.stringify(avatar.to_dict()) if avatar != null else "", AVATAR_BYTES)
	return w.to_bytes()


static func read_join(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var net_id := r.read_varint()
	var display_name := r.read_string(NAME_BYTES)
	var team := r.read_uint(2)
	var text := r.read_string(AVATAR_BYTES)
	var avatar: DotAvatar = null

	# A document that does not parse is the stock person, not a refused join: an avatar is
	# cosmetic, and somebody who cannot be drawn as themselves can still be drawn.
	if text != "":
		var parsed: Variant = JSON.parse_string(text)

		if parsed is Dictionary:
			var built := DotAvatar.from_dict(parsed)

			if built.ok:
				avatar = built.value

	return {
		"player_id": player_id,
		"net_id": net_id,
		"name": display_name,
		"team": team,
		"avatar": avatar,
		"ok": r.ok(),
	}


static func write_player(player_id: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	return w.to_bytes()


static func read_player(r: DotNetReader) -> int:
	return r.read_varint()


## A side change. One player per message, because a swap is rare and a list is a second
## encoding of the same fact that can disagree with the first.
static func write_team(player_id: int, team: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_uint(clampi(team, 0, 3), 2)
	return w.to_bytes()


static func read_team(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var team := r.read_uint(2)
	return {"player_id": player_id, "team": team, "ok": r.ok()}


# --- What is in the bowl

## Something the world has put out: a crate, a barrel, a block or a bus.
static func write_prop(
	net_id: int, kind_id: StringName, at: Vector3, vehicle: bool
) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_string(String(kind_id), ID_BYTES)
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	w.write_bool(vehicle)
	return w.to_bytes()


static func read_prop(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var kind_id := r.read_string(ID_BYTES)
	var at := r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	var vehicle := r.read_bool()
	return {
		"net_id": net_id,
		"kind_id": StringName(kind_id),
		"position": at,
		"vehicle": vehicle,
		"ok": r.ok(),
	}


static func write_prop_gone(net_id: int, reason: StringName) -> PackedByteArray:
	var w := _w()
	w.write_varint(net_id)
	w.write_string(String(reason), ID_BYTES)
	return w.to_bytes()


static func read_prop_gone(r: DotNetReader) -> Dictionary:
	var net_id := r.read_varint()
	var reason := r.read_string(ID_BYTES)
	return {"net_id": net_id, "reason": StringName(reason), "ok": r.ok()}


## Who is driving what.
static func write_seat(player_id: int, net_id: int, seated: bool) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(net_id)
	w.write_bool(seated)
	return w.to_bytes()


static func read_seat(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var net_id := r.read_varint()
	var seated := r.read_bool()
	return {"player_id": player_id, "net_id": net_id, "seated": seated, "ok": r.ok()}


# --- The round

## The clock and the two numbers a client cannot count for itself.
static func write_clock(
	round_number: int, elapsed: float, cover: int, alive: int, playable: bool,
	drivers_won: int, runners_won: int
) -> PackedByteArray:
	var w := _w()
	w.write_varint(round_number)
	w.write_float_range(clampf(elapsed, 0.0, CLOCK_MAX), 0.0, CLOCK_MAX, CLOCK_BITS)
	w.write_uint(clampi(cover, 0, 1023), 10)
	w.write_uint(clampi(alive, 0, 255), 8)
	w.write_bool(playable)
	# The score, which is dot-match's rounds won per side. Here rather than in ROUND because
	# a player who joins mid-match is sent a CLOCK and never the ROUNDs before them.
	w.write_varint(maxi(drivers_won, 0))
	w.write_varint(maxi(runners_won, 0))
	return w.to_bytes()


static func read_clock(r: DotNetReader) -> Dictionary:
	var round_number := r.read_varint()
	var elapsed := r.read_float_range(0.0, CLOCK_MAX, CLOCK_BITS)
	var cover := r.read_uint(10)
	var alive := r.read_uint(8)
	var playable := r.read_bool()
	var drivers_won := r.read_varint()
	var runners_won := r.read_varint()
	return {
		"round": round_number,
		"elapsed": elapsed,
		"cover": cover,
		"alive": alive,
		"playable": playable,
		"drivers_won": drivers_won,
		"runners_won": runners_won,
		"ok": r.ok(),
	}


## A round began, or ended with a winner. [param winner] is a `BfhGame.TEAM_*`, or 0.
static func write_round(number: int, began: bool, winner: int) -> PackedByteArray:
	var w := _w()
	w.write_varint(number)
	w.write_bool(began)
	w.write_uint(clampi(winner, 0, 3), 2)
	return w.to_bytes()


static func read_round(r: DotNetReader) -> Dictionary:
	var number := r.read_varint()
	var began := r.read_bool()
	var winner := r.read_uint(2)
	return {"round": number, "began": began, "winner": winner, "ok": r.ok()}


## [param death] is how the body falls (dot-player-char's [DotPlayerDeath], the server's pick),
## last and optional, so every client draws the same fall and an older one reads the rest.
static func write_death(player_id: int, by: int, death: DotPlayerDeath = null) -> PackedByteArray:
	var w := _w()
	w.write_varint(player_id)
	w.write_varint(by)
	if death != null:
		death.write_to(w)
	return w.to_bytes()


static func read_death(r: DotNetReader) -> Dictionary:
	var player_id := r.read_varint()
	var by := r.read_varint()
	var out := {"player_id": player_id, "by": by}
	# A byte or more left is the fall; less is the padding to the last byte.
	if r.bits_remaining() >= 8:
		out["death"] = DotPlayerDeath.read_from(r)
	out["ok"] = r.ok()
	return out


## Where a barrel went off and how far it reached.
static func write_blast(at: Vector3, radius: float) -> PackedByteArray:
	var w := _w()
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	w.write_float_range(radius, 0.0, 64.0, 12)
	return w.to_bytes()


static func read_blast(r: DotNetReader) -> Dictionary:
	var at := r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	var radius := r.read_float_range(0.0, 64.0, 12)
	return {"position": at, "radius": radius, "ok": r.ok()}


# --- Chat

## A chat line's own field widths. Wider than the rules allow, so a rule can be raised
## without the wire silently truncating what it lets through.
const CHAT_BYTES := 200
const CHAT_CHANNEL_BYTES := 24
const CHAT_KEY_BYTES := 48
const CHAT_KIND_BITS := 4


## Whether every [enum DotChatMessage.Kind] fits in [constant CHAT_KIND_BITS]. dot-chat owns
## that enum, so it can grow under this game; headless_net reads this.
static func chat_kinds_fit() -> bool:
	return DotChatMessage.KIND_NAMES.size() <= (1 << CHAT_KIND_BITS)


## One routed line, in [DotChatMessage]'s own wire shape.
static func write_chat(wire: Dictionary) -> PackedByteArray:
	var w := _w()
	w.write_varint(int(wire.get("n", 0)))
	w.write_uint(int(wire.get("t", 0)), 32)
	w.write_string(str(wire.get("c", "")), CHAT_CHANNEL_BYTES)
	w.write_uint(
		maxi(0, DotChatMessage.kind_from_name(str(wire.get("k", "say")))), CHAT_KIND_BITS
	)
	w.write_string(str(wire.get("s", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("d", "")), NAME_BYTES)
	w.write_string(str(wire.get("w", "")), CHAT_KEY_BYTES)
	w.write_string(str(wire.get("m", "")), CHAT_BYTES)

	var meta: Variant = wire.get("x")
	var player_id := 0

	if typeof(meta) == TYPE_DICTIONARY:
		player_id = int((meta as Dictionary).get("p", 0))

	w.write_varint(maxi(player_id, 0))
	return w.to_bytes()


static func read_chat(r: DotNetReader) -> Dictionary:
	var out := {
		"n": r.read_varint(),
		"t": r.read_uint(32),
		"c": r.read_string(CHAT_CHANNEL_BYTES),
	}

	var kind := r.read_uint(CHAT_KIND_BITS)
	out["k"] = (
		DotChatMessage.KIND_NAMES[kind] if kind >= 0 and kind < DotChatMessage.KIND_NAMES.size()
		else "say"
	)

	out["s"] = r.read_string(CHAT_KEY_BYTES)
	out["d"] = r.read_string(NAME_BYTES)
	out["w"] = r.read_string(CHAT_KEY_BYTES)
	out["m"] = r.read_string(CHAT_BYTES)

	var player_id := r.read_varint()

	if player_id > 0:
		out["x"] = {"p": player_id}

	out["ok"] = r.ok()
	return out


## What a client sends when somebody presses Enter: a channel and a line, and nothing else.
static func write_say(channel_id: StringName, text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(String(channel_id), CHAT_CHANNEL_BYTES)
	w.write_string(text, CHAT_BYTES)
	return w.to_bytes()


static func read_say(r: DotNetReader) -> Dictionary:
	var out := {
		"channel": r.read_string(CHAT_CHANNEL_BYTES),
		"text": r.read_string(CHAT_BYTES),
	}
	out["ok"] = r.ok()
	return out


# --- Sound

## A noise the server decided, by its index in `BfhSounds.WORLD`, and where it was.
static func write_sound(index: int, at: Vector3) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(index, 0, (1 << BfhSounds.WORLD_BITS) - 1), BfhSounds.WORLD_BITS)
	w.write_vector3_range(at, -WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	return w.to_bytes()


static func read_sound(r: DotNetReader) -> Dictionary:
	var index := r.read_uint(BfhSounds.WORLD_BITS)
	var at := r.read_vector3_range(-WORLD_EXTENT, WORLD_EXTENT, POS_BITS)
	return {"index": index, "position": at, "ok": r.ok()}


## What a spectator asked for: `BfhSpectate.ASK_NEXT`, `ASK_PREVIOUS`, `ASK_VIEW` or `ASK_ROAM`.
static func write_watch(ask: int) -> PackedByteArray:
	var w := _w()
	w.write_uint(clampi(ask, 0, 3), 2)
	return w.to_bytes()


static func read_watch(r: DotNetReader) -> Dictionary:
	var ask := r.read_uint(2)
	return {"ask": ask, "ok": r.ok()}


static func write_notice(text: String) -> PackedByteArray:
	var w := _w()
	w.write_string(text, TEXT_BYTES)
	return w.to_bytes()


static func read_notice(r: DotNetReader) -> Dictionary:
	var text := r.read_string(TEXT_BYTES)
	return {"text": text, "ok": r.ok()}
