# 胜利弹窗文案池：按档位随机挑一条翻译 key，再把 {N} 步数与 {CATS} 猫数替换进文本
extends RefCounted
class_name WinToastMessages

# 各档位的候选翻译 key 列表
const _TIER_KEYS: Dictionary = {
	WinToastTier.TIER_PERFECT:
	[
		"WIN_TOAST_PERFECT_01",
		"WIN_TOAST_PERFECT_02",
		"WIN_TOAST_PERFECT_03",
		"WIN_TOAST_PERFECT_04",
		"WIN_TOAST_PERFECT_05",
		"WIN_TOAST_PERFECT_06",
		"WIN_TOAST_PERFECT_07",
		"WIN_TOAST_PERFECT_08",
		"WIN_TOAST_PERFECT_09",
	],
	WinToastTier.TIER_P5:
	[
		"WIN_TOAST_P5_01",
		"WIN_TOAST_P5_02",
		"WIN_TOAST_P5_03",
		"WIN_TOAST_P5_04",
		"WIN_TOAST_P5_05",
		"WIN_TOAST_P5_06",
		"WIN_TOAST_P5_07",
	],
	WinToastTier.TIER_P10:
	[
		"WIN_TOAST_P10_01",
		"WIN_TOAST_P10_02",
		"WIN_TOAST_P10_03",
		"WIN_TOAST_P10_04",
		"WIN_TOAST_P10_05",
		"WIN_TOAST_P10_06",
		"WIN_TOAST_P10_07",
	],
	WinToastTier.TIER_P20:
	[
		"WIN_TOAST_P20_01",
		"WIN_TOAST_P20_02",
		"WIN_TOAST_P20_03",
		"WIN_TOAST_P20_04",
		"WIN_TOAST_P20_05",
		"WIN_TOAST_P20_06",
		"WIN_TOAST_P20_07",
	],
}


# 随机取一条该档位文案并填充步数/猫数；档位无效返回空串
static func pick_random(tier: int, step_count: int, cat_count: int) -> String:
	# 档位不在表里（含 TIER_NONE）
	if not _TIER_KEYS.has(tier):
		return ""
	var keys: Array = _TIER_KEYS[tier]
	# 该档位没有候选文案
	if keys.is_empty():
		return ""
	# 随机取一条
	var key: String = keys[randi() % keys.size()]
	# 先翻译，再替换占位符
	var text: String = TranslationServer.translate(key)
	text = text.replace("{N}", str(step_count))
	text = text.replace("{CATS}", str(cat_count))
	return text
