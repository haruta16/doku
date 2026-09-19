# A/B 实验配置基类：统一「默认值 / 延迟加载 / 调试覆盖」三件事，子类只声明 key 与档位
extends RefCounted
class_name AbConfigBase

# ---- 实验身份（子类在 _init 里赋值） ----
var key: String = "" # 实验 key，同时也是 ABTestManager 里的索引
var default_value: Variant = 0 # 兜底值；类型决定走 get_ab_int 还是 get_ab_string
var timing: String = "" # 染色时机，取值见 ABTestManager.TIMING_*

# ---- 取值缓存与调试开关 ----
var _value: Variant = 0 # reload_value() 之后缓存下来的真实分组值
var _value_loaded: bool = false # 缓存是否来自一次真实的远端读取
var _has_debug_override: bool = false # 是否被作弊面板强制指定（优先于真实值）
var _debug_override: Variant = null # 作弊面板指定的值
var _debug_disabled: bool = false # 作弊面板的「临时绕过该实验」标记，由调用点自行判断


# 注册阶段预填默认值，避免未加载时取到 null
func init_default() -> void:
	_value = default_value


# 取当前分组值：调试覆盖 > 已加载的远端值 > 默认值
func value() -> Variant:
	if _has_debug_override:
		return _debug_override
	return _value if _value_loaded else default_value


# 按 key 从 SDK 拉取真实分组并缓存，同时上报一次染色（有埋点副作用）
func reload_value() -> void:
	if typeof(default_value) == TYPE_STRING:
		_value = ABTestManager.get_ab_string(key, default_value)
	else:
		_value = ABTestManager.get_ab_int(key, default_value)
	_value_loaded = true
	ABTestManager.dye_ab(key)


# 只读探测：不动缓存，直接问 SDK；常用于需要实时跟随的场景
func peek_value() -> Variant:
	if _has_debug_override:
		return _debug_override
	if typeof(default_value) == TYPE_STRING:
		return ABTestManager.get_ab_string(key, default_value)
	else:
		return ABTestManager.get_ab_int(key, default_value)


# 是否已有可用值（取过远端或已被调试覆盖）
func is_value_loaded() -> bool:
	return _value_loaded or _has_debug_override


# 作弊面板用：强制指定该实验取值
func set_debug_override(v: Variant) -> void:
	_debug_override = v
	_has_debug_override = true


# 撤销调试覆盖，回到远端值/默认值
func clear_debug_override() -> void:
	_debug_override = null
	_has_debug_override = false


# 该实验是否被作弊面板停用（调用点据此跳过这道闸门）
func is_debug_disabled() -> bool:
	return _debug_disabled


# 设置调试停用标记
func set_debug_disabled(disabled: bool) -> void:
	_debug_disabled = disabled


# 作弊面板显示名；子类可覆写成更易懂的说明
func cheat_label() -> String:
	return key


# 作弊面板显示当前取值
func cheat_value_str() -> String:
	return str(value())
