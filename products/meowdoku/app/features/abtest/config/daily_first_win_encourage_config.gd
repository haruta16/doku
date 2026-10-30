## 实验配置 daily_first_win_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailyFirstWinEncourageConfig

const VALUE_CONTROL: int = 0
const VALUE_GOAL_TOAST: int = 1
const VALUE_WIN_PRAISE: int = 2
const VALUE_GOAL_AND_PRAISE: int = 3

const GOAL_TEXT_KEYS: Array[StringName] = [
	&"DAILY_FIRST_WIN_GOAL_0",
	&"DAILY_FIRST_WIN_GOAL_1",
	&"DAILY_FIRST_WIN_GOAL_2",
	&"DAILY_FIRST_WIN_GOAL_3",
	&"DAILY_FIRST_WIN_GOAL_4",
	&"DAILY_FIRST_WIN_GOAL_5",
	&"DAILY_FIRST_WIN_GOAL_6",
	&"DAILY_FIRST_WIN_GOAL_7",
	&"DAILY_FIRST_WIN_GOAL_8",
	&"DAILY_FIRST_WIN_GOAL_9",
	&"DAILY_FIRST_WIN_GOAL_10",
	&"DAILY_FIRST_WIN_GOAL_11",
	&"DAILY_FIRST_WIN_GOAL_12",
	&"DAILY_FIRST_WIN_GOAL_13",
	&"DAILY_FIRST_WIN_GOAL_14",
]

const WIN_TEXT_PAIRS: Array[Dictionary] = [
	{"title_key": &"DAILY_FIRST_WIN_TITLE_0", "body_key": &"DAILY_FIRST_WIN_BODY_0"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_1", "body_key": &"DAILY_FIRST_WIN_BODY_1"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_2", "body_key": &"DAILY_FIRST_WIN_BODY_2"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_3", "body_key": &"DAILY_FIRST_WIN_BODY_3"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_4", "body_key": &"DAILY_FIRST_WIN_BODY_4"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_5", "body_key": &"DAILY_FIRST_WIN_BODY_5"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_6", "body_key": &"DAILY_FIRST_WIN_BODY_6"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_7", "body_key": &"DAILY_FIRST_WIN_BODY_7"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_8", "body_key": &"DAILY_FIRST_WIN_BODY_8"},
	{"title_key": &"DAILY_FIRST_WIN_TITLE_9", "body_key": &"DAILY_FIRST_WIN_BODY_9"},
]


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "daily_first_win_encourage"
	default_value = VALUE_CONTROL


func has_goal_toast() -> bool:
	return int(value()) == VALUE_GOAL_TOAST or int(value()) == VALUE_GOAL_AND_PRAISE


func has_win_praise() -> bool:
	return int(value()) == VALUE_WIN_PRAISE or int(value()) == VALUE_GOAL_AND_PRAISE


func is_first_eligible_entry(
	level_num: int, kind: int, main_win_today: bool, entry_seen_today: bool
) -> bool:
	return level_num > 1 and kind == LevelKind.MAIN and not main_win_today and not entry_seen_today


func pick_goal_text_key() -> StringName:
	return GOAL_TEXT_KEYS[randi() % GOAL_TEXT_KEYS.size()]


func pick_win_text_keys() -> Dictionary:
	return WIN_TEXT_PAIRS[randi() % WIN_TEXT_PAIRS.size()]
