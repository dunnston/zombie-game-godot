class_name TestCase
extends RefCounted
## Base class for headless tests. Subclass, name methods `test_*`, use the
## assertions below. Failures are recorded, not thrown, so one test reports
## every broken assertion instead of stopping at the first.

var _failures: Array[String] = []
var _asserts := 0

func before_each() -> void:
	pass

func after_each() -> void:
	pass

func _fail(msg: String) -> void:
	var where := ""
	for frame in get_stack():
		var src: String = frame.get("source", "")
		if src.ends_with("_test.gd"):
			where = "%s:%d " % [src.get_file(), frame.get("line", 0)]
			break
	_failures.append(where + msg)

func ok(cond: bool, msg := "") -> void:
	_asserts += 1
	if not cond:
		_fail("expected true" + ("" if msg.is_empty() else ": " + msg))

func eq(actual, expected, msg := "") -> void:
	_asserts += 1
	if actual != expected:
		_fail("expected %s, got %s%s" % [str(expected), str(actual), "" if msg.is_empty() else " (" + msg + ")"])

func ne(actual, unexpected, msg := "") -> void:
	_asserts += 1
	if actual == unexpected:
		_fail("expected something other than %s%s" % [str(unexpected), "" if msg.is_empty() else " (" + msg + ")"])

func near(actual: float, expected: float, tol := 1e-6, msg := "") -> void:
	_asserts += 1
	if absf(actual - expected) > tol:
		_fail("expected %f ± %f, got %f%s" % [expected, tol, actual, "" if msg.is_empty() else " (" + msg + ")"])

func gt(actual, floor_value, msg := "") -> void:
	_asserts += 1
	if not (actual > floor_value):
		_fail("expected > %s, got %s%s" % [str(floor_value), str(actual), "" if msg.is_empty() else " (" + msg + ")"])

func has(container, item, msg := "") -> void:
	_asserts += 1
	if not container.has(item):
		_fail("expected %s to contain %s%s" % [str(container), str(item), "" if msg.is_empty() else " (" + msg + ")"])
