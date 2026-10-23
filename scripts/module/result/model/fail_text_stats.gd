## 失败鼓励文案工具：按完成度抽取文本，按关卡类型生成复活提示的展示百分比。
class_name FailTextStats
extends RefCounted

## 完成度 > 80% 时的鼓励语候选（随机取一条）
const _KEYS_HIGH: Array[String] = [
	"FAIL_ENC_HIGH_1",
	"FAIL_ENC_HIGH_2",
	"FAIL_ENC_HIGH_3",
	"FAIL_ENC_HIGH_4",
]
## 完成度 20% ~ 80% 时的鼓励语候选
const _KEYS_MID: Array[String] = [
	"FAIL_ENC_MID_1",
	"FAIL_ENC_MID_2",
	"FAIL_ENC_MID_3",
	"FAIL_ENC_MID_4",
]
## 完成度 < 20% 时的鼓励语候选
const _KEYS_LOW: Array[String] = [
	"FAIL_ENC_LOW_1",
	"FAIL_ENC_LOW_2",
	"FAIL_ENC_LOW_3",
	"FAIL_ENC_LOW_4",
]


## 按完成度挑一组候选并随机翻译输出；返回已加 [center] 的富文本
static func pick_encourage_text(found_ratio: float) -> String:
	# 先按完成度落进高 / 中 / 低某一档
	var keys: Array[String]
	if found_ratio > 0.8:
		keys = _KEYS_HIGH
	elif found_ratio >= 0.2:
		keys = _KEYS_MID
	else:
		keys = _KEYS_LOW

	return "[center]%s[/center]" % TranslationServer.translate(keys[randi() % keys.size()])


## 按每日挑战、难度和尺寸选取展示区间，避开边界及整数百分比；这是客户端文案数值。
static func pick_revive_promote_x(level: int, sz: int, is_daily: bool) -> float:
	var lo: float
	var hi: float

	var _is_hard: bool = (
		LevelSelector.is_hard_level(level) or LevelSelector.is_super_hard_level(level)
	)
	if is_daily or _is_hard:
		lo = 72.0
		hi = 87.0
	elif sz <= 5:
		lo = 25.0
		hi = 45.0
	elif sz <= 7:
		lo = 35.0
		hi = 55.0
	elif sz <= 9:
		lo = 52.0
		hi = 67.0
	else:
		lo = 62.0
		hi = 77.0

	for _i in range(20):
		var raw: float = randf_range(lo, hi)
		var x: float = snappedf(raw, 0.1)
		if x <= lo or x >= hi:
			continue
		if int(round(x * 10)) % 10 == 0:
			continue
		return x

	return snappedf(lo + 0.1, 0.1)


## 把 x 套进 FAIL_REVIVE_PROMOTE 模板（模板里留了一个 %s 占位）
static func format_revive_promote(x: float) -> String:
	return TranslationServer.translate("FAIL_REVIVE_PROMOTE") % I18nFormat.percent(x, 1)
