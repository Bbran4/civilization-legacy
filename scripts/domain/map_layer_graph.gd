extends RefCounted
## Dependency traversal is independent from rendering and storage.

static func affected(layers: Array, source: String) -> Array[String]:
	var found := false
	for layer in layers:
		found = found or layer.id == source
	if not found:
		return []
	var result: Array[String] = [source]
	var cursor := 0
	while cursor < result.size():
		var changed: String = result[cursor]
		for layer in layers:
			if changed in layer.dependencies and not layer.id in result:
				result.append(layer.id)
		cursor += 1
	return result

static func lock_reason(layers: Array, source: String) -> String:
	var impacted := affected(layers, source)
	if impacted.is_empty():
		return "Unknown map layer."
	var locked: PackedStringArray = []
	for layer in layers:
		if layer.id in impacted and layer.locked:
			locked.append(layer.title)
	return "" if locked.is_empty() else "Unlock affected layers first: " + ", ".join(locked) + "."
