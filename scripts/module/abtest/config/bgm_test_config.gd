extends AbConfigBase
class_name BgmTestConfig
















const VALUE_DISABLED: int = 0
const VALUE_WHITE_NOISE: int = 1
const VALUE_AFTERNOON_TEA: int = 2
const VALUE_MEDITATION: int = 3
const VALUE_CUTE: int = 4
const VALUE_CUTE_DEFAULT_OFF: int = 5
const VALUE_AFTERNOON_TEA_LOUD: int = 6



const _BGM_PATHS: Dictionary = {
    VALUE_WHITE_NOISE: "res://assets/audio/bgm/bgm_white_noise.ogg", 
    VALUE_AFTERNOON_TEA: "res://assets/audio/bgm/bgm_afternoon_tea.ogg", 
    VALUE_MEDITATION: "res://assets/audio/bgm/bgm_meditation.ogg", 
    VALUE_CUTE: "res://assets/audio/bgm/bgm_cute.ogg", 
    VALUE_CUTE_DEFAULT_OFF: "res://assets/audio/bgm/bgm_cute.ogg", 
    VALUE_AFTERNOON_TEA_LOUD: "res://assets/audio/bgm/bgm_afternoon_tea_loud.ogg", 
}

func _init() -> void :
    key = "bgm_test"
    default_value = VALUE_DISABLED
    timing = ABTestManager.TIMING_APP_START


func is_enabled() -> bool:
    return value() != VALUE_DISABLED



func default_music_on() -> bool:
    return value() != VALUE_CUTE_DEFAULT_OFF


func bgm_path() -> String:
    return _BGM_PATHS.get(value(), "")
