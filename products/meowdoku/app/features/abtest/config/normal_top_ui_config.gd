## 实验配置 normal_top_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NormalTopUiConfig

const VALUE_CONTROL: int = 0
const VALUE_SWAP: int = 1
const VALUE_MERGE: int = 2
const VALUE_HIDE: int = 3
const VALUE_FIRE_PREFIX: int = 4

const VALUE_CAT_PROGRESS: int = 5

const VALUE_CAT_PROGRESS_COLORED: int = 6

const VALUE_SHOW_DONE_COLOR: int = 7

const VALUE_LAYOUT_MIDDLE: int = 8

const VALUE_FULL_OPEN: int = 9

const VALUE_AUTO_SORT: int = 10


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_top_ui"
	default_value = VALUE_CONTROL


func _group() -> int:
	return int(peek_value())


func shows_hard_tag() -> bool:
	var group: int = _group()
	return (
		group == VALUE_CONTROL
		or group == VALUE_SWAP
		or group == VALUE_CAT_PROGRESS
		or group == VALUE_CAT_PROGRESS_COLORED
		or group == VALUE_SHOW_DONE_COLOR
		or group == VALUE_LAYOUT_MIDDLE
		or group == VALUE_FULL_OPEN
		or group == VALUE_AUTO_SORT
	)


func is_swap_fire() -> bool:
	return _group() == VALUE_SWAP


func is_merge_level() -> bool:
	return _group() == VALUE_MERGE


func is_hide_hard() -> bool:
	return _group() == VALUE_HIDE


func is_fire_prefix() -> bool:
	return _group() == VALUE_FIRE_PREFIX


func is_cat_progress_bar() -> bool:
	var group: int = _group()
	return (
		group == VALUE_CAT_PROGRESS
		or group == VALUE_CAT_PROGRESS_COLORED
		or group == VALUE_SHOW_DONE_COLOR
		or group == VALUE_LAYOUT_MIDDLE
		or group == VALUE_FULL_OPEN
		or group == VALUE_AUTO_SORT
	)


func is_cat_progress_colored() -> bool:
	var group: int = _group()
	return (
		group == VALUE_CAT_PROGRESS_COLORED
		or group == VALUE_SHOW_DONE_COLOR
		or group == VALUE_LAYOUT_MIDDLE
		or group == VALUE_FULL_OPEN
		or group == VALUE_AUTO_SORT
	)


func is_cat_progress_show_done_color() -> bool:
	var group: int = _group()
	return group == VALUE_SHOW_DONE_COLOR or group == VALUE_FULL_OPEN


func is_cat_progress_adjacent_board() -> bool:
	var group: int = _group()
	return group == VALUE_LAYOUT_MIDDLE or group == VALUE_FULL_OPEN


func is_cat_progress_compact() -> bool:
	return _group() == VALUE_AUTO_SORT
