## 实验配置基类：统一默认值、远端缓存、本地调试覆盖，以及分组切换记录。
extends RefCounted
class_name AbConfigBase

const DebugOverrideStore: GDScript = preload(
	"res://scripts/module/abtest/debug_ab_override_store.gd"
)

signal debug_override_changed

# ---- 实验身份（子类在 _init 里赋值） ----
var key: String = "" # 实验 key，同时也是 ABTestManager 里的索引
var default_value: Variant = 0 # 兜底值；类型决定走 get_ab_int 还是 get_ab_string

# ---- 取值缓存与调试开关 ----
var _value: Variant = 0 # load_value() 之后缓存下来的真实分组值
var _value_loaded: bool = false # 缓存是否来自一次真实的远端读取
var _has_debug_override: bool = false # 是否被作弊面板强制指定（优先于真实值）
var _debug_override: Variant = null # 作弊面板指定的值
var _debug_disabled: bool = false # 作弊面板的「临时绕过该实验」标记，由调用点自行判断

var _prev_saved_group: int = -1

var _switch_group_stored: bool = false

const _SWITCH_STRATEGY_PATH: String = "res://assets/cfg/ab_switch_popup_strategy.json"

const _SWITCH_STORE_EXCLUDE: Array = ["daily_streak"]

const _SWITCH_STORE_INCLUDE: Array = [
	"normal_level",
	"golden_fish_func",
	"golden_fish_timing",
	"dyeing_test",
	"draft_mode",
	"dc_costume",
	"color_challenge_func",
	"home_companion_cat",
]

static var _peek_store_keys: Dictionary = {}
static var _switch_store_keys: Dictionary = {}
static var _switch_store_keys_loaded: bool = false


## 先设置默认值；只有类型匹配的本地覆盖才进入调试缓存。
func init_default() -> void:
	_value = default_value
	var saved_override: Variant = DebugOverrideStore.get_override(key)
	if saved_override == null:
		return
	if typeof(saved_override) != typeof(default_value):
		push_warning("[ABTest] 忽略与参数类型不符的本地调试覆盖：%s" % key)
		return
	_debug_override = saved_override
	_has_debug_override = true


## 取当前分组值：调试覆盖 > 已加载的远端值 > 默认值
func value() -> Variant:
	if _has_debug_override:
		return _debug_override
	return _value if _value_loaded else default_value


## 按默认值类型读取 SDK 配置；首次加载记录切换前分组，必要时保存 peek 回退值。
func load_value() -> void:
	if typeof(default_value) == TYPE_STRING:
		_value = ABTestManager.get_ab_string(key, default_value)
	else:
		_value = ABTestManager.get_ab_int(key, default_value)
	_value_loaded = true

	_check_raw_value_type()

	if not _switch_group_stored:
		_switch_group_stored = true
		_maybe_store_switch_group()
	if _peek_store_keys.has(key):
		_store_peek_fallback(_value)


func _check_raw_value_type() -> void:
	if OS.has_feature("rel"):
		return
	var raw_experiments: Dictionary = ABTestManager.get_all_ab_experiments()

	if not raw_experiments.has(key):
		return
	var raw_value: Variant = raw_experiments[key]
	var raw_type: int = typeof(raw_value)
	var raw_is_number: bool = raw_type == TYPE_INT or raw_type == TYPE_FLOAT
	var default_is_string: bool = typeof(default_value) == TYPE_STRING
	var mismatched: bool = (
		(default_is_string and raw_is_number) or (not default_is_string and raw_type == TYPE_STRING)
	)
	if not mismatched:
		return
	push_error(
		(
			"[ABTest] 参数类型不一致 key=%s: SDK 下发值=%s(%s), default_value=%s(%s),请核对 AB 平台配置与 config 的取值类型"
			% [
				key,
				var_to_str(raw_value),
				type_string(raw_type),
				var_to_str(default_value),
				type_string(typeof(default_value))
			]
		)
	)


## 记录实验曝光，再通过事件总线提供含当前取值的观察事件。
func dye() -> void:
	ABTestManager.dye_ab(key)
	_emit_timeline_dye()


