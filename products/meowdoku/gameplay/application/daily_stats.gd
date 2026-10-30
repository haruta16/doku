## 每日挑战成绩估算：按盘面尺寸、难度和用时曲线计算展示百分比。
class_name DailyStats
extends RefCounted


## 标准正态分布 CDF 的数值近似（Abramowitz-Stegun 多项式），只用得到 x>=0 的分支
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


const _ANCHOR_TIMES: Array = [30, 60, 90, 120, 180, 300, 600, 900]

const _ANCHOR_CURVES: Dictionary = {
	"10_3":
	{
		"pcts": [99.0, 98.0, 95.0, 90.0, 85.0, 75.0, 60.0, 49.0],
		"segs":
		[
			[9.3165, 2.5427],
			[6.1309, 0.9916],
			[5.8023, 0.7919],
			[6.9074, 1.6542],
			[6.6557, 1.4113],
			[6.8139, 1.6459],
			[6.7659, 1.4563],
		],
	},
	"10_4":
	{
		"pcts": [99.0, 98.0, 96.0, 92.0, 88.0, 80.0, 62.0, 50.0],
		"segs":
		[
			[9.3165, 2.5427],
			[6.842, 1.3379],
			[5.957, 0.8324],
			[7.2636, 1.7622],
			[6.9934, 1.5323],
			[6.7919, 1.2928],
			[6.8024, 1.3273],
		],
	},
	"12_4":
	{
		"pcts": [99.0, 98.5, 97.0, 95.0, 90.0, 80.0, 65.0, 52.0],
		"segs":
		[
			[13.7207, 4.4359],
			[7.1358, 1.4016],
			[6.7931, 1.2193],
			[6.6232, 1.1161],
			[6.681, 1.1612],
			[6.9823, 1.5191],
			[6.8631, 1.2097],
		],
	},
}


## 在预设时间锚点间使用对数正态分段曲线，边界直接取对应端点百分比。
static func _anchor_percent(elapsed_sec: int, curve: Dictionary) -> float:
	var pcts: Array = curve["pcts"]
	var segs: Array = curve["segs"]
	var last_i: int = _ANCHOR_TIMES.size() - 1
	var t: float = float(elapsed_sec)
	if t <= float(_ANCHOR_TIMES[0]):
		return pcts[0]
	if t >= float(_ANCHOR_TIMES[last_i]):
		return pcts[last_i]
	for i in segs.size():
		if t <= float(_ANCHOR_TIMES[i + 1]):
			var mu: float = segs[i][0]
			var sigma: float = segs[i][1]
			var z: float = (log(t) - mu) / sigma
			var p: float = snappedf((1.0 - _norm_cdf(z)) * 100.0, 0.1)
			return clampf(p, 49.0, 99.0)
	return pcts[last_i]


## 按尺寸与难度选择客户端拟合曲线，结果夹在 49% 至 99%，并非实时玩家排行榜。
static func beat_percent(
	elapsed_sec: int, rank: int, sz: int = 12, use_anchor_curve: bool = false
) -> float:
	if elapsed_sec <= 0:
		return 99.0

	if use_anchor_curve:
		var curve: Dictionary = _ANCHOR_CURVES.get("%d_%d" % [sz, rank], {})
		if not curve.is_empty():
			return _anchor_percent(elapsed_sec, curve)
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
		push_error("DailyStats.beat_percent: 未知组合 sz=%d rank=%d" % [sz, rank])
		mu = 6.7747
		sigma = 1.4422
	var z: float = (log(float(elapsed_sec)) - mu) / sigma
	var p: float = snappedf((1.0 - _norm_cdf(z)) * 100.0, 0.1)
	return clampf(p, 49.0, 99.0)
