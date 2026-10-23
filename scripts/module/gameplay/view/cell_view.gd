## 单格状态与表现：连接 CellState、底色图案、叉动画及猫骨骼；通过代理把猫同步到棋盘集中绘制层。
@tool
class_name CellView
extends Control

# ---- 可调参数（Inspector 可改） ----
@export var region_colors: PackedColorArray = PackedColorArray() # 12 色区域调色板（BoardView 取它作基准色）

@export var _cross_stroke_tex_control: Texture2D = preload(
	"res://assets/sprites/game/icon_mark_white_2.png"
)
@export var _cross_stroke_tex_fulfill: Texture2D = preload(
	"res://assets/sprites/game/icon_mark_white_G5_2.png"
)
@export
var _draft_cross_tex_control: Texture2D = preload("res://assets/sprites/game/icon_mark_white_3.png")
@export var _draft_cross_tex_fulfill: Texture2D = preload(
	"res://assets/sprites/game/icon_mark_white_G5_3.png"
)
@export
var _auto_x_fill_tex_control: Texture2D = preload("res://assets/sprites/game/icon_mark_white.png")
@export var _auto_x_fill_tex_fulfill: Texture2D = preload(
	"res://assets/sprites/game/icon_mark_white_G5.png"
)

var _stroke_region_baseline: Rect2 = Rect2()
var _stroke_region_captured: bool = false

const _FULFILL_STROKE_NP1_POS := Vector2(11.0, 26.25)
const _FULFILL_STROKE_NP2_POS := Vector2(73.0, 11.0)
const _FULFILL_STROKE_SIZE := Vector2(46.0, 178.0)

@onready var _bg: CellFace = $BgPanel/BgPanel
@onready var _glow: Sprite2D = $Glows/Glow # 光晕 1（显隐由动画轨驱动）
@onready var _glow2: Sprite2D = $Glows/Glow2 # 光晕 2

@onready var _glow4: Sprite2D = $Glows/Glow4
@onready var _anim: AnimationPlayer = $AnimationPlayer # 主体动画播放器：RESET / 叉 / 猫 / 错标 全走它
@onready var _cross: Node = $Crosses/CrossOut # 玩家打的叉节点
@onready var _cross_np1: NinePatchRect = $Crosses/CrossOut/NinePatchRect
@onready var _cross_np2: NinePatchRect = $Crosses/CrossOut/NinePatchRect2
@onready var _red_cross_np1: NinePatchRect = $Crosses/RedCross/NinePatchRect
@onready var _red_cross_np2: NinePatchRect = $Crosses/RedCross/NinePatchRect2
@onready var _draft_cross_sprite: Sprite2D = $Crosses/PromptCrossOut/White
@onready var _auto_x_fill_cross_sprite: Sprite2D = $Crosses/AutoXFillMode/White
@onready var _hint_light: Sprite2D = $Frames/HighLight # 提示高亮（呼吸闪烁）

@onready var _cat_icon: Node2D = $CatIcon

@onready var _collect_player: AnimationPlayer = $CollectPlayer
@onready var _glow_player: AnimationPlayer = $GlowPlayer
@onready var _cat_prompt: Sprite2D = $CatPrompt # 草稿猫 / 提示猫剪影
@onready var _prompt_frame: Sprite2D = $Frames/PromptFrame # 草稿与提示用的边框
@onready var _prompt_cross_out: Control = $Crosses/PromptCrossOut # 草稿叉
@onready var _red_rect: Panel = $BgPanel/BgRed/RedRecttangle2
@onready var _mouse: CanvasItem = get_node_or_null("Mouse") as CanvasItem

# ---- 提示闪烁参数 ----
const _HINT_ALPHA_MIN: float = 50.0 / 255.0 # 闪烁最暗时的透明度（50/255）
const _HINT_HALF_CYCLE: float = 0.65 # 单程时长（秒）：暗→亮、亮→暗 各这么多
const _HINT_FADE_OUT: float = 0.12 # 收尾淡出时长（秒）

static var debug_gold_flash_bug: bool = false

const _CAT_ICON_BASE_SCALE: Vector2 = Vector2(0.35, 0.35)


## 返回猫代理节点的设计缩放基准，供外部动画统一尺度。
static func get_cat_icon_base_scale() -> Vector2:
	return _CAT_ICON_BASE_SCALE


## 返回实际显示的 SpineSprite，尚未创建时可能为 null。
func get_cat_icon() -> Node2D:
	return _cat_spine


## 取得猫出现粒子控件，场景没有该节点时返回 null。
func get_appear_particles() -> Control:
	return get_node_or_null("EffectCatIconAppear2") as Control


const _WIN_ENLARGE_RATIO: float = 1.25
const _WIN_ENLARGE_DUR: float = 0.5
const _WIN_SHRINK_AT: float = 0.95
const _WIN_SHRINK_DUR: float = 0.3

# ---- 进行中的 Tween（重播前先 kill，避免叠在一起） ----
var _hint_tween: Tween = null # 高亮闪烁循环
var _frame_tween: Tween = null # PromptFrame 闪烁循环
var _preview_tween: Tween = null # R2 预览
var _win_scale_tween: Tween = null

const NEAR_DEATH_APPEAR_SPINE: String = "Appear_neardeath"

const _BLAST_SCENES: Array[PackedScene] = [
	preload("res://assets/prefab/effect_blast_low.tscn"),
	preload("res://assets/prefab/effect_blast_medium.tscn"),
	preload("res://assets/prefab/effect_blast_high.tscn"),
]

var _blast_fx_by_tier: Dictionary = {}
var _blast_emitters_by_tier: Dictionary = {}

# ---- 运行时状态 ----
@export var _region_color: Color = Color.WHITE # 本格区域底色（@export 便于编辑器里预览）
var _state: int = CellState.EMPTY # 当前格子状态，取 CellState 常量
var _cat_visual_revealed: bool = false

var _dim_alpha: float = 1.0

var _dim_target_alpha: float = 1.0

var _dim_tween: Tween = null

const _DIM_TWEEN_SEC: float = 0.1

const _RED_CROSS_BASE_COLOR: Color = Color(0.99215686, 0.41568628, 0.18039216, 1.0)

const _RED_CROSS_DIM_TARGET: Color = Color(1.0, 1.0, 1.0, 1.0)

var _use_hard_bg: bool = false


## 记录圆角底面是否使用硬边；后续圆角更新会传给 CellFace。
func set_use_hard_bg(value: bool) -> void:
	_use_hard_bg = value


var _pattern_tex: Texture2D = null
var _pattern_on: bool = false
var _pattern_keep: bool = false

var _pattern_base_color: Color = Color.WHITE

# ---- 视觉尺寸设计值（按容器缩放做补偿） ----
const DESIGN_CELL_VISUAL_PX: float = 97.55 # 设计稿格子边长（像素），当前未被引用
const DESIGN_CORNER_VISUAL_PX: float = 10.0 # 设计稿圆角半径（像素）

const DESIGN_OUTER_CORNER_VISUAL_PX: float = 14.0

const CORNER_TL: int = 1
const CORNER_TR: int = 2
const CORNER_BR: int = 4
const CORNER_BL: int = 8
var _round_corners_mask: int = 0
var _last_container_scale: float = 1.0
var _last_board_size: int = 0

# ---- 「打过叉 / 出过错」追踪（R4+ 鼓掌提示按区域聚合，见 BoardView） ----
const _DOUBLE_TAP_MARK_GRACE_MS: int = 1000 # 叉→猫 的宽容窗口（毫秒）：窗口内切换不算「打过叉」
var _ever_marked_x: bool = false # 本局是否打过分叉
var _ever_errored: bool = false # 本局是否出过错标
var _mark_entered_time_ms: int = -1 # 进入 MARK 的时刻（毫秒）；-1 表示当前不在 MARK
var _ever_marked_x_snapshot: bool = false # 进入 MARK 前的 _ever_marked_x 快照，用于宽容窗口回滚

# ---- 猫的闲置动画 ----
const _IDLE_INTERVAL: float = 5.0 # 闲置多久后重播 idle（秒）
const CROSS_OUT_APPEAR_DURATION: float = 0.49 # 叉出现动画时长（秒）；当前全仓未被引用
const _WIN_RED_MARK_TO_WHITE_ANIM: StringName = &"WinRedMarkToWhite"

var _log_cell_anim_play: bool = not OS.has_feature("rel")

const _LOG_CELL_ANIM_SKIP: Array[StringName] = [&"RESET", &"CatIconIdle"]
var _idle_timer: Timer = null # 闲置定时器（运行时 Timer.new，只对猫生效）
var _cat_cry_loop: bool = false # 是否在循环播放「猫哭」

var _custom_appear_clip: String = ""

const BATCH_LAYER_NAME: StringName = &"CatBatchLayer"

const CAT_LAYER_Z_INDEX: int = 3

static var _spine_batching_supported: int = -1

var _cat_spine: SpineSprite = null

var _cat_proxy: Node2D = null

var _frame_pre_draw_cb: Callable = Callable()

var _cat_xform_synced: Transform2D = Transform2D()

var _pending_spine_clip: String = ""
var _pending_spine_loop: bool = false
var _pending_spine_seek_end: bool = false
var _pending_spine_dirty: bool = false

const _CAT_SPINE_CLIP_BY_ANIM: Dictionary = {
	"CatIconAppear": "Appear",
	"CatIconIdle": "idle",
	"CatIconCry": "cry",
	"CatIconFrustrated": "frustrated",
	"CatIconAngry": "anger1",
	"CatIconAngry2": "anger2",
	"PreCat2": "Appear",
	"CatIconGreet": "greet",
}

const _CAT_SPINE_LOOP_ANIMS: Array[String] = ["CatIconCry"]

static var _cat_spine_clip_exists: Dictionary = {}


