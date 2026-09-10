extends SceneTree
## Moves one content table out of `config.gd` into `data/<name>.json`.
##
##   godot --headless --path . -s tools/migrate_table.gd -- WEAPONS weapons
##
## Reads the constant as the game sees it, carries its comments across as
## `notes` (the `##` block above it onto the table, a `#` comment inside the
## literal onto the row it sits on or above), writes the canonical file, then
## decodes that file back and fails unless every row, key, value, type and the
## row order match the literal exactly, and unless every word of every comment
## arrived. Only after it passes is the literal replaced with the loader.
##
## Scaffolding: it reads constants that the migration deletes, so it goes when
## the last table has moved.

const CONFIG := "res://src/config.gd"
var failures := []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -s tools/migrate_table.gd -- <CONST_NAME> <file_name>")
		quit(2)
		return
	var const_name: String = args[0]
	var table: String = args[1]
	var constants: Dictionary = (load(CONFIG) as GDScript).get_script_constant_map()
	if not constants.has(const_name) or typeof(constants[const_name]) != TYPE_DICTIONARY:
		printerr("%s is not a Dictionary constant in config.gd (already migrated?)" % const_name)
		quit(2)
		return
	var table_value: Dictionary = constants[const_name]
	var lines := FileAccess.get_file_as_string(CONFIG).split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].begins_with("const %s :=" % const_name):
			start = i
	if start < 0:
		printerr("no `const %s :=` line" % const_name)
		quit(2)
		return

	# The `##` block directly above the constant is the table's design note.
	var header := []
	var i := start - 1
	while i >= 0 and lines[i].begins_with("##"):
		header.push_front(lines[i])
		i -= 1
	var table_notes := unwrap(header)

	var row_notes := row_comments(lines, start, table_value)
	var doc := build(table_value, table_notes, row_notes)
	if not failures.is_empty():
		finish()
		return

	var text := DataTable.encode(doc)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DataTable.DIR))
	var path := DataTable.DIR + table + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

	# Parity: read back what was written, through the loader the game uses.
	var got := DataTable.decode(FileAccess.get_file_as_string(path))
	for e: String in got.errors:
		failures.append("decode: " + e)
	if DataTable.encode(got.doc) != text:
		failures.append("the written file is not canonical")
	strict_equal(DataTable.rows(got.doc), table_value, const_name)
	if not failures.is_empty():
		finish()
		return

	# Every word of every comment arrived, in order.
	var said := words("\n".join(header))
	var kept := words(table_notes)
	if said != kept:
		failures.append("table notes lost words")
	for id: String in row_notes:
		if words(row_notes[id].raw) != words(row_notes[id].text):
			failures.append("%s notes lost words" % id)

	print("%s -> %s: %d rows, %d fields, table notes %d words, row notes on %s" % [
		const_name, path, table_value.size(), doc.fields.size(), kept.size(),
		row_notes.keys() if not row_notes.is_empty() else "none"])
	print("parity: every row, key, value, type and the row order match the literal")
	finish()


func finish() -> void:
	for f: String in failures:
		printerr("FAIL " + f)
	quit(1 if failures.size() > 0 else 0)


## `fields` inferred from the values the game already reads. A key that is an
## int on one row and a float on another is a real ambiguity in the literal,
## and it stops the migration rather than being guessed.
func build(table_value: Dictionary, table_notes: String, row_notes: Dictionary) -> Dictionary:
	var fields := {}
	var rows := []
	for id: String in table_value:
		var src: Dictionary = table_value[id]
		if String(src.get("id", id)) != id:
			failures.append("%s: key and id disagree" % id)
		var row := src.duplicate(true)
		row["id"] = id
		for k: String in src:
			if k == "id":
				continue
			var t := type_name(src[k])
			if t.is_empty():
				failures.append("%s.%s: %s is not a supported field type yet" % [id, k, type_string(typeof(src[k]))])
			elif fields.has(k) and fields[k].type != t:
				failures.append("%s: %s here, %s elsewhere" % [k, t, fields[k].type])
			else:
				fields[k] = {"type": t}
		if row_notes.has(id):
			row["notes"] = row_notes[id].text
		rows.append(row)
	var doc := {"fields": fields, "rows": rows}
	if not table_notes.is_empty():
		doc["notes"] = table_notes
	return doc


func type_name(v: Variant) -> String:
	match typeof(v):
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_BOOL: return "bool"
		TYPE_STRING: return "string"
	return ""


