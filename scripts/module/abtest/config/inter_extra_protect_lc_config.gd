extends AbConfigBase
class_name InterExtraProtectLcConfig

























const VALUE_DEFAULT: String = "{session_game_2}"


var _seg_regex: RegEx = null

func _init() -> void :
    key = "inter_extra_protect_lc"
    default_value = VALUE_DEFAULT
    timing = ABTestManager.TIMING_GAME_START







func eval_start_interstitial() -> Dictionary:
    var schemes: Array = _parse_schemes()
    if schemes.is_empty():
        return {"blocked": false, "reason": ""}
    var idx: int = ABTestManager.living_days.current_segment_index()
    var pick_idx: int = idx if idx >= 0 and schemes.size() == ABTestManager.living_days.segment_count() and idx < schemes.size() else 0
    return ProtectScheme.eval_scheme(schemes[pick_idx])



func _parse_schemes() -> Array:
    var raw: String = str(value()).strip_edges()
    if raw.is_empty():
        return []
    if _seg_regex == null:
        _seg_regex = RegEx.new()
        _seg_regex.compile("\\{([^}]*)\\}")
    var result: Array = []
    for m: RegExMatch in _seg_regex.search_all(raw):
        result.append(m.get_string(1).strip_edges())
    return result