## 初始化底面与运行时动画信号，创建闲置计时器，并把格子复位为空状态。
func _ready() -> void:
	set_corner_radius_compensated(1.0)
	_update_bg()

	if Engine.is_editor_hint():
		return

	_idle_timer = Timer.new()
	_idle_timer.wait_time = _IDLE_INTERVAL
	_idle_timer.one_shot = false
	_idle_timer.autostart = false
	add_child(_idle_timer)
	_idle_timer.timeout.connect(_on_idle_timer_timeout)
	_anim.animation_started.connect(_on_anim_started)
	_anim.animation_finished.connect(_on_anim_finished)

	_set_children_mouse_ignore(self)

	_cat_proxy = _cat_icon

	_reset_to_empty_baseline()


## 检查 SpineSprite 是否公开 batching_enabled 属性，并缓存引擎能力判断。
static func engine_supports_spine_batching() -> bool:
	if _spine_batching_supported < 0:
		_spine_batching_supported = 0
		if ClassDB.class_exists("SpineSprite"):
			var props: Array = ClassDB.class_get_property_list("SpineSprite", true)
			for prop in props:
				if String(prop.get("name", "")) == "batching_enabled":
					_spine_batching_supported = 1
					break
	return _spine_batching_supported == 1


## 按需从棋盘池取得或新建猫骨骼，挂到集中绘制层，连接逐帧代理同步并执行待播动画。
func _ensure_cat_spine() -> bool:
	if _cat_spine != null and is_instance_valid(_cat_spine):
		return true
	if _cat_proxy == null or not is_instance_valid(_cat_proxy):
		return false
	var host := get_parent()
	if host == null:
		return false

	var layer: Node2D = null
	if host.has_method("ensure_cat_batch_layer"):
		layer = host.call("ensure_cat_batch_layer") as Node2D
	else:
		layer = host.get_node_or_null(NodePath(BATCH_LAYER_NAME)) as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = BATCH_LAYER_NAME
		layer.z_index = CAT_LAYER_Z_INDEX
		layer.z_as_relative = true
		host.add_child(layer)

		if layer.get_parent() == null:
			layer.free()
			push_error("CellView(%s): CatBatchLayer 挂载失败,本格猫头不显示" % name)
			return false

	var spine: SpineSprite = null
	if host.has_method("acquire_pooled_cat_spine"):
		spine = host.call("acquire_pooled_cat_spine") as SpineSprite
	if spine == null or not is_instance_valid(spine):
		spine = SpineSprite.new()

		spine.skeleton_data_res = CostumeSkin.SKELETON_RES

	spine.name = "CatIconSpine_%s" % name
	layer.add_child(spine)

	spine.global_transform = _cat_proxy.global_transform

	spine.z_index = 0

	_cat_spine = spine

	if cat_settle_enabled:
		_cat_settle = _CatSettle.LIVE
		_cat_settle_frames = 0
		SpineIdleGuard.set_settled(spine, false)
	_cat_xform_synced = spine.global_transform

	CostumeSkin.apply(spine, _cat_costume_id)

	_apply_cat_spine_now("idle", false, false)

	if (
		_frame_pre_draw_cb.is_valid()
		and RenderingServer.frame_pre_draw.is_connected(_frame_pre_draw_cb)
	):
		RenderingServer.frame_pre_draw.disconnect(_frame_pre_draw_cb)
	_frame_pre_draw_cb = _sync_cat_proxy
	RenderingServer.frame_pre_draw.connect(_frame_pre_draw_cb)

	_sync_cat_proxy()

	_flush_pending_cat_spine()
	return true


## 绘制前把本格 CatIcon 代理的全局变换、颜色和可见性同步到集中层中的骨骼。
## 动画节点仍留在格子内，真实猫骨骼在棋盘公共层，两者通过这个回调保持一致。
func _sync_cat_proxy() -> void:
	if _cat_spine == null or _cat_proxy == null:
		return
	if not is_instance_valid(_cat_spine) or not is_instance_valid(_cat_proxy):
		return

	if not _cat_proxy.is_inside_tree():
		_cat_spine.visible = false
		return
	if not _cat_spine.is_inside_tree():
		return

	var want_visible: bool = _cat_proxy.is_visible_in_tree()
	_cat_spine.visible = want_visible

	_cat_spine.modulate = _cat_proxy.modulate * modulate

	var xform: Transform2D = _cat_proxy.global_transform
	var xform_changed: bool = xform != _cat_xform_synced

	if (
		_cat_settle != _CatSettle.LIVE
		and (xform_changed or _pending_spine_dirty or not want_visible)
	):
		_wake_cat_settle()
	if xform_changed:
		_cat_xform_synced = xform
		_cat_spine.global_transform = xform

	_flush_pending_cat_spine()

	_update_cat_settle(xform_changed)


enum _CatSettle { LIVE, LEAVING, SETTLED }
var _cat_settle: int = _CatSettle.LIVE
var _cat_settle_frames: int = 0
const _CAT_SETTLE_LEAVE_FRAMES: int = 2

static var cat_settle_enabled: bool = false


## 判断猫的非循环动画是否结束且混合已收尾，供静止优化决定是否暂停骨骼更新。
func _cat_pose_is_static() -> bool:
	if _pending_spine_dirty:
		return false
	if not _cat_spine.visible or not _cat_spine.is_visible_in_tree():
		return false
	var state: SpineAnimationState = _cat_spine.get_animation_state()
	if state == null:
		return false
	var entry: SpineTrackEntry = state.get_current(0)
	if entry == null:
		return true
	return not entry.get_loop() and entry.is_complete() and entry.get_mixing_from() == null


## 按 LIVE→LEAVING→SETTLED 推进静止状态；稳定两帧后通知 SpineIdleGuard，变化时唤醒。
func _update_cat_settle(xform_changed: bool) -> void:
	if not cat_settle_enabled and _cat_settle == _CatSettle.LIVE:
		return
	if not is_instance_valid(_cat_spine):
		return
	var want_static: bool = cat_settle_enabled and not xform_changed and _cat_pose_is_static()
	match _cat_settle:
		_CatSettle.LIVE:
			if want_static:
				_cat_settle = _CatSettle.LEAVING
				_cat_settle_frames = 0
		_CatSettle.LEAVING:
			if not want_static:
				_wake_cat_settle()
				return
			_cat_settle_frames += 1
			if _cat_settle_frames >= _CAT_SETTLE_LEAVE_FRAMES:
				_cat_settle = _CatSettle.SETTLED
				SpineIdleGuard.set_settled(_cat_spine, true)
		_CatSettle.SETTLED:
			if not want_static:
				_wake_cat_settle()


## 退出静止状态并让 SpineIdleGuard 恢复该骨骼的更新。
func _wake_cat_settle() -> void:
	if _cat_settle == _CatSettle.LIVE:
		return
	_cat_settle = _CatSettle.LIVE
	_cat_settle_frames = 0
	if _cat_spine != null and is_instance_valid(_cat_spine):
		SpineIdleGuard.set_settled(_cat_spine, false)


## 同时更新代理与原猫节点的颜色，下一次同步再作用到真实骨骼。
func _set_cat_modulate(color: Color) -> void:
	if _cat_proxy != null:
		_cat_proxy.modulate = color
	if _cat_icon != null:
		_cat_icon.modulate = color


## 取得应由动画修改的猫代理节点，无代理时退回原节点。
func _cat_xform_target() -> Node2D:
	return _cat_proxy if _cat_proxy != null else _cat_icon


## 修改猫代理的缩放，让集中层中的骨骼跟随。
func _set_cat_scale(scale_value: Vector2) -> void:
	var target := _cat_xform_target()
	if target != null:
		target.scale = scale_value


## 格子销毁前解除骨骼与绘制回调的绑定。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		release_cat_spine()


## 判断当前格子是否持有有效猫骨骼实例。
func has_cat_spine() -> bool:
	return _cat_spine != null and is_instance_valid(_cat_spine)


## 断开绘制前同步，清除待播请求并把骨骼交还棋盘池；无池时延迟释放。
func release_cat_spine() -> void:
	if _frame_pre_draw_cb.is_valid():
		if RenderingServer.frame_pre_draw.is_connected(_frame_pre_draw_cb):
			RenderingServer.frame_pre_draw.disconnect(_frame_pre_draw_cb)
		_frame_pre_draw_cb = Callable()

	_wake_cat_settle()
	var spine: SpineSprite = _cat_spine
	_cat_spine = null

	_pending_spine_dirty = false
	if spine == null or not is_instance_valid(spine):
		return
	var host := get_parent()
	if host != null and host.has_method("recycle_cat_spine"):
		host.call("recycle_cat_spine", spine)
	else:
		spine.queue_free()


## 把 AnimationPlayer 的片段名映射到 Spine 动画名，未知映射直接忽略。
func _drive_cat_spine(clip: String, seek_end: bool = false) -> void:
	var spine_clip: String = str(_CAT_SPINE_CLIP_BY_ANIM.get(clip, ""))
	if spine_clip.is_empty():
		return
	_request_cat_spine(spine_clip, clip in _CAT_SPINE_LOOP_ANIMS, seek_end)


## 优先播放存在的指定 Spine 片段，否则按默认动画映射。
func _drive_cat_spine_with_override(default_clip: String, spine_override: String) -> void:
	if spine_override != "" and _has_cat_spine_clip(spine_override):
		_request_cat_spine(spine_override, false, false)
		return
	_drive_cat_spine(default_clip)


## 请求骨骼回到非循环 idle。
func _reset_cat_spine_idle() -> void:
	_request_cat_spine("idle", false, false)


