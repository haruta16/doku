# 单个格子的视图：一格的全部外观与动画（区域底色、猫/叉/草稿、提示闪烁、按压回弹）
# 不持有棋盘逻辑：状态由 BoardView 经 change_state() 推下来，读回去用 get_state()
@tool
class_name CellView
extends Control

# ---- 可调参数（Inspector 可改） ----
@export var region_colors: PackedColorArray = PackedColorArray() # 12 色区域调色板（BoardView 取它作基准色）

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _bg: Panel = $BgPanel # 区域底色块（StyleBoxFlat 由 _style 覆盖）
@onready var _glow: Sprite2D = $Glows/Glow # 光晕 1（显隐由动画轨驱动）
@onready var _glow2: Sprite2D = $Glows/Glow2 # 光晕 2
@onready var _anim: AnimationPlayer = $AnimationPlayer # 主体动画播放器：RESET / 叉 / 猫 / 错标 全走它
@onready var _scale_anim: AnimationPlayer = $ScalePlayer # 按压缩放播放器：PressShrink / PressGrow
@onready var _cross: Node = $Crosses/CrossOut # 玩家打的叉节点
@onready var _hint_light: Sprite2D = $Frames/HighLight # 提示高亮（呼吸闪烁）
@onready var _cat_icon: CanvasItem = $CatIcon # 猫本体（Spine 骨骼动画）
@onready var _cat_prompt: Sprite2D = $CatPrompt # 草稿猫 / 提示猫剪影
@onready var _prompt_frame: Sprite2D = $Frames/PromptFrame # 草稿与提示用的边框
@onready var _prompt_cross_out: Control = $Crosses/PromptCrossOut # 草稿叉

# ---- 提示闪烁参数 ----
const _HINT_ALPHA_MIN: float = 50.0 / 255.0 # 闪烁最暗时的透明度（50/255）
const _HINT_HALF_CYCLE: float = 0.65 # 单程时长（秒）：暗→亮、亮→暗 各这么多
const _HINT_FADE_OUT: float = 0.12 # 收尾淡出时长（秒）

# ---- 进行中的 Tween（重播前先 kill，避免叠在一起） ----
var _hint_tween: Tween = null # 高亮闪烁循环
var _frame_tween: Tween = null # PromptFrame 闪烁循环
var _preview_tween: Tween = null # R2 预览

# ---- 运行时状态 ----
@export var _region_color: Color = Color.WHITE # 本格区域底色（@export 便于编辑器里预览）
var _state: int = CellState.EMPTY # 当前格子状态，取 CellState 常量
var _style: StyleBoxFlat # 底块样式（_ready 里 new，改圆角/颜色都写它）

# ---- 视觉尺寸设计值（按容器缩放做补偿） ----
const DESIGN_CELL_VISUAL_PX: float = 97.55 # 设计稿格子边长（像素），当前未被引用
const DESIGN_CORNER_VISUAL_PX: float = 10.0 # 设计稿圆角半径（像素）

# ---- 「打过叉 / 出过错」追踪（R4+ 鼓掌提示按区域聚合，见 BoardView） ----
const _DOUBLE_TAP_MARK_GRACE_MS: int = 1000 # 叉→猫 的宽容窗口（毫秒）：窗口内切换不算「打过叉」
var _ever_marked_x: bool = false # 本局是否打过分叉
var _ever_errored: bool = false # 本局是否出过错标
var _mark_entered_time_ms: int = -1 # 进入 MARK 的时刻（毫秒）；-1 表示当前不在 MARK
var _ever_marked_x_snapshot: bool = false # 进入 MARK 前的 _ever_marked_x 快照，用于宽容窗口回滚
var _press_shrunk: bool = false # 是否处于按下缩小状态，等 play_mark_release 回弹

# ---- 猫的闲置动画 ----
const _IDLE_INTERVAL: float = 5.0 # 闲置多久后重播 idle（秒）
const CROSS_OUT_APPEAR_DURATION: float = 0.49 # 叉出现动画时长（秒）；当前全仓未被引用
var _idle_timer: Timer = null # 闲置定时器（运行时 Timer.new，只对猫生效）
var _cat_cry_loop: bool = false # 是否在循环播放「猫哭」
var _demo_cat_no_idle: bool = false # 说明页演示模式：禁用自动 idle


