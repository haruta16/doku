## 实验配置 dailystreak_icon：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DailystreakIconConfig

const VALUE_SUN: int = 0
const VALUE_WOOL: int = 4

const NODE_SUN: StringName = &"IconSun"
const NODE_WOOL: StringName = &"IconWool"

const CANVAS_RECT_SUN := Rect2(0.0, 0.0, 512.0, 512.0)
const CANVAS_RECT_WOOL := Rect2(88.0, -18.0, 334.0, 540.0)

const DESIGN_SIZE_SUN := Vector2(70.0, 70.0)
const DESIGN_SIZE_WOOL := Vector2(49.0, 78.0)

const DESIGN_BASE_HEIGHT: float = 70.0

const ANIM_SUN_LIGHT_UP: StringName = &"SunLightUp"
const ANIM_WOOL_SIGN: StringName = &"WoolSign"


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dailystreak_icon"
	default_value = VALUE_SUN


func is_themed_icon() -> bool:
	return value() != VALUE_SUN


func icon_node_name(group: int = -1) -> StringName:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return NODE_WOOL
	return NODE_SUN


func unchecked_alpha(group: int = -1) -> float:
	return 1.0


func canvas_content_rect(group: int = -1) -> Rect2:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return CANVAS_RECT_WOOL
	return CANVAS_RECT_SUN


func is_canvas_calibrated(group: int = -1) -> bool:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return true
	return false


func has_unchecked_art(group: int = -1) -> bool:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return true
	return false


func canvas_content_center(group: int = -1) -> Vector2:
	var r: Rect2 = canvas_content_rect(group)
	return r.position + r.size * 0.5


func design_icon_size(group: int = -1) -> Vector2:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return DESIGN_SIZE_WOOL
	return DESIGN_SIZE_SUN


func checkin_anim(group: int = -1) -> StringName:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return ANIM_WOOL_SIGN
	return ANIM_SUN_LIGHT_UP


func plays_on_every_checkin(group: int = -1) -> bool:
	var g: int = int(value()) if group < 0 else group
	return g == VALUE_WOOL


func all_form_node_names() -> Array[StringName]:
	return [NODE_SUN, NODE_WOOL]


func unchecked_anim(group: int = -1) -> StringName:
	return &""


func idle_loop_anim(group: int = -1) -> StringName:
	return &""


func idle_loop_delay(group: int = -1) -> float:
	return 0.0


func page_lit_anim(group: int = -1) -> StringName:
	return &""


func page_lit_slot_delay(group: int = -1) -> float:
	return -1.0


func tap_hint_key(group: int = -1) -> String:
	match int(value()) if group < 0 else group:
		VALUE_WOOL:
			return "DAILY_STREAK_TAP_YARN"
	return "DAILY_STREAK_TAP_SUN"
