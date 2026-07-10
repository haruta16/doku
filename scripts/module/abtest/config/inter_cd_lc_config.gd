extends AbConfigBase
class_name InterCdLcConfig



















const VALUE_DEFAULT: String = "{60}"


var _seg_regex: RegEx = null

func _init() -> void :
    key = "inter_cd_lc"
    default_value = VALUE_DEFAULT
    timing = ABTestManager.TIMING_GAME_START





func get_cd_sec() -> int:
    var vals: Array = _parse_values()
    if vals.is_empty():
        return 60
    var idx: int = ABTestManager.living_days.current_segment_index()
    if idx >= 0 and vals.size() == ABTestManager.living_days.segment_count() and idx < vals.size():
        return vals[idx]
    return vals[0]


func _parse_values() -> Array:
    var raw: String = str(value()).strip_edges()
    if raw.is_empty():
        return []
    if _seg_regex == null:
        _seg_regex = RegEx.new()
        _seg_regex.compile("\\{([^}]*)\\}")
    var result: Array = []
    for m: RegExMatch in _seg_regex.search_all(raw):
        var inner: String = m.get_string(1).strip_edges()
        if inner.is_valid_int():
            result.append(inner.to_int())
    return result
