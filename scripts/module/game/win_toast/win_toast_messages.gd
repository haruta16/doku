extends RefCounted
class_name WinToastMessages










const _TIER_KEYS: Dictionary = {
    WinToastTier.TIER_PERFECT: [
        "WIN_TOAST_PERFECT_01", 
        "WIN_TOAST_PERFECT_02", 
        "WIN_TOAST_PERFECT_03", 
        "WIN_TOAST_PERFECT_04", 
        "WIN_TOAST_PERFECT_05", 
        "WIN_TOAST_PERFECT_06", 
        "WIN_TOAST_PERFECT_07", 
        "WIN_TOAST_PERFECT_08", 
        "WIN_TOAST_PERFECT_09", 
    ], 
    WinToastTier.TIER_P5: [
        "WIN_TOAST_P5_01", 
        "WIN_TOAST_P5_02", 
        "WIN_TOAST_P5_03", 
        "WIN_TOAST_P5_04", 
        "WIN_TOAST_P5_05", 
        "WIN_TOAST_P5_06", 
        "WIN_TOAST_P5_07", 
    ], 
    WinToastTier.TIER_P10: [
        "WIN_TOAST_P10_01", 
        "WIN_TOAST_P10_02", 
        "WIN_TOAST_P10_03", 
        "WIN_TOAST_P10_04", 
        "WIN_TOAST_P10_05", 
        "WIN_TOAST_P10_06", 
        "WIN_TOAST_P10_07", 
    ], 
    WinToastTier.TIER_P20: [
        "WIN_TOAST_P20_01", 
        "WIN_TOAST_P20_02", 
        "WIN_TOAST_P20_03", 
        "WIN_TOAST_P20_04", 
        "WIN_TOAST_P20_05", 
        "WIN_TOAST_P20_06", 
        "WIN_TOAST_P20_07", 
    ], 
}


static func pick_random(tier: int, step_count: int, cat_count: int) -> String:
    if not _TIER_KEYS.has(tier):
        return ""
    var keys: Array = _TIER_KEYS[tier]
    if keys.is_empty():
        return ""
    var key: String = keys[randi() % keys.size()]
    var text: String = TranslationServer.translate(key)
    text = text.replace("{N}", str(step_count))
    text = text.replace("{CATS}", str(cat_count))
    return text
