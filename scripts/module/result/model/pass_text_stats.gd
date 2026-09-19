# 通关文案的统计工具：由用时估算「击败了百分之多少玩家」，纯静态函数
class_name PassTextStats
extends RefCounted

# 各盘面尺寸的 P90 基准用时（秒）：达到这个时长约等于 51 分位
const _P90_BY_SIZE: Dictionary = {
	4: 44,
	5: 37,
	6: 107,
	7: 187,
	8: 265,
	9: 360,
	10: 431,
}


# 用时 → 击败百分比：0 秒约 99，到达 P90 基准只剩约 51；再叠 0~1 的随机抖动
static func beat_percent_from_elapsed(elapsed_sec: float, size: int) -> float:
	var p90: float = float(_lookup_p90(size))
	# 查不到基准就别加分，直接给最低档 51
	if p90 <= 0.0:
		return 51.0
	var delta_t: float = maxf(0.0, p90 - elapsed_sec)
	var x: float = 51.0 + 48.0 * sqrt(delta_t / p90) + randf()
	return x


# 收敛到 1 位小数；正好落在整数上（如 80.0）时再补 0.1，避免露出整数百分比
static func round_non_zero_decimal(pct: float) -> float:
	var r: float = snappedf(pct, 0.1)
	var ip: float = roundf(r)
	if absf(r - ip) < 0.05:
		r = ip + 0.1
	return r


# 按尺寸取 P90；尺寸越界时夹到 4×4 与 10×10 两端
static func _lookup_p90(size: int) -> int:
	if _P90_BY_SIZE.has(size):
		return _P90_BY_SIZE[size]
	if size < 4:
		return _P90_BY_SIZE[4]
	return _P90_BY_SIZE[10]
