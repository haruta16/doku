extends RefCounted
class_name WinToastTier











const TIER_NONE: int = -1
const TIER_PERFECT: int = 0
const TIER_P5: int = 1
const TIER_P10: int = 2
const TIER_P20: int = 3


const _THRESHOLDS: Dictionary = {
    6: {"p5": 16, "p10": 20, "p20": 30}, 
    7: {"p5": 30, "p10": 32, "p20": 36}, 
    8: {"p5": 25, "p10": 32, "p20": 40}, 
    9: {"p5": 28, "p10": 35, "p20": 45}, 
    10: {"p5": 30, "p10": 38, "p20": 50}, 
    11: {"p5": 60, "p10": 65, "p20": 71}, 
    12: {"p5": 70, "p10": 75, "p20": 80}, 
}


static func get_thresholds(scale: int) -> Dictionary:
    return _THRESHOLDS.get(scale, {})


static func tier_name(tier: int) -> String:
    match tier:
        TIER_PERFECT: return "PERFECT"
        TIER_P5: return "P5"
        TIER_P10: return "P10"
        TIER_P20: return "P20"
        TIER_NONE: return "NONE"
    return "UNKNOWN(%d)" % tier


static func determine_tier(scale: int, step_used: int) -> int:
    if scale <= 0 or step_used <= 0:
        return TIER_NONE
    if not _THRESHOLDS.has(scale):
        return TIER_NONE


    if step_used < scale:
        return TIER_NONE

    if step_used == scale:
        return TIER_PERFECT
    var th: Dictionary = _THRESHOLDS[scale]
    if step_used <= int(th["p5"]):
        return TIER_P5
    if step_used <= int(th["p10"]):
        return TIER_P10
    if step_used <= int(th["p20"]):
        return TIER_P20
    return TIER_NONE
