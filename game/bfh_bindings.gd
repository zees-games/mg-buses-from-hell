extends RefCounted

## Every key this game reads, as one dot-menu [DotMenuBindings] table: the action, the setting that
## stores it, the words a player sees, the default, and the card it goes on.

const SCOREBOARD := &"bfh_scoreboard"
## First or third person (the family's F5), under the server's `mp_forceview`.
const VIEW := &"bfh_view"
## A spectator's free camera: does nothing to anybody who is playing.
const ROAM := &"bfh_roam"
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
	# One hammer and no switching, so the wheel is free: each tick is one press of jump.
	keys.add_wheel_jump("Movement")
	keys.add(CHAT, &"bind_chat", "Chat", "Y", "Communication")
	keys.add(CHAT_TEAM, &"bind_chat_team", "Chat to your side", "U", "Communication")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "General")
	keys.add(VIEW, &"bind_view", "First or third person, where the server allows it", "F5", "General")
	keys.add(ROAM, &"bind_roam", "Free camera (while out)", "G", "General")
	return keys


## The key an action is on, for a line of help; its default where no table put it on the map.
static func key_name(action: StringName) -> String:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return (event as InputEventKey).as_text_physical_keycode()

	return "G" if action == ROAM else str(action)
