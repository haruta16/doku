## 头像与头像框的静态规则；特别定义冠军框累计获胜次数、形态门槛及默认解锁项。

class_name ProfileCatalog
extends RefCounted

const ACQUIRE_THRESHOLD: int = 100

const AVATAR_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]

const EVENT_AVATAR_IDS: Array[int] = [101]

const EVENT_FRAME_IDS: Array[int] = [200]

const HALLOWEEN_AVATAR_ID: int = 101
const HALLOWEEN_FRAME_ID: int = 200

const CLASSIC_FRAME_IDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]

const LEADERBOARD_FRAME_IDS: Array[int] = [100]

const FIRST_PLACE_FRAME_ID: int = 100

const FIRST_FRAME_FORM_THRESHOLDS: Array[int] = [1, 5, 15, 30, 50, 75, 100, 150, 200, 300, 500]
const FIRST_FRAME_FORM_COUNT: int = 11


static func is_valid_avatar(id: int) -> bool:
	return AVATAR_IDS.has(id) or EVENT_AVATAR_IDS.has(id)


static func is_default_owned_avatar(id: int) -> bool:
	return id > 0 and id < ACQUIRE_THRESHOLD


static func is_valid_frame(id: int) -> bool:
	return CLASSIC_FRAME_IDS.has(id) or LEADERBOARD_FRAME_IDS.has(id) or EVENT_FRAME_IDS.has(id)


static func shows_frame_count(id: int) -> bool:
	return is_counted_frame(id) and not EVENT_FRAME_IDS.has(id)


static func is_default_owned_frame(id: int) -> bool:
	return id > 0 and id < ACQUIRE_THRESHOLD


static func is_counted_frame(id: int) -> bool:
	return id >= ACQUIRE_THRESHOLD


static func default_frame_count(id: int) -> int:
	return 0 if is_counted_frame(id) else -1


static func is_valid_form(form: int) -> bool:
	return form >= 0 and form < FIRST_FRAME_FORM_COUNT


static func threshold_for_form(form: int) -> int:
	return FIRST_FRAME_FORM_THRESHOLDS[form] if is_valid_form(form) else 0


static func form_for_wins(wins: int) -> int:
	var best: int = -1
	for i in range(FIRST_FRAME_FORM_COUNT):
		if wins >= FIRST_FRAME_FORM_THRESHOLDS[i]:
			best = i
	return best


static func is_form_unlocked(form: int, wins: int) -> bool:
	return is_valid_form(form) and wins >= FIRST_FRAME_FORM_THRESHOLDS[form]
