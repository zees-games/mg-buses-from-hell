extends DotGameModule

const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhServices := preload("bfh_services.gd")
const BfhPlayer := preload("bfh_player.gd")

const BfhGame := preload("bfh_game.gd")
const BfhStats := preload("bfh_stats.gd")
const BfhAvatars := preload("bfh_avatars.gd")
const BfhBowls := preload("bfh_bowls.gd")
const BfhMapConfig := preload("bfh_map_config.gd")
const BfhVote := preload("bfh_vote.gd")
const BfhAmbience := preload("bfh_ambience.gd")
## The workbench kind of the ambience cvar set (saved to cfg/.../ambience/server.yml).
const AMBIENT_KIND := "ambience"

## Where the services keep punishments. Empty is [DotGameServices]'s own default,
## `user://buses_punishments.json` — the store a real server enforces.
static var punishments_file: String = ""

## The players' vote for the next bowl; null when it could not be built.
var vote: BfhVote = null

## The drawn ballot's notice topic. The client shell draws one menu per topic.
const BOWL_BALLOT_TOPIC := &"map_ballot"

func _wire_chat() -> void:
	if bridge == null or services == null:
		return

	bridge.connect("say_requested", _on_say_requested)

	# What a client that has gone quiet is told, and what an admin's own commands echo
	# through. A refusal reaches the one person who asked; a refusal broadcast would be
	# a rate limit announced to the server.
	services.connect("command_entered", _on_chat_command)

func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	var said: DotResult = services.call("say", peer_id, channel_id, text)

	if said.ok:
		return

	# Back to the one person who asked. See [method BfhNetBridge.notice].
	bridge.call("notice", peer_id, said.error.message)

## A `!command` typed into chat. Run through the console as the person who typed it.
func _on_chat_command(peer_id: int, command: String, args: PackedStringArray) -> void:
	if server == null:
		return

	var session := server.session_of(peer_id)

	if session == null:
		return

	for reply in server.run_command_as_uid(
		session.uid(), command, args, DotCmdContext.Source.CHAT
	):
		bridge.call("notice", peer_id, reply)

## The operator's own voice in the room. `bfh_say the server is restarting in a minute`.
func _cmd_say(ctx: DotCmdContext) -> void:
	var text := ctx.rest()

	if text.strip_edges() == "":
		ctx.reply("Say what?")
		return

	if services == null or services.get("chat") == null:
		ctx.reply("This server has no chat.")
		return

	var announced: Variant = services.get("chat").call("announce", text, BfhServices.CH_ALL)

	if announced is DotResult and not (announced as DotResult).ok:
		ctx.reply_error(announced)
		return

	ctx.reply("Said: %s" % text)

## Who somebody is reaches the world: a face as they are seated, the real name and face once dot-
## platform has them, and the key (dot-game's stable one) what they keep is filed under.
func _wire_identity(world: BfhGame) -> void:
	var link := bridge as BfhNetBridge

	if link != null:
		link.avatar_fn = _avatar_for
		hook_post("player_admitted", _on_profile)
		hook_post("player_avatar_changed", _on_profile)
		hook_post("player_renamed", _on_profile)

	if world.progress != null:
		var _report := bind_stats_report(world.progress.set_reporting)
		world.progress.durable_key_fn = func(id: StringName) -> String:
			var session := server.session_by_userid(BfhNetBridge.session_of(id)) \
				if server != null else null
			return String(stats_feed.key_for(session)) if session != null and stats_feed != null else ""

## dot-platform's state for a session, through its module, or null.
func _platform_player(session_id: int) -> Object:
	var session := server.session_by_userid(session_id) if server != null else null
	var platform: Object = server.modules.get_module("platform") \
		if server != null and server.modules != null else null

	if session == null or platform == null or not platform.has_method("player_for"):
		return null

	var held: Variant = platform.call("player_for", session)
	return held as Object if held is Object else null

## What a session looks like: what dot-platform resolved for them, or the stock person.
func _avatar_for(session_id: int) -> DotAvatar:
	var held := _platform_player(session_id)

	if held != null and held.get("avatar") is DotAvatar:
		return held.get("avatar") as DotAvatar

	if identity != null and identity.has_method("avatar_for"):
		return identity.call("avatar_for", String(BfhNetBridge.player_key(session_id)))

	return null

func _on_profile(event: DotEvent) -> void:
	var session_id := event.get_int("userid")
	var session := server.session_by_userid(session_id) if server != null else null
	var link := bridge as BfhNetBridge

	if session == null or link == null:
		return

	link.refresh_player(session_id, session.display_name, _avatar_for(session_id))

## One player's session: the five numbers and what they have earned. With no argument, everybody
## counted, one line each.
func _cmd_stats(ctx: DotCmdContext) -> void:
	var world := game as BfhGame

	if world == null or world.progress == null:
		ctx.reply("This server is not counting anything.")
		return

	var wanted := ctx.rest().strip_edges()

	if wanted != "":
		ctx.reply_lines(world.progress.player_lines(BfhNetBridge.player_key(wanted.to_int())))
		return

	var any := false

	for id: StringName in world.players:
		if world.progress.key_of(id) == "":
			continue
		any = true
		var values: DotStatsValues = world.progress.session_values(id)
		ctx.reply("%-8s %-20s flattened %d  survived %d  broken %d  in the way %d  %d s" % [
			String(id).trim_prefix("u"),
			(world.players[id] as BfhPlayer).display_name,
			int(values.get_value(BfhStats.RUNNERS_FLATTENED)),
			int(values.get_value(BfhStats.ROUNDS_SURVIVED)),
			int(values.get_value(BfhStats.CRATES_BROKEN)),
			int(values.get_value(BfhStats.CRATES_INTO_PATH)),
			int(values.get_value(BfhStats.SECONDS_SURVIVED)),
		])

	if not any:
		ctx.reply("Nobody is being counted. Bots are not.")

func _cmd_status(ctx: DotCmdContext) -> void:
	var world := game as BfhGame

	if world == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.describe_lines())

func _cmd_net(ctx: DotCmdContext) -> void:
	if bridge == null:
		ctx.reply("No bridge; this server is not replicating anything.")
		return

	ctx.reply_lines(bridge.call("describe_lines"))

	if services != null:
		ctx.reply_lines(services.call("describe_lines"))
