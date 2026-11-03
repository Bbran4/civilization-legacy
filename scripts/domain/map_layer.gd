extends RefCounted
## Editor state only. Payloads remain owned by their terrain systems.
var id: String
var title: String
var visible := true
var locked := false
var dependencies: Array[String] = []

func _init(key: String = "", label: String = "", reads: Array[String] = []) -> void:
	id = key
	title = label
	dependencies = reads

func to_dict() -> Dictionary:
	return {"id": id, "visible": visible, "locked": locked}
