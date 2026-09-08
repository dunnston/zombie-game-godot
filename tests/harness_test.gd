extends "res://tests/test_case.gd"
## Proves the runner itself: discovery, before_each, every assertion helper.

var setup_ran := false

func before_each() -> void:
	setup_ran = true

func test_before_each_runs() -> void:
	ok(setup_ran, "before_each should run")

func test_assertions() -> void:
	eq(1 + 1, 2)
	ne("a", "b")
	near(0.1 + 0.2, 0.3, 1e-9)
	gt(3, 2)
	has([1, 2, 3], 2)
	has({"k": 1}, "k")
