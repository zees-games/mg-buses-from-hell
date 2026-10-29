extends DotNetMessage

const BfhEvents := preload("bfh_events.gd")

## Anything the authority tells a client that is not a snapshot. Reliable, to clients.

const NAME := &"bfh.event"
## Room for 32 kinds. It was 4 bits with [enum BfhEvents.Kind] at 15 of 16, and the 17th
## kind would have gone out as HELLO: game-zombie-zone sent HURT and AMMO as HELLO and MAP
## that way from its first commit. headless_net checks every kind fits ([method fits]).
const KIND_BITS := 5
const MAX_BODY := 4096

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## Measured on 4.7.2 with a two-line reproduction: a script that [code]extends DotNetMessage[/code]
## and preloads ITSELF is enough, whether the base is named or given by path; a self-preload over
## [code]RefCounted[/code], [DotResult] or [DotNetBehaviour] is not, nor is a two-script cycle.
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= BfhEvents.Kind.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown event kind %d." % kind)
	return DotResult.success(true)


## Whether every [enum BfhEvents.Kind] fits in [constant KIND_BITS]. What a check reads; the
## writer masks, so a kind past the field goes out as a smaller one and nothing errors.
static func fits() -> bool:
	return int(BfhEvents.Kind.values().max()) < (1 << KIND_BITS)


func reader() -> DotNetReader:
	return DotNetReader.new(body)


func _to_string() -> String:
	return "BfhEvent(%s, %d bytes)" % [BfhEvents.kind_name(kind), body.size()]
