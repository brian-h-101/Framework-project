extends RefCounted

const CodecImplementation = preload(
	"res://Framework/Infrastructure/Implementation/Persistence/session_codec.gd"
)


static func encode(snapshot: Dictionary) -> Dictionary:
	return CodecImplementation.encode(snapshot)


static func decode(bytes: PackedByteArray) -> Dictionary:
	return CodecImplementation.decode(bytes)