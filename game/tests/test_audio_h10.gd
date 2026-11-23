extends "res://tests/test_base.gd"
## G7.1 H10: distant boom flash-to-sound delay math.

const AudioDirector = preload("res://presentation/audio/audio_director.gd")


func test_flash_delay_scales_with_distance() -> void:
	check(is_equal_approx(AudioDirector.flash_delay_s(0.5, true), 0.0), "close boom = 0")
	check(is_equal_approx(AudioDirector.flash_delay_s(2.0, false), 0.0), "non-boom = 0")
	var d := AudioDirector.flash_delay_s(AudioDirector.FAR_START + 1.0, true)
	check(d >= 0.05 and d <= AudioDirector.FLASH_DELAY_MAX, "mid delay in range")
	var far := AudioDirector.flash_delay_s(20.0, true)
	check(is_equal_approx(far, AudioDirector.FLASH_DELAY_MAX), "caps at max")
	check(AudioDirector.is_boom_id("shot_artillery"), "artillery is boom")
	check(not AudioDirector.is_boom_id("shot_rifle"), "rifle not boom")
