## 本地通知数据：同时支持绝对毫秒时间和本地日历时间，并携带重复与免打扰规则。
class_name UniKitNotificationData
extends RefCounted

const DISTURB_TYPE_NONE: int = 0
const DISTURB_TYPE_TODAY: int = 1
const DISTURB_TYPE_TWENTY_FOUR_HOURS: int = 2

var id: String = ""

var alarm_time: int = 0
var is_repeat: bool = false

var repeat_interval: int = 0

var content_map: Dictionary = {}
var disturb_type: int = DISTURB_TYPE_NONE

var local_time: Dictionary = {}


## 保存通知标识、触发毫秒时间、重复间隔和候选内容。
func _init(
	p_id: String = "",
	p_alarm_time: int = 0,
	p_is_repeat: bool = false,
	p_repeat_interval: int = 0,
	p_content_map: Dictionary = {}
) -> void:
	id = p_id
	alarm_time = p_alarm_time
	is_repeat = p_is_repeat
	repeat_interval = p_repeat_interval
	content_map = p_content_map


## 设置免打扰规则并返回自身，便于链式配置通知。
func set_disturb_type(p_disturb_type: int) -> UniKitNotificationData:
	disturb_type = p_disturb_type
	return self


## 指定本地年月日时分；发送时会优先使用它而非绝对时间戳。
func set_alarm_local_time(
	year: int, month: int, day: int, hour: int, minute: int
) -> UniKitNotificationData:
	local_time = {"year": year, "month": month, "day": day, "hour": hour, "minute": minute}
	return self
