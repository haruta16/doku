# 每日挑战的成绩换算：把「通关秒数」映射成「打赢了全球百分之多少的人」
# 做法是对秒数取对数后套正态分布，参数按 (棋盘大小, 难度档位) 查表
class_name DailyStats
extends RefCounted


# 标准正态分布 CDF 的数值近似（Abramowitz-Stegun 多项式），只用得到 x>=0 的分支
static func _norm_cdf(x: float) -> float:
	var t: float = 1.0 / (1.0 + 0.2316419 * abs(x))
	var poly: float = (
		t
		* (
			0.31938153
			+ t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429)))
		)
	)
	var cdf: float = 1.0 - (1.0 / sqrt(2.0 * PI)) * exp(-x * x / 2.0) * poly
	return cdf if x >= 0.0 else 1.0 - cdf


# 通关秒数 → 超越百分比：mu/sigma 是「秒数取对数」后的正态参数，越大越难
# 原理：秒数越短 z 越小，右尾 (1-cdf) 越大，也就是打得越快百分比越高
# sz = 棋盘边长，rank = 难度档位；下表按 (sz, rank) 组合取对应的 mu / sigma
static func beat_percent(elapsed_sec: int, rank: int, sz: int = 12) -> float:
	if elapsed_sec <= 0:
		# 没测到时间（0 或负数）就直接给最高的 99%
		return 99.0
	var mu: float
	var sigma: float
	if sz == 10 and rank == 3:
		mu = 6.6884
		sigma = 1.6383
	elif sz == 10 and rank == 4:
		mu = 6.7747
		sigma = 1.4422
	elif sz == 10 and rank == 5:
		mu = 6.7783
		sigma = 1.3357
	elif sz == 12 and rank == 3:
		mu = 6.7747
		sigma = 1.4422
	elif sz == 12 and rank == 4:
		mu = 6.7783
		sigma = 1.3357
	elif sz == 12 and rank == 5:
		mu = 7.1134
		sigma = 1.3881
	else:
		# 查不到的组合属于配置错误：报错并退回 sz12/rank4 的参数
		push_error("DailyStats.beat_percent: 未知组合 sz=%d rank=%d" % [sz, rank])
		mu = 6.7747
		sigma = 1.4422
	var z: float = (log(float(elapsed_sec)) - mu) / sigma
	# 夹到 49~99 之间：再慢也不低于 49%，再快也不给满分 100%
	var p: float = snappedf((1.0 - _norm_cdf(z)) * 100.0, 0.1)
	return clampf(p, 49.0, 99.0)
