# Toast 基类：入场/退场动画、点击跳过、变体卡片选择与埋点；子类只提供动画名与文案路径
class_name BaseGameToast
extends CanvasLayer

# ---- 动画标记约定 ----
const DISAPPEAR_MARKER: StringName = &"Disappear" # 退场标记名：播到这里就可以开始消失

const DISAPPEAR_MARKER_FALLBACK: StringName = &"Mark" # 退场标记的备用名
const HOLD_AT_DISAPPEAR_SEC: float = 1.4 # 在退场点停留的秒数

# ---- 子节点引用 ----
@onready var _root: Control = $Root # 整体根节点，接收点击
@onready var _card: Control = $Root/Card # 卡片容器，决定弹窗位置
@onready var _anim_player: AnimationPlayer = $AnimationPlayer # 动画播放器

# ---- 变体卡片与运行时状态 ----
const _CARD_NAMES: Array[String] = ["Card2", "Card4", "Card5", "Card6"] # 场景里的 4 张变体卡片名，由 AB 决定用哪张

var _label: RichTextLabel = null # 当前卡片里的文案节点，选卡后才有值

var _active_appear_anim: StringName = &"" # 当前生效的入场动画名，空表示用子类默认

@export var sibling_toast: CanvasLayer # 兄弟 Toast：显示前先关掉它，避免叠加

var _seq_token: int = 0 # 播放序号，用来作废过期的异步等待


# ================= 生命周期 =================
# 进树：接上动画结束回调、根节点点击，并调子类钩子
func _ready() -> void:
	_anim_player.animation_finished.connect(_on_anim_finished)

	_root.gui_input.connect(_on_root_gui_input)
	# 子类自己的初始化
	_on_ready_extra()


# ================= 子类覆写点与动画解析 =================
# 子类返回默认入场动画名
func _appear_anim() -> StringName:
	return &""


# 解析真正要播的入场动画：变体动画存在就用变体，否则用子类默认
func _resolve_appear_anim() -> StringName:
	if (
		_active_appear_anim != &""
		and _anim_player != null
		and _anim_player.has_animation(_active_appear_anim)
	):
		return _active_appear_anim
	return _appear_anim()


# 取动画里的退场标记时间；没有标记返回 -1
func _disappear_marker_time(anim: Animation) -> float:
	if anim == null:
		return -1.0
	# 优先 Disappear，老动画退回 Mark
	if anim.has_marker(DISAPPEAR_MARKER):
		return anim.get_marker_time(DISAPPEAR_MARKER)
	if anim.has_marker(DISAPPEAR_MARKER_FALLBACK):
		return anim.get_marker_time(DISAPPEAR_MARKER_FALLBACK)
	return -1.0


# 子类返回埋点用的弹窗名
func _dlg_name() -> String:
	return ""


# 子类返回文案节点在卡片里的相对路径
func _label_subpath() -> String:
	return ""


# 默认文案填充：翻译 text_key 后用 pct_str 替换占位符
func _apply_text(params: Dictionary) -> void:
	# 默认取首次尝试文案与 0.0%
	var text_key: String = params.get("text_key", "GAME_TOAST_FIRST_TRY")
	var pct_str: String = params.get("pct_str", "0.0%")
	# tr(...) % pct_str 做字符串格式化
	_label.text = tr(text_key) % pct_str


# 子类可选的进树钩子
func _on_ready_extra() -> void:
	pass


# ================= 展示与隐藏 =================
# 把卡片左上角移到指定位置
func set_card_position(top_left: Vector2) -> void:
	if _card != null:
		_card.position = top_left


# 把卡片中心对准指定位置
func set_card_center(center: Vector2) -> void:
	if _card != null:
		_card.position = center - _card.size * 0.5


# 显示 Toast：先关掉兄弟 Toast，再选卡片、填文案、播入场动画
func show_toast(params: Dictionary = {}) -> void:
	if sibling_toast != null and is_instance_valid(sibling_toast) and sibling_toast.visible:
		if sibling_toast.has_method("hide_toast"):
			sibling_toast.hide_toast()
	visible = true

	# 选变体卡片并填文案
	_select_variant_card()
	_apply_text(params)

	# 点击穿透分组不拦截输入，其余分组要吃掉点击
	_root.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE if _is_click_through_group() else Control.MOUSE_FILTER_STOP
	)
	# 序号 +1，作废上一次还在等待的异步流程
	_seq_token += 1
	# 上报弹窗展示
	Tracker.track_dlg_show(_dlg_name())
	_play_entry_anim(_seq_token)