## 记录最新待播片段；已有骨骼时立即执行，落猫且可见时尝试创建骨骼。
func _request_cat_spine(spine_clip: String, loop: bool, seek_end: bool) -> void:
	_pending_spine_clip = spine_clip
	_pending_spine_loop = loop
	_pending_spine_seek_end = seek_end
	_pending_spine_dirty = true
	if _cat_spine != null and is_instance_valid(_cat_spine):
		_flush_pending_cat_spine()
	elif _state == CellState.CAT and is_visible_in_tree():
		_ensure_cat_spine()


## 消费待播请求，并把片段、循环和跳到末帧选项传给实际播放器。
func _flush_pending_cat_spine() -> void:
	if not _pending_spine_dirty:
		return
	_pending_spine_dirty = false
	_apply_cat_spine_now(_pending_spine_clip, _pending_spine_loop, _pending_spine_seek_end)


## 校验片段与播放器，唤醒静止骨骼后设置动画，可直接定位到末帧。
func _apply_cat_spine_now(spine_clip: String, loop: bool, seek_end: bool) -> void:
	var spine := _cat_spine
	if spine == null or not is_instance_valid(spine):
		return
	if not _has_cat_spine_clip(spine_clip):
		return
	var state: SpineAnimationState = spine.get_animation_state()
	if state == null:
		return

	_wake_cat_settle()
	var entry: SpineTrackEntry = state.set_animation(spine_clip, loop, 0)
	if seek_end and entry != null:
		entry.set_track_time(entry.get_animation_end())


## 从共享骨骼资源查找片段是否存在，并按名称缓存结果。
static func _has_cat_spine_clip(spine_clip: String) -> bool:
	if _cat_spine_clip_exists.has(spine_clip):
		return bool(_cat_spine_clip_exists[spine_clip])
	var data: SpineSkeletonDataResource = CostumeSkin.SKELETON_RES
	var exists: bool = data != null and data.find_animation(spine_clip) != null
	_cat_spine_clip_exists[spine_clip] = exists
	return exists


var _cat_costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID


## 保存装扮编号；骨骼已经创建时立即应用皮肤。
func set_cat_costume(costume_id: int) -> void:
	_cat_costume_id = costume_id
	if _cat_spine == null or not is_instance_valid(_cat_spine):
		return
	CostumeSkin.apply(_cat_spine, costume_id)


## 停止提示补间与闲置计时，执行 RESET，并清空草稿、淡化、爆破和本局追踪状态。
## 棋盘复用格子时依靠这里清除上一题的视觉残留。
func _reset_to_empty_baseline() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = null
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = null
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_tween = null

	_wake_cat_settle()

	reset_grid_blast()
	if _idle_timer != null:
		_idle_timer.stop()

	_state = CellState.EMPTY
	_anim.stop()
	_anim.play("RESET")
	_anim.advance(0.0)
	_reset_cat_spine_idle()
	if _mouse != null:
		_mouse.visible = false

	reset_collect_glow()

	_glow.visible = false
	_glow2.visible = false

	if ABTestManager.levelwin_anim.is_enlarged():
		if _win_scale_tween != null and _win_scale_tween.is_valid():
			_win_scale_tween.kill()
		_set_cat_scale(_CAT_ICON_BASE_SCALE)

	_cross.visible = false
	_hint_light.visible = false
	_prompt_frame.visible = false
	_prompt_frame.modulate.a = 1.0
	_cat_prompt.modulate = Color.WHITE
	_cat_prompt.scale = Vector2.ONE
	_bg.modulate.a = 1.0

	_kill_dim_tween()
	_dim_alpha = 1.0
	_dim_target_alpha = 1.0
	_apply_dim_visuals()

	_apply_draft_visual(CellState.EMPTY)

	_cat_cry_loop = false

	_custom_appear_clip = ""
	reset_clap_tracking()

	$Glows.visible = false

	if not debug_gold_flash_bug:
		_clear_cat_glow_particles()


## 停止并重启猫光粒子后再次关闭发射，清掉仍存活的旧粒子。
func _clear_cat_glow_particles() -> void:
	var cat_glow: CPUParticles2D = get_node_or_null("Glows/CatGlow") as CPUParticles2D
	if cat_glow == null:
		return
	cat_glow.emitting = false
	cat_glow.restart()
	cat_glow.emitting = false


## 按网格模式启停背景缩放轨道；单线模式关闭弹跳并恢复单位缩放。
func _apply_bounce_for_anim(anim_name: String) -> void:
	if ABTestManager == null or ABTestManager.game_grid_ui == null:
		return
	var anim: Animation = _anim.get_animation(anim_name)
	if anim == null:
		return
	var enabled: bool = not ABTestManager.game_grid_ui.is_single_line()
	for i in anim.get_track_count():
		var track_path := str(anim.track_get_path(i))
		if (
			track_path != "BgPanel:scale"
			and track_path != "BgPanel:scale:x"
			and track_path != "BgPanel:scale:y"
		):
			continue

		if anim.track_is_enabled(i) == enabled:
			continue
		anim.track_set_enabled(i, enabled)
	if not enabled:
		$BgPanel.scale = Vector2.ONE


## 递归把所有子 Control 设成不吃鼠标，点击统一由棋盘处理
func _set_children_mouse_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_ignore(child)


## 给底面四角设置相同半径，并沿用当前软硬边选项。
func set_corner_radius(rad: int) -> void:
	if _bg == null:
		return
	_bg.set_corner_radii(Vector4(rad, rad, rad, rad), _use_hard_bg)


## 按四角掩码选择普通或外框半径，同时更新底面与错误红底的圆角。
func _apply_corner_radius(base_rad: int, outer_rad: int) -> void:
	if _bg == null:
		return
	var c_tl: int = outer_rad if (_round_corners_mask & CORNER_TL) else base_rad
	var c_tr: int = outer_rad if (_round_corners_mask & CORNER_TR) else base_rad
	var c_br: int = outer_rad if (_round_corners_mask & CORNER_BR) else base_rad
	var c_bl: int = outer_rad if (_round_corners_mask & CORNER_BL) else base_rad
	_bg.set_corner_radii(Vector4(c_tl, c_tr, c_br, c_bl), _use_hard_bg)

	if _red_rect != null:
		var sb := _red_rect.get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null:
			sb.corner_radius_top_left = c_tl
			sb.corner_radius_top_right = c_tr
			sb.corner_radius_bottom_right = c_br
			sb.corner_radius_bottom_left = c_bl


## 把参考圆角半径换算为当前底面尺寸中的实际半径。
func get_face_render_radii() -> Vector4:
	if _bg == null:
		return Vector4.ZERO
	return _bg.get_corner_radii() * (_bg.size.x / CellFace.RADIUS_REFERENCE_PX)


## 保存棋盘外角掩码，并重新计算补偿后的圆角。
func set_round_corners(mask: int) -> void:
	_round_corners_mask = mask
	set_corner_radius_compensated(_last_container_scale, _last_board_size)


## 按棋盘缩放与布局实验推导内外圆角，让不同棋盘尺寸保持预期外观。
func set_corner_radius_compensated(container_scale: float, board_size: int = 0) -> void:
	if _bg == null or container_scale <= 0.0:
		return
	_last_container_scale = container_scale
	_last_board_size = board_size
	var rad: int = maxi(1, int(round(DESIGN_CORNER_VISUAL_PX / container_scale)))
	var outer_visual_px: float = DESIGN_OUTER_CORNER_VISUAL_PX
	if not Engine.is_editor_hint() and ABTestManager != null and ABTestManager.game_grid_ui != null:
		var cfg := ABTestManager.game_grid_ui
		if cfg.is_different_corners():
			rad = cfg.get_difference_size_cell_corners(board_size)
		elif cfg.is_single_line() or cfg.is_reduce_spacing():
			rad = 0

		outer_visual_px = float(
			cfg.get_board_layout().get("bg_corner", DESIGN_OUTER_CORNER_VISUAL_PX)
		)
	var outer_rad: int = maxi(1, int(round(outer_visual_px / container_scale)))
	_apply_corner_radius(rad, outer_rad)


## 保存区域底色并立即刷新底面。
func set_region_color(color: Color) -> void:
	_region_color = color
	_update_bg()


## 读回当前区域底色
func get_region_color() -> Color:
	return _region_color


## 按档位懒建爆破效果，用区域色着色并重新发射该档粒子。
func play_grid_blast(tier: int) -> void:
	if tier < 1 or tier > _BLAST_SCENES.size():
		return
	if not _blast_fx_by_tier.has(tier) and not _build_blast_fx(tier):
		return
	var fx: Control = _blast_fx_by_tier[tier] as Control

	fx.modulate = get_region_color()

	fx.visible = true
	var emitters: Array = _blast_emitters_by_tier[tier]
	for emitter: CPUParticles2D in emitters:
		emitter.restart()

		emitter.emitting = true


## 实例化对应爆破场景，放在猫下方并缓存所有粒子发射器。
func _build_blast_fx(tier: int) -> bool:
	var fx: Control = _BLAST_SCENES[tier - 1].instantiate() as Control
	if fx == null:
		push_error("CellView: grid_blast fx instantiate failed, tier=%d" % tier)
		return false

	fx.position = Vector2(CELL_FACE_NATIVE_PX, CELL_FACE_NATIVE_PX) * 0.5

	fx.z_index = _blast_fx_z_index()

	fx.visible = false
	add_child(fx)

	var emitters: Array[CPUParticles2D] = []
	var found: Array[Node] = fx.find_children("*", "CPUParticles2D", true, false)
	for node: Node in found:
		var emitter: CPUParticles2D = node as CPUParticles2D
		if emitter == null:
			continue
		emitter.position = Vector2.ZERO
		emitter.emitting = false
		emitters.append(emitter)
	_blast_fx_by_tier[tier] = fx
	_blast_emitters_by_tier[tier] = emitters
	return true


