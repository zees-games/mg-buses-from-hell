extends DotGameNetIo

const BfhBusNet := preload("bfh_bus_net.gd")
const BfhEvent := preload("bfh_event.gd")
const BfhEvents := preload("bfh_events.gd")
const BfhNetCommand := preload("bfh_net_command.gd")
const BfhNetLink := preload("bfh_net_link.gd")
const BfhPlayerNet := preload("bfh_player_net.gd")
const BfhPropNet := preload("bfh_prop_net.gd")
const BfhRequest := preload("bfh_request.gd")

const BfhContent := preload("../bfh_content.gd")
const BfhGame := preload("../bfh_game.gd")
const BfhPlayer := preload("../bfh_player.gd")
const BfhSounds := preload("../bfh_sounds.gd")

## Joins a [BfhGame] to a [DotNetManager]. The netcode seam, and the only file in this project that
## names both.

const CHANNEL := "bfh.net"

## Bytes of acknowledgement in front of every input packet. [method DotNetManager.encode_ack].
const ACK_BYTES := 4

## Commands in every input packet: this tick's and the four before it, so a lost packet costs the
## server no tick unless the next four are lost too.
const INPUT_COPIES := 5

## How often the round clock and the cover count go out, in ticks.
const CLOCK_EVERY := 30

## The client has been told who it is. [param player_id] is the session id.
signal hello_received(player_id: int)

## Somebody joined, left or changed sides. Client side; the HUD and a scoreboard read it.
signal roster_changed(player_id: int)

## A round began or ended.
signal round_changed(number: int, began: bool, winner: int)

## Somebody was run over or caught a barrel. Client side.
signal death_received(player_id: int, by: int)

## A barrel went off, where, and how far it reached. What a client draws.
signal blast_received(at: Vector3, radius: float)

## A player got into or out of a bus. The camera and the HUD read it.
signal seat_changed(player_id: int, seated: bool)

signal notice_received(text: String)

## Somebody pressed Enter. Server side, and the only thing this bridge does with chat.
signal say_requested(peer_id: int, channel_id: StringName, text: String)

## A voice frame arrived. Server side; the payload is unparsed and must not be trusted —
## [method DotVoiceRouter.relay] is what stamps the speaker, from the peer id below.
signal voice_requested(peer_id: int, payload: PackedByteArray)

## Client side: one routed line, and one voice frame.
signal chat_received(wire: Dictionary)
signal voice_arrived(payload: PackedByteArray)

var game: BfhGame = null

## Which session this process is. Zero on a server.
var local_player_id: int = 0

## Where a voice frame goes on the server. Assigned by [DotGameModule] to the services
## layer's `relay_voice`, because the bridge is the only thing that names both ends.
var voice_relay_fn: Callable = Callable()

## `func(session_id: int) -> DotAvatar`: what a player looks like, asked once as they are
## seated. Assigned by the module, which is what has the identity layer; unset, or answering
## null, is the stock person, which is what everybody was before there was one.
var avatar_fn: Callable = Callable()

var _entities: Node = null

## session id -> [BfhPlayerNet].
var _behaviours: Dictionary = {}

## The next session id handed to somebody the world made itself.
const FIRST_BOT_SESSION := 900000

var _next_bot_session: int = FIRST_BOT_SESSION

## net id -> the behaviour replicating that body, on BOTH ends.
var _bodies: Dictionary = {}

## Server only: `"p<instance>"` or `"v<instance>"` -> net id, so a removal can find it.
var _net_of: Dictionary = {}

var _player_of_peer: Dictionary = {}
var _peer_of_player: Dictionary = {}
var _ready_peers: Dictionary = {}
## Carries the game's profile runtime over this manager; null when the types would not register.
var profile_link: DotNetProfileLink = null
## Server: peers whose READY came before their seat ([method add_player]).
var _ready_unseated: Dictionary = {}

