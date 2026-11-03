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
	draft.nations.assign(current.nations.duplicate(true))
	for i in range(current.records.size()):
		draft.records[i].name = current.records[i].name
		draft.records[i].nation_id = current.records[i].get("nation_id",0)
	var error: String = draft._index_regions(true)
	if not error.is_empty():
		cancel()
		return {"error": "Stroke cancelled: it would disconnect an unmarked land province or a sea region.", "layer": null}
	var indices := PackedInt32Array()
	var before := PackedInt32Array()
	var before_mask := PackedByteArray()
	var after_mask := PackedByteArray()
	for pixel in changes:
		indices.append(pixel)
		before.append(changes[pixel])
		before_mask.append(1 if current.blocked(pixel) else 0)
		after_mask.append(1 if draft.blocked(pixel) else 0)
	for entry in redo_stack: history_bytes -= entry.indices.size() * 10
	redo_stack.clear()
	var policy_before: Dictionary = {}
	var policy_after: Dictionary = {}
	var retired: Array[int] = []
	for i in range(current.records.size()):
		if current.records[i].get("allow_fragments",false) != draft.records[i].get("allow_fragments",false):
			policy_before[i] = current.records[i].get("allow_fragments",false)
			policy_after[i] = draft.records[i].get("allow_fragments",false)
		if current.records[i].get("active", true) and not draft.records[i].active: retired.append(i)
	undo_stack.append({"indices": indices, "before": before, "policy_before":policy_before,"policy_after":policy_after,"before_mask": before_mask, "after_mask": after_mask, "target": target, "retired": retired, "created": range(current.records.size(), draft.records.size())})
	history_bytes += indices.size() * 10
	while undo_stack.size() > 50 or history_bytes > MAX_BYTES:
		history_bytes -= undo_stack.pop_front().indices.size() * 10
	current = draft
	cancel()
	var result := {"error": "", "layer": current}
	if not undo_stack[-1].created.is_empty(): result.new_id = target
	return result
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
	if not next.impassable.is_empty() or entry.before_mask.has(1) or entry.after_mask.has(1): next.impassable.resize(next.ids.size())
	for j in range(entry.indices.size()):
		next.ids[entry.indices[j]] = entry.target if forward else entry.before[j]
		if not next.impassable.is_empty(): next.impassable[entry.indices[j]] = entry.after_mask[j] if forward else entry.before_mask[j]
	for id in entry.get("retired", []): next.records[id].active = not forward
	for id in entry.get("created", []): next.records[id].active = forward
	var policy: Dictionary = entry.policy_after if forward else entry.policy_before
	for id in policy: next.records[id].allow_fragments = policy[id]
	var error: String = next._index_regions()
	if not error.is_empty(): return {"error": error, "layer": null}
	stack.pop_back()
	(undo_stack if forward else redo_stack).append(entry)
	current = next
	var result := {"error": "", "layer": current}
	if not entry.get("created", []).is_empty(): result.select_id = entry.target if forward else entry.before[0]
	return result

func split(layer: RefCounted, id: int, points: PackedVector2Array) -> Dictionary:
	if not begin(layer, id): return {"error": "Select an active province to split.", "layer": null}
	var result: Dictionary = draft.split_region(id, points)
	if not result.error.is_empty():
		cancel()
		return {"error": result.error, "layer": null}
	changes = result.changes
	target = result.new_id
	var committed := finish()
	if committed.layer != null: committed.new_id = target
	return committed

func merge(layer: RefCounted, keep: int, selected: Array[int]) -> Dictionary:
	if not begin(layer, keep): return {"error": "Select the province to keep.", "layer": null}
	var unique: Dictionary = {keep: true}
	for id in selected:
		if id < 1 or id > layer.records.size() or not layer.records[id - 1].active or layer.records[id - 1].kind != layer.records[keep - 1].kind:
			cancel()
			return {"error": "Merge only active provinces of the same land/ocean kind.", "layer": null}
		unique[id] = true
	if unique.size() < 2:
		cancel()
		return {"error": "Select at least two provinces to merge.", "layer": null}
	for pixel in range(draft.ids.size()):
		if draft.ids[pixel] != keep and unique.has(draft.ids[pixel]):
			changes[pixel] = draft.ids[pixel]
			draft.ids[pixel] = keep
	for id in unique:
		if layer.records[id-1].get("allow_fragments",false): draft.records[keep-1].allow_fragments = true
		if id != keep: draft.records[id - 1].active = false
	return finish()

func begin_erase(layer: RefCounted) -> bool:
	sync(layer)
	if layer == null: return false
	target = 0
	draft = layer.editable_copy()
	changes.clear()
	return true

func begin_new_land(layer: RefCounted, pixel: int) -> bool:
	sync(layer)
	if layer == null or layer.records.size() >= 65535 or pixel < 0 or pixel >= layer.ids.size() or not layer.blocked(pixel): return false
	draft = layer.editable_copy()
	target = draft.records.size() + 1
	draft.records.append({"id":target,"name":"Province " + str(target),"kind":"land","active":true,"landmasses":[layer._land_components[pixel]]})
	changes.clear()
	return true
