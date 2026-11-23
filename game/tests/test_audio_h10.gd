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


func test_unique_weapon_voices_and_armour_impact() -> void:
	const Cat = preload("res://presentation/audio/audio_catalog.gd")
	check_eq(Cat.shot_sound("g71_railgun"), "shot_rail", "rail voice")
	check_eq(Cat.shot_sound("g71_laser_beam"), "shot_energy", "laser voice")
	check_eq(Cat.shot_sound("g71_mlrs_pod"), "shot_rocket", "mlrs voice")
	var armour := "g71_m_reclaimer" if not Content.unit("g71_m_reclaimer").is_empty() else "m_walker"
	check_eq(Cat.impact_sound("rifle", armour), "impact_heavy", "armour clang")
	check_eq(Cat.impact_sound("rifle", "infantry_soft"), "impact_bullet", "flesh/ground thud")
