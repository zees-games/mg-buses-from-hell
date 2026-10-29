extends DotNetInput

## One tick of a player's intent, on the wire: a [DotFpsCommand] and nothing else.

## The hammer. `BUTTON_USER_0`, which is what dot-player-controller reserves for a game.
const BUTTON_SWING := DotFpsCommand.BUTTON_USER_0

var move: DotFpsCommand = DotFpsCommand.new()


func _write(writer: DotNetWriter) -> void:
	move.write(writer)


func _read(reader: DotNetReader) -> void:
	move = DotFpsCommand.new()
	move.read(reader)


## Not optional. Quantisation bounds each field; it cannot bound the relationship between
## them, and a move vector of (1, 1) is 41% more speed than anybody else.
func _sanitise() -> void:
	move.sanitise()


func _equals(other: DotNetInput) -> bool:
	# No self-preload for the type: a script holding itself is never freed at exit.
	if other == null or other.get_script() != get_script():
		return false
	return move.equals(other.get(&"move"))
