extends AbConfigBase
class_name BannerUnlockDiffLcConfig

























const VALUE_DEFAULT: String = "{all}"


var _seg_regex: RegEx = null

func _init() -> void :
    key = "banner_unlock_diff_lc"
    default_value = VALUE_DEFAULT
    timing = ABTestManager.TIMING_GAME_START





func is_unlocked_for_size(size: int) -> bool:
    var segs: Array = _parse_segments()
    if segs.is_empty():
        return true
    var idx: int = ABTestManager.living_days.current_segment_index()
    var pick_idx: int = idx if idx >= 0 and segs.size() == ABTestManager.living_days.segment_count() and idx < segs.size() else 0
    return _size_allowed(segs[pick_idx], size)



func _size_allowed(seg: String, size: int) -> bool:
    var s: String = seg.strip_edges().to_lower()
    if s == "no":
        return false
    if s == "all" or s == "yes":
        return true
    for part in s.split(","):
        var p: String = part.strip_edges()
        if p.is_valid_int() and p.to_int() == size:
            return true
    return false


func _parse_segments() -> Array:
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
