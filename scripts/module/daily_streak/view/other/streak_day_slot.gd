# 打卡页里的单个星期格子：三种静态形态（未打卡 / 已打卡 / 宝箱）+ 打卡动画
# @tool 让它在编辑器里也能按 weekday 预览
@tool
extends Control

# ---- 颜色常量 ----
const COLOR_CHECKED := Color(0.94509804, 0.5764706, 0.1254902, 1) # 已打卡时的星期文字色
const COLOR_INACTIVE := Color(0.5769231, 0.3522559, 0.3522559, 1) # 未打卡时的星期文字色

# ---- 可调参数（Inspector 可改，改动会立刻刷新显示） ----
# 星期文案 key（如 WEEKDAY_WED）
@export var weekday: String = "WEEKDAY_WED":
	set = set_weekday
# 是否已打卡
@export var checked: bool = false:
	set = set_checked
# 是不是第 7 天的宝箱格
@export var is_chest: bool = false:
	set = set_chest

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _label: Label = $WeekLabel # 星期文字
@onready var _anim: AnimationPlayer = $AnimationPlayer # 格子动画播放器
@onready var _unchecked: Control = $UncheckedDot # 未打卡的圆点
@onready var _checked: Control = $CheckedDot # 已打卡的圆点
@onready var _chest: Control = $Chest # 宝箱整块
@onready var _gift_cell: Control = $Chest/StreakGiftCell # 宝箱里的礼物格
@onready var _click_area: Button = $Chest/ClickArea # 宝箱的点击区

# ---- 运行时状态 ----
var _applying: bool = false # 批量赋值期间置位，抑制 setter 里的重复刷新


# ================= 生命周期 =================
# 进场景树先按当前属性画一遍，并接上宝箱点击
func _ready() -> void:
	_show_static()

	if _click_area and not _click_area.pressed.is_connected(_on_chest_pressed):
		_click_area.pressed.connect(_on_chest_pressed)


# 取宝箱里礼物格的动画播放器（可能不存在，返回 null）
func _gift_anim() -> AnimationPlayer:
	if _gift_cell == null:
		return null
	return _gift_cell.get_node_or_null("AnimationPlayer") as AnimationPlayer


# 把礼物格的 Loop 设为线性循环并播放
func _play_chest_loop() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Loop"):
		return
	ap.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
	ap.play(&"Loop")


# 点宝箱：播一次 Click 再回到循环
func _on_chest_pressed() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Click"):
		return
	ap.play(&"Click")
	await ap.animation_finished
	if is_instance_valid(ap):
		_play_chest_loop()


# ================= 属性 setter（@export 与代码赋值都会走这里） =================
# 星期变化：只重刷文字
func set_weekday(v: String) -> void:
	weekday = v
	if is_inside_tree():
		_refresh_label()


# 打卡状态变化：重画静态形态（批量赋值时不重画）
func set_checked(v: bool) -> void:
	checked = v
	if is_inside_tree() and not _applying:
		_show_static()


# 宝箱标记变化：重画静态形态（批量赋值时不重画）
func set_chest(v: bool) -> void:
	is_chest = v
	if is_inside_tree() and not _applying:
		_show_static()


# ================= 对外接口（streak_page 调用） =================
# 一次性设置两个状态再重画，避免 setter 连环刷新
func apply_static(is_checked: bool, is_chest_slot: bool) -> void:
	_applying = true
	checked = is_checked
	is_chest = is_chest_slot
	_applying = false
	_show_static()


# 播打卡动画并返回时长（秒）供调用方等待；只改状态不写存档
func play_checkin(chest: bool) -> float:
	_applying = true
	is_chest = chest
	checked = true
	_applying = false
	_refresh_label()
	if _anim == null:
		return 0.0
	# 宝箱格：亮宝箱点并播开奖动画
	if chest:
		_set_dots(false, false, true)
		_anim.play(&"Reward")
	else:
		_set_dots(true, true, false)

		# 先 RESET 再播，避免残留上一帧
		if _anim.has_animation(&"RESET"):
			_anim.play(&"RESET")
			_anim.seek(0.0, true)
		_anim.play(&"CheckIn")

		if not Engine.is_editor_hint():
			SoundManager.play(SoundManager.Kind.USE_HINT)
	return _anim.current_animation_length


# 退回「未打卡」形态（开完宝箱后调用）
func show_unchecked_dot() -> void:
	_set_dots(true, false, false)


# ================= 内部显示 =================
# 按 checked / is_chest 画成三种静态形态之一，并把动画定格到对应帧
func _show_static() -> void:
	_refresh_label()
	if checked:
		_set_dots(false, true, false)
	elif is_chest:
		_set_dots(false, false, true)
	else:
		_set_dots(true, false, false)
	if _anim == null:
		return
	_anim.play(&"Idle" if checked else &"RESET")
	_anim.seek(_anim.current_animation_length, true)


# 隐藏宝箱（开完奖后不再显示）
func hide_chest() -> void:
	if _chest:
		_chest.visible = false


# 三个点的显隐开关：未打卡点 / 已打卡点 / 宝箱；显示宝箱时顺带播循环
func _set_dots(unchecked: bool, checked_dot: bool, chest: bool) -> void:
	if _unchecked:
		_unchecked.visible = unchecked
	if _checked:
		_checked.visible = checked_dot
	if _chest:
		_chest.visible = chest
	if chest:
		_play_chest_loop()


# 按当前星期 key 刷文字（走翻译）与文字颜色
func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = tr(weekday)
	_label.add_theme_color_override("font_color", COLOR_CHECKED if checked else COLOR_INACTIVE)
