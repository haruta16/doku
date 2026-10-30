## 关卡玩法类型：区分主线、困难金鱼、插入金鱼与颜色挑战，并决定是否占用关号或参与主线 DDA。
class_name LevelKind
extends Object

enum { MAIN = 1, GOLDEN_FISH_HARD = 2, GOLDEN_FISH_INSERT = 3, COLOR_CHALLENGE = 4 }


## 同时认可困难金鱼和插入金鱼两种玩法。
static func is_golden_fish(kind: int) -> bool:
	return kind == GOLDEN_FISH_HARD or kind == GOLDEN_FISH_INSERT


## 仅判断不占主线关号的插入金鱼玩法。
static func is_insert_golden_fish(kind: int) -> bool:
	return kind == GOLDEN_FISH_INSERT


## 插入金鱼和颜色挑战不推进主线关号，其他类型占用关号。
static func occupies_level_number(kind: int) -> bool:
	return kind != GOLDEN_FISH_INSERT and kind != COLOR_CHALLENGE


## 金鱼与颜色挑战统一排除在主线动态难度计数之外。
static func is_excluded_from_main_dda(kind: int) -> bool:
	return is_golden_fish(kind) or is_color_challenge(kind)


## 判断是否为颜色挑战玩法。
static func is_color_challenge(kind: int) -> bool:
	return kind == COLOR_CHALLENGE


## 返回默认的普通主线玩法。
static func default_kind() -> int:
	return MAIN