## 参考真实骨骼所在层计算爆破层级，使爆破位于猫下面。
func _blast_fx_z_index() -> int:
	var cat_layer_z: int = -1
	if _cat_spine != null and is_instance_valid(_cat_spine):
		var holder: CanvasItem = _cat_spine.get_parent() as CanvasItem
		if holder != null and holder != self:
			cat_layer_z = holder.z_index + _cat_spine.z_index
	if cat_layer_z < 0 and _cat_icon != null:
		cat_layer_z = _cat_icon.z_index

	if cat_layer_z < 0:
		return 2
	return cat_layer_z - 1


## 隐藏已创建的全部爆破效果并停止发射，保留节点供后续复用。
func reset_grid_blast() -> void:
	for tier: int in _blast_fx_by_tier:
		var fx: Control = _blast_fx_by_tier[tier] as Control
		fx.visible = false
		var emitters: Array = _blast_emitters_by_tier[tier]
		for emitter: CPUParticles2D in emitters:
			emitter.emitting = false


## 将区域淡化目标限制在 0～1，取消旧过渡后立即应用或启动短补间。
func set_dim_alpha(alpha: float, animated: bool = false) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	if is_equal_approx(_dim_target_alpha, alpha):
		return
	_dim_target_alpha = alpha
	_kill_dim_tween()
	if not animated or Engine.is_editor_hint() or not is_inside_tree():
		_dim_alpha = alpha
		_apply_dim_visuals()
		return
	_dim_tween = create_tween()
	_dim_tween.tween_method(_apply_dim_alpha_frame, _dim_alpha, alpha, _DIM_TWEEN_SEC).set_trans(
		Tween.TRANS_LINEAR
	)


## 接收补间值并同步更新底色、图案和错标颜色。
func _apply_dim_alpha_frame(a: float) -> void:
	_dim_alpha = a
	_apply_dim_visuals()


## 统一刷新受区域淡化影响的三类视觉元素。
func _apply_dim_visuals() -> void:
	_update_bg()
	_update_pattern_color()
	_update_red_cross_dim()


## 区域淡化时把红叉逐渐混向白色，保持标记可见。
func _update_red_cross_dim() -> void:
	var shown: Color = _RED_CROSS_BASE_COLOR.lerp(_RED_CROSS_DIM_TARGET, 1.0 - _dim_alpha)
	if _red_cross_np1 != null:
		_red_cross_np1.modulate = shown
	if _red_cross_np2 != null:
		_red_cross_np2.modulate = shown


## 停止正在进行的区域淡化补间并清空引用。
func _kill_dim_tween() -> void:
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = null


const CELL_FACE_NATIVE_PX: float = 100.0


## 调整底面与错误红底的尺寸，使它们围绕原始 100 像素格子居中。
func apply_cell_face_px(px: float) -> void:
	if _bg != null:
		var half: float = px * 0.5
		_bg.offset_left = -half
		_bg.offset_top = -half
		_bg.offset_right = half
		_bg.offset_bottom = half

	var red_root: Control = _bg_red_root()
	if red_root != null:
		var inset: float = (CELL_FACE_NATIVE_PX - px) * 0.5
		red_root.offset_left = inset
		red_root.offset_top = inset
		red_root.offset_right = inset + px
		red_root.offset_bottom = inset + px
	if _red_rect != null:
		_red_rect.offset_left = 0.0
		_red_rect.offset_top = 0.0
		_red_rect.offset_right = px
		_red_rect.offset_bottom = px


## 按场景路径取得错误红底容器。
func _bg_red_root() -> Control:
	return get_node_or_null("BgPanel/BgRed") as Control


## 保存区域图案与基础颜色，并立即更新颜色和可见性。
func configure_pattern(texture: Texture2D, color: Color) -> void:
	_pattern_tex = texture
	_pattern_base_color = color
	_update_pattern_color()
	_refresh_pattern_visibility()


## 保持图案 RGB，把基础透明度乘上当前区域淡化值。
func _update_pattern_color() -> void:
	if _bg != null:
		_bg.set_pattern_color(
			Color(
				_pattern_base_color.r,
				_pattern_base_color.g,
				_pattern_base_color.b,
				_pattern_base_color.a * _dim_alpha
			)
		)


## 设置图案开关与已填格保留规则，然后更新底面显示。
func set_pattern_mode(on: bool, keep_on_filled: bool) -> void:
	_pattern_on = on
	_pattern_keep = keep_on_filled
	_refresh_pattern_visibility()


## 返回配置的图案纹理。
func get_pattern_tex() -> Texture2D:
	return _pattern_tex


## 返回尚未乘区域淡化值的图案基础色。
func get_pattern_color() -> Color:
	return _pattern_base_color


## 返回图案模式开关；是否实际绘制还取决于纹理与格子状态。
func is_pattern_on() -> bool:
	return _pattern_on


## 空格可显示图案，已填格只有启用保留选项时才继续显示。
func _refresh_pattern_visibility() -> void:
	if _bg == null:
		return
	var show_it: bool = (
		_pattern_on and _pattern_tex != null and (_state == CellState.EMPTY or _pattern_keep)
	)
	_bg.set_pattern(_pattern_tex, show_it)


## 更新格子的逻辑状态并驱动草稿、叉、错标或猫的视觉；相同状态和锁定叉会直接返回。
## 同时维护打叉/出错历史、双击宽容窗口及音效；CAT 状态可先成立而暂不揭示猫。
func change_state(params: Dictionary) -> void:
	var state: int = params.get("state", _state)
	var is_play_anim: bool = params.get("play_anim", true)
	var show_cat_visual: bool = params.get("show_cat_visual", true)

	var appear_anim: String = params.get("appear_anim", "")

	var disappear_anim: String = params.get("disappear_anim", "")

	var cat_spine_anim: String = params.get("cat_spine_anim", "")

	var play_sound_with_custom_anim: bool = params.get("play_sound_with_custom_anim", false)

	var apply_eliminate_effect: bool = params.get("apply_eliminate_effect", true)
	if _state == state:
		return

	if _state == CellState.LOCKED_MARK:
		return
	var prev_state := _state
	_cat_visual_revealed = state == CellState.CAT and show_cat_visual

	if CellState.is_draft(state) or (CellState.is_draft(prev_state) and state == CellState.EMPTY):
		_state = state
		_apply_draft_visual(state)
		_refresh_pattern_visibility()
		return

	if CellState.is_draft(prev_state):
		_apply_draft_visual(CellState.EMPTY)
	_state = state
	_refresh_pattern_visibility()

	if state == CellState.MARK:
		_mark_entered_time_ms = Time.get_ticks_msec()
		_ever_marked_x_snapshot = _ever_marked_x
		_ever_marked_x = true
	else:
		if prev_state == CellState.MARK and _mark_entered_time_ms >= 0:
			if state == CellState.CAT:
				var mark_dur_ms: int = Time.get_ticks_msec() - _mark_entered_time_ms
				if mark_dur_ms < _DOUBLE_TAP_MARK_GRACE_MS:
					_ever_marked_x = _ever_marked_x_snapshot
			_mark_entered_time_ms = -1
		if state == CellState.ERROR:
			_ever_marked_x = true
			_ever_errored = true

	if (
		is_play_anim
		and not Engine.is_editor_hint()
		and (play_sound_with_custom_anim or (appear_anim == "" and disappear_anim == ""))
	):
		_emit_state_sound(prev_state, state)

	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
		_preview_tween = null

	_anim.stop()
	_anim.play("RESET")
	_anim.advance(0.0)
	if _mouse != null:
		_mouse.visible = false

	if state == CellState.CAT:
		_ensure_cat_spine()
		_cat_cry_loop = false
		_cross.visible = false
		if not show_cat_visual:
			_set_particles_visible(false)
			return
		_set_particles_visible(is_play_anim)
		if is_play_anim:
			var cat_anim: String = appear_anim if appear_anim != "" else "CatIconAppear"
			if not _anim.has_animation(cat_anim):
				cat_anim = "CatIconAppear"

			_custom_appear_clip = cat_anim if cat_anim != "CatIconAppear" else ""
			_apply_bounce_for_anim(cat_anim)
			_anim.play(cat_anim)
			_drive_cat_spine_with_override(cat_anim, cat_spine_anim)

			if _cat_icon != null and not _anim_fades_cat_icon(cat_anim):
				_cat_icon.modulate = Color(1, 1, 1, 1)
		else:
			_anim.play("CatIconIdle")

			_anim.advance(_anim.current_animation_length)
			_drive_cat_spine("CatIconIdle", true)

			_set_cat_modulate(Color(1, 1, 1, 1))

		if not _idle_frozen:
			_idle_timer.start()
		return

	_idle_timer.stop()
	_cat_cry_loop = false

	var anim_name := _get_anim_name(prev_state, state)

	if appear_anim != "":
		anim_name = appear_anim

	if disappear_anim != "" and prev_state == CellState.MARK and state == CellState.EMPTY:
		anim_name = disappear_anim

	if appear_anim == "":
		anim_name = _map_eliminate_effect_anim(anim_name, apply_eliminate_effect)

	_cross.visible = (
		anim_name == "CrossOutDisAppear" or String(anim_name).begins_with("CrossOutAppear")
	)

	if anim_name == "":
		return

	_apply_bounce_for_anim(anim_name)
	_apply_fulfill_cross_stroke_track_override(anim_name)
	_anim.play(anim_name)
	_anim.advance(0.0)

	if _needs_fulfill_stroke_geometry_code(anim_name):
		_apply_fulfill_cross_stroke_geometry()
	if not is_play_anim:
		_anim.advance(_anim.current_animation_length)

		if _needs_fulfill_stroke_geometry_code(anim_name):
			_apply_fulfill_cross_stroke_layout()


## 读当前状态（BoardView.get_board() / get_cell_state() 都走这里）
func get_state() -> int:
	return _state


