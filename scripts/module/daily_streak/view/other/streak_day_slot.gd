## 打卡周进度槽：展示星期、勾选和宝箱，控制签到落点动画与震动。
@tool
extends Control

# ---- 颜色常量 ----
const COLOR_CHECKED := Color(0.94509804, 0.5764706, 0.1254902, 1) # 已打卡时的星期文字色
const COLOR_INACTIVE := Color(0.5769231, 0.3522559, 0.3522559, 1) # 未打卡时的星期文字色

# ---- 可调参数（Inspector 可改，改动会立刻刷新显示） ----
## 星期文案 key（如 WEEKDAY_WED）
@export var weekday: String = "WEEKDAY_WED":
	set = set_weekday
## 是否已打卡
@export var checked: bool = false:
	set = set_checked
## 是不是第 7 天的宝箱格
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
var _checkin_generation: int = 0


# ================= 生命周期 =================
## 进场景树先按当前属性画一遍，并接上宝箱点击
func _ready() -> void:
	_show_static()

	if _click_area and not _click_area.pressed.is_connected(_on_chest_pressed):
		_click_area.pressed.connect(_on_chest_pressed)


## 取宝箱里礼物格的动画播放器（可能不存在，返回 null）
func _gift_anim() -> AnimationPlayer:
	if _gift_cell == null:
		return null
	return _gift_cell.get_node_or_null("AnimationPlayer") as AnimationPlayer


## 把礼物格的 Loop 设为线性循环并播放
func _play_chest_loop() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Loop"):
		return
	ap.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
	ap.play(&"Loop")


## 点宝箱：播一次 Click 再回到循环
func _on_chest_pressed() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Click"):
		return
	ap.play(&"Click")
	await ap.animation_finished
	if is_instance_valid(ap):
		_play_chest_loop()


# ================= 属性 setter（@export 与代码赋值都会走这里） =================
## 星期变化：只重刷文字
func set_weekday(v: String) -> void:
	weekday = v
	if is_inside_tree():
		_refresh_label()


## 打卡状态变化：重画静态形态（批量赋值时不重画）
func set_checked(v: bool) -> void:
	checked = v
	if is_inside_tree() and not _applying:
		_show_static()


## 宝箱标记变化：重画静态形态（批量赋值时不重画）
func set_chest(v: bool) -> void:
	is_chest = v
	if is_inside_tree() and not _applying:
		_show_static()


# ================= 对外接口（streak_page 调用） =================
## 一次性设置两个状态再重画，避免 setter 连环刷新
func apply_static(is_checked: bool, is_chest_slot: bool) -> void:
	_applying = true
	checked = is_checked
	is_chest = is_chest_slot
	_applying = false
	_show_static()


func play_checkin(chest: bool, success_effect: bool = false) -> float:
	_checkin_generation += 1
	var pos := (
		VibrateManager.Pos.STREAK_DAY_CHEST if chest else VibrateManager.Pos.STREAK_DAY_NORMAL
	)
	VibrateManager.play_at(pos)
	_applying = true
	is_chest = chest
	checked = true
	_applying = false
	_refresh_label()
	if _anim == null:
		return 0.0
	if chest:
		_set_dots(false, false, true)
		_anim.play(&"Reward")
	else:
		_set_dots(true, true, false)

		if _anim.has_animation(&"RESET"):
			_anim.play(&"RESET")
			_anim.seek(0.0, true)
		_anim.play(&"CheckIn")
		if success_effect and not Engine.is_editor_hint():
			_play_landing_vibrate(_checkin_generation)
			_finish_checkin_empty_tail(_checkin_generation)

		if not Engine.is_editor_hint():
			SoundManager.play(SoundManager.Kind.USE_HINT)
	return _anim.current_animation_length


func _get_landing_time(animation: Animation) -> float:
	var track_index: int = animation.find_track(^"CheckedDot:position:y", Animation.TYPE_BEZIER)
	if track_index < 0:
		return -1.0
	var key_count: int = animation.track_get_key_count(track_index)
	for key_index: int in range(1, key_count - 1):
		var position_y: float = animation.bezier_track_get_key_value(track_index, key_index)
		var previous_y: float = animation.bezier_track_get_key_value(track_index, key_index - 1)
		var next_y: float = animation.bezier_track_get_key_value(track_index, key_index + 1)
		if position_y > previous_y and position_y > next_y:
			return animation.track_get_key_time(track_index, key_index)
	return -1.0


func _is_checkin_current(generation: int) -> bool:
	return (
		generation == _checkin_generation
		and is_visible_in_tree()
		and _anim != null
		and _anim.is_playing()
		and _anim.current_animation == &"CheckIn"
	)


func _play_landing_vibrate(generation: int) -> void:
	var landing_time: float = _get_landing_time(_anim.get_animation(&"CheckIn"))
	if landing_time < 0.0:
		return
	while _is_checkin_current(generation):
		if _anim.current_animation_position >= landing_time:
			VibrateManager.play_at(VibrateManager.Pos.STREAK_DAY_LAND)
			return
		await get_tree().process_frame


func _finish_checkin_empty_tail(generation: int) -> void:
	var animation: Animation = _anim.get_animation(&"CheckIn")
	if animation.loop_mode != Animation.LOOP_NONE:
		return
	var last_key_time: float = 0.0
	var particles: Array[CPUParticles2D] = []
	for track_index: int in animation.get_track_count():
		var key_count: int = animation.track_get_key_count(track_index)
		for key_index: int in key_count:
			last_key_time = maxf(
				last_key_time, animation.track_get_key_time(track_index, key_index)
			)
		var track_path: NodePath = animation.track_get_path(track_index)
		if track_path.get_concatenated_subnames() != "emitting":
			continue
		var particle_node: CanvasItem = (
			get_node_or_null(NodePath(track_path.get_concatenated_names())) as CanvasItem
		)
		if particle_node == null or not particle_node.is_visible_in_tree():
			continue
		if not particle_node is CPUParticles2D:
			return
		var particle: CPUParticles2D = particle_node as CPUParticles2D
		if not particles.has(particle):
			particles.append(particle)
	while _is_checkin_current(generation):
		var particles_finished: bool = true
		for particle: CPUParticles2D in particles:
			if (
				particle.is_visible_in_tree()
				and (particle.emitting or particle.is_processing_internal())
			):
				particles_finished = false
				break
		var playing_speed: float = _anim.get_playing_speed()
		if (
			particles_finished
			and playing_speed > 0.0
			and _anim.current_animation_position >= last_key_time
		):
			var remaining: float = maxf(0.0, animation.length - _anim.current_animation_position)
			_anim.advance(remaining / playing_speed + 1e-05)
			return
		await get_tree().process_frame


## 退回「未打卡」形态（开完宝箱后调用）
func show_unchecked_dot() -> void:
	_set_dots(true, false, false)


func _show_static() -> void:
	_checkin_generation += 1
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


## 隐藏宝箱（开完奖后不再显示）
func hide_chest() -> void:
	if _chest:
		_chest.visible = false


## 三个点的显隐开关：未打卡点 / 已打卡点 / 宝箱；显示宝箱时顺带播循环
func _set_dots(unchecked: bool, checked_dot: bool, chest: bool) -> void:
	if _unchecked:
		_unchecked.visible = unchecked
	if _checked:
		_checked.visible = checked_dot
	if _chest:
		_chest.visible = chest
	if chest:
		_play_chest_loop()


## 按当前星期 key 刷文字（走翻译）与文字颜色
func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = tr(weekday)
	_label.add_theme_color_override("font_color", COLOR_CHECKED if checked else COLOR_INACTIVE)
