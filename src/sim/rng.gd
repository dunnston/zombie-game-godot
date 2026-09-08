class_name Rng
extends RefCounted
## Mulberry32, bit-for-bit the prototype's makeRng, so a seed produces the
## same world in both builds. Everything is kept masked to 32 bits; the low
## bits of a wrapped 64-bit product are the same as JS's Math.imul.

const MASK := 0xFFFFFFFF

var _a: int


func _init(seed_value: int) -> void:
	_a = seed_value & MASK


func next() -> float:
	_a = (_a + 0x6d2b79f5) & MASK
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & MASK)) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0


func frange(lo: float, hi: float) -> float:
	return lo + next() * (hi - lo)


## Inclusive on both ends.
func irange(lo: int, hi: int) -> int:
	return floori(lo + next() * (hi - lo + 1))


func pick(arr: Array) -> Variant:
	return arr[floori(next() * arr.size())]


func chance(p: float) -> bool:
	return next() < p


static func _imul(a: int, b: int) -> int:
	return (a * b) & MASK