## 逻辑状态为猫且揭示标志开启时返回真。
func is_cat_visual_revealed() -> bool:
	return _state == CellState.CAT and _cat_visual_revealed


## 清空「打过叉 / 出过错」追踪（BoardView 建格与复用时调用）
func reset_clap_tracking() -> void:
	_ever_marked_x = false
	_ever_errored = false
	_mark_entered_time_ms = -1
	_ever_marked_x_snapshot = false


## 本局是否打过分叉（BoardView 按区域聚合后喂给 R4+ 鼓掌提示）
func has_ever_marked_x() -> bool:
	return _ever_marked_x


## 本局是否出过错标（同上，按区域聚合）
func has_ever_errored() -> bool:
	return _ever_errored


## 按前后状态选择落猫、错标、打叉或撤叉音效。
func _emit_state_sound(prev_state: int, state: int) -> void:
	if state == CellState.CAT:
		SoundManager.play(SoundManager.Kind.MARK_CAT)
	elif state == CellState.ERROR:
		SoundManager.play(SoundManager.Kind.MARK_WRONG)
	elif state == CellState.MARK and prev_state == CellState.EMPTY:
		SoundManager.play(SoundManager.Kind.MARK_X)
	elif state == CellState.EMPTY and prev_state == CellState.MARK:
		SoundManager.play(SoundManager.Kind.UNMARK_X)


## 鼠标动画落下且当前仍是叉时，补发打叉音效与震动。
func _on_mouse_mark_landed() -> void:
	if _state != CellState.MARK:
		return
	_emit_state_sound(CellState.EMPTY, CellState.MARK)
	VibrateManager.play_at(VibrateManager.Pos.CELL_MARK)


## 由鼠标动画事件请求猫播放 anger2 反应。
func _on_mouse_appear3_anger() -> void:
	_request_cat_spine("anger2", false, false)


## 把普通状态切换映射为叉出现、叉消失或错误出现片段。
func _get_anim_name(prev: int, target: int) -> String:
	match target:
		CellState.EMPTY:
			return "CrossOutDisAppear" if prev == CellState.MARK else ""
		CellState.MARK:
			return "CrossOutAppear"
		CellState.ERROR:
			return "ErrorAppear"
		_:
			return ""


## 根据消除效果实验选择动画后缀；没有对应片段时保留原动画。
func _map_eliminate_effect_anim(anim_name: String, apply_effect: bool) -> StringName:
	if not apply_effect or anim_name.is_empty():
		return anim_name
	if Engine.is_editor_hint() or ABTestManager == null or ABTestManager.eliminate_effect == null:
		return anim_name
	var cfg: EliminateEffectConfig = ABTestManager.eliminate_effect
	if not cfg.is_experiment_group():
		return anim_name
	var suffix: String = ""
	if cfg.is_cell_squeeze() and cfg.is_cross_big():
		suffix = "_G6"
	elif cfg.is_cell_squeeze():
		suffix = "_G3"
	elif cfg.is_cross_big():
		suffix = "_G4"
	elif cfg.use_new_art():
		suffix = "_G5"
	else:
		return anim_name
	const _MAPPABLE_BASES: Array[String] = [
		"CrossOutAppear",
		"CrossOutAppear_2",
		"ErrorAppear",
	]
	if anim_name not in _MAPPABLE_BASES:
		return anim_name
	var mapped: String = anim_name + suffix
	if _anim.has_animation(mapped):
		return mapped
	return anim_name


## 判断片段是否属于普通叉或错误叉的出现动画族。
func _is_cross_stroke_anim(anim_name: StringName) -> bool:
	var s := String(anim_name)
	return s.begins_with("CrossOutAppear") or s.begins_with("ErrorAppear")


const _MOUSE_MARK_ANIMS: Array[StringName] = [&"MouseAppear1", &"MouseAppear2", &"MouseAppear3"]
const _AUTO_X_FILL_STROKE_ANIM: StringName = &"AutoXFillMode2"

const _FULFILL_STROKE_TRACK_RESTORE_CLIPS: Array[StringName] = [
	&"CrossOutDisAppear",
	&"CrossOutAppear",
	&"CrossOutAppear_2",
	&"ErrorAppear",
	_AUTO_X_FILL_STROKE_ANIM,
	&"MouseAppear1",
	&"MouseAppear2",
	&"MouseAppear3",
	_WIN_RED_MARK_TO_WHITE_ANIM,
]


## 识别需要代码接管新叉几何的片段，排除已自带新几何的 G5/G6 变体。
func _is_fulfill_stroke_geometry_clip(anim_name: StringName) -> bool:
	if _is_fulfill_cross_stroke_variant_clip(anim_name):
		return false
	var s := String(anim_name)
	if s.begins_with("CrossOutAppear") or s.begins_with("ErrorAppear"):
		return true
	if s == "CrossOutDisAppear":
		return true
	if s == String(_AUTO_X_FILL_STROKE_ANIM):
		return true
	if s == String(_WIN_RED_MARK_TO_WHITE_ANIM):
		return true
	return anim_name in _MOUSE_MARK_ANIMS


## 只有启用新叉贴图且当前片段需要接管时才返回真。
func _needs_fulfill_stroke_geometry_code(anim_name: StringName) -> bool:
	return _use_fulfill_cross_art() and _is_fulfill_stroke_geometry_clip(anim_name)


## 确定动画结束后是否需要重新固定新叉的静态布局。
func _should_apply_fulfill_layout_on_anim_finished(anim_name: StringName) -> bool:
	if not _use_fulfill_cross_art():
		return false
	if _is_cross_stroke_anim(anim_name):
		return true
	if anim_name == _AUTO_X_FILL_STROKE_ANIM:
		return true
	return anim_name == &"MouseAppear1" or anim_name == &"MouseAppear2"


## 读取消除效果实验是否使用新叉贴图，编辑器默认关闭。
func _use_fulfill_cross_art() -> bool:
	if Engine.is_editor_hint() or ABTestManager == null or ABTestManager.eliminate_effect == null:
		return false
	return ABTestManager.eliminate_effect.use_new_art()


## 按后缀识别自带新叉布局的 G5/G6 动画。
func _is_fulfill_cross_stroke_variant_clip(anim_name: StringName) -> bool:
	var s := String(anim_name)
	return s.ends_with("_G5") or s.ends_with("_G6")


## 只识别普通叉与红叉笔画的位置、尺寸轨道，保留透明度等其他动画轨。
func _is_fulfill_stroke_geometry_track(track_path: String) -> bool:
	const _PREFIXES: Array[String] = [
		"Crosses/CrossOut/NinePatchRect2:",
		"Crosses/CrossOut/NinePatchRect:",
		"Crosses/RedCross/NinePatchRect2:",
		"Crosses/RedCross/NinePatchRect:",
	]
	for prefix in _PREFIXES:
		if track_path.begins_with(prefix):
			var prop := track_path.substr(prefix.length())

			return prop.begins_with("size:") or prop.begins_with("position:") or prop == "size"
	return false


## 切换叉几何轨道开关，避免动画轨与代码布局同时写位置和尺寸。
func _apply_fulfill_cross_stroke_track_override(anim_name: StringName) -> void:
	if not _is_fulfill_stroke_geometry_clip(anim_name):
		return
	var anim: Animation = _anim.get_animation(anim_name)
	if anim == null:
		return
	var want_enabled: bool = not _needs_fulfill_stroke_geometry_code(anim_name)
	for i in anim.get_track_count():
		var track_path := str(anim.track_get_path(i))
		if not _is_fulfill_stroke_geometry_track(track_path):
			continue

		if anim.track_is_enabled(i) == want_enabled:
			continue
		anim.track_set_enabled(i, want_enabled)


## 将普通叉和红叉的两条笔画同步到新贴图要求的位置与尺寸。
func _apply_fulfill_cross_stroke_geometry() -> void:
	if _cross_np1 == null:
		return
	_cross_np1.position = _FULFILL_STROKE_NP1_POS
	_cross_np1.size = _FULFILL_STROKE_SIZE
	_cross_np2.position = _FULFILL_STROKE_NP2_POS
	_cross_np2.size = _FULFILL_STROKE_SIZE
	if _red_cross_np1 != null:
		_red_cross_np1.position = _FULFILL_STROKE_NP1_POS
		_red_cross_np1.size = _FULFILL_STROKE_SIZE
	if _red_cross_np2 != null:
		_red_cross_np2.position = _FULFILL_STROKE_NP2_POS
		_red_cross_np2.size = _FULFILL_STROKE_SIZE


## 应用新叉几何，并按当前 MARK 或 ERROR 状态恢复笔画可见性和缩放。
func _apply_fulfill_cross_stroke_layout() -> void:
	if _cross_np1 == null:
		return
	_apply_fulfill_cross_stroke_geometry()
	if _state == CellState.MARK:
		_cross.visible = true
		_cross.scale = Vector2.ONE
		_cross_np1.visible = true
		_cross_np2.visible = true
	elif _state == CellState.ERROR:
		var red_cross := (
			_red_cross_np1.get_parent() as CanvasItem if _red_cross_np1 != null else null
		)
		if red_cross != null:
			red_cross.visible = true
			red_cross.scale = Vector2.ONE
		if _red_cross_np1 != null:
			_red_cross_np1.visible = true
		if _red_cross_np2 != null:
			_red_cross_np2.visible = true


## 用 RESET 恢复旧叉布局，再按当前状态重新显示普通叉或红叉。
func _apply_control_cross_stroke_layout_via_reset() -> void:
	if _anim == null or not _anim.has_animation(&"RESET"):
		return
	_anim.play(&"RESET")
	_anim.advance(0.0)
	if _state == CellState.MARK:
		_cross.scale = Vector2.ONE
		_cross.visible = true
		_cross_np1.visible = true
		_cross_np2.visible = true
	elif _state == CellState.ERROR:
		_cross.visible = false
		var red_cross := (
			_red_cross_np1.get_parent() as CanvasItem if _red_cross_np1 != null else null
		)
		if red_cross != null:
			red_cross.visible = true
			red_cross.scale = Vector2.ONE
		if _red_cross_np1 != null:
			_red_cross_np1.visible = true
		if _red_cross_np2 != null:
			_red_cross_np2.visible = true


