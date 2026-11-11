extends RefCounted
## Free loopback ports for suites, so two suites (or two runs) never collide on a fixed one.


## A port whose next `span - 1` neighbours are free too (the feel suite's proxy sits at port + 1).
static func free_port(span: int = 1) -> int:
	for attempt in 40:
		var probe := TCPServer.new()
		if probe.listen(0, "127.0.0.1") != OK:
			continue
		var port := probe.get_local_port()
		probe.stop()
		var clear := true
		for offset in range(1, span):
			var neighbour := TCPServer.new()
			if neighbour.listen(port + offset, "127.0.0.1") != OK:
				clear = false
			neighbour.stop()
		if clear:
			return port
	return 28700 + randi() % 200