# ================= 生命周期 =================
# 建样式、补偿圆角；编辑器里只做静态外观，运行时再建定时器、接信号、复位到空态
func _ready() -> void:
    _style = StyleBoxFlat.new() # 样式在 _ready 里创建，编辑器里也要有

    set_corner_radius_compensated(1.0)
    _update_bg()

    # 编辑器里不建定时器、不接信号
    if Engine.is_editor_hint():
        return

    # 闲置定时器：非一次性，由 change_state / revive_to_idle 手动 start
    _idle_timer = Timer.new()
    _idle_timer.wait_time = _IDLE_INTERVAL
    _idle_timer.one_shot = false
    _idle_timer.autostart = false
    add_child(_idle_timer)
    _idle_timer.timeout.connect(_on_idle_timer_timeout) # 超时回调：重播 idle
    _anim.animation_finished.connect(_on_anim_finished) # 动画结束回调：接续 idle 或哭循环

    _set_children_mouse_ignore(self) # 子节点一律不吃鼠标，点击由棋盘统一处理

    _reset_to_empty_baseline() # 复位到空态基线


# 把格子强行拉回「空」基准态：杀 Tween、停动画、隐藏装饰、清追踪标记
# BoardView.setup(recycle_reused=true) 复用旧格子时也会直接调用
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
    if _idle_timer != null:
        _idle_timer.stop()

    # 主体动画停到 RESET 基准帧，避免残留姿势
    _anim.stop()
    _anim.play("RESET") # 回到 RESET 基准帧
    _anim.advance(0.0)

    # 猫是 Spine 骨骼动画，要手动摆回 idle
    var cat_spine := _cat_icon as SpineSprite
    if cat_spine != null:
        var st := cat_spine.get_animation_state()
        if st != null:
            st.set_animation("idle", false, 0)
        cat_spine.update_skeleton(0.0)

    _glow.visible = false # 光晕由动画轨控制，这里统一关掉
    _glow2.visible = false

    _cross.visible = false # 叉节点
    _hint_light.visible = false # 提示高亮
    _prompt_frame.visible = false # 提示边框
    _prompt_frame.modulate.a = 1.0 # 边框透明度复位
    _cat_prompt.modulate = Color.WHITE # 猫剪影颜色复位
    _cat_prompt.scale = Vector2.ONE # 猫剪影缩放复位
    _bg.modulate.a = 1.0 # 底块透明度复位（预览时会把它压低）
    _apply_draft_visual(CellState.EMPTY) # 草稿贴图按 EMPTY 清掉

    _state = CellState.EMPTY # 状态字段本身也要复位
    _cat_cry_loop = false
    _demo_cat_no_idle = false
    reset_clap_tracking() # 清「打过叉 / 出过错」追踪
    set_auto_mark_locked(false) # 解锁输入

    _apply_eliminate_effect() # 按 AB 配置套用消除特效


# 按 ABTest 的「消除特效」配置调整外观：叉与光晕可整体缩小，光晕也可直接隐藏
func _apply_eliminate_effect() -> void:
    if _is_eliminate_shrink_cross():
        $Crosses.scale = Vector2(0.865, 0.865)
        $Glows.scale = Vector2(0.865, 0.865)
    if _is_eliminate_remove_glow():
        $Glows.visible = false


