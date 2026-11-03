extends RefCounted
## Draft strokes never mutate the installed world. History stores bounded pixel deltas.
const MAX_BYTES = 64 * 1024 * 1024
var current: RefCounted
var draft: RefCounted
var target := 0
var changes: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var history_bytes := 0
func sync(layer: RefCounted) -> void:
	if current == layer: return
	current = layer
	cancel()
	undo_stack.clear()
	redo_stack.clear()
	history_bytes = 0
func cancel() -> void:
	draft = null
	changes.clear()
func begin(layer: RefCounted, id: int) -> bool:
	sync(layer)
	if layer == null or id < 1 or id > layer.records.size() or not layer.records[id - 1].get("active", true): return false
	target = id
	draft = layer.editable_copy()
	changes.clear()
	return true
func stroke(a: Vector2, b: Vector2, radius: float, attach_islands: bool = false) -> void:
	if draft != null: draft.paint_segment(a, b, radius, target, changes, attach_islands)
func finish() -> Dictionary:
	if draft == null or changes.is_empty():
		cancel()
		return {"error": "", "layer": null}
	for i in range(draft.records.size()): draft.records[i].name = current.records[i].name
	var error: String = draft._index_regions(true)
	if not error.is_empty():
		cancel()
		return {"error": "Stroke cancelled: it would split a region on the same island or disconnect an ocean region.", "layer": null}
	var indices := PackedInt32Array()
	var before := PackedInt32Array()
	for pixel in changes:
		indices.append(pixel)
		before.append(changes[pixel])
	for entry in redo_stack: history_bytes -= entry.indices.size() * 8
	redo_stack.clear()
	var retired: Array[int] = []
	for i in range(draft.records.size()):
		if current.records[i].get("active", true) and not draft.records[i].active: retired.append(i)
	undo_stack.append({"indices": indices, "before": before, "target": target, "retired": retired})
	history_bytes += indices.size() * 8
	while undo_stack.size() > 50 or history_bytes > MAX_BYTES:
		history_bytes -= undo_stack.pop_front().indices.size() * 8
	current = draft
	cancel()
	return {"error": "", "layer": current}
func undo(layer: RefCounted) -> Dictionary:
	sync(layer)
	return _apply(false)
func redo(layer: RefCounted) -> Dictionary:
	sync(layer)
	return _apply(true)
func _apply(forward: bool) -> Dictionary:
	cancel()
	var stack: Array[Dictionary] = redo_stack if forward else undo_stack
	if stack.is_empty(): return {"error": "Nothing to redo." if forward else "Nothing to undo.", "layer": null}
	var entry: Dictionary = stack[-1]
	var next: RefCounted = current.editable_copy()
	for j in range(entry.indices.size()):
		next.ids[entry.indices[j]] = entry.target if forward else entry.before[j]
	for id in entry.get("retired", []): next.records[id].active = not forward
	var error: String = next._index_regions()
	if not error.is_empty(): return {"error": error, "layer": null}
	stack.pop_back()
	(undo_stack if forward else redo_stack).append(entry)
	current = next
	return {"error": "", "layer": current}
