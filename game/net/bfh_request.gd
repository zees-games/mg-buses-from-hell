extends GSNetMessage

const BfhEvents := preload("bfh_events.gd")

## Anything a client asks the authority for. Reliable, rare, to the server only.

const NAME := &"bfh.request"
const KIND_BITS := 4
const MAX_BODY := 256

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## Measured on 4.7.2 with a two-line reproduction: a script that [code]extends GSNetMessage[/code]
## and preloads ITSELF is enough, whether the base is named or given by path; a self-preload over
## [code]RefCounted[/code], [GSResult] or [GSNetBehaviour] is not, nor is a two-script cycle.
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: GSNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: GSNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> GSResult:
	if kind < 0 or kind >= BfhEvents.Ask.size():
		return GSResult.fail(GSError.CODE_INVALID, "Unknown request kind %d." % kind)
	return GSResult.success(true)


## Whether every [enum BfhEvents.Ask] fits in [constant KIND_BITS]. What a check reads; the
## writer masks, so a kind past the field goes out as a smaller one and nothing errors.
static func fits() -> bool:
	return int(BfhEvents.Ask.values().max()) < (1 << KIND_BITS)


func reader() -> GSNetReader:
	return GSNetReader.new(body)


func _to_string() -> String:
	return "BfhRequest(%s, %d bytes)" % [BfhEvents.ask_name(kind), body.size()]
