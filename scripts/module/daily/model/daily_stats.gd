class_name DailyStats
extends RefCounted


static func _norm_cdf(x: float) -> float:
    var t: float = 1.0 / (1.0 + 0.2316419 * abs(x))
    var poly: float = t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
    var cdf: float = 1.0 - (1.0 / sqrt(2.0 * PI)) * exp( - x * x / 2.0) * poly
    return cdf if x >= 0.0 else 1.0 - cdf










static func beat_percent(elapsed_sec: int, rank: int, sz: int = 12) -> float:
    if elapsed_sec <= 0:
        return 99.0
    var mu: float
    var sigma: float
    if sz == 10 and rank == 3:
        mu = 6.6884;sigma = 1.6383
    elif sz == 10 and rank == 4:
        mu = 6.7747;sigma = 1.4422
    elif sz == 10 and rank == 5:
        mu = 6.7783;sigma = 1.3357
    elif sz == 12 and rank == 3:
        mu = 6.7747;sigma = 1.4422
    elif sz == 12 and rank == 4:
        mu = 6.7783;sigma = 1.3357
    elif sz == 12 and rank == 5:
        mu = 7.1134;sigma = 1.3881
    else:
        push_error("DailyStats.beat_percent: 未知组合 sz=%d rank=%d" % [sz, rank])
        mu = 6.7747;sigma = 1.4422
    var z: float = (log(float(elapsed_sec)) - mu) / sigma
    var p: float = snappedf((1.0 - _norm_cdf(z)) * 100.0, 0.1)
    return clampf(p, 49.0, 99.0)
