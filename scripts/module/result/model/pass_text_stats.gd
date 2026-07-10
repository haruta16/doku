class_name PassTextStats
extends RefCounted























const _P90_BY_SIZE: Dictionary = {
    4: 44, 
    5: 37, 
    6: 107, 
    7: 187, 
    8: 265, 
    9: 360, 
    10: 431, 
}



static func beat_percent_from_elapsed(elapsed_sec: float, size: int) -> float:
    var p90: float = float(_lookup_p90(size))
    if p90 <= 0.0:
        return 51.0
    var delta_t: float = maxf(0.0, p90 - elapsed_sec)
    var x: float = 51.0 + 48.0 * sqrt(delta_t / p90) + randf()
    return x


static func round_non_zero_decimal(pct: float) -> float:
    var r: float = snappedf(pct, 0.1)
    var ip: float = roundf(r)
    if absf(r - ip) < 0.05:
        r = ip + 0.1
    return r


static func _lookup_p90(size: int) -> int:
    if _P90_BY_SIZE.has(size):
        return _P90_BY_SIZE[size]
    if size < 4:
        return _P90_BY_SIZE[4]
    return _P90_BY_SIZE[10]
