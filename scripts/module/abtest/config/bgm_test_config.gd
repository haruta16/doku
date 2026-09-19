# BGM 试听实验：给不同分组换背景音乐；0=不换，1~6 各对应一首，其中档位 5 还会把音乐开关默认置为关
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

# 档位 → 曲目资源路径；档位 0 不在表里
const _BGM_PATHS: Dictionary = {
	VALUE_WHITE_NOISE: "res://assets/audio/bgm/bgm_white_noise.ogg",
	VALUE_AFTERNOON_TEA: "res://assets/audio/bgm/bgm_afternoon_tea.ogg",
	VALUE_MEDITATION: "res://assets/audio/bgm/bgm_meditation.ogg",
	VALUE_CUTE: "res://assets/audio/bgm/bgm_cute.ogg",
	VALUE_CUTE_DEFAULT_OFF: "res://assets/audio/bgm/bgm_cute.ogg",
	VALUE_AFTERNOON_TEA_LOUD: "res://assets/audio/bgm/bgm_afternoon_tea_loud.ogg",
}


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "bgm_test"
	default_value = VALUE_DISABLED # 默认档：不换曲
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否启用了实验曲目
func is_enabled() -> bool:
	return value() != VALUE_DISABLED


# 冷启动时把设置页「音乐」开关默认设成开还是关（只有档位 5 为关）
func default_music_on() -> bool:
	return value() != VALUE_CUTE_DEFAULT_OFF


# 取当前档位对应的曲目路径，未命中返回空串
func bgm_path() -> String:
	return _BGM_PATHS.get(value(), "")
