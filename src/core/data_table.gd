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
## - `fields` names every key a row may carry, once, with its type: a scalar
##   (`int`, `float`, `bool`, `string`) or a `map<…>` / `list<…>` of one.
##   JSON has one number type and Godot parses all of them as float, so
##   without it a magazine of 12 would come back as 12.0. It is also what
##   refuses a typo: a misspelt key used to be a silent no-op. A field whose
##   value names something in another table says so with `ref` (or `key_ref`
##   for the keys of a map), and `check_refs` holds it to that.
## - `notes` on the table and on a row is the design reasoning that used to be
##   comments beside the literal. The game never reads it; `rows()` strips it.
## - Rows stay sparse. A key that is absent means what it always meant.
##
## `encode` is the only way a file is written, and it is deterministic: keys
## sorted, one entry per line, floats in one fixed form, a trailing newline.
## A one-field edit is a one-line diff, which is what lets two people change
## the same table and have git merge it. `data_test.gd` holds every file to it.

const DIR := "res://data/"
const SCALARS := ["int", "float", "bool", "string"]
const SPEC_KEYS := ["type", "ref", "key_ref"]
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
		elif typeof(spec) != TYPE_DICTIONARY or not valid_type(String(spec.get("type", ""))):
			errors.append("field '%s' needs a type: %s, or map<…> / list<…> of one" % [f, ", ".join(SCALARS)])
		else:
			for setting: String in spec:
				if not setting in SPEC_KEYS:
					errors.append("field '%s' has an unknown setting '%s'" % [f, setting])
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
			if typeof(typed) == TYPE_NIL:
				errors.append("%s.%s: expected %s, got %s" % [id, k, fields[k].type, JSON.stringify(row[k])])
			else:
				row[k] = typed
	return {"doc": doc, "errors": errors}


static func valid_type(type: String) -> bool:
	for wrap: String in ["map", "list"]:
		if type.begins_with(wrap + "<") and type.ends_with(">"):
			return type.substr(wrap.length() + 1, type.length() - wrap.length() - 2) in SCALARS
	return type in SCALARS


## Every `ref` names a set the value must be in, and every `key_ref` a set
## the keys of a map must be in — "every ammo is in AMMO_IDS", "every cost is
## a resource". `sets` maps a name to a Dictionary (its keys are the ids) or
## an Array (its items are). A set that is not there is an error, not a pass:
## a misspelt `ref` would otherwise check nothing for ever.
static func check_refs(doc: Dictionary, sets: Dictionary) -> Array:
	var errors := []
	var fields: Dictionary = doc.get("fields", {})
	for f: String in fields:
		for setting: String in ["ref", "key_ref"]:
			var set_name := String(fields[f].get(setting, ""))
			if not set_name.is_empty() and not sets.has(set_name):
				errors.append("field '%s' refers to '%s', which is not a table" % [f, set_name])
	for row: Variant in doc.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		for k: String in row:
			var spec: Variant = fields.get(k)
			if typeof(spec) != TYPE_DICTIONARY:
				continue
			var v: Variant = row[k]
			var keys: Array = v.keys() if typeof(v) == TYPE_DICTIONARY else []
			var values: Array = v.values() if typeof(v) == TYPE_DICTIONARY else (v if typeof(v) == TYPE_ARRAY else [v])
			for pair: Array in [["ref", values], ["key_ref", keys]]:
				var set_name := String(spec.get(pair[0], ""))
				if set_name.is_empty() or not sets.has(set_name):
					continue
				for x: Variant in pair[1]:
					if not in_set(sets[set_name], x):
						errors.append("%s.%s: '%s' is not in %s" % [row.get("id", "?"), k, x, set_name])
	return errors


static func in_set(s: Variant, id: Variant) -> bool:
	if typeof(s) == TYPE_DICTIONARY:
		return s.has(id)
	if typeof(s) == TYPE_ARRAY:
		return id in s
	return false


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


## The value as `type` declares it, or null when it cannot be one. A map's
## keys are always strings; its values and a list's items are each coerced.
static func _coerce(v: Variant, type: String) -> Variant:
	if type.begins_with("map<"):
		if typeof(v) != TYPE_DICTIONARY:
			return null
		var inner := type.substr(4, type.length() - 5)
		var out := {}
		for k: Variant in v:
			var c: Variant = _coerce(v[k], inner)
			if typeof(c) == TYPE_NIL:
				return null
			out[String(k)] = c
		return out
	if type.begins_with("list<"):
		if typeof(v) != TYPE_ARRAY:
			return null
		var inner := type.substr(5, type.length() - 6)
		var out := []
		for x: Variant in v:
			var c: Variant = _coerce(x, inner)
			if typeof(c) == TYPE_NIL:
				return null
			out.append(c)
		return out
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
