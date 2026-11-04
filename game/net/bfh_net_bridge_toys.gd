extends "bfh_net_bridge_base.gd"
## The bridge's loose toys: mirrored on a client, registered and paired before the bowl is built.

func _build_entity(player: BfhPlayer, peer_id: int) -> DotNetIdentity:
	# The behaviour is added BEFORE the identity: [DotNetIdentity] collects behaviours in
	# `_ready` by walking the subtree, and one added afterwards would never be found.
	var behaviour := BfhPlayerNet.new()
	behaviour.name = "Net"
	behaviour.player = player
	behaviour.bridge = self
	player.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = peer_id
	# SHARED: the server corrects, the owner predicts. SERVER would put a runner's own
	# movement a round trip behind their keys, which in this game is the difference
	# between dodging a bus and being told you were hit by one.
	identity.authority = DotNetIdentity.Authority.SHARED
	# [b]Always, and the bowl is why.[/b] Interest management is a saving on a map where most players
	# are out of sight; this one is a 46 m disc with nothing tall in it, so everybody can see everybody
	# and culling would only ever produce a player who disappears in the open.
	identity.always_relevant = true
	player.add_child(identity)

	_behaviours[session_of(player.player_id)] = behaviour
	return identity

func _release_entity(session_id: int) -> void:
	var behaviour: BfhPlayerNet = _behaviours.get(session_id)
	_behaviours.erase(session_id)

	if behaviour == null or behaviour.identity == null or net == null:
		return

	net.registry.unregister(behaviour.identity.net_id)

## Everything in the bowl, to one peer, once its world exists.

## The bowl's toys on the wire, one behaviour per toy in toy order, and the TOYS event that names
## their net ids (kept for a joiner).
var _toy_nets: Array = []
var _toys_body: PackedByteArray = PackedByteArray()

## The one id TOYS carries here: there is one bowl, and HELLO and BOWL say what it is.
const BOWL := &"bowl"

## Client: which map the last TOYS was for. Its mirrors are registered at once and handed their
## toys when this end's toys for the bowl exist ([method _pair_pending_toys]).
var _toys_map: StringName = &""

## Client: where the mirrors live, which is not under the toys: a client registers them the
## moment TOYS arrives, before its own map may be built, and keeps them through a map change.
var _toy_holder: Node3D = null

## Server: an entity for each of the bowl's toys, and TOYS naming them.
func _register_toys() -> void:
	if net == null or not net.is_server or game == null:
		return
	_release_toys()
	var ids := PackedInt64Array()
	if game.toys != null:
		for toy in game.toys.toys:
			var behaviour := _toy_entity(toy, toy, 0)
			if behaviour == null:
				break
			ids.append(behaviour.identity.net_id)
	_toys_body = BfhEvents.write_toys(BOWL, ids)
	_broadcast(BfhEvents.Kind.TOYS, _toys_body)

## A toy's behaviour and identity under [param parent], registered under [param net_id] (0
## allocates: the server); null when the registry refused it. The behaviour before the
## identity, which collects behaviours in its `_ready`.
func _toy_entity(toy: DotPropToy, parent: Node, net_id: int) -> BfhToyNet:
	var behaviour := BfhToyNet.new()
	behaviour.name = "Net"
	behaviour.toy = toy
	var holder := Node3D.new() if parent != toy else null
	if holder != null:
		holder.name = "Toy%d" % _toy_nets.size()
		parent.add_child(holder)
	var at: Node = holder if holder != null else toy
	at.add_child(behaviour)
	if net.is_server:
		behaviour.pull()
	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	at.add_child(identity)
	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)
	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a toy", {"toy": _toy_nets.size(), "error": str(registered.error)})
		at.remove_child(behaviour)
		at.remove_child(identity)
		behaviour.queue_free()
		identity.queue_free()
		if holder != null:
			parent.remove_child(holder)
			holder.queue_free()
		return null
	_toy_nets.append(behaviour)
	return behaviour

## Every toy entity out of the registry and out of the tree at once: a new identity on the same
## toy collects every behaviour under it in its `_ready`, and a freed one found there broke the
## next snapshot. The server's, on a map change or a new set.
func _release_toys() -> void:
	for behaviour: BfhToyNet in _toy_nets:
		if not is_instance_valid(behaviour):
			continue
		if behaviour.identity != null and net != null and net.registry.has(behaviour.identity.net_id):
			net.registry.unregister(behaviour.identity.net_id)
			if net.is_server and net.history != null:
				net.history.forget(behaviour.identity.net_id)
		var at := behaviour.get_parent()
		for node: Node in [behaviour.identity, behaviour]:
			if node != null and is_instance_valid(node) and node.get_parent() != null:
				node.get_parent().remove_child(node)
				node.queue_free()
		if at != null and at.get_parent() == _toy_holder and _toy_holder != null:
			_toy_holder.remove_child(at)
			at.queue_free()
	_toy_nets.clear()

## Client, on TOYS: a mirror for every id at once, under the holder, whether this end's toys for the
## bowl exist yet or not.
func _apply_toys(told: Dictionary) -> void:
	if net == null or net.is_server:
		return
	_release_toys()
	if _toy_holder == null:
		_toy_holder = Node3D.new()
		_toy_holder.name = "ToyMirrors"
		add_child(_toy_holder)
	_toys_map = told["map_id"]
	for id in (told["ids"] as PackedInt64Array):
		var _mirror := _toy_entity(null, _toy_holder, int(id))
	_pair_pending_toys()

## Client: each mirror handed this end's toy at its index, once this end's toys are for the map
## TOYS named; none while they are not (a map change on the way, or another map).
func _pair_pending_toys() -> void:
	if net == null or net.is_server or game == null:
		return
	var box := game.toys if game.toys != null and _toys_map == BOWL else null
	if box != null and box.count() != _toy_nets.size():
		DotLog.warn(CHANNEL, "the server's map has a different number of toys", {"server": _toy_nets.size(), "here": box.count()})
	for i in range(_toy_nets.size()):
		var behaviour: BfhToyNet = _toy_nets[i]
		behaviour.toy = box.toy(i) if box != null else null

## Client: the old bowl's toys are about to go; the mirrors stay registered, without them.
func _unpair_toys() -> void:
	for behaviour: BfhToyNet in _toy_nets:
		if is_instance_valid(behaviour):
			behaviour.toy = null

## How many toys this end replicates (a client: mirrors paired with a toy). For a check.
func toy_count() -> int:
	var n := 0
	for behaviour: BfhToyNet in _toy_nets:
		if is_instance_valid(behaviour) and (net.is_server or behaviour.toy != null):
			n += 1
	return n
