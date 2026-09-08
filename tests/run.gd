extends SceneTree
## Headless test runner. Discovers res://tests/**/*_test.gd, runs every
## `test_*` method, prints one line per failure and a summary, and exits
## non-zero if anything failed. Run via tools/test.cmd.
##
## Optional filter: pass `-- <substring>` to run only matching test files.

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files := _discover("res://tests", filter)
	if files.is_empty():
		push_error("no test files found")
		quit(2)
		return
	var total_tests := 0
	var total_asserts := 0
	var failures: Array[String] = []
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			failures.append("%s: failed to load" % path)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if m.name.begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for name in methods:
			var case = script.new()
			case.before_each()
			case.call(name)
			case.after_each()
			total_tests += 1
			total_asserts += case._asserts
			for f in case._failures:
				failures.append("%s::%s  %s" % [path.get_file(), name, f])
	var ms := Time.get_ticks_msec() - t0
	for f in failures:
		printerr("FAIL " + f)
	print("tests: %d  asserts: %d  failures: %d  (%d ms, %d files)" % [total_tests, total_asserts, failures.size(), ms, files.size()])
	quit(1 if failures.size() > 0 else 0)

func _discover(dir: String, filter: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_discover(full, filter))
		elif name.ends_with("_test.gd") and (filter.is_empty() or name.contains(filter)):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
