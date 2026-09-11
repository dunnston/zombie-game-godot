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
##
## A slot may also carry `w`: uses left, for a weapon that wears (see `Wear`).
## It is the one piece of per-object state a stack has, and it is here rather
## than on the player because condition has to travel with the weapon — into
## a chest, onto the ground, into somebody else's hands. Absent means "new",
## so nothing has to write a full value into a slot to say the obvious. Only
## weapons wear and weapons never stack, so no merge ever has to decide what
## the condition of two joined stacks would be.

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


## Uses left in the slot at `i`, or -1 for a slot that says nothing — which
## is every slot that is not a worn weapon.
func wear_at(i: int) -> int:
	var s := at(i)
	return int(s.get("w", -1)) if not s.is_empty() else -1


## Writes the condition of the slot at `i`. -1 clears it back to "new".
func set_wear_at(i: int, w: int) -> void:
	if i < 0 or i >= slots.size() or slots[i].is_empty():
		return
	if w < 0:
		slots[i].erase("w")
	else:
		slots[i]["w"] = w


## A weapon's level in the slot at `i`, or 0 for a slot that says nothing —
## which is level 1 (`Upgrade.level_in`). Carried beside the condition, on
## every path the condition takes.
func level_at(i: int) -> int:
	var s := at(i)
	return int(s.get("lv", 0)) if not s.is_empty() else 0


func set_level_at(i: int, lv: int) -> void:
	if i < 0 or i >= slots.size() or slots[i].is_empty():
		return
	if lv <= 1:
		slots[i].erase("lv")
	else:
		slots[i]["lv"] = lv


## Adds up to `n` units, topping up part-used stacks before opening new
## slots. Returns how many actually fitted so the caller can spill the rest —
## no path may destroy material for want of somewhere to put it.
##
## `wear` is uses left for a weapon that arrives already worn — out of a
## chest, off the ground, out of the pack of somebody who died. -1 is the
## ordinary case: a new thing, whole. `level` is a weapon's level on the way
## in, beside it, for the same reason; 0 or 1 is level 1.
func add(id: String, n: int, wear := -1, level := 0) -> int:
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
		if wear >= 0:
			slots[i]["w"] = wear
		if level > 1:
			slots[i]["lv"] = level
		left -= take
	return n - left


## Adds as much of `id` as fits without the carrier's weight budget going over
## `allowance`. Returns how many were added; the caller puts the rest on the
## ground. Slot space can still refuse what weight allowed, and `add` reports
## what actually fitted.
func add_capped(id: String, n: int, allowance: float, wear := -1, level := 0) -> int:
	if n <= 0 or not Items.has(id):
		return 0
	var per := Items.weight_of(id)
	var fit := n
	if per > 0.0:
		fit = mini(n, maxi(0, floori((allowance - weight()) / per + 1e-9)))
	if fit <= 0:
		return 0
	return add(id, fit, wear, level)


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


## Moves up to `n` units from one slot to another, which `move` cannot do —
## it takes the whole stack or merges what fits. Used where a rule has to
## cap the transfer: taking from a chest is limited by what you can carry.
##
## Only into an empty slot or one holding the same thing. A partial swap is
## not a thing.
func move_amount(from: int, to: int, n: int, other: Slots = null) -> bool:
	var dst: Slots = other if other != null else self
	if from < 0 or from >= slots.size() or to < 0 or to >= dst.slots.size() or n <= 0:
		return false
	var a := slots[from]
	if a.is_empty():
		return false
	var b := dst.slots[to]
	var room := Items.stack_limit(a.id)
	if not b.is_empty():
		if b.id != a.id:
			return false
		room -= b.n
	var got := mini(mini(n, a.n), room)
	if got <= 0:
		return false
	if b.is_empty():
		dst.slots[to] = {"id": a.id, "n": got}
		if a.has("w"):
			dst.slots[to]["w"] = a.w
		if a.has("lv"):
			dst.slots[to]["lv"] = a.lv
	else:
		b.n += got
	a.n -= got
	if a.n <= 0:
		slots[from] = {}
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


## For saving and for the wire: a compact list of [index, id, n], with a
## fourth field only where a slot has a condition to report. Keeping it
## optional means every stack in the game writes exactly what it used to.
func to_record() -> Array:
	var out: Array = []
	for i in range(slots.size()):
		if slots[i].is_empty():
			continue
		# A level rides fifth, after the condition — with -1 there for a
		# levelled weapon that is still whole.
		if slots[i].has("lv"):
			out.append([i, slots[i].id, slots[i].n, int(slots[i].get("w", -1)), int(slots[i].lv)])
		elif slots[i].has("w"):
			out.append([i, slots[i].id, slots[i].n, int(slots[i].w)])
		else:
			out.append([i, slots[i].id, slots[i].n])
	return out


func from_record(rec: Array) -> void:
	clear_all()
	for e in rec:
		var i: int = e[0]
		if i >= 0 and i < slots.size():
			slots[i] = {"id": String(e[1]), "n": int(e[2])}
			if e.size() > 3 and int(e[3]) >= 0:
				slots[i]["w"] = int(e[3])
			if e.size() > 4 and int(e[4]) > 1:
				slots[i]["lv"] = int(e[4])
