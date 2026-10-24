extends RefCounted
## Alea / Mash (Johannes Baagoe, MIT). See licenses/Alea-MIT.txt.
## Float64 arithmetic and JS unsigned conversion are intentional.

const UNIT: float = 2.3283064365386963e-10
var _n: float = 4022871197.0
var _s0: float
var _s1: float
var _s2: float
var _carry: int = 1


func _init(seed_text: String = "42") -> void:
	_s0 = _mash(" ")
	_s1 = _mash(" ")
	_s2 = _mash(" ")
	_s0 = fposmod(_s0 - _mash(seed_text), 1.0)
	_s1 = fposmod(_s1 - _mash(seed_text), 1.0)
	_s2 = fposmod(_s2 - _mash(seed_text), 1.0)


func next() -> float:
	var value: float = 2091639.0 * _s0 + _carry * UNIT
	_s0 = _s1
	_s1 = _s2
	_carry = int(value)
	_s2 = value - _carry
	return _s2


func probability(chance: float) -> bool:
	return true if chance >= 1.0 else (false if chance <= 0.0 else next() < chance)


func integer(minimum: float, maximum: float) -> float:
	# The source random helper can receive fractional bounds; do not round the bounds first.
	return floorf(next() * (maximum - minimum + 1.0)) + minimum


func number(text: String) -> int:
	if text.is_valid_float():
		var value: float = float(text)
		return int(value) + int(probability(value - int(value)))
	var separator: int = text.find("-", 1)
	return int(integer(float(text.left(separator)), float(text.substr(separator + 1))))


func _mash(text: String) -> float:
	var utf16: PackedByteArray = text.to_utf16_buffer()
	for i in range(0, utf16.size(), 2):
		_n += utf16[i] + utf16[i + 1] * 256
		var h: float = 0.02519603282416938 * _n
		_n = float(int(h) & 0xffffffff)
		h -= _n
		h *= _n
		_n = float(int(h) & 0xffffffff)
		h -= _n
		_n += h * 4294967296.0
	return float(int(_n) & 0xffffffff) * UNIT
