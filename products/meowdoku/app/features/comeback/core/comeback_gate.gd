## 回流欢迎判定：结合实验、冷启动、离开天数和首页目标决定是否播放欢迎。
class_name ComebackGate
extends RefCounted

const GROUP_CONTROL: int = 0

const GROUP_WELCOME: int = 1

const GROUP_WELCOME_TEXT: int = 2

const RETURNEE_GAP_DAYS: int = 3


static func has_welcome_show(group: int) -> bool:
	return group == GROUP_WELCOME or group == GROUP_WELCOME_TEXT


static func has_welcome_text(group: int) -> bool:
	return group == GROUP_WELCOME_TEXT


## 实验开启、冷启动、返回首页且本次未展示时，离开至少 3 天才允许欢迎演出。
static func should_play(
	group: int, is_cold_start: bool, gap_days: int, is_home_target: bool, already_shown: bool
) -> bool:
	if not has_welcome_show(group):
		return false
	if not is_cold_start or already_shown or not is_home_target:
		return false
	return gap_days >= RETURNEE_GAP_DAYS
