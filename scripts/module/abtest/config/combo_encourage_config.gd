extends AbConfigBase
class_name ComboEncourageConfig

const VALUE_DISABLED: int = 0
const VALUE_ENCOURAGE_FIXED: int = 1
const VALUE_ENCOURAGE_VOICE: int = 2
const VALUE_ENCOURAGE_SCORE: int = 3
const VALUE_ENCOURAGE_IQ: int = 4
const VALUE_ENCOURAGE_FOLLOW: int = 5
const VALUE_ENCOURAGE_VOICE_FEMALE: int = 6


func _init() -> void:
	key = "combo_encourage"
	default_value = VALUE_DISABLED
	timing = ABTestManager.TIMING_GAME_START


func is_enabled() -> bool:
	return value() != VALUE_DISABLED


func has_score_display() -> bool:
	var v: int = value()
	return v == VALUE_ENCOURAGE_SCORE or v == VALUE_ENCOURAGE_IQ or v == VALUE_ENCOURAGE_FOLLOW


func is_iq_mode() -> bool:
	return value() == VALUE_ENCOURAGE_IQ


func should_play_voice() -> bool:
	var v: int = value()
	return v == VALUE_ENCOURAGE_VOICE or v == VALUE_ENCOURAGE_VOICE_FEMALE


func is_female_voice() -> bool:
	return value() == VALUE_ENCOURAGE_VOICE_FEMALE


func is_follow_cat() -> bool:
	return value() == VALUE_ENCOURAGE_FOLLOW
