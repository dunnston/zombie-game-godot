extends "res://tests/test_case.gd"
## The RNG must match the prototype bit-for-bit so the same seed gives the
## same map. Reference values were produced by the browser build's makeRng.


func test_matches_prototype_sequence() -> void:
	var r := Rng.new(20240917)
	var expected := [0.5065789793152362, 0.454005642561242, 0.6535965329967439, 0.694403933826834, 0.8579618928488344]
	for e in expected:
		near(r.next(), e, 1e-15)


func test_helpers_match_prototype() -> void:
	var r := Rng.new(20240917)
	eq(r.irange(0, 3), 2)
	eq(r.irange(-5, 5), -1)
	eq(r.chance(0.5), false)
	near(r.frange(0, 6.28), 4.360856704432518, 1e-12)


func test_hash2_matches_prototype() -> void:
	near(Util.hash2(10, 20), 0.18978750333189964, 1e-15)
	near(Util.hash2(300, 7), 0.0710948018822819, 1e-15)
	near(Util.hash2(0, 0), 0.0, 1e-15)
