class_name UiScreen
extends Control
## What every full screen shares: sections that rebuild themselves when what
## they show changes, per-frame refreshers for the numbers that move, and
## lookups by name for the buttons and rows the smoke run and the keyboard
## have to find.
##
## A section is a container, a signature function and a build function. Once
## a frame the screen asks each signature; a changed one clears its container
## and builds it again. Rebuilding happens here, in `refresh`, and never inside
## a button's own callback — so a button is never freed while it is emitting.

var _sections: Array[Dictionary] = []
## {f, owner}: a refresher registered while a section is being built belongs to
## that section and goes when it is rebuilt — otherwise it would go on
## refreshing nodes the rebuild has already freed.
var _refreshers: Array[Dictionary] = []
var _building := -1
## Buttons by id and rows by "kind:id", rebuilt with the screen.
var _buttons := {}
var _named := {}


## A container whose contents are rebuilt when `sig` changes.
func section(box: Container, sig: Callable, build: Callable) -> Container:
	_sections.append({"box": box, "sig": sig, "build": build, "last": "<unbuilt>", "id": _sections.size()})
	return box


## Called every frame while the screen is up.
func refresher(f: Callable) -> void:
	_refreshers.append({"f": f, "owner": _building})


func reset_screen() -> void:
	_sections.clear()
	_refreshers.clear()
	_buttons.clear()
	_named.clear()
	Ui.clear(self)


func run_sections() -> void:
	for s in _sections:
		var v: String = s.sig.call()
		if v != s.last:
			s.last = v
			var box: Container = s.box
			var sid: int = s.id
			_forget(box)
			Ui.clear(box)
			_refreshers = _refreshers.filter(func(r: Dictionary) -> bool: return int(r.owner) != sid)
			_building = sid
			s.build.call(box)
			_building = -1
	for r in _refreshers:
		(r.f as Callable).call()


## Drops lookups into a section that is about to be rebuilt.
func _forget(box: Node) -> void:
	for k in _buttons.keys():
		var b: Node = _buttons[k]
		if not is_instance_valid(b) or box.is_ancestor_of(b):
			_buttons.erase(k)
	for k in _named.keys():
		var r: Node = _named[k]
		if not is_instance_valid(r) or box.is_ancestor_of(r):
			_named.erase(k)


func reg_button(id: String, b: Button) -> Button:
	_buttons[id] = b
	return b


func reg_row(key: String, c: Control) -> Control:
	_named[key] = c
	return c


## The middle of a button, for the smoke run's cursor; zero when it is not on
## screen, which the smoke run reports rather than clicking nothing.
func button_centre(id: String) -> Vector2:
	var b: Control = _buttons.get(id, null)
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree():
		return Vector2.ZERO
	return b.get_global_rect().get_center()


func _centre(key: String) -> Vector2:
	var c: Control = _named.get(key, null)
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return Vector2.ZERO
	return c.get_global_rect().get_center()
