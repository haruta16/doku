extends AbConfigBase
class_name ComboVoiceConfig

const VALUE_DISABLED: int = 0
const VALUE_AI_CAT: int = 1
const VALUE_AI_FEMALE: int = 2
const VALUE_REAL_FEMALE_1: int = 3
const VALUE_REAL_FEMALE_2: int = 4
const VALUE_REAL_FEMALE_3: int = 5
const VALUE_REAL_MALE_1: int = 6
const VALUE_REAL_MALE_2: int = 7
const VALUE_REAL_MALE_3: int = 8

const _VOICE_SET_PATHS: Dictionary = {
	VALUE_AI_CAT:
	{
		3: "res://assets/audio/sfx/combo_nice_s1.ogg",
		4: "res://assets/audio/sfx/combo_great_s1.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s1.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s1.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s1.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s1.ogg",
	},
	VALUE_AI_FEMALE:
	{
		3: "res://assets/audio/sfx/combo_nice_s2.ogg",
		4: "res://assets/audio/sfx/combo_great_s2.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s2.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s2.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s2.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s2.ogg",
	},
	VALUE_REAL_FEMALE_1:
	{
		3: "res://assets/audio/sfx/combo_nice_s3.ogg",
		4: "res://assets/audio/sfx/combo_great_s3.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s3.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s3.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s3.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s3.ogg",
	},
	VALUE_REAL_FEMALE_2:
	{
		3: "res://assets/audio/sfx/combo_nice_s4.ogg",
		4: "res://assets/audio/sfx/combo_great_s4.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s4.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s4.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s4.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s4.ogg",
	},
	VALUE_REAL_FEMALE_3:
	{
		3: "res://assets/audio/sfx/combo_nice_s5.ogg",
		4: "res://assets/audio/sfx/combo_great_s5.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s5.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s5.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s5.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s5.ogg",
	},
	VALUE_REAL_MALE_1:
	{
		3: "res://assets/audio/sfx/combo_nice_s6.ogg",
		4: "res://assets/audio/sfx/combo_great_s6.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s6.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s6.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s6.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s6.ogg",
	},
	VALUE_REAL_MALE_2:
	{
		3: "res://assets/audio/sfx/combo_nice_s7.ogg",
		4: "res://assets/audio/sfx/combo_great_s7.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s7.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s7.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s7.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s7.ogg",
	},
	VALUE_REAL_MALE_3:
	{
		3: "res://assets/audio/sfx/combo_nice_s8.ogg",
		4: "res://assets/audio/sfx/combo_great_s8.ogg",
		5: "res://assets/audio/sfx/combo_perfect_s8.ogg",
		6: "res://assets/audio/sfx/combo_excellent_s8.ogg",
		7: "res://assets/audio/sfx/combo_amazing_s8.ogg",
		8: "res://assets/audio/sfx/combo_unbelievable_s8.ogg",
	},
}


func _init() -> void:
	key = "combo_voice"
	default_value = VALUE_DISABLED
	timing = ABTestManager.TIMING_APP_START


func is_enabled() -> bool:
	return value() != VALUE_DISABLED


func get_combo_voice(combo_count: int) -> String:
	var voice_set: int = value()
	if voice_set <= 0:
		return ""
	var paths: Dictionary = _VOICE_SET_PATHS.get(voice_set, {})
	var level: int = clampi(combo_count, 3, 8)
	return paths.get(level, "")