# 递归把所有子 Control 设成不吃鼠标，点击统一由棋盘处理
func _set_children_mouse_ignore(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _set_children_mouse_ignore(child)


# 设置底块四角圆角半径（像素），写进 StyleBoxFlat 覆盖 Panel
func set_corner_radius(rad: int) -> void:
    if _style == null:
        return
    _style.corner_radius_top_left = rad
    _style.corner_radius_top_right = rad
    _style.corner_radius_bottom_right = rad
    _style.corner_radius_bottom_left = rad
    _bg.add_theme_stylebox_override("panel", _style)


# 按容器缩放补偿圆角：视觉半径固定为 DESIGN_CORNER_VISUAL_PX，缩小放大都不变形
func set_corner_radius_compensated(container_scale: float) -> void:
    if _style == null:
        return
    if container_scale <= 0.0: # 缩放非法时直接返回
        return
    var rad: int = maxi(1, int(round(DESIGN_CORNER_VISUAL_PX / container_scale))) # 本地半径 = 设计半径 / 缩放
    set_corner_radius(rad)


# 设置本格区域底色；样式已就绪时立即重刷底块
func set_region_color(color: Color) -> void:
    _region_color = color
    if _style != null:
        _update_bg()


# 读回当前区域底色
func get_region_color() -> Color:
    return _region_color


# ================= 状态切换（由 BoardView 推入） =================
# 唯一的状态入口：params 支持 state / play_anim / show_cat_visual / appear_anim /
# disappear_anim / lock_anim / split_press；动画与音效都在这里统一触发
func change_state(params: Dictionary) -> void:
    var state: int = params.get("state", _state) # 目标状态；缺省沿用当前状态
    var is_play_anim: bool = params.get("play_anim", true) # false 时把动画快进到末帧（瞬间到位）
    var show_cat_visual: bool = params.get("show_cat_visual", true) # false 时跳过出场动画（只关粒子）

    var appear_anim: String = params.get("appear_anim", "") # 指定出场动画，覆盖默认查表结果

    var disappear_anim: String = params.get("disappear_anim", "") # 指定消失动画，覆盖默认查表结果

    var lock_anim: String = params.get("lock_anim", "") # 锁定叉专用动画（可空）

    var split_press: bool = params.get("split_press", false) # 分屏按压：改用不带缩放的叉动画
    if _state == state: # 状态没变，直接返回（幂等）
        return

    # 锁定叉是终态，之后任何改动都被吞掉
    if _state == CellState.LOCKED_MARK:
        return
    var prev_state := _state

    # 草稿只换贴图、不走进场动画；草稿→空 同理
    if _is_draft_state(state) or (_is_draft_state(prev_state) and state == CellState.EMPTY):
        _state = state
        _apply_draft_visual(state)
        return

    # 从草稿切到正式状态：先把草稿贴图清掉
    if _is_draft_state(prev_state):
        _apply_draft_visual(CellState.EMPTY)
    _state = state

    # 进入叉：记下时刻，供宽容窗口回滚
    if state == CellState.MARK: # 进入 MARK 才需要记账
        _mark_entered_time_ms = Time.get_ticks_msec()
        _ever_marked_x_snapshot = _ever_marked_x
        _ever_marked_x = true
    else:
        # 离开叉：结算宽容窗口
        if prev_state == CellState.MARK and _mark_entered_time_ms >= 0:
            if state == CellState.CAT:
                # 1 秒内 叉→猫 视为误触，回滚「打过叉」记录
                var mark_dur_ms: int = Time.get_ticks_msec() - _mark_entered_time_ms
                if mark_dur_ms < _DOUBLE_TAP_MARK_GRACE_MS:
                    _ever_marked_x = _ever_marked_x_snapshot
            _mark_entered_time_ms = -1 # 结算完就清掉时刻
        # 错标：既算打过叉，也算出过错
        if state == CellState.ERROR:
            _ever_marked_x = true
            _ever_errored = true

    # 只有走默认动画路径时才由这里配音，自定义动画的音画交给调用方
    if is_play_anim and not Engine.is_editor_hint() and appear_anim == "" and disappear_anim == "":
        _emit_state_sound(prev_state, state)

    # 锁定叉：只播 lock_anim，不做其它视觉重置
    if state == CellState.LOCKED_MARK:
        if lock_anim != "":
            _anim.stop()
            _anim.play(lock_anim)
            _anim.advance(0.0)
            if not is_play_anim:
                _anim.advance(_anim.current_animation_length)
        return

    # 正常状态切换优先，先停掉 R2 预览 tween
    if _preview_tween != null and _preview_tween.is_valid():
        _preview_tween.kill()
        _preview_tween = null

    # 一律先回 RESET，再放目标动画
    _anim.stop()
    _anim.play("RESET")
    _anim.advance(0.0)

    _press_shrunk = false # 缩放复位，等下次按压

    # 猫：藏叉、播出现动画；不播动画时直接定格到 idle 末帧
    if state == CellState.CAT:
        _cat_cry_loop = false
        _cross.visible = false
        if not show_cat_visual:
            _set_particles_visible(false)
            return
        _set_particles_visible(is_play_anim) # 只有真的播动画时才开粒子
        if is_play_anim:
            _anim.play("CatIconAppear")
        else:
            _anim.play("CatIconIdle")
            _anim.advance(_anim.current_animation_length)

            if _cat_icon != null:
                _cat_icon.modulate = Color(1, 1, 1, 1)
        _idle_timer.start() # 启动闲置定时器：到点重播 idle
        return

    _idle_timer.stop() # 非猫状态：停掉闲置定时器
    _cat_cry_loop = false

    var anim_name := _get_anim_name(prev_state, state) # 按前后状态查表拿默认动画名

    if appear_anim != "": # appear_anim 优先级最高
        anim_name = appear_anim

    if disappear_anim != "" and prev_state == CellState.MARK and state == CellState.EMPTY: # 叉→空：用指定的消失动画
        anim_name = disappear_anim

    if split_press and is_play_anim and state == CellState.MARK and anim_name == "CrossOutAppear": # 分屏按压：改用 NoScale 版
        anim_name = "CrossOutAppearNoScale"
    elif (
        split_press
        and is_play_anim
        and state == CellState.EMPTY
        and anim_name == "CrossOutDisAppear"
    ):
        anim_name = "CrossOutDisAppearNoScale"

    # 只有这几个动画需要叉节点可见
    _cross.visible = (
        anim_name == "CrossOutAppear"
        or anim_name == "CrossOutDisAppear"
        or anim_name == "AutomaticAppear"
        or anim_name == "AutomaticDisappear"
        or anim_name == "CrossOutAppearNoScale"
        or anim_name == "CrossOutDisAppearNoScale"
    )

    if anim_name == "": # 没有动画可播（例如 空→空）
        return
    _anim.play(anim_name)
    _anim.advance(0.0)
    if not is_play_anim: # 不播动画时快进到末帧
        _anim.advance(_anim.current_animation_length)

    if anim_name == "CrossOutAppearNoScale" or anim_name == "CrossOutDisAppearNoScale": # NoScale 版：缩放交给 ScalePlayer
        _scale_anim.stop()
        _scale_anim.play("PressShrink")
        _press_shrunk = true


# 松手回弹：只有按下时缩小过才播 PressGrow（BoardView.play_mark_release 转发）
func play_mark_release() -> void:
    if not _press_shrunk:
        return
    _press_shrunk = false
    _scale_anim.stop()
    _scale_anim.play("PressGrow")


# 读当前状态（BoardView.get_board() / get_cell_state() 都走这里）
func get_state() -> int:
    return _state


# 自动打叉的「预置」：只置状态并记账，不播动画
# 出场动画留给 play_pending_auto_cross_appear()（自动清屏流程分两步走）
func preset_mark_for_auto_cross() -> void:
    if _state != CellState.EMPTY:
        return
    _state = CellState.MARK
    _mark_entered_time_ms = Time.get_ticks_msec()
    _ever_marked_x_snapshot = _ever_marked_x
    _ever_marked_x = true


# 补播自动打叉的出场动画（AutomaticAppear）；叉已可见则跳过
func play_pending_auto_cross_appear() -> void:
    if _state != CellState.MARK:
        return
    if _cross.visible:
        return
    _cross.visible = true
    _anim.stop()
    _anim.play("AutomaticAppear")
    _anim.advance(0.0)


# ---- 输入锁 ----
var _auto_mark_locked: bool = false # true = 自动打叉流程中禁止玩家改动


# 加锁 / 解锁本格输入（自动打叉流程中禁止玩家再改）
func set_auto_mark_locked(locked: bool) -> void:
    _auto_mark_locked = locked


# 查询输入是否被锁（BoardView.is_cell_input_locked 转发）
func is_auto_mark_locked() -> bool:
    return _auto_mark_locked


# 是否草稿态：语义同 CellState.is_draft，本文件内的快捷判断
func _is_draft_state(s: int) -> bool:
    return s == CellState.DRAFT_CROSS or s == CellState.DRAFT_CAT


# 清空「打过叉 / 出过错」追踪（BoardView 建格与复用时调用）
func reset_clap_tracking() -> void:
    _ever_marked_x = false
    _ever_errored = false
    _mark_entered_time_ms = -1
    _ever_marked_x_snapshot = false


# 本局是否打过分叉（BoardView 按区域聚合后喂给 R4+ 鼓掌提示）
func has_ever_marked_x() -> bool:
    return _ever_marked_x


# 本局是否出过错标（同上，按区域聚合）
func has_ever_errored() -> bool:
    return _ever_errored


# ================= 音效与动画名 =================
# 按目标状态配音；错标音效受 ABTest「错音量降低」影响
func _emit_state_sound(prev_state: int, state: int) -> void:
    if state == CellState.CAT:
        SoundManager.play(SoundManager.Kind.MARK_CAT)
    elif state == CellState.ERROR:
        if ABTestManager.wrong_cat_effect.should_lower_wrong_volume():
            SoundManager.play(SoundManager.Kind.MARK_WRONG_LOW)
        else:
            SoundManager.play(SoundManager.Kind.MARK_WRONG)
    elif state == CellState.MARK and prev_state == CellState.EMPTY:
        SoundManager.play(SoundManager.Kind.MARK_X)
    elif state == CellState.EMPTY and prev_state == CellState.MARK:
        SoundManager.play(SoundManager.Kind.UNMARK_X)


# 前后状态 → 默认动画名：只有 空→叉 / 叉→空 / 错标 三种有动画，其余返回空串
func _get_anim_name(prev: int, target: int) -> String:
    match target:
        CellState.EMPTY:
            return "CrossOutDisAppear" if prev == CellState.MARK else ""
        CellState.MARK:
            return "CrossOutAppear"
        CellState.ERROR:
            return _resolve_error_appear_anim()
        _:
            return ""


# 错标出场动画共 6 种变体：「是否跳过红色填充」× 图标崩坏类型（心碎/不崩/鱼碎）
func _resolve_error_appear_anim() -> String:
    var no_red: bool = ABTestManager.wrong_cat_effect.should_skip_red_fill()
    var crash_val: int = ABTestManager.icon_crash.value() as int
    if no_red:
        if crash_val == IconCrashConfig.VALUE_NO_CRASH:
            return "ErrorAppear5"
        elif crash_val == IconCrashConfig.VALUE_FISH_CRASH:
            return "ErrorAppear4"
        return "ErrorAppear3"
    else:
        if crash_val == IconCrashConfig.VALUE_NO_CRASH:
            return "ErrorAppear1"
        elif crash_val == IconCrashConfig.VALUE_FISH_CRASH:
            return "ErrorAppear2"
        return "ErrorAppear"


# 强制重播猫的出现动画（通关时 BoardView.replay_all_cat_appear 逐格调用）
func force_play_appear(with_particles: bool = true) -> void:
    _set_particles_visible(with_particles)
    _idle_timer.stop()
    _anim.stop()
    _anim.play("CatIconAppear")


# 开关猫出现时的粒子特效节点；节点不存在时静默跳过
func _set_particles_visible(show: bool) -> void:
    var fx: Control = get_node_or_null("EffectCatIconAppear2")
    if fx != null:
        fx.visible = show


# ================= 猫的表情动画 =================
# 循环播放「猫哭」（猜错时全盘一起哭，由 revive_to_idle 收场）
func play_cry_loop() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return
    _cat_cry_loop = true
    _idle_timer.stop()

    if _cat_icon != null:
        _cat_icon.modulate = Color(1, 1, 1, 1)
    _anim.play("CatIconCry")


# 播一次沮丧表情（动画名由 ABTest error_catface 决定）
func play_frustrated_once() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return

    if _cat_icon != null:
        _cat_icon.modulate = Color(1, 1, 1, 1)
    _anim.play(_error_catface_anim())


# 结束哭 / 沮丧回到 idle，并重启闲置定时器（只对猫生效）
func revive_to_idle() -> void:
    if _state != CellState.CAT:
        return
    _cat_cry_loop = false
    _anim.stop()
    _anim.play("CatIconIdle")
    _anim.advance(_anim.current_animation_length)
    _idle_timer.start()


# 动画播完的回调：哭循环续播；沮丧与出现结束后接 idle，idle 被禁用时定格末帧
func _on_anim_finished(anim_name: StringName) -> void:
    if _state != CellState.CAT:
        return
    if anim_name == "CatIconCry" and _cat_cry_loop:
        _anim.play("CatIconCry")
    elif anim_name == _error_catface_anim():
        _anim.play("CatIconIdle")
        if not _is_idle_anim_enabled():
            _anim.advance(_anim.current_animation_length)
    elif anim_name == "CatIconAppear":
        _anim.play("CatIconIdle")
        if not _is_idle_anim_enabled():
            _anim.advance(_anim.current_animation_length)


# 闲置超时：重播 idle 让猫动一下（哭 / 沮丧中或 idle 被禁用时跳过）
func _on_idle_timer_timeout() -> void:
    if _state != CellState.CAT or _cat_cry_loop:
        return
    if not _is_idle_anim_enabled():
        return
    var cur := _anim.current_animation
    if cur == "CatIconCry" or cur == _error_catface_anim():
        return
    _anim.play("CatIconIdle")


# idle 循环是否启用：说明页演示一律关，否则读 ABTest
func _is_idle_anim_enabled() -> bool:
    if _demo_cat_no_idle:
        return false
    if ABTestManager == null or ABTestManager.play_anim == null:
        return true
    return ABTestManager.play_anim.is_idle_anim_enabled()


# 沮丧表情的动画名；ABTest 不可用时退回默认 CatIconFrustrated
func _error_catface_anim() -> StringName:
    if ABTestManager == null or ABTestManager.error_catface == null:
        return &"CatIconFrustrated"
    return ABTestManager.error_catface.anim_for_error()


# AB 配置：消除特效是否要缩小叉（ABTest 缺失时按 false）
func _is_eliminate_shrink_cross() -> bool:
    if ABTestManager == null or ABTestManager.eliminate_effect == null:
        return false
    return ABTestManager.eliminate_effect.is_shrink_cross()


# AB 配置：消除特效是否要隐藏光晕
func _is_eliminate_remove_glow() -> bool:
    if ABTestManager == null or ABTestManager.eliminate_effect == null:
        return false
    return ABTestManager.eliminate_effect.is_remove_glow()


# ================= 提示与预览 =================
# 提示高亮：HighLight 与 PromptFrame 同步无限呼吸闪烁（由 play_hide_hint 收尾）
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


# R2 提示预演：底块淡入后延迟播出 PromptCrossOut（delay 叠加在 0.317 秒之后）
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


# 提示猫剪影：延迟淡入 + 回弹放大，随后猫与边框各自呼吸闪烁
func play_prompt_cat(delay: float = 0.0) -> void:
    var tw := create_tween() # 并行：底块淡入与延迟回调同时跑
    tw.set_parallel(true)
    tw.tween_property(_bg, "modulate:a", 1.0, 0.2)
    tw.tween_callback(
        func() -> void:
            _cat_prompt.visible = true
            _cat_prompt.modulate.a = 1.0
            _cat_prompt.scale = Vector2(0.3, 0.3)

            _prompt_frame.visible = true
            _prompt_frame.modulate.a = 1.0
            var tw2 := _cat_prompt.create_tween()
            tw2.tween_property(_cat_prompt, "scale", Vector2(1.0, 1.0), 0.25).set_ease(
                Tween.EASE_OUT
            ).set_trans(Tween.TRANS_BACK)
            tw2.tween_callback(
                func() -> void:
                    var tw3 := _cat_prompt.create_tween()
                    tw3.set_loops()
                    tw3.tween_property(_cat_prompt, "modulate:a", 0.5, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    tw3.tween_property(_cat_prompt, "modulate:a", 1.0, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    var tw4 := _prompt_frame.create_tween()
                    tw4.set_loops()
                    tw4.tween_property(_prompt_frame, "modulate:a", 0.6, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
                    tw4.tween_property(_prompt_frame, "modulate:a", 1.0, 1.0).set_ease(
                        Tween.EASE_IN_OUT
                    )
            )
    ).set_delay(delay)


# 收起提示：杀 Tween、隐藏猫剪影与边框；非 叉/错标/猫 状态连叉一起复位
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


# ---- 遗留接口：撤销高亮（全仓已无调用，仅保留信号与空函数） ----
signal undo_highlight_finished


# 空实现：历史遗留接口，保留以免外部调用报错
func play_undo_highlight(_duration: float) -> void:
    pass


# 空实现：历史遗留接口
func stop_undo_highlight() -> void:
    pass


# ================= 草稿渲染 =================
# 草稿只换贴图不播动画：DRAFT_CROSS 亮草稿叉，DRAFT_CAT 亮猫剪影，其余全隐藏
# 提示边框正在闪时不抢它的显示（靠 _prompt_frame.visible 判断）
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


# 草稿叉撤销：状态先回落 EMPTY，再播 PromptCrossOutDisappear 收场
func play_draft_cross_disappear() -> void:
    if _state != CellState.DRAFT_CROSS:
        return

    _state = CellState.EMPTY
    _prompt_cross_out.visible = true
    _anim.stop()
    _anim.play("PromptCrossOutDisappear")


# 草稿叉转正：状态改 MARK 并记账，草稿叉消失后补播正式叉 CrossOutAppear2
func play_draft_cross_apply() -> void:
    if _state != CellState.DRAFT_CROSS:
        return

    _state = CellState.MARK
    _ever_marked_x = true
    _mark_entered_time_ms = Time.get_ticks_msec()
    _anim.stop()
    _prompt_cross_out.visible = true
    _anim.play("PromptCrossOutDisappear")

    # 一次性连接：草稿叉消失后补正式叉，随后自动断开
    _anim.animation_finished.connect(
        func(anim_name: StringName) -> void:
            if anim_name == &"PromptCrossOutDisappear" and _state == CellState.MARK:
                _cross.visible = true
                _anim.play("CrossOutAppear2"),
        CONNECT_ONE_SHOT
    )


# ================= 说明页演示接口（HowToPlay 直接调用） =================
# 直接播指定动画；CrossOut* 系列会自动把叉节点打开，instant=true 时快进到末帧
func demo_play(anim_name: String, instant: bool = false) -> void:
    _idle_timer.stop()
    _anim.stop()
    if anim_name.begins_with("CrossOut"): # 叉类动画要先把叉节点打开
        _cross.visible = true
    _anim.play(anim_name)
    if instant:
        _anim.advance(_anim.current_animation_length)


# 演示用猫：绕过状态机直接置 CAT，并关掉 idle 自动重播
func demo_cat(animate: bool) -> void:
    _idle_timer.stop()
    _cat_cry_loop = false
    _demo_cat_no_idle = true # 演示时不自动动
    _state = CellState.CAT
    _cross.visible = false
    _set_particles_visible(animate)
    _anim.stop()
    if animate:
        _anim.play("CatIconAppear")
    else:
        _anim.play("CatIconIdle")
        _anim.advance(_anim.current_animation_length)

        if _cat_icon != null:
            _cat_icon.modulate = Color(1, 1, 1, 1)


# 演示结束复位：回到 EMPTY 并播放 RESET
func demo_clear() -> void:
    _idle_timer.stop()
    _cat_cry_loop = false
    _demo_cat_no_idle = false
    _state = CellState.EMPTY
    _anim.stop()
    _anim.play("RESET")
    _anim.advance(0.0)
    _cross.visible = false


# 取动画时长（秒）供说明页排时间轴；动画不存在返回 0.0
func demo_anim_length(anim_name: String) -> float:
    return _anim.get_animation(anim_name).length if _anim.has_animation(anim_name) else 0.0


# ================= 内部工具 =================
# 把区域色写进底块样式（唯一写 _style.bg_color 的地方）
func _update_bg() -> void:
    _style.bg_color = _region_color
