extends "headless_net_out.gd"
## The flashlight over the wire: the ask, and the replicated flag.


func _test_the_flashlight_crosses() -> void:
	_section("the flashlight is asked for, and the server's state comes back to everybody")
	var server_me := _server_player()
	var mine := _client_player()
	var server_net := server_me.get_node("Net") as DotNetBehaviour
	_check(server_net.find_var(&"net_flashlight").audience == DotNetVar.Audience.EVERYONE,
		"the flag is declared for everybody: the beam is drawn for the others")
	var was := server_me.flashlight
	_client_bridge.ask_flashlight()
	_exchange()
	await _steps(8)
	_check(server_me.flashlight != was, "the server switched it")
	_check(mine.flashlight == server_me.flashlight, "and the owner is told")
	var bot_key := BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	var bot: BfhPlayer = _server_game.players.get(bot_key)
	var theirs: BfhPlayer = _client_game.players.get(bot_key)
	_check(bot != null and theirs != null, "another player is in both worlds")
	if bot != null and theirs != null:
		bot.flashlight = true
		await _steps(8)
		_check(theirs.flashlight, "and the others' flag is the server's")
	else:
		_check(false, "(no other player)")
	_client_bridge.ask_flashlight()
	_exchange()
	await _steps(8)
	_check(server_me.flashlight == was and mine.flashlight == was, "the next ask switches it back")
	_done()