func _emit_timeline_dye() -> void:
	if not is_instance_valid(EventBus):
		return
	var payload: Dictionary = {"key": key, "value": value()}
	if _has_debug_override and str(_debug_override) != str(_value):
		payload["sdk"] = _value
	EventBus.emit_event(EventName.AB_DYE, payload)


var _dbg_store_calls: int = 0


## 仅记录被跟踪的实验：保留磁盘旧分组供提示判断，再把当前分组写入存档。
func _maybe_store_switch_group() -> void:
	if key in _SWITCH_STORE_EXCLUDE:
		return
	if not _is_switch_tracked_key(key):
		return
	var disk_before: int = GameState.get_saved_ab_group(key)
	var cur: int = int(value())
	_prev_saved_group = disk_before
	GameState.set_saved_ab_group(key, cur)
	_dbg_store_calls += 1
	if not OS.has_feature("rel"):
		print(
			(
				"[SwitchDbg] %s 第%d次 store: 磁盘旧值=%d → 写入=%d, _prev_saved_group=%d"
				% [key, _dbg_store_calls, disk_before, cur, _prev_saved_group]
			)
		)


func get_prev_saved_group() -> int:
	if _prev_saved_group != -1:
		return _prev_saved_group
	_prev_saved_group = GameState.get_saved_ab_group(key)
	return _prev_saved_group


func consume_switch() -> void:
	var cur: int = int(peek_value())
	_prev_saved_group = cur
	GameState.set_saved_ab_group(key, cur)


static func _is_switch_tracked_key(k: String) -> bool:
	if k in _SWITCH_STORE_INCLUDE:
		return true
	if not _switch_store_keys_loaded:
		_load_switch_store_keys()
	return _switch_store_keys.has(k)


static func _load_switch_store_keys() -> void:
	_switch_store_keys_loaded = true
	if not FileAccess.file_exists(_SWITCH_STRATEGY_PATH):
		return
	var f: FileAccess = FileAccess.open(_SWITCH_STRATEGY_PATH, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Array:
		return
	for entry in parsed:
		if not entry is Dictionary:
			continue

		for part in str(entry.get("Trigger", "")).split(","):
			var kv: PackedStringArray = part.split("=")
			if kv.size() == 2 and kv[0].strip_edges() == "key":
				_switch_store_keys[kv[1].strip_edges()] = true


func peek_value() -> Variant:
	_peek_store_keys[key] = true
	if _has_debug_override:
		return _debug_override

	if not ABTestManager.is_ab_init_done():
		var local_save: Variant = GameState.get_saved_peek_ab_group(key)
		if local_save == null:
			return default_value
		return local_save

	var peek: Variant
	if typeof(default_value) == TYPE_STRING:
		peek = ABTestManager.get_ab_string(key, default_value)
	else:
		peek = ABTestManager.get_ab_int(key, default_value)
	_store_peek_fallback(peek)
	return peek


func _store_peek_fallback(v: Variant) -> void:
	if not ABTestManager.is_ab_init_done():
		return
	GameState.set_saved_peek_ab_group(key, v)


## 是否已有可用值（取过远端或已被调试覆盖）
func is_value_loaded() -> bool:
	return _value_loaded or _has_debug_override


func set_debug_override(value: Variant, persist: bool = false) -> bool:
	if OS.has_feature("rel"):
		return false
	if persist and not DebugOverrideStore.set_override(key, value):
		return false
	_debug_override = value
	_has_debug_override = true

	_maybe_store_switch_group()
	debug_override_changed.emit()
	return true


func clear_debug_override() -> bool:
	if OS.has_feature("rel"):
		return false
	if not DebugOverrideStore.clear_override(key):
		return false
	_debug_override = null
	_has_debug_override = false
	debug_override_changed.emit()
	return true


## 该实验是否被作弊面板停用（调用点据此跳过这道闸门）
func is_debug_disabled() -> bool:
	return _debug_disabled


## 设置调试停用标记
func set_debug_disabled(disabled: bool) -> void:
	_debug_disabled = disabled


## 作弊面板显示名；子类可覆写成更易懂的说明
func cheat_label() -> String:
	return key


## 作弊面板显示当前取值
func cheat_value_str() -> String:
	return str(value())
