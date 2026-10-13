extends DotNetBehaviour

## One of the map's toys on the wire (dot-props' [DotPropToy]): where its moving part is and
## how it is turned, whether it is on, and how often it has been used.
##
## [b]The server's physics, never predicted[/b], for the reason game-arena's ArenaProps gives: Godot's
## rigid-body solver is not the same on two machines. The client's toy is frozen and posed from
## these ([method DotPropToy.show_state]), so a see-saw a person stands on there is the plank the
## server tipped, an interpolation behind, and a roundabout's spin is measured from the poses.
##
## [b]Paired by index[/b]: both ends build the same toys in the same order from the map, so the
## TOYS event carries only the net ids, in toy order, and nothing here says which toy it is.
##
## [b]A use count, not a use event[/b]: a honk, a switch and a bounce each move
## [member net_count] by one, and a client plays the sound when it sees it move, so a joiner and
## a lost packet cost nothing but a late sound. Eight bits; it wraps. game-hide-n-seek's
## HsToyNet, game-playground's PlaygroundToyNet and game-arena's arena_toy_net.gd are the same file.

var toy: DotPropToy = null

var net_position: Vector3 = Vector3.ZERO
var net_rotation: Quaternion = Quaternion.IDENTITY
var net_on: bool = false
var net_count: int = 0


func _register_net_vars() -> void:
	replicate(&"net_position", DotNetVar.Type.VECTOR3_POSITION).interpolated()
	# Nine bits an element, under a degree: nobody lines a ball up to a degree.
	replicate(&"net_rotation", DotNetVar.Type.QUATERNION).bits(9).interpolated()
	replicate(&"net_on", DotNetVar.Type.BOOL)
	replicate(&"net_count", DotNetVar.Type.UINT).bits(8)


## Authority only: the toy's state into the replicated fields.
func pull() -> void:
	if toy == null or not is_instance_valid(toy):
		return
	var at := toy.state_transform()
	net_position = at.origin
	net_rotation = at.basis.get_rotation_quaternion()
	net_on = toy.on
	net_count = toy.count


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


func _net_state_applied(_tick: int) -> void:
	_seen = true
	_draw()


## Every frame between snapshots, or a ball steps at the snapshot rate.
func _net_interpolated(_tick: int) -> void:
	_draw()


## Whether a state has arrived: before one the fields are zero, and a toy posed from them would
## jump to the world's origin.
var _seen: bool = false


func _draw() -> void:
	if not _seen or toy == null or not is_instance_valid(toy) or (identity != null and identity.is_authoritative):
		return
	toy.show_state(net_position, net_rotation, net_on, net_count)