## 切换正式叉、草稿叉与自动叉的贴图和裁切区域，并按当前状态恢复布局。
## 可选择是否同步修改共享动画资源中的笔画轨道。
func apply_cross_art_variant(apply_shared_stroke_tracks: bool = true) -> void:
	if _cross_np1 == null:
		return
	var use_fulfill: bool = false
	if (
		not Engine.is_editor_hint()
		and ABTestManager != null
		and ABTestManager.eliminate_effect != null
	):
		use_fulfill = ABTestManager.eliminate_effect.use_new_art()
	var stroke_tex: Texture2D = (
		_cross_stroke_tex_fulfill if use_fulfill else _cross_stroke_tex_control
	)
	var draft_tex: Texture2D = _draft_cross_tex_fulfill if use_fulfill else _draft_cross_tex_control
	var auto_x_tex: Texture2D = (
		_auto_x_fill_tex_fulfill if use_fulfill else _auto_x_fill_tex_control
	)
	if stroke_tex != null:
		if not _stroke_region_captured:
			_stroke_region_baseline = _cross_np1.region_rect
			_stroke_region_captured = true
		_cross_np1.texture = stroke_tex
		_cross_np2.texture = stroke_tex
		if _red_cross_np1 != null:
			_red_cross_np1.texture = stroke_tex
		if _red_cross_np2 != null:
			_red_cross_np2.texture = stroke_tex

		var stroke_region: Rect2
		if use_fulfill:
			stroke_region = Rect2(Vector2.ZERO, stroke_tex.get_size())
		else:
			stroke_region = _stroke_region_baseline
		_cross_np1.region_rect = stroke_region
		_cross_np2.region_rect = stroke_region
		if _red_cross_np1 != null:
			_red_cross_np1.region_rect = stroke_region
		if _red_cross_np2 != null:
			_red_cross_np2.region_rect = stroke_region
	if draft_tex != null and _draft_cross_sprite != null:
		_draft_cross_sprite.texture = draft_tex
	if auto_x_tex != null and _auto_x_fill_cross_sprite != null:
		_auto_x_fill_cross_sprite.texture = auto_x_tex
	if _state == CellState.MARK or _state == CellState.ERROR:
		if use_fulfill:
			_apply_fulfill_cross_stroke_layout()
		else:
			_apply_control_cross_stroke_layout_via_reset()
	if apply_shared_stroke_tracks:
		apply_shared_cross_stroke_track_override()


## 批量更新会恢复叉几何的共享动画轨道，棋盘建格后可统一执行一次。
func apply_shared_cross_stroke_track_override() -> void:
	if _anim == null:
		return
	for clip in _FULFILL_STROKE_TRACK_RESTORE_CLIPS:
		_apply_fulfill_cross_stroke_track_override(clip)


## 只揭示已经处于 CAT 状态的格子，重播出现效果并可追加粒子与延迟光晕。
func reveal_hidden_cat(
	appear_anim: String = "CatIconAppear",
	with_particles: bool = false,
	with_halo: bool = false,
) -> void:
	if _state != CellState.CAT:
		return
	_cat_visual_revealed = true
	_cat_cry_loop = false
	_cross.visible = false
	_set_particles_visible(with_particles)
	_idle_timer.stop()
	_anim.stop()
	_anim.play("RESET")
	_anim.advance(0.0)
	var anim_name: String = appear_anim if appear_anim != "" else "CatIconAppear"
	_apply_bounce_for_anim(anim_name)
	_anim.play(anim_name)

	_anim.advance(0.0)

	_drive_cat_spine(anim_name)

	if _cat_icon != null and not _anim_fades_cat_icon(anim_name):
		_set_cat_modulate(Color(1, 1, 1, 1))
	_idle_timer.start()
	if with_halo:
		var delay_tw: Tween = create_tween()
		delay_tw.tween_interval(_HALO_PULSE_DELAY)
		delay_tw.tween_callback(_play_halo_pulse)


## 检查片段是否写入 CatIcon 的颜色轨道，避免代码覆盖它控制的淡入。
func _anim_fades_cat_icon(anim_name: String) -> bool:
	var a: Animation = _anim.get_animation(anim_name)
	if a == null:
		return false
	for i in a.get_track_count():
		if a.track_get_path(i) == NodePath("CatIcon:modulate"):
			return true
	return false


const _HALO_PULSE_DELAY: float = 0.05

var _halo_tween: Tween = null


## 设置猫爪方向并播放预填猫动画。
func play_pre_cat_paw(flip: bool = false) -> void:
	var paw: TextureRect = get_node_or_null("BgPanel/Paw") as TextureRect
	if paw != null:
		paw.flip_h = flip
	_anim.play("PreCat")


