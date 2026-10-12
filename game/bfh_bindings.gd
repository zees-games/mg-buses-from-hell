extends RefCounted

## Every key this game reads, as one dot-menu [DotMenuBindings] table: the action, the setting
## that stores it, the words a player sees, the default, and the card it goes on.
##
## [b]A table, because four things read it:[/b] the client matches events against the actions,
## the settings document stores one binding per row, the menu's Controls page draws a key per
## row, and the help screen (H) lists them with the key each is on now. Until 2026-10-11 the
## board's Tab and the spectator's Space were keycodes and the rest were nobody's, so the
## help screen had nothing to list and the Escape menu had no Help.
##
## [b]One set of keys for both sides.[/b] A driver steers the bus with the runner's movement
## keys, so the rows say both. H is help, in every game of the family (dot-menu adds the row),
## so nothing here may default to it; the talk key is dot-menu's row too (V).

const SCOREBOARD := &"bfh_scoreboard"
## First or third person (the family's F5), under the server's `mp_forceview`.
const VIEW := &"bfh_view"
## The chat box's actions (`BfhClientChat`), which dot-ui's window creates only if missing.
const CHAT := &"bfh_chat"
const CHAT_TEAM := &"bfh_chat_team"


static func make() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	keys.add_movement("Movement", "Ctrl", "Crouch")
	keys.add(&"dot_fps_forward", &"bind_forward", "Forward (driving: accelerate)", "W", "Movement")
	keys.add(&"dot_fps_back", &"bind_back", "Back (driving: brake and reverse)", "S", "Movement")
	keys.add(&"dot_fps_left", &"bind_left", "Strafe left (driving: steer)", "A", "Movement")
	keys.add(&"dot_fps_right", &"bind_right", "Strafe right (driving: steer)", "D", "Movement")
	keys.add(&"dot_fps_jump", &"bind_jump", "Jump (while out: change the view)", "Space", "Movement")
	keys.add(CHAT, &"bind_chat", "Chat", "Y", "Communication")
	keys.add(CHAT_TEAM, &"bind_chat_team", "Chat to your side", "U", "Communication")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "General")
	keys.add(VIEW, &"bind_view", "First or third person, where the server allows it", "F5", "General")
	return keys
