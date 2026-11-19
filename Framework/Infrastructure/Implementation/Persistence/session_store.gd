extends RefCounted

const SessionCodec = preload(
	"res://Framework/Infrastructure/Implementation/Persistence/session_codec.gd"
)


static func save_file(path: String, snapshot: Dictionary) -> Dictionary:
	if path.is_empty() or path.get_file().is_empty():
		return _failure("Save path must name a file.")

	var target_path := ProjectSettings.globalize_path(path).simplify_path()
	if not target_path.is_absolute_path():
		return _failure("Save path must be absolute or use user://.")

	if DirAccess.dir_exists_absolute(target_path):
		return _failure("Save path points to a directory.")

	var encoded := SessionCodec.encode(snapshot)
	if not encoded["ok"]:
		return encoded

	var bytes: PackedByteArray = encoded["value"]
	var directory_error := DirAccess.make_dir_recursive_absolute(
		target_path.get_base_dir()
	)
	if directory_error != OK:
		return _failure(
			"Could not create save directory: %s"
			% error_string(directory_error)
		)

	var random_bytes := Crypto.new().generate_random_bytes(16)
	if random_bytes.size() != 16:
		return _failure("Could not generate a temporary save name.")

	var pending_path := target_path + ".pending-" + random_bytes.hex_encode()
	if FileAccess.file_exists(pending_path):
		return _failure("Temporary save path already exists.")

	var file := FileAccess.open(pending_path, FileAccess.WRITE)
	if file == null:
		return _discard_pending(
			pending_path,
			"Could not open temporary save: %s"
			% error_string(FileAccess.get_open_error())
		)

	var stored := file.store_buffer(bytes)
	file.flush()
	var written_size := file.get_length()
	var write_error := file.get_error()
	file.close()

	if not stored or write_error != OK or written_size != bytes.size():
		return _discard_pending(
			pending_path,
			"Could not write the complete session data."
		)

	var publish_error := DirAccess.rename_absolute(pending_path, target_path)
	if publish_error != OK:
		return _discard_pending(
			pending_path,
			"Could not publish save: %s" % error_string(publish_error)
		)

	return {
		"ok": true,
		"value": path,
		"error": "",
	}

static func load_file(path: String) -> Dictionary:
	if path.is_empty() or path.get_file().is_empty():
		return _failure("Save path must name a file.")

	var source_path := ProjectSettings.globalize_path(path).simplify_path()
	if not source_path.is_absolute_path():
		return _failure("Save path must be absolute or use user://.")

	if DirAccess.dir_exists_absolute(source_path):
		return _failure("Save path points to a directory.")

	if not FileAccess.file_exists(source_path):
		return _failure("Save file does not exist: %s" % path)

	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return _failure(
			"Could not open save file: %s"
			% error_string(FileAccess.get_open_error())
		)

	var length := file.get_length()
	if length <= 0:
		file.close()
		return _failure("Save file is empty or unreadable.")

	var bytes := file.get_buffer(length)
	var read_error := file.get_error()
	file.close()

	if read_error != OK:
		return _failure(
			"Could not read save file: %s" % error_string(read_error)
		)

	if bytes.size() != length:
		return _failure("Could not read the complete save file.")

	return SessionCodec.decode(bytes)

static func _discard_pending(path: String, message: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var cleanup_error := DirAccess.remove_absolute(path)
		if cleanup_error != OK:
			message += " Temporary file cleanup failed: %s" % path

	return _failure(message)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"value": null,
		"error": message,
	}