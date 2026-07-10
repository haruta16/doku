extends RefCounted
class_name AbConfigBase
















var key: String = ""
var default_value: Variant = 0
var timing: String = ""



var _value: Variant = 0
var _value_loaded: bool = false
var _has_debug_override: bool = false
var _debug_override: Variant = null
var _debug_disabled: bool = false





func init_default() -> void :
    _value = default_value



func value() -> Variant:
    if _has_debug_override:
        return _debug_override
    return _value if _value_loaded else default_value




func reload_value() -> void :
    if typeof(default_value) == TYPE_STRING:
        _value = ABTestManager.get_ab_string(key, default_value)
    else:
        _value = ABTestManager.get_ab_int(key, default_value)
    _value_loaded = true
    ABTestManager.dye_ab(key)




func peek_value() -> Variant:
    if _has_debug_override:
        return _debug_override
    if typeof(default_value) == TYPE_STRING:
        return ABTestManager.get_ab_string(key, default_value)
    else:
        return ABTestManager.get_ab_int(key, default_value)



func is_value_loaded() -> bool:
    return _value_loaded or _has_debug_override





func set_debug_override(v: Variant) -> void :
    _debug_override = v
    _has_debug_override = true

func clear_debug_override() -> void :
    _debug_override = null
    _has_debug_override = false





func is_debug_disabled() -> bool:
    return _debug_disabled

func set_debug_disabled(disabled: bool) -> void :
    _debug_disabled = disabled





func cheat_label() -> String:
    return key



func cheat_value_str() -> String:
    return str(value())
