## 实验配置 combo_voice：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ComboVoiceConfig

const VALUE_REAL_MALE_1: int = 6 # 真人男声 第 1 套

const VALUE_REAL_MALE_A_TEXT1: int = 9

const VALUE_REAL_MALE_B_TEXT2: int = 10

const VALUE_REAL_FEMALE_MEOW_TEXT3: int = 11

const VALUE_JAPANESE: int = 12

const VALUE_ENGLISH_AI_CAT: int = 13

const VOICE_NONE: int = -1

const _VOICE_KINDS: Dictionary = {
	3: SoundManager.Kind.VOICE_NICE_S6,
	4: SoundManager.Kind.VOICE_GREAT_S6,
	5: SoundManager.Kind.VOICE_PERFECT_S6,
	6: SoundManager.Kind.VOICE_EXCELLENT_S6,
	7: SoundManager.Kind.VOICE_AMAZING_S6,
	8: SoundManager.Kind.VOICE_UNBELIEVABLE_S6,
	9: SoundManager.Kind.VOICE_UNREAL_S10,
	10: SoundManager.Kind.VOICE_INSANE_S10,
	11: SoundManager.Kind.VOICE_EPIC_S10,
	12: SoundManager.Kind.VOICE_BREATHTAKING_S10,
}

const _JAPANESE_VOICE_KINDS: Array[int] = [
	SoundManager.Kind.VOICE_COMBO_03_JP,
	SoundManager.Kind.VOICE_COMBO_04_JP,
	SoundManager.Kind.VOICE_COMBO_05_JP,
	SoundManager.Kind.VOICE_COMBO_06_JP,
	SoundManager.Kind.VOICE_COMBO_07_JP,
	SoundManager.Kind.VOICE_COMBO_08_JP,
	SoundManager.Kind.VOICE_COMBO_09_JP,
	SoundManager.Kind.VOICE_COMBO_10_JP,
	SoundManager.Kind.VOICE_COMBO_11_JP,
	SoundManager.Kind.VOICE_COMBO_12_JP,
]

const _ENGLISH_AI_CAT_VOICE_KINDS: Array[int] = [
	SoundManager.Kind.VOICE_COMBO_03_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_04_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_05_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_06_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_07_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_08_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_09_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_10_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_11_EN_AI_CAT,
	SoundManager.Kind.VOICE_COMBO_12_EN_AI_CAT,
]


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "combo_voice"

	default_value = VALUE_REAL_MALE_B_TEXT2


func get_combo_voice(combo_count: int) -> int:
	var level: int = clampi(combo_count, 3, 12)
	if LanguageManager.resolve_language_family() == "jp":
		var group: int = value()
		if group == VALUE_JAPANESE:
			return _JAPANESE_VOICE_KINDS[level - 3]
		if group == VALUE_ENGLISH_AI_CAT:
			return _ENGLISH_AI_CAT_VOICE_KINDS[level - 3]
	return _VOICE_KINDS.get(level, VOICE_NONE)
