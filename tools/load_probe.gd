extends GSLoadProbe

## The load probe: dot-game's [GSLoadProbe] on this game's offline solo client, with the round clock
## column(s) before player/cam/hud. Needs xvfb-run, never --headless:
##   xvfb-run -a godot --path . res://tools/load_probe.tscn -- [--frames=90] [--shot=N]
const BfhClient := preload("../game/bfh_client.gd")


func _make_client() -> Node:
	var c := BfhClient.new()
	c.set("force_offline", true)
	return c


func _columns(gate: Object) -> String:
	return "round=%s %s" % [client.get("game").round_elapsed, super(gate)]
