class_name Slots
extends RefCounted
## A slot container: the pack, the hotbar, a chest. One addressable list of
## `{id, n}` stacks, so everything the player owns can be moved, split,
## dropped and looked at the same way.
##
## An empty slot is an empty Dictionary rather than null, which keeps the
## array typed and matches how the rest of the sim spells "nothing here".
## Capacity in slots is enforced here; capacity in *weight* is the caller's
## business, because the player's budget spans two containers at once.

var slots: Array[Dictionary] = []


func _init(count: int = 0) -> void:
	for i in range(count):
		slots.append({})


func size() -> int:
	return slots.size()


func at(i: int) -> Dictionary:
	return slots[i] if i >= 0 and i < slots.size() else {}


func id_at(i: int) -> String:
	var s := at(i)
	return s.get("id", "")


func used() -> int:
	var n := 0
	for s in slots:
		if not s.is_empty():
			n += 1
	return n


## Total units of `id` held, across however many stacks hold it.
func count(id: String) -> int:
	var n := 0
	for s in slots:
		if not s.is_empty() and s.id == id:
			n += s.n
	return n


func weight() -> float:
	var w := 0.0
	for s in slots:
		if not s.is_empty():
			w += Items.weight_of(s.id) * s.n
	return w


func first_empty() -> int:
	for i in range(slots.size()):
		if slots[i].is_empty():
			return i
	return -1


## Everything held, flattened to id -> count. For iteration and for saving.
func entries() -> Dictionary:
	var out := {}
	for s in slots:
		if not s.is_empty():
			out[s.id] = out.get(s.id, 0) + s.n
	return out


## Adds up to `n` units, topping up part-used stacks before opening new
## slots. Returns how many actually fitted so the caller can spill the rest —
## no path may destroy material for want of somewhere to put it.
func add(id: String, n: int) -> int:
	if n <= 0 or not Items.has(id):
		return 0
	var maximum := Items.stack_limit(id)
	var left := n
	for s in slots:
		if left <= 0:
			break
		if not s.is_empty() and s.id == id and s.n < maximum:
			var take := mini(maximum - s.n, left)
			s.n += take
			left -= take
	for i in range(slots.size()):
		if left <= 0:
			break
		if not slots[i].is_empty():
			continue
		var take := mini(maximum, left)
		slots[i] = {"id": id, "n": take}
		left -= take
	return n - left


## Adds as much of `id` as fits without the carrier's weight budget going over
## `allowance`. Returns how many were added; the caller puts the rest on the
## ground. Slot space can still refuse what weight allowed, and `add` reports
## what actually fitted.
func add_capped(id: String, n: int, allowance: float) -> int:
	if n <= 0 or not Items.has(id):
		return 0
	var per := Items.weight_of(id)
	var fit := n
	if per > 0.0:
		fit = mini(n, maxi(0, floori((allowance - weight()) / per + 1e-9)))
	if fit <= 0:
		return 0
	return add(id, fit)


## Removes up to `n` units. Returns how many were actually removed.
func take(id: String, n: int) -> int:
	var left := n
	for i in range(slots.size()):
		if left <= 0:
			break
		var s := slots[i]
		if s.is_empty() or s.id != id:
			continue
		var got := mini(s.n, left)
		s.n -= got
		left -= got
		if s.n <= 0:
			slots[i] = {}
	return n - left


## How many more of `id` would fit, by slot space alone.
func room_for(id: String) -> int:
	if not Items.has(id):
		return 0
	var maximum := Items.stack_limit(id)
	var room := 0
	for s in slots:
		if s.is_empty():
			room += maximum
		elif s.id == id:
			room += maximum - s.n
	return room


func clear_all() -> void:
	for i in range(slots.size()):
		slots[i] = {}


## Moves or merges the stack at `from` onto `to`, optionally in another
## container. Same item merges up to the stack limit and leaves any remainder
## behind; anything else swaps.
func move(from: int, to: int, other: Slots = null) -> bool:
	var dst: Slots = other if other != null else self
	if from < 0 or from >= slots.size() or to < 0 or to >= dst.slots.size():
		return false
	if dst == self and from == to:
		return false
	var a := slots[from]
	if a.is_empty():
		return false
	var b := dst.slots[to]
	if not b.is_empty() and b.id == a.id:
		var room: int = Items.stack_limit(a.id) - b.n
		if room <= 0:
			return false
		var got := mini(room, a.n)
		b.n += got
		a.n -= got
		if a.n <= 0:
			slots[from] = {}
		return true
	dst.slots[to] = a
	slots[from] = b
	return true


## Splits half of a stack into an empty slot.
func split(from: int, to: int) -> bool:
	if from < 0 or from >= slots.size() or to < 0 or to >= slots.size():
		return false
	var a := slots[from]
	if a.is_empty() or a.n < 2 or not slots[to].is_empty():
		return false
	var half: int = a.n / 2
	slots[to] = {"id": a.id, "n": half}
	a.n -= half
	return true


## For saving and for the wire: a compact list of [index, id, n].
func to_record() -> Array:
	var out: Array = []
	for i in range(slots.size()):
		if not slots[i].is_empty():
			out.append([i, slots[i].id, slots[i].n])
	return out


func from_record(rec: Array) -> void:
	clear_all()
	for e in rec:
		var i: int = e[0]
		if i >= 0 and i < slots.size():
			slots[i] = {"id": String(e[1]), "n": int(e[2])}