## `#` comments inside the literal. One on its own line belongs to the next row
## that opens at the same depth, or to the enclosing row if it sits inside
## one; one trailing a row belongs to that row. A comment that lands on no row
## fails the migration rather than being dropped.
func row_comments(lines: PackedStringArray, start: int, table_value: Dictionary) -> Dictionary:
	var out := {}
	var pending := []
	var depth := 0
	var current := ""
	for i in range(start, lines.size()):
		var line := lines[i]
		var code := strip_comment(line)
		var comment := line.substr(code.length()).strip_edges()
		var opens_row := ""
		if depth == 1:
			var m := RegEx.create_from_string("^\\s*\"([^\"]+)\"\\s*:").search(code)
			if m != null and table_value.has(m.get_string(1)):
				opens_row = m.get_string(1)
		if not opens_row.is_empty():
			current = opens_row
			if not pending.is_empty():
				note(out, current, pending)
				pending = []
		if comment.begins_with("#"):
			if code.strip_edges().is_empty() and depth == 1:
				pending.append(comment)
			elif not current.is_empty():
				note(out, current, [comment])
			else:
				failures.append("line %d: comment outside any row: %s" % [i + 1, comment])
		for ch in code:
			if ch in "{[":
				depth += 1
			elif ch in "}]":
				depth -= 1
		if depth == 1 and code.strip_edges().ends_with("},") or depth == 1 and code.strip_edges().ends_with("}"):
			current = ""
		if i > start and depth == 0:
			break
	if not pending.is_empty():
		failures.append("comment after the last row: %s" % pending)
	return out


func note(out: Dictionary, id: String, comments: Array) -> void:
	var raw := "\n".join(comments)
	var text := unwrap(comments)
	if out.has(id):
		out[id].raw += "\n" + raw
		out[id].text += "\n\n" + text
	else:
		out[id] = {"raw": raw, "text": text}


## A line with any comment removed. `#` inside a string (a colour) is not one.
func strip_comment(line: String) -> String:
	var in_str := false
	for j in line.length():
		var ch := line[j]
		if ch == "\"" and (j == 0 or line[j - 1] != "\\"):
			in_str = not in_str
		elif ch == "#" and not in_str:
			return line.substr(0, j)
	return line


## Comment lines to prose: markers off, lines of a paragraph joined, blank
## comment lines kept as paragraph breaks, and list or table lines kept on
## their own line. The wrap was the editor's, not the author's.
func unwrap(comment_lines: Array) -> String:
	var paras := []
	var cur := []
	for l: String in comment_lines:
		var t := l.lstrip("#").strip_edges()
		if t.is_empty():
			if not cur.is_empty():
				paras.append(" ".join(cur))
			cur = []
		elif is_list_line(t) and not cur.is_empty():
			paras.append(" ".join(cur))
			cur = [t]
		else:
			cur.append(t)
	if not cur.is_empty():
		paras.append(" ".join(cur))
	# A list item and its continuation lines are one paragraph; consecutive
	# list items are separated by one newline rather than a blank line.
	var out := ""
	for p_i in paras.size():
		if p_i > 0:
			out += "\n" if is_list_line(paras[p_i]) and is_list_line(paras[p_i - 1]) else "\n\n"
		out += paras[p_i]
	return out


func is_list_line(t: String) -> bool:
	return t.begins_with("- ") or t.begins_with("* ") or t.begins_with("|") \
		or RegEx.create_from_string("^\\d+\\. ").search(t) != null


func words(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in s.replace("\n", " ").split(" ", false):
		var t := w.lstrip("#")
		if not t.is_empty():
			out.append(t)
	return out


## Same keys, same values, same Variant types, and the same row order. Plain
## `==` on dictionaries would pass 12 against 12.0.
func strict_equal(a: Variant, b: Variant, path: String) -> void:
	if typeof(a) != typeof(b):
		failures.append("%s: %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			failures.append("%s: %d keys vs %d" % [path, a.size(), b.size()])
		for k: Variant in b:
			if not a.has(k):
				failures.append("%s.%s missing" % [path, k])
			else:
				strict_equal(a[k], b[k], "%s.%s" % [path, k])
	elif typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			failures.append("%s: %d items vs %d" % [path, a.size(), b.size()])
		else:
			for j in a.size():
				strict_equal(a[j], b[j], "%s[%d]" % [path, j])
	elif a != b:
		failures.append("%s: %s vs %s" % [path, a, b])
	if path.count(".") == 0 and typeof(a) == TYPE_DICTIONARY and a.keys() != b.keys():
		failures.append("%s: row order differs" % path)
