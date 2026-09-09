extends SceneTree
## Headless test runner. Discovers res://tests/**/*_test.gd, runs every
## `test_*` method, prints one line per failure and a summary, and exits
## non-zero if anything failed. Run via tools/test.cmd.
##
## Optional filter: pass `-- <substring>` to run only matching test files.
##
## `_slow_test.gd` files are skipped unless the filter names them or `--all`
## is passed. There is exactly one: the compound siege harness, which is
## three and a half seconds of simulated raid on its own. The working
## agreement is that `tools\test` stays under ten seconds — the slow tier
## runs with `tools\test --all`, once per branch, beside the smoke run.

## Any engine-level error raised while a test runs. A GDScript runtime error
## inside a test method aborts that method and returns to this loop: the test
## then reports as passing on however few assertions it reached before the
## abort. Four methods in building_test.gd sat like that. An error the engine
## logged during a test is a failed test, so the counts in the summary are
## counts of tests that actually ran to the end.
##
## Keep `_log_error` cheap and format-free: it runs inside the engine's own
## error path, and an error raised in here would recurse.
class ErrorSpy extends Logger:
	var caught := []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		# Script errors carry the message in `code` and leave `rationale` empty;
		# push_error does the reverse.
		caught.append([file, line, function, code if rationale.is_empty() else rationale])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var filter := ""
	var run_all := false
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--all":
			run_all = true
		elif filter.is_empty():
			filter = a
	var files := _discover("res://tests", filter)
	if not run_all and filter.is_empty():
		var fast: Array[String] = []
		for f in files:
			if not f.get_file().ends_with("_slow_test.gd"):
				fast.append(f)
		files = fast
	if files.is_empty():
		push_error("no test files found")
		quit(2)
		return
	var total_tests := 0
	var total_asserts := 0
	var failures: Array[String] = []
	var t0 := Time.get_ticks_msec()
	var spy := ErrorSpy.new()
	for path in files:
		var script: GDScript = load(path)
		# A file with a parse error still loads as a script object; it just
		# cannot be instantiated and has no methods. Counting that as "zero
		# tests, zero failures" is how a broken test file passes a run.
		if script == null or not script.can_instantiate():
			failures.append("%s: failed to load (parse error above)" % path)
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if m.name.begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for name in methods:
			# Installed before the case is constructed: `_init` and the property
			# initializers are as much a part of the test as its body.
			spy.caught.clear()
			OS.add_logger(spy)
			var case = script.new()
			case.before_each()
			case.call(name)
			case.after_each()
			OS.remove_logger(spy)
			total_tests += 1
			total_asserts += case._asserts
			for f in case._failures:
				failures.append("%s::%s  %s" % [path.get_file(), name, f])
			for e in spy.caught:
				failures.append("%s::%s  engine error in %s (%s:%d): %s" % [path.get_file(), name, e[2], String(e[0]).get_file(), e[1], e[3]])
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
