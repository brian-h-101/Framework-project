extends RefCounted

const StoreImplementation = preload(
	"res://Framework/Infrastructure/Implementation/Persistence/session_store.gd"
)


static func save_file(path: String, snapshot: Dictionary) -> Dictionary:
	return StoreImplementation.save_file(path, snapshot)


static func load_file(path: String) -> Dictionary:
	return StoreImplementation.load_file(path)