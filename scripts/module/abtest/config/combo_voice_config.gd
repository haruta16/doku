# 连击语音包实验：0=关闭 1~2=AI 猫叫/AI 女声 3~5=真人女声三套 6~8=真人男声三套，每包含连击 3~8 六段音频
extends AbConfigBase
class_name ComboVoiceConfig

# ---- 分组取值（同时也是语音包编号） ----
const VALUE_DISABLED: int = 0 # 关闭连击语音
const VALUE_AI_CAT: int = 1 # AI 猫叫
const VALUE_AI_FEMALE: int = 2 # AI 女声
const VALUE_REAL_FEMALE_1: int = 3 # 真人女声 第 1 套
const VALUE_REAL_FEMALE_2: int = 4 # 真人女声 第 2 套
const VALUE_REAL_FEMALE_3: int = 5 # 真人女声 第 3 套
const VALUE_REAL_MALE_1: int = 6 # 真人男声 第 1 套
const VALUE_REAL_MALE_2: int = 7 # 真人男声 第 2 套
const VALUE_REAL_MALE_3: int = 8 # 真人男声 第 3 套

# 语音包 → {连击数 3~8: 音频路径}；键即素材的 s1~s8 后缀，档位 0 无表项
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


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "combo_voice"
	default_value = VALUE_DISABLED # 默认档：关闭
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否启用连击语音
func is_enabled() -> bool:
	return value() != VALUE_DISABLED


# 取该连击数对应的语音路径；连击数会钳到 3~8，未命中返回空串
func get_combo_voice(combo_count: int) -> String:
	var voice_set: int = value()
	if voice_set <= 0:
		return ""
	var paths: Dictionary = _VOICE_SET_PATHS.get(voice_set, {})
	var level: int = clampi(combo_count, 3, 8)
	return paths.get(level, "")
