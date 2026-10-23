## 实验配置 comeback_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ComebackFuncConfig

const VALUE_CONTROL: int = 0

const VALUE_WELCOME: int = 1

const VALUE_WELCOME_TEXT: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "comeback_func"
	default_value = VALUE_CONTROL


func has_welcome_show() -> bool:
	return ComebackGate.has_welcome_show(int(value()))


func has_welcome_text() -> bool:
	return ComebackGate.has_welcome_text(int(value()))


func should_play_welcome(
	is_cold_start: bool, gap_days: int, is_home_target: bool, already_shown: bool
) -> bool:
	return ComebackGate.should_play(
		int(value()), is_cold_start, gap_days, is_home_target, already_shown
	)


func get_start_text_key() -> StringName:
	return &"COMEBACK_START_TOAST" if has_welcome_text() else &""


func get_win_text_keys() -> Dictionary:
	if not has_welcome_text():
		return {}
	return {"title_key": &"COMEBACK_WIN_TITLE", "body_key": &"COMEBACK_WIN_BODY"}


func load_value() -> void:
	_value = 0
	_value_loaded = true

	_check_raw_value_type()

	if not _switch_group_stored:
		_switch_group_stored = true
		_maybe_store_switch_group()
	if _peek_store_keys.has(key):
		_store_peek_fallback(_value)