var _tick: int = 0
var _game_ticked_for: int = -1
var _client_ticked_for: int = -1

# --- Wiring

func _exit_tree() -> void:
	# The link and the runtime hold each other through broadcast; left, both outlive the process's exit.
	if profile_link != null:
		profile_link.release()
		profile_link = null

# --- Identity helpers

static func player_key(session_id: int) -> StringName:
	return StringName("u%d" % session_id)

static func session_of(id: StringName) -> int:
	return String(id).trim_prefix("u").to_int()

func peer_for_player(session_id: int) -> int:
	return int(_peer_of_player.get(session_id, 0))

func player_for_peer(peer_id: int) -> int:
	return int(_player_of_peer.get(peer_id, 0))

func net_id_of_node(node: Node) -> int:
	if node == null:
		return 0

	for net_id in _bodies:
		var behaviour: BfhPropNet = _bodies[net_id]
		if behaviour != null and behaviour.prop == node:
			return int(net_id)

	return 0

## The node drawn for a replicated body, or null. The inverse of [method net_id_of_node],
## and what a client turns `BfhPlayerNet.net_bus` back into a bus with.
func body_of_net_id(net_id: int) -> Node3D:
	var behaviour: BfhPropNet = _bodies.get(net_id)

	if behaviour == null or behaviour.prop == null or not is_instance_valid(behaviour.prop):
		return null

	return behaviour.prop as Node3D

## The CLOCK as the server has it now. One place, because three send it.
func _clock_bytes() -> PackedByteArray:
	return BfhEvents.write_clock(
		game.round_number,
		game.round_elapsed,
		game.crates_left(),
		game.alive_runners(),
		game.sides_are_playable(),
		game.rounds_won(BfhGame.TEAM_DRIVERS),
		game.rounds_won(BfhGame.TEAM_RUNNERS)
	)

## Which catalogue entry a replicated body came from.
func _kind_of(behaviour: BfhPropNet) -> StringName:
	if behaviour is BfhBusNet:
		var bus: DotVehicleInstance = (behaviour as BfhBusNet).vehicle
		return bus.def.id if bus != null and bus.def != null else BfhContent.BUS

	var prop := game.props.prop_for_node(behaviour.prop) if game.props != null else null
	return prop.def.id if prop != null and prop.def != null else BfhContent.CRATE

## To every peer that has said it is ready, and to nobody else.
func _broadcast(kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or body.is_empty():
		return

	for peer_id in _ready_peers.keys():
		_tell(int(peer_id), kind, body)

## One peer, and never zero.
func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	if peer_id <= 0 or net == null or body.is_empty():
		return

	net.send(BfhEvent.new(kind, body), peer_id)

# --- Client: what it does with all that

func ask_ready() -> void:
	_ask(BfhEvents.Ask.READY, PackedByteArray([0]))

## Switch the flashlight. The server owns on/off and answers in the player's replicated state.
func ask_flashlight() -> void:
	_ask(BfhEvents.Ask.FLASHLIGHT, PackedByteArray([0]))

## Says something. The server decides what it means and who hears it.
func ask_say(channel_id: StringName, text: String) -> void:
	if text.strip_edges() == "":
		return

	_ask(BfhEvents.Ask.SAY, BfhEvents.write_say(channel_id, text))

## Sends one encoded voice packet to the server. Client side.
func send_voice(payload: PackedByteArray) -> void:
	if link != null and net != null and not net.is_server:
		link.send_voice(1, payload)

func _ask(kind: int, body: PackedByteArray) -> void:
	if net == null or net.is_server:
		return

	net.send(BfhRequest.new(kind, body), 1)

## Who owns a mirrored player on this client: this client, if it is this client's own player, and
## the server's 0 otherwise.
func _mirror_owner(session_id: int) -> int:
	if net == null or net.local_peer_id <= 0:
		return 0

	if local_player_id != 0 and session_id == local_player_id:
		return net.local_peer_id

	return 0
