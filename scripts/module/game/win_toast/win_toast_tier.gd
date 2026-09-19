# 胜利弹窗档位表：按棋盘尺寸与实际步数判定 PERFECT / P5 / P10 / P20，并给出阈值与档位名
extends RefCounted
class_name WinToastTier

# ---- 档位常量 ----
const TIER_NONE: int = -1 # 无档位，不弹
const TIER_PERFECT: int = 0 # 完美：步数正好等于尺寸
const TIER_P5: int = 1 # 步数 ≤ p5 上限
const TIER_P10: int = 2 # 步数 ≤ p10 上限
const TIER_P20: int = 3 # 步数 ≤ p20 上限

# 各棋盘尺寸的步数阈值表：内层 p5/p10/p20 是步数上限（尺寸不在表里就没有档位）
const _THRESHOLDS: Dictionary = {
	6: {"p5": 16, "p10": 20, "p20": 30},
	7: {"p5": 30, "p10": 32, "p20": 36},
	8: {"p5": 25, "p10": 32, "p20": 40},
	9: {"p5": 28, "p10": 35, "p20": 45},
	10: {"p5": 30, "p10": 38, "p20": 50},
	11: {"p5": 60, "p10": 65, "p20": 71},
	12: {"p5": 70, "p10": 75, "p20": 80},
}


# 取某个尺寸的阈值表，没有则返回空字典
static func get_thresholds(scale: int) -> Dictionary:
	return _THRESHOLDS.get(scale, {})


# 档位 → 字符串名，用于日志与 AB 覆盖判断
static func tier_name(tier: int) -> String:
	match tier:
		TIER_PERFECT:
			return "PERFECT"
		TIER_P5:
			return "P5"
		TIER_P10:
			return "P10"
		TIER_P20:
			return "P20"
		TIER_NONE:
			return "NONE"
	return "UNKNOWN(%d)" % tier


# 判档：不合法或无阈值表 → 无档；步数等于尺寸 → PERFECT；否则按 p5/p10/p20 逐级放宽
static func determine_tier(scale: int, step_used: int) -> int:
	# 参数非法（尺寸或步数 ≤ 0）
	if scale <= 0 or step_used <= 0:
		return TIER_NONE
	# 这个尺寸没有阈值表
	if not _THRESHOLDS.has(scale):
		return TIER_NONE

	# 步数比尺寸还少，数据异常
	if step_used < scale:
		return TIER_NONE

	# 正好等于尺寸 = 完美
	if step_used == scale:
		return TIER_PERFECT
	var th: Dictionary = _THRESHOLDS[scale]
	# 依次比对 p5 / p10 / p20 的步数上限
	if step_used <= int(th["p5"]):
		return TIER_P5
	if step_used <= int(th["p10"]):
		return TIER_P10
	if step_used <= int(th["p20"]):
		return TIER_P20
	# 超过 p20 上限 → 无档
	return TIER_NONE
