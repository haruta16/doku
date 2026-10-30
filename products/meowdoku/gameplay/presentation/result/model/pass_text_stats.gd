## 通关表现数值工具：按尺寸用时基准估算展示百分比，并处理非整数小数表现。
class_name PassTextStats
extends RefCounted

## 各盘面尺寸的 P90 基准用时（秒）：达到这个时长约等于 51 分位
const _P90_BY_SIZE: Dictionary = {
	4: 44,
	5: 37,
	6: 107,
	7: 187,
	8: 265,
	9: 360,
	10: 431,
}


## 将完成用时映射成展示百分比，复用尺寸基准与随机小扰动，不读取实时排名。
static func beat_percent_from_elapsed(elapsed_sec: float, size: int) -> float:
	return _beat_percent(elapsed_sec, size, 51.0, 48.0)


static func _beat_percent(elapsed_sec: float, size: int, base: float, span: float) -> float:
	var p90: float = float(_lookup_p90(size))
	if p90 <= 0.0:
		return base
	var delta_t: float = maxf(0.0, p90 - elapsed_sec)
	return base + span * sqrt(delta_t / p90) + randf()


## 收敛到 1 位小数；正好落在整数上（如 80.0）时再补 0.1，避免露出整数百分比
static func round_non_zero_decimal(pct: float) -> float:
	var r: float = snappedf(pct, 0.1)
	var ip: float = roundf(r)
	if absf(r - ip) < 0.05:
		r = ip + 0.1
	return r


## 按尺寸取 P90；尺寸越界时夹到 4×4 与 10×10 两端
static func _lookup_p90(size: int) -> int:
	if _P90_BY_SIZE.has(size):
		return _P90_BY_SIZE[size]
	if size < 4:
		return _P90_BY_SIZE[4]
	return _P90_BY_SIZE[10]
