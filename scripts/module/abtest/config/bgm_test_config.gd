## 实验配置 bgm_test：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BgmTestConfig

# ---- 分组取值（同时也是曲目编号） ----
const VALUE_DISABLED: int = 0 # 不换曲，用游戏原有 BGM
const VALUE_WHITE_NOISE: int = 1 # 白噪音
const VALUE_AFTERNOON_TEA: int = 2 # 下午茶
const VALUE_MEDITATION: int = 3 # 冥想
const VALUE_CUTE: int = 4 # 可爱风
const VALUE_CUTE_DEFAULT_OFF: int = 5 # 可爱风，但音乐开关默认关闭
const VALUE_AFTERNOON_TEA_LOUD: int = 6 # 下午茶（响亮版，另一份素材）
const VALUE_G7: int = 7
const VALUE_G8: int = 8
const VALUE_G9: int = 9
const VALUE_G10: int = 10
const VALUE_G11: int = 11
const VALUE_G12: int = 12
const VALUE_G13: int = 13
const VALUE_G14: int = 14
const VALUE_G15: int = 15

const _RAIN_PATH: String = "res://assets/audio/bgm/bgm_rain.ogg"

const _FALLBACK_MUSIC: Dictionary = {state = 0, path = _RAIN_PATH}

const MUSIC_BY_GROUP: Dictionary = {
	8: {state = 0, path = _RAIN_PATH},
	12: {state = 0, path = "res://assets/audio/bgm/bgm_piano_rain.ogg"},
	13: {state = 0, path = "res://assets/audio/bgm/bgm_piano_fireplace.ogg"},
	14: {state = 0, path = "res://assets/audio/bgm/bgm_meowdoku_melody.ogg"},
	15: {state = 0, path = "res://assets/audio/bgm/bgm_meowdoku_melody_rain.ogg"},
}


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "bgm_test"
	default_value = VALUE_G8


static func _music_entry_for(group: int) -> Dictionary:
	return MUSIC_BY_GROUP.get(group, MUSIC_BY_GROUP.get(VALUE_G8, _FALLBACK_MUSIC))


static func music_state_for(group: int) -> int:
	return int(_music_entry_for(group).get("state", -1))


static func music_path_for(group: int) -> String:
	return String(_music_entry_for(group).get("path", ""))


static func has_music_switch_for(group: int) -> bool:
	return music_state_for(group) != -1


static func default_music_on_for(group: int) -> bool:
	return music_state_for(group) == 1


func get_music_state() -> int:
	return music_state_for(int(value()))


func get_music_path() -> String:
	return music_path_for(int(value()))


func has_music_switch() -> bool:
	return has_music_switch_for(int(value()))


func default_music_on() -> bool:
	return default_music_on_for(int(value()))
