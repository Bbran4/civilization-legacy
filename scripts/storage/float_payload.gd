extends RefCounted
## Lossless, bounded float32 payloads for derived caches and water profiles.
static func encode(values: PackedFloat32Array) -> Dictionary:
	return {"count": values.size(), "deflate": Marshalls.raw_to_base64(values.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE))}

static func decode(data: Variant, count: int, minimum: float, maximum: float) -> Dictionary:
	if not data is Dictionary or not (data.get("count") is int or data.get("count") is float) or data.count != count or not data.get("deflate") is String or data.deflate.length() > 128 * 1024 * 1024:
		return {"error": "Invalid float payload."}
	if count < 0 or count > 17210000:
		return {"error": "Float payload exceeds the supported dimensions."}
	var compressed := Marshalls.base64_to_raw(data.deflate)
	if compressed.size() < 2 or compressed.size() > count * 4 + 65536:
		return {"error": "Invalid compressed float payload."}
	var bytes := compressed.decompress(count * 4, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != count * 4:
		return {"error": "Float payload is truncated."}
	var values := bytes.to_float32_array()
	for value in values:
		if not is_finite(value) or value < minimum or value > maximum:
			return {"error": "Float payload contains invalid values."}
	return {"error": "", "values": values}
