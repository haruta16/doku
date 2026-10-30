## 每日挑战人数展示模型：用日期增长曲线、小时占比和设备种子生成稳定的展示数值。
class_name DcPlayersCount
extends RefCounted

const L: float = 4026516.0
const K_RATE: float = 0.0945
const T0: float = 49.2
const EPOCH_YMD: Array = [2026, 5, 3]
const DC_SHARE_TOP: float = 1.05

const GAIN_STEP: float = 0.003
const GAIN_CAP: float = 1.3
const GAIN_EPOCH_YMD: Array = [2026, 9, 23]

const CV: float = 0.05
const DISPLAY_MIN: int = 10000

const CUMSHARE: Array[float] = [
	0.0607,
	0.0893,
	0.1059,
	0.1183,
	0.132,
	0.1576,
	0.2084,
	0.2783,
	0.3472,
	0.4101,
	0.4638,
	0.5107,
	0.5611,
	0.6055,
	0.6462,
	0.6843,
	0.7218,
	0.7608,
	0.7996,
	0.8397,
	0.8848,
	0.9301,
	0.9697,
	1.0,
]


## 组合日期总量、小时累计占比、增长系数和设备固定扰动；这里没有请求实时在线人数。
static func raw_value(first_open_ms: int, now: Dictionary) -> int:
	var jdn: int = _local_date_to_jdn(
		int(now.get("year", EPOCH_YMD[0])),
		int(now.get("month", EPOCH_YMD[1])),
		int(now.get("day", EPOCH_YMD[2]))
	)
	var hour: int = clampi(int(now.get("hour", 0)), 0, CUMSHARE.size() - 1)
	var day_total: float = _day_total(jdn)
	var gain: float = _gain(jdn)
	return int(round(day_total * CUMSHARE[hour] * gain * _device_rand(first_open_ms)))


## 小于一万时隐藏人数，否则按 K 或 M 显示三位小数。
static func format_count(v: int) -> String:
	if v < DISPLAY_MIN:
		return ""
	if v >= 1000000:
		return "%.3fM" % (float(v) / 1000000.0)
	return "%.3fK" % (float(v) / 1000.0)


static func display_text(first_open_ms: int, now: Dictionary) -> String:
	return format_count(raw_value(first_open_ms, now))


## 按相对基准日的逻辑斯蒂曲线计算总量，再限制取值范围。
static func _day_total(jdn: int) -> float:
	var t: float = float(jdn - _local_date_to_jdn(EPOCH_YMD[0], EPOCH_YMD[1], EPOCH_YMD[2]))
	var target: float = L / (1.0 + exp(-K_RATE * (t - T0)))
	return clampf(target, 0.85 * L, 1.15 * L) * DC_SHARE_TOP


static func _gain(jdn: int) -> float:
	var n: int = maxi(
		1, jdn - _local_date_to_jdn(GAIN_EPOCH_YMD[0], GAIN_EPOCH_YMD[1], GAIN_EPOCH_YMD[2]) + 1
	)
	return minf(1.0 + GAIN_STEP * float(n - 1), GAIN_CAP)


## 以首次打开时间播种随机数，使同一设备的展示扰动保持稳定。
static func _device_rand(first_open_ms: int) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(first_open_ms)
	return 1.0 + rng.randf_range(-CV, CV)


static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
