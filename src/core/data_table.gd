class_name DataTable
## A content table kept as data in `data/<name>.json` instead of as a literal
## in `config.gd`. Config still owns every table (invariant 5): it loads each
## one through here at boot and exposes it under the name it always had, so
## nothing that reads `Config.WEAPONS` knows the difference.
##
## The file is the merge layer for collaboration, so its shape is dictated by
## git rather than by taste:
##
## - `rows` is an array, because row order is meaningful — the game iterates
##   tables in order and the RNG draws against that order.
## - `fields` names every key a row may carry, once, with its type. JSON has
##   one number type and Godot parses all of them as float, so without it a
##   magazine of 12 would come back as 12.0. It is also what refuses a typo:
##   a misspelt key used to be a silent no-op.
## - `notes` on the table and on a row is the design reasoning that used to be
##   comments beside the literal. The game never reads it; `rows()` strips it.
## - Rows stay sparse. A key that is absent means what it always meant.
##
## `encode` is the only way a file is written, and it is deterministic: keys
## sorted, one entry per line, floats in one fixed form, a trailing newline.
## A one-field edit is a one-line diff, which is what lets two people change
## the same table and have git merge it. `data_test.gd` holds every file to it.

const DIR := "res://data/"
const TYPES := ["int", "float", "bool", "string"]
## Not listed in `fields`: every row has an `id`, and any row may have `notes`.
const RESERVED := ["id", "notes"]


## The table as the game sees it: rows keyed by id, in file order, notes
## removed, typed by the schema, and read-only all the way down the way a
## `const` literal was. A broken file is an engine error, which fails the test
## run and is loud in the game — never a quietly empty table.
static func load_rows(table: String) -> Dictionary:
	var path := DIR + table + ".json"
	if not FileAccess.file_exists(path):
		push_error("%s: file not found" % path)
		return {}
	var got := decode(FileAccess.get_file_as_string(path))
	for problem: String in got.errors:
		push_error("%s: %s" % [path, problem])
	return rows(got.doc)


## Parses and checks a file's text. Returns `{"doc": Dictionary, "errors":
## Array}`; numbers in `doc` are already the type their field declares.
static func decode(text: String) -> Dictionary:
	var errors := []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"doc": {}, "errors": ["not a JSON object"]}
	var doc: Dictionary = parsed
	for k: String in doc:
		if not k in ["fields", "notes", "rows"]:
			errors.append("unknown top-level key '%s'" % k)
	if typeof(doc.get("notes", "")) != TYPE_STRING:
		errors.append("table notes must be a string")
	var fields: Dictionary = doc.get("fields", {}) if typeof(doc.get("fields")) == TYPE_DICTIONARY else {}
	if fields.is_empty():
		errors.append("'fields' must be a non-empty object")
	for f: String in fields:
		var spec: Variant = fields[f]
		if f in RESERVED:
			errors.append("field '%s' is reserved and must not be declared" % f)
		elif typeof(spec) != TYPE_DICTIONARY or not String(spec.get("type", "")) in TYPES:
			errors.append("field '%s' needs a type, one of %s" % [f, TYPES])
	if typeof(doc.get("rows")) != TYPE_ARRAY:
		errors.append("'rows' must be an array")
		return {"doc": doc, "errors": errors}
	var seen := {}
	for i in doc.rows.size():
		var row: Variant = doc.rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			errors.append("row %d is not an object" % i)
			continue
		var id: Variant = row.get("id")
		if typeof(id) != TYPE_STRING or String(id).is_empty():
			errors.append("row %d has no id" % i)
			continue
		if seen.has(id):
			errors.append("id '%s' appears twice" % id)
		seen[id] = true
		for k: String in row:
			if k == "id":
				continue
			if k == "notes":
				if typeof(row[k]) != TYPE_STRING:
					errors.append("%s.notes must be a string" % id)
				continue
			if not fields.has(k) or typeof(fields[k]) != TYPE_DICTIONARY:
				errors.append("%s.%s is not a declared field" % [id, k])
				continue
			var typed: Variant = _coerce(row[k], String(fields[k].get("type", "")))
			if typed == null:
				errors.append("%s.%s: expected %s, got %s" % [id, k, fields[k].type, JSON.stringify(row[k])])
			else:
				row[k] = typed
	return {"doc": doc, "errors": errors}


## Id -> row, in file order, without notes, deep read-only.
static func rows(doc: Dictionary) -> Dictionary:
	var out := {}
	for row: Variant in doc.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("id")) != TYPE_STRING:
			continue
		var r: Dictionary = row.duplicate(true)
		r.erase("notes")
		out[r.id] = r
	_freeze(out)
	return out


## The canonical text of a document. Any file that differs from
## `encode(decode(text).doc)` was not written by this, and the tests say so.
static func encode(doc: Dictionary) -> String:
	return _enc(doc, "") + "\n"


static func _enc(v: Variant, indent: String) -> String:
	var inner := indent + "  "
	match typeof(v):
		TYPE_DICTIONARY:
			if v.is_empty():
				return "{}"
			# By text, not by Variant: `row.dur = 5` makes a StringName key, and
			# a plain sort puts every StringName after every String.
			var keys: Array = v.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
			var parts := []
			for k: Variant in keys:
				parts.append(inner + JSON.stringify(String(k)) + ": " + _enc(v[k], inner))
			return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
		TYPE_ARRAY:
			if v.is_empty():
				return "[]"
			var parts := []
			for x: Variant in v:
				parts.append(inner + _enc(x, inner))
			return "[\n" + ",\n".join(parts) + "\n" + indent + "]"
		TYPE_FLOAT:
			return float_text(v)
		TYPE_INT:
			return str(v)
		TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(v)
	push_error("DataTable cannot encode %s" % type_string(typeof(v)))
	return "null"


## One fixed form for every float: Godot's shortest text, always with a
## decimal point, never an exponent. `12.0`, `0.075`, `1150.0`.
static func float_text(f: float) -> String:
	var s := str(f)
	if not s.contains("."):
		s += ".0"
	return s


static func _coerce(v: Variant, type: String) -> Variant:
	match type:
		"float":
			if typeof(v) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(v)):
				return float(v)
		"int":
			if typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) == floorf(float(v)) and abs(float(v)) < 9.0e15:
				return int(v)
		"bool":
			if typeof(v) == TYPE_BOOL:
				return v
		"string":
			if typeof(v) == TYPE_STRING:
				return v
	return null


static func _freeze(v: Variant) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v:
			_freeze(v[k])
		v.make_read_only()
	elif typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			_freeze(x)
		v.make_read_only()