## 停止旧光晕补间，显示 Glow4 并同步放大、淡出，结束后复位。
func _play_halo_pulse() -> void:
	var glows: CanvasItem = get_node_or_null("Glows") as CanvasItem
	if _glow4 == null or not is_instance_valid(_glow4) or glows == null:
		return
	if _halo_tween != null and _halo_tween.is_valid():
		_halo_tween.kill()
	glows.visible = true

	if _glow != null and is_instance_valid(_glow):
		_glow.visible = false
	if _glow2 != null and is_instance_valid(_glow2):
		_glow2.visible = false
	_glow4.visible = true
	_glow4.scale = _HALO_SCALE_FROM
	_glow4.modulate = Color(1, 1, 1, 1)
	_halo_tween = _glow4.create_tween()
	_halo_tween.set_parallel(true)
	(
		_halo_tween
		. tween_property(_glow4, "scale", _HALO_SCALE_TO, _HALO_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_halo_tween
		. tween_property(_glow4, "modulate:a", 0.0, _HALO_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_halo_tween.chain().tween_callback(_restore_halo)


const _HALO_SCALE_FROM: Vector2 = Vector2(0.5, 0.5)
const _HALO_SCALE_TO: Vector2 = Vector2(3.75, 3.75)
const _HALO_DURATION: float = 0.5


## 隐藏光晕并恢复初始尺度和颜色，供下一次播放复用。
func _restore_halo() -> void:
	if _glow4 != null and is_instance_valid(_glow4):
		_glow4.visible = false
		_glow4.scale = _HALO_SCALE_FROM
		_glow4.modulate = Color(1, 1, 1, 1)
	var glows: CanvasItem = get_node_or_null("Glows") as CanvasItem
	if glows != null:
		glows.visible = false


## 只有当前正在播放普通 Appear 时，才在后面追加濒危出现片段。
func play_near_death_appear() -> void:
	if _state != CellState.CAT or not _has_cat_spine_clip(NEAR_DEATH_APPEAR_SPINE):
		return
	_flush_pending_cat_spine()
	if _cat_spine == null or not is_instance_valid(_cat_spine):
		return
	var state: SpineAnimationState = _cat_spine.get_animation_state()
	if state == null:
		return
	var current: SpineTrackEntry = state.get_current(0)
	if current == null or current.get_animation().get_name() != "Appear":
		return

	state.add_animation(NEAR_DEATH_APPEAR_SPINE, 0.0, false, 0)


## 取得当前濒危出现轨道，当前播放其他片段时返回 null。
func _near_death_appear_entry() -> SpineTrackEntry:
	if _cat_spine == null or not is_instance_valid(_cat_spine):
		return null
	var state: SpineAnimationState = _cat_spine.get_animation_state()
	if state == null:
		return null
	var entry: SpineTrackEntry = state.get_current(0)
	if entry == null or entry.get_animation().get_name() != NEAR_DEATH_APPEAR_SPINE:
		return null
	return entry


## 计算濒危出现剩余时长；若仍在排队，还计入前一段普通出现的剩余时间。
func _near_death_appear_remaining() -> float:
	var entry: SpineTrackEntry = _near_death_appear_entry()
	if entry != null:
		return maxf(entry.get_animation_end() - entry.get_track_time(), 0.0)
	if _cat_spine == null or not is_instance_valid(_cat_spine):
		return 0.0
	var state: SpineAnimationState = _cat_spine.get_animation_state()
	if state == null:
		return 0.0
	var current: SpineTrackEntry = state.get_current(0)
	if current == null:
		return 0.0
	var queued: SpineTrackEntry = current.get_next()
	if queued == null or queued.get_animation().get_name() != NEAR_DEATH_APPEAR_SPINE:
		return 0.0
	var appear_left: float = maxf(current.get_animation_end() - current.get_track_time(), 0.0)
	return appear_left + queued.get_animation_end()


## 计时结束时仍为猫且仍处于濒危片段，才切回闲置。
func _on_near_death_appear_finished() -> void:
	if _state == CellState.CAT and _near_death_appear_entry() != null:
		_enter_cat_idle()


## 重播猫出现效果，并按通关动画实验叠加放大缩回；不修改逻辑格子状态。
func force_play_appear(
	with_particles: bool = true, appear_anim: String = "", cat_spine_anim: String = ""
) -> void:
	var clip: String = appear_anim if appear_anim != "" else "CatIconAppear"
	if not _anim.has_animation(clip):
		clip = "CatIconAppear"

	_custom_appear_clip = clip if clip != "CatIconAppear" else ""

	if ABTestManager.levelwin_anim.is_enlarged():
		_set_particles_visible(with_particles)
		_idle_timer.stop()
		_anim.stop()
		_anim.play("RESET")
		_anim.advance(0.0)
		_apply_bounce_for_anim(clip)
		_anim.play(clip)
		_drive_cat_spine_with_override(clip, cat_spine_anim)

		if _cat_icon != null and not _anim_fades_cat_icon(clip):
			_cat_icon.modulate = Color(1, 1, 1, 1)

		var cat_xform_node := _cat_xform_target()
		if cat_xform_node != null:
			if _win_scale_tween != null and _win_scale_tween.is_valid():
				_win_scale_tween.kill()
			cat_xform_node.scale = _CAT_ICON_BASE_SCALE
			_win_scale_tween = cat_xform_node.create_tween()

			(
				_win_scale_tween
				. tween_property(
					cat_xform_node,
					"scale",
					_CAT_ICON_BASE_SCALE * _WIN_ENLARGE_RATIO,
					_WIN_ENLARGE_DUR
				)
				. set_trans(Tween.TRANS_CUBIC)
				. set_ease(Tween.EASE_OUT)
			)
			_win_scale_tween.tween_interval(_WIN_SHRINK_AT - _WIN_ENLARGE_DUR)
			(
				_win_scale_tween
				. tween_property(cat_xform_node, "scale", _CAT_ICON_BASE_SCALE, _WIN_SHRINK_DUR)
				. set_trans(Tween.TRANS_CUBIC)
				. set_ease(Tween.EASE_OUT)
			)
		return

	_set_particles_visible(with_particles)
	_idle_timer.stop()
	_anim.stop()
	_anim.play("RESET")
	_anim.advance(0.0)
	_apply_bounce_for_anim(clip)
	_anim.play(clip)
	_drive_cat_spine_with_override(clip, cat_spine_anim)
	if _cat_icon != null and not _anim_fades_cat_icon(clip):
		_cat_icon.modulate = Color(1, 1, 1, 1)


## 对错误格播放通关红叉变白，必要时先接管新叉几何。
func play_win_error_mark_to_white() -> void:
	if _state != CellState.ERROR:
		return
	if not _anim.has_animation(_WIN_RED_MARK_TO_WHITE_ANIM):
		push_error("CellView: missing animation %s" % _WIN_RED_MARK_TO_WHITE_ANIM)
		return

	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_tween = null

	if _use_fulfill_cross_art():
		_apply_fulfill_cross_stroke_track_override(_WIN_RED_MARK_TO_WHITE_ANIM)
		_apply_fulfill_cross_stroke_geometry()

	_anim.play(_WIN_RED_MARK_TO_WHITE_ANIM)
	_anim.advance(0.0)


## 开关猫出现时的粒子特效节点；节点不存在时静默跳过
func _set_particles_visible(show: bool) -> void:
	var fx: Control = get_node_or_null("EffectCatIconAppear2")
	if fx != null:
		fx.visible = show


## 停止收集光效播放器并执行其 RESET。
func reset_collect_glow() -> void:
	if _collect_player != null and _collect_player.has_animation("RESET"):
		_collect_player.stop()
		_collect_player.play("RESET")
		_collect_player.advance(0.0)


## 猫进入哭泣循环前停止闲置计时，并让普通动画与骨骼同步播放。
func play_cry_loop() -> void:
	if _state != CellState.CAT or _cat_cry_loop:
		return
	_cat_cry_loop = true
	_idle_timer.stop()

	_set_cat_modulate(Color(1, 1, 1, 1))
	_anim.play("RESET")
	_anim.advance(0.0)
	_anim.play("CatIconCry")

	_drive_cat_spine("CatIconCry")


## 播放一次沮丧反应；哭泣循环中的猫保持原反应。
func play_frustrated_once() -> void:
	if _state != CellState.CAT or _cat_cry_loop:
		return

	_set_cat_modulate(Color(1, 1, 1, 1))
	_anim.play("RESET")
	_anim.advance(0.0)
	_anim.play("CatIconFrustrated")
	_drive_cat_spine("CatIconFrustrated")


## 在猫未哭泣、未冻结且没有高优先级反应时播放发现反馈，关闭出现粒子。
func play_found_blink(anim_name: String = "") -> void:
	if _state != CellState.CAT or _cat_cry_loop or _idle_frozen:
		return
	if _is_playing_high_priority_reaction():
		return
	var clip_name: String = anim_name if anim_name != "" else "CatIconAppear"
	if not _anim.has_animation(clip_name):
		return
	_idle_timer.stop()
	_anim.stop()
	_anim.play("RESET")
	_anim.advance(0.0)

	_set_particles_visible(false)
	_apply_bounce_for_anim(clip_name)
	_anim.play(clip_name)

	_drive_cat_spine(clip_name)

	if _cat_icon != null and not _anim_fades_cat_icon(clip_name):
		_cat_icon.modulate = Color(1, 1, 1, 1)
	_idle_timer.start()


## 结束哭泣，显示 idle 末帧并重启闲置计时。
func revive_to_idle() -> void:
	if _state != CellState.CAT:
		return
	_cat_cry_loop = false
	_anim.stop()
	_anim.play("CatIconIdle")

	_anim.advance(_anim.current_animation_length)
	_drive_cat_spine("CatIconIdle", true)
	_set_cat_modulate(Color(1, 1, 1, 1))
	_idle_timer.start()


## 在调试日志开启时输出非 RESET、非闲置动画的状态和时长。
func _on_anim_started(anim_name: StringName) -> void:
	if not _log_cell_anim_play or anim_name in _LOG_CELL_ANIM_SKIP:
		return
	var len_sec: float = (
		_anim.get_animation(anim_name).length if _anim.has_animation(anim_name) else -1.0
	)
	print(
		(
			"[cell_anim] %s state=%s play=%s len=%.3fs"
			% [name, CellState.name_of(_state), anim_name, len_sec]
		)
	)


## 补齐新叉静态布局，或把猫反应切回闲置；濒危出现排队时等待骨骼完成。
func _on_anim_finished(anim_name: StringName) -> void:
	if (
		(_state == CellState.MARK or _state == CellState.ERROR)
		and _should_apply_fulfill_layout_on_anim_finished(anim_name)
	):
		_apply_fulfill_cross_stroke_layout()
		return
	if _state != CellState.CAT:
		return
	if anim_name == "CatIconCry" and _cat_cry_loop:
		_anim.play("CatIconCry")
	elif (
		anim_name == "CatIconFrustrated"
		or anim_name == StringName(MisplaceReactionConfig.CONFLICT_REACTION_ANIM_NAME)
		or anim_name == StringName(MisplaceReactionConfig.TARGET_REACTION_ANIM_NAME)
	):
		_enter_cat_idle()
	elif anim_name == "CatIconAppear":
		var near_death_remaining: float = _near_death_appear_remaining()
		if near_death_remaining > 0.0:
			get_tree().create_timer(near_death_remaining, false).timeout.connect(
				_on_near_death_appear_finished
			)
		else:
			_enter_cat_idle()
	elif anim_name == "MouseAppear3":
		_enter_cat_idle()
	elif anim_name == "CatIconGreet":
		_enter_cat_idle()
	elif _custom_appear_clip != "" and anim_name == StringName(_custom_appear_clip):
		_custom_appear_clip = ""
		_enter_cat_idle()


var _idle_frozen: bool = false


## 停止周期闲置播放，并让猫停在 idle 末帧。
func freeze_cat_idle() -> void:
	_idle_frozen = true
	if _idle_timer != null:
		_idle_timer.stop()
	if _state == CellState.CAT:
		_enter_cat_idle()


## 解除闲置冻结，对猫重新启动周期计时。
func resume_cat_idle() -> void:
	_idle_frozen = false
	if _state == CellState.CAT and _idle_timer != null:
		_idle_timer.start()


## 进入闲置动画；冻结状态直接定位到末帧。
func _enter_cat_idle() -> void:
	_anim.play("CatIconIdle")
	if _idle_frozen:
		_anim.advance(_anim.current_animation_length)
		_drive_cat_spine("CatIconIdle", true)
	else:
		_drive_cat_spine("CatIconIdle")


## 把哭泣、沮丧和放错位置反应视为高优先级，避免被普通闲置抢播。
func _is_playing_high_priority_reaction() -> bool:
	var cur := _anim.current_animation
	return (
		cur == "CatIconCry"
		or cur == "CatIconFrustrated"
		or cur == MisplaceReactionConfig.CONFLICT_REACTION_ANIM_NAME
		or cur == MisplaceReactionConfig.TARGET_REACTION_ANIM_NAME
	)


## 只有正常猫状态且没有高优先级反应时，周期性重播 idle。
func _on_idle_timer_timeout() -> void:
	if _state != CellState.CAT or _cat_cry_loop or _idle_frozen:
		return
	if _is_playing_high_priority_reaction():
		return
	_anim.play("CatIconIdle")
	_drive_cat_spine("CatIconIdle")


# ================= 提示与预览 =================
## 提示高亮：HighLight 与 PromptFrame 同步无限呼吸闪烁（由 play_hide_hint 收尾）
func play_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_light.modulate.a = _HINT_ALPHA_MIN # 从最暗开始闪
	_hint_light.visible = true

	_prompt_frame.visible = true # 边框一起亮
	_prompt_frame.modulate.a = _HINT_ALPHA_MIN
	_hint_tween = create_tween() # 两条独立 tween，各自无限循环
	_hint_tween.set_loops()
	_hint_tween.tween_property(_hint_light, "modulate:a", 1.0, _HINT_HALF_CYCLE)
	_hint_tween.tween_property(_hint_light, "modulate:a", _HINT_ALPHA_MIN, _HINT_HALF_CYCLE)
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = create_tween()
	_frame_tween.set_loops()
	_frame_tween.tween_property(_prompt_frame, "modulate:a", 1.0, _HINT_HALF_CYCLE)
	_frame_tween.tween_property(_prompt_frame, "modulate:a", _HINT_ALPHA_MIN, _HINT_HALF_CYCLE)


## R2 提示预演：底块淡入后延迟播出 PromptCrossOut（delay 叠加在 0.317 秒之后）
func play_r2_preview(delay: float = 0.0) -> void:
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_tween = create_tween()
	_preview_tween.set_parallel(true)
	_preview_tween.tween_property(_bg, "modulate:a", 1.0, 0.2) # 底块恢复到不透明
	(
		_preview_tween
		. tween_callback(func() -> void: _anim.play("PromptCrossOut"))
		. set_delay(0.317 + delay)
	)


## 延迟弹出猫剪影与提示边框，随后分别循环改变透明度；只改变提示视觉。
func play_prompt_cat(delay: float = 0.0) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_bg, "modulate:a", 1.0, 0.2)
	tw.tween_callback(func() -> void:
		_cat_prompt.visible = true
		_cat_prompt.modulate.a = 1.0
		_cat_prompt.scale = Vector2(0.3, 0.3)

		_prompt_frame.visible = true
		_prompt_frame.modulate.a = 1.0
		var tw2 := _cat_prompt.create_tween()
		tw2.tween_property(_cat_prompt, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw2.tween_callback(func() -> void:
			if not is_instance_valid(_cat_prompt) or not is_instance_valid(_prompt_frame):
				return

			var tw3 := _cat_prompt.create_tween()
			tw3.set_loops()
			tw3.tween_property(_cat_prompt, "modulate:a", 0.5, 1.0).set_ease(Tween.EASE_IN_OUT)
			tw3.tween_property(_cat_prompt, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN_OUT)
			var tw4 := _prompt_frame.create_tween()
			tw4.set_loops()
			tw4.tween_property(_prompt_frame, "modulate:a", 0.6, 1.0).set_ease(Tween.EASE_IN_OUT)
			tw4.tween_property(_prompt_frame, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN_OUT)
		)
	).set_delay(delay)

## 收起提示：杀 Tween、隐藏猫剪影与边框；非 叉/错标/猫 状态连叉一起复位
func play_hide_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
		_hint_tween = null
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
		_frame_tween = null
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
		_preview_tween = null

	_cat_prompt.modulate.a = 1.0
	_cat_prompt.visible = false
	_prompt_frame.modulate.a = 1.0
	_prompt_frame.visible = false
	if _state != CellState.MARK and _state != CellState.ERROR and _state != CellState.CAT: # 空 / 草稿态：连叉一起复位
		_anim.play("RESET")
		_cross.visible = false
	if not _hint_light.visible: # 已经隐藏就不用再淡出
		return
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_light, "modulate:a", 0.0, _HINT_FADE_OUT)
	_hint_tween.tween_callback(func() -> void: _hint_light.visible = false)


## 用区域底色乘上淡化值更新 CellFace。
func _update_bg() -> void:
	if _bg != null:
		_bg.color = Color(
			_region_color.r, _region_color.g, _region_color.b, _region_color.a * _dim_alpha
		)


## 片段存在时播放指定动画，并按映射同步骨骼；猫状态额外确保代理不透明。
func play_named_anim(anim_name: String) -> void:
	if _anim != null and _anim.has_animation(anim_name):
		_ensure_cat_spine()
		_anim.stop()
		_anim.play(anim_name)
		_drive_cat_spine(anim_name)

		if _state == CellState.CAT:
			_set_cat_modulate(Color(1, 1, 1, 1))


## 播放放错位置反应并隐藏普通叉，避免与猫反应叠在一起。
func play_wrong_pos_reaction(anim_name: String) -> void:
	_set_cat_modulate(Color(1, 1, 1, 1))
	play_named_anim(anim_name)

	if _cross != null:
		(_cross as CanvasItem).visible = false


## 停止主体 AnimationPlayer，不在这里修改逻辑状态。
func stop_named_anim() -> void:
	if _anim != null:
		_anim.stop()


## 执行主体 RESET、恢复骨骼闲置并清理网格发光。
func reset_wrong_pos_reaction() -> void:
	if _anim != null:
		_anim.stop()
		_anim.play("RESET")
		_anim.advance(0.0)

	_reset_cat_spine_idle()
	stop_grid_glow()


## 播放并等待动画结束信号；缺少片段时仅等待指定的回退秒数。
func play_named_anim_and_wait(anim_name: String, fallback_sec: float) -> void:
	if _anim != null and _anim.has_animation(anim_name):
		_anim.stop()
		_anim.play(anim_name)
		_drive_cat_spine(anim_name)
		await _anim.animation_finished
	else:
		await get_tree().create_timer(fallback_sec).timeout


## 通过发光播放器播放默认 GridGlowing。
func play_grid_glow() -> void:
	play_grid_glow_named(&"GridGlowing")


## 启用发光容器，清理旧的主要光晕显示后播放指定片段。
func play_grid_glow_named(anim_name: StringName) -> void:
	if _glow_player == null or not _glow_player.has_animation(anim_name):
		return

	$Glows.visible = true
	_glow.visible = false
	_glow2.visible = false
	_glow_player.stop()
	_glow_player.play(anim_name)


## 隐藏发光容器及各个光晕节点，保留节点供复用。
func reset_glow_nodes() -> void:
	$Glows.visible = false
	for n: String in ["Glow", "Glow2", "Glow3", "Glow4", "Glow5"]:
		var node: CanvasItem = get_node_or_null("Glows/" + n) as CanvasItem
		if node != null:
			node.visible = false


## 取消循环标记，停止并复位发光播放器，同时清除残留猫光粒子。
func stop_grid_glow() -> void:
	_grid_glow_loop = &""
	if _glow_player != null:
		_glow_player.stop()
		_glow_player.play("RESET")
		_glow_player.advance(0.0)

		$Glows.visible = false

		_clear_cat_glow_particles()


var _grid_glow_loop: StringName = &""


## 记录循环片段并连接结束回调，靠重播实现持续发光。
func play_grid_glow_loop(anim_name: StringName) -> void:
	if _glow_player == null or not _glow_player.has_animation(anim_name):
		return
	$Glows.visible = true
	_glow.visible = false
	_glow2.visible = false
	_grid_glow_loop = anim_name
	_glow_player.stop()
	_glow_player.play(anim_name)

	if not _glow_player.animation_finished.is_connected(_on_grid_glow_loop_finished):
		_glow_player.animation_finished.connect(_on_grid_glow_loop_finished)


## 只有结束的片段仍是当前循环目标时才重播。
func _on_grid_glow_loop_finished(anim_name: StringName) -> void:
	if _grid_glow_loop == &"" or anim_name != _grid_glow_loop:
		return
	_glow_player.play(_grid_glow_loop)


## 播放一次 GridGlowing2，并监听结束以统一清理。
func play_grid_glow_2() -> void:
	if _glow_player == null or not _glow_player.has_animation("GridGlowing2"):
		return
	$Glows.visible = true
	_glow.visible = false
	_glow2.visible = false

	_glow_player.stop()
	_glow_player.play("GridGlowing2")

	if not _glow_player.animation_finished.is_connected(_on_grid_glow_2_finished):
		_glow_player.animation_finished.connect(_on_grid_glow_2_finished)


## 第二种发光片段结束后停止并复位全部网格发光。
func _on_grid_glow_2_finished(anim_name: StringName) -> void:
	if anim_name != &"GridGlowing2":
		return
	stop_grid_glow()


# ================= 草稿渲染 =================
## 草稿只换贴图不播动画：DRAFT_CROSS 亮草稿叉，DRAFT_CAT 亮猫剪影，其余全隐藏
## 提示边框正在闪时不抢它的显示（靠 _prompt_frame.visible 判断）
func _apply_draft_visual(state: int) -> void:
	match state:
		CellState.DRAFT_CROSS:
			_prompt_cross_out.visible = true
			_prompt_cross_out.scale = Vector2.ONE
			_prompt_cross_out.modulate = Color.WHITE
			if not _prompt_frame.visible: # 不在提示态时才收起猫剪影
				_cat_prompt.visible = false
		CellState.DRAFT_CAT:
			_prompt_cross_out.visible = false
			_cat_prompt.visible = true
			_cat_prompt.modulate = Color.WHITE
			_cat_prompt.scale = Vector2.ONE

		_:
			_prompt_cross_out.visible = false

			if not _prompt_frame.visible: # 同理
				_cat_prompt.visible = false


## 草稿叉撤销：状态先回落 EMPTY，再播 PromptCrossOutDisappear 收场
func play_draft_cross_disappear() -> void:
	if _state != CellState.DRAFT_CROSS:
		return

	_state = CellState.EMPTY
	_prompt_cross_out.visible = true
	_anim.stop()
	_anim.play("PromptCrossOutDisappear")


## 把草稿叉提交为普通叉并记录打叉历史；先收起草稿，再通过一次性回调播放正式叉。
func play_draft_cross_apply() -> void:
	if _state != CellState.DRAFT_CROSS:
		return

	_state = CellState.MARK
	_ever_marked_x = true
	_mark_entered_time_ms = Time.get_ticks_msec()
	_anim.stop()
	_prompt_cross_out.visible = true
	_anim.play("PromptCrossOutDisappear")

	_anim.animation_finished.connect(
		func(anim_name: StringName) -> void:
			if anim_name == &"PromptCrossOutDisappear" and _state == CellState.MARK:
				_anim.play("RESET")
				_anim.advance(0.0)
				_cross.visible = true
				var appear_2: StringName = _map_eliminate_effect_anim("CrossOutAppear_2", true)
				_apply_bounce_for_anim(appear_2)
				_apply_fulfill_cross_stroke_track_override(appear_2)
				_anim.play(appear_2)
				_anim.advance(0.0)
				if _needs_fulfill_stroke_geometry_code(appear_2):
					_apply_fulfill_cross_stroke_geometry(),
		CONNECT_ONE_SHOT
	)