# 当前 AB 分组是否要求点击穿透（取值 3/5/6）
func _is_click_through_group() -> bool:
	return ABTestManager.normal_start_toast.value() in [3, 5, 6]


# 按 AB 选中的卡片名切换显示，并缓存该卡片里的文案节点
func _select_variant_card() -> void:
	var target: String = ABTestManager.normal_start_toast.get_variant_card()
	# 只让目标卡片可见
	for card_name in _CARD_NAMES:
		var c: Control = _card.get_node_or_null(card_name) as Control
		if c != null:
			c.visible = (card_name == target)

	_label = _card.get_node_or_null("%s/%s" % [target, _label_subpath()]) as RichTextLabel

	# 变体卡片有同名动画就一并作为入场动画
	if _anim_player != null and _anim_player.has_animation(target):
		_active_appear_anim = StringName(target)

		_card.scale = Vector2.ONE
	else:
		_active_appear_anim = &""


# 立即隐藏（不动画）
func hide_toast() -> void:
	if not visible:
		return
	visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 序号 +1，让等待中的异步流程失效
	_seq_token += 1
	_anim_player.stop()
	Tracker.notify_dlg_closed(_dlg_name())


# 入场动画播完：恢复点击穿透；若期间被隐藏则补一次关闭埋点
func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == _resolve_appear_anim():
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if visible:
			visible = false
			Tracker.notify_dlg_closed(_dlg_name())


# ================= 输入与跳过 =================
# 根节点收到点击：跳到退场点
func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skip_to_disappear()
		_root.accept_event()


# 全局输入兜底：只有点击穿透分组才需要在这里补一次「跳过」
func _input(event: InputEvent) -> void:
	if not visible or not _is_click_through_group():
		return
	var pressed: bool = (
		(event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	)
	if pressed:
		_skip_to_disappear()


# ================= 动画细节 =================
# 把入场动画快进到退场标记后继续播（点击跳过）
func _skip_to_disappear() -> void:
	# 正在播的不是入场动画就不处理
	var appear: StringName = _resolve_appear_anim()
	if _anim_player.assigned_animation != appear:
		return
	var anim: Animation = _anim_player.get_animation(appear)
	# 拿不到动画也不处理
	if anim == null:
		return
	# 退场标记时间（-1 表示没有标记）
	var marker_time: float = _disappear_marker_time(anim)
	var cur: float = _anim_player.current_animation_position

	# 已经播过退场点就不用再跳
	if cur >= marker_time and _anim_player.is_playing():
		return
	# 序号 +1，作废正在等待的停留流程
	_seq_token += 1

	# 还没到退场点就快进过去
	if cur < marker_time:
		_anim_player.seek(marker_time, true)
	_anim_player.play(appear)


# 播入场动画：到退场标记处暂停 HOLD_AT_DISAPPEAR_SEC 秒再继续（即停留展示）
func _play_entry_anim(token: int) -> void:
	var appear: StringName = _resolve_appear_anim()
	var anim: Animation = _anim_player.get_animation(appear)
	# 拿不到动画就不播
	if anim == null:
		return
	var marker_time: float = _disappear_marker_time(anim)
	# 没有标记（-1）就整段播
	if marker_time < 0.0:
		_anim_player.play(appear)
		return
	_anim_player.play(appear)
	await get_tree().create_timer(marker_time).timeout
	# 期间被隐藏或被新的显示顶掉 → 放弃
	if token != _seq_token or not is_inside_tree() or not visible:
		return
	# 先暂停在退场点
	_anim_player.pause()
	# 停留够时间再继续播
	await get_tree().create_timer(HOLD_AT_DISAPPEAR_SEC).timeout
	# 再次确认没被打断
	if token != _seq_token or not is_inside_tree() or not visible:
		return
	_anim_player.play(appear) # 继续播退场部分
