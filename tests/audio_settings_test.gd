extends "res://tests/test_case.gd"
## The three sliders (master, music, effects) and the row that drives each:
## that a click steps and wraps, that Left/Right nudges without wrapping, and
## that both halves of the audio actually multiply the sliders in.

var menu: MenuScreen


func before_each() -> void:
	menu = MenuScreen.new()
	Sfx.set_master_volume(1.0)
	Sfx.set_music_volume(1.0)
	Sfx.set_sfx_volume(1.0)


func after_each() -> void:
	menu.free()
	Sfx.set_master_volume(1.0)
	Sfx.set_music_volume(1.0)
	Sfx.set_sfx_volume(1.0)


func test_a_click_steps_a_tenth_and_wraps_from_full_to_silent() -> void:
	Sfx.set_music_volume(0.0)
	for i in range(10):
		menu._step_volume("vol_music")
	near(Sfx.music_volume(), 1.0, 1e-6, "ten steps from silent reaches full")
	menu._step_volume("vol_music")
	eq(Sfx.music_volume(), 0.0, "the eleventh wraps to silent")


func test_left_and_right_nudge_without_wrapping() -> void:
	Sfx.set_sfx_volume(0.0)
	menu._nudge_volume("vol_sfx", -0.1)
	eq(Sfx.sfx_volume(), 0.0, "Left at zero stays at zero")
	Sfx.set_sfx_volume(1.0)
	menu._nudge_volume("vol_sfx", 0.1)
	eq(Sfx.sfx_volume(), 1.0, "Right at full stays at full")


func test_each_slider_moves_its_own_row_only() -> void:
	Sfx.set_master_volume(0.0)
	menu._step_volume("vol_master")
	near(Sfx.master_volume(), 0.1, 1e-6)
	eq(Sfx.music_volume(), 1.0)
	eq(Sfx.sfx_volume(), 1.0)


# --------------------------------------------------------------- the mix --

func test_effects_volume_and_master_multiply_into_playback_gain() -> void:
	var full := Sfx.effective_gain()
	Sfx.set_sfx_volume(0.5)
	near(Sfx.effective_gain(), full * 0.5, 1e-4)
	Sfx.set_master_volume(0.5)
	near(Sfx.effective_gain(), full * 0.25, 1e-4)


func test_music_volume_and_master_multiply_into_the_score() -> void:
	var full := Music.effective_gain()
	Sfx.set_music_volume(0.5)
	near(Music.effective_gain(), full * 0.5, 1e-4)
	Sfx.set_master_volume(0.0)
	eq(Music.effective_gain(), 0.0)


func test_effects_volume_does_not_touch_the_score() -> void:
	var full := Music.effective_gain()
	Sfx.set_sfx_volume(0.0)
	eq(Music.effective_gain(), full)


func test_music_volume_does_not_touch_effects() -> void:
	var full := Sfx.effective_gain()
	Sfx.set_music_volume(0.0)
	eq(Sfx.effective_gain(), full)


# ----------------------------------------------------------- the sliders --

func _open_sound_tab() -> void:
	menu.open(MenuScreen.Page.CONTROLS)
	menu.settings_tab = "sound"
	menu.refresh()


func test_the_sound_tab_builds_a_slider_and_a_label_per_volume() -> void:
	_open_sound_tab()
	for id in ["vol_master", "vol_music", "vol_sfx"]:
		var ui: Dictionary = menu._vol_ui.get(id, {})
		ok(not ui.is_empty(), "%s built nothing" % id)
		ok(ui.slider is UiSlider, id)
		ok(ui.label is Label, id)


func test_a_drag_moves_the_bar_and_the_label_live() -> void:
	_open_sound_tab()
	menu._set_volume("vol_music", 0.4, false)
	var ui: Dictionary = menu._vol_ui.vol_music
	near((ui.slider as UiSlider).value, 0.4, 1e-6, "the bar followed the drag")
	eq((ui.label as Label).text, "40%", "and so did the label")


## The bug this guards: `_process` calls `refresh()` every frame, and
## `refresh()` throws the whole page away and rebuilds it when the page's
## signature changes. A drag calls `_set_volume` dozens of times a second —
## if the volume's own percentage were part of that signature, the very
## `UiSlider` mid-drag would be freed and replaced out from under the mouse,
## and dragging would die after one pixel of movement.
func test_dragging_does_not_rebuild_the_page_out_from_under_the_slider() -> void:
	_open_sound_tab()
	var before: UiSlider = menu._vol_ui.vol_master.slider
	menu._set_volume("vol_master", 0.4, false)
	menu.refresh()
	menu._set_volume("vol_master", 0.7, false)
	menu.refresh()
	eq(menu._vol_ui.vol_master.slider, before, "the drag rebuilt the slider out from under itself")
	near((before as UiSlider).value, 0.7, 1e-6)


func test_releasing_the_drag_persists_the_value() -> void:
	_open_sound_tab()
	menu._set_volume("vol_sfx", 0.6, true)
	eq(Sfx.sfx_volume(), 0.6)
