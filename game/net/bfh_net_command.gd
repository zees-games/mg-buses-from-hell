extends GSNetInput

## One tick of a player's intent, on the wire: a [GSFpsCommand] and nothing else.

## The hammer. `BUTTON_USER_0`, which is what dot-player-controller reserves for a game.
const BUTTON_SWING := GSFpsCommand.BUTTON_USER_0

var move: GSFpsCommand = GSFpsCommand.new()


func _write(writer: GSNetWriter) -> void:
	move.write(writer)


func _read(reader: GSNetReader) -> void:
	move = GSFpsCommand.new()
	move.read(reader)


## Not optional. Quantisation bounds each field; it cannot bound the relationship between
## them, and a move vector of (1, 1) is 41% more speed than anybody else.
func _sanitise() -> void:
	move.sanitise()


func _equals(other: GSNetInput) -> bool:
	# No self-preload for the type: a script holding itself is never freed at exit.
	if other == null or other.get_script() != get_script():
		return false
	return move.equals(other.get(&"move"))
