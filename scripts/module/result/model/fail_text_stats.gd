class_name FailTextStats
extends RefCounted

const _KEYS_HIGH: Array[String] = [
	"FAIL_ENC_HIGH_1",
	"FAIL_ENC_HIGH_2",
	"FAIL_ENC_HIGH_3",
	"FAIL_ENC_HIGH_4",
]
const _KEYS_MID: Array[String] = [
	"FAIL_ENC_MID_1",
	"FAIL_ENC_MID_2",
	"FAIL_ENC_MID_3",
	"FAIL_ENC_MID_4",
]
const _KEYS_LOW: Array[String] = [
	"FAIL_ENC_LOW_1",
	"FAIL_ENC_LOW_2",
	"FAIL_ENC_LOW_3",
	"FAIL_ENC_LOW_4",
]


static func pick_encourage_text(found_ratio: float) -> String:
	var keys: Array[String]
	if found_ratio > 0.8:
		keys = _KEYS_HIGH
	elif found_ratio >= 0.2:
		keys = _KEYS_MID
	else:
		keys = _KEYS_LOW

	return "[center]%s[/center]" % TranslationServer.translate(keys[randi() % keys.size()])


static func pick_revive_promote_x(level: int, sz: int, is_daily: bool) -> float:
	var lo: float
	var hi: float
	var _is_hard: bool = (
		LevelData.is_hard_level_group_j(level)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(level)
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


static func format_revive_promote(x: float) -> String:
	return TranslationServer.translate("FAIL_REVIVE_PROMOTE") % I18nFormat.percent(x, 1)
