extends RefCounted

# Tokens carry character spans. Edits replace only selected spans; unrelated text,
# comments, resource declarations and native Variant literals stay untouched.
static func parse(source: String) -> Dictionary:
	var lexed := _tokens(source)
	if not lexed["ok"]:
		return lexed
	var tokens: Array = lexed["value"]
	var sections: Array[Dictionary] = []
	var cursor := 0
	while cursor < tokens.size():
		if tokens[cursor]["text"] == "[":
			var end := _balanced_end(tokens, cursor)
			if end < 0 or cursor + 1 >= end:
				return failure("Malformed scene section header.")
			var fields := _fields(tokens, cursor + 2, end, source)
			if not fields["ok"]:
				return fields
			sections.append({
				"tag": tokens[cursor + 1]["text"], "attributes": fields["value"],
				"start": tokens[cursor]["start"], "header_end": tokens[end]["end"],
				"end": _line_end(source, tokens[end]["end"]), "properties": [],
			})
			cursor = end + 1
		else:
			if sections.is_empty() or cursor + 1 >= tokens.size() or tokens[cursor + 1]["text"] != "=":
				return failure("Expected a scene property assignment.")
			var first := cursor + 2
			if first >= tokens.size():
				return failure("Scene property is missing its value.")
			var end := _value_end(tokens, first, source)
			if end <= first:
				return failure("Malformed scene property value.")
			sections[-1]["properties"].append({
				"name": tokens[cursor]["text"], "start": tokens[cursor]["start"],
				"value_start": tokens[first]["start"], "value_end": tokens[end - 1]["end"],
				"tokens": tokens.slice(first, end),
			})
			sections[-1]["end"] = _line_end(source, tokens[end - 1]["end"])
			cursor = end
	if sections.is_empty() or sections[0]["tag"] not in ["gd_scene", "gd_resource"]:
		return failure("Expected a Godot text scene or Resource header.")
	return success({"source": source, "sections": sections})


static func attribute(section: Dictionary, name: String, fallback: String = "") -> String:
	var value: Dictionary = section["attributes"].get(name, {})
	return String(value.get("text", fallback))


static func node_path(section: Dictionary) -> String:
	if not section["attributes"].has("parent"):
		return "."
	var parent := attribute(section, "parent")
	var name := attribute(section, "name")
	return name if parent == "." else parent.path_join(name)


static func replacement(field: Dictionary, text: String) -> Dictionary:
	return {"start": field["start"], "end": field["end"], "text": text}


static func apply(source: String, edits: Array[Dictionary]) -> Dictionary:
	edits.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["start"]) > int(right["start"])
	)
	var boundary := source.length()
	for edit in edits:
		var start: int = edit["start"]
		var end: int = edit["end"]
		if start < 0 or end < start or end > boundary:
			return failure("Scene edit spans overlap or exceed the document.")
		source = source.substr(0, start) + String(edit["text"]) + source.substr(end)
		boundary = start
	return success(source)


static func node_paths(tokens: Array) -> Array[Dictionary]:
	var paths: Array[Dictionary] = []
	for index in range(tokens.size()):
		if tokens[index]["text"] == "NodePath" and index + 3 < tokens.size():
			if tokens[index + 1]["text"] == "(" and tokens[index + 2]["kind"] == "string" and tokens[index + 3]["text"] == ")":
				paths.append(tokens[index + 2])
		elif tokens[index]["text"] == "^" and index + 1 < tokens.size() and tokens[index + 1]["kind"] == "string":
			paths.append(tokens[index + 1])
	return paths


static func _tokens(source: String) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var cursor := 0
	while cursor < source.length():
		var character := source[cursor]
		if character in [" ", "\t", "\r", "\n"]:
			cursor += 1
			continue
		if character in [";", "#"]:
			cursor = _line_end(source, cursor)
			continue
		var start := cursor
		if character == "\"":
			cursor += 1
			var escaped := false
			var closed := false
			while cursor < source.length():
				var next := source[cursor]
				cursor += 1
				if escaped:
					escaped = false
				elif next == "\\":
					escaped = true
				elif next == "\"":
					closed = true
					break
			if not closed:
				return failure("Unterminated string in scene document.")
			var literal := source.substr(start, cursor - start)
			var decoded: Variant = str_to_var(literal)
			if not decoded is String:
				return failure("Invalid quoted scene string.")
			tokens.append({"kind": "string", "text": decoded, "start": start, "end": cursor})
		elif character in ["[", "]", "(", ")", "{", "}", "=", ","]:
			cursor += 1
			tokens.append({"kind": "symbol", "text": character, "start": start, "end": cursor})
		else:
			while cursor < source.length() and source[cursor] not in [" ", "\t", "\r", "\n", "\"", "[", "]", "(", ")", "{", "}", "=", ",", ";", "#"]:
				cursor += 1
			tokens.append({"kind": "word", "text": source.substr(start, cursor - start), "start": start, "end": cursor})
		if tokens.size() > 500000:
			return failure("Scene document exceeds the token limit.")
	return success(tokens)


static func _fields(tokens: Array, first: int, end: int, source: String) -> Dictionary:
	var fields := {}
	var cursor := first
	while cursor < end:
		if cursor + 2 >= end or tokens[cursor + 1]["text"] != "=":
			return failure("Malformed scene header attribute.")
		var name: String = tokens[cursor]["text"]
		if fields.has(name):
			return failure("Duplicate scene header attribute: %s" % name)
		var value_start := cursor + 2
		cursor = value_start
		var depth := 0
		while cursor < end:
			if cursor > value_start and depth == 0 and cursor + 1 < end and tokens[cursor + 1]["text"] == "=":
				break
			if tokens[cursor]["kind"] == "symbol":
				if tokens[cursor]["text"] in ["[", "(", "{"]:
					depth += 1
				elif tokens[cursor]["text"] in ["]", ")", "}"]:
					depth -= 1
			cursor += 1
		var value_tokens := tokens.slice(value_start, cursor)
		fields[name] = {
			"start": tokens[value_start]["start"], "end": tokens[cursor - 1]["end"],
			"text": value_tokens[0]["text"] if value_tokens.size() == 1 else source.substr(tokens[value_start]["start"], tokens[cursor - 1]["end"] - tokens[value_start]["start"]),
			"tokens": value_tokens,
		}
	return success(fields)


static func _balanced_end(tokens: Array, first: int) -> int:
	var stack: Array[String] = []
	for index in range(first, tokens.size()):
		if tokens[index]["kind"] != "symbol":
			continue
		var token: String = tokens[index]["text"]
		if token in ["[", "(", "{"]:
			stack.append(token)
		elif token in ["]", ")", "}"]:
			if stack.is_empty() or {"[": "]", "(": ")", "{": "}"}[stack.pop_back()] != token:
				return -1
			if stack.is_empty():
				return index
	return -1


static func _value_end(tokens: Array, first: int, source: String) -> int:
	var cursor := first
	while cursor < tokens.size():
		if cursor > first and source.substr(tokens[cursor - 1]["end"], tokens[cursor]["start"] - tokens[cursor - 1]["end"]).contains("\n"):
			return cursor
		if tokens[cursor]["kind"] == "symbol" and tokens[cursor]["text"] in ["[", "(", "{"]:
			var balanced := _balanced_end(tokens, cursor)
			if balanced < 0:
				return -1
			cursor = balanced + 1
		else:
			cursor += 1
	return cursor


static func _line_end(source: String, offset: int) -> int:
	var newline := source.find("\n", offset)
	return source.length() if newline < 0 else newline + 1


static func success(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
