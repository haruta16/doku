# 弹窗式 Toast：一台 AnimationPlayer 连播「弹出 → 停住 → 消失」，用 Mark 标记把动画切成前后两段
class_name PopUpToast
extends Control

@onready var _label: Label = $Panel/Label # 文案节点
@onready var _anim: AnimationPlayer = $AnimationPlayer # 承载 Appear 动画的播放器

const _ANIM_NAME: StringName = &"Appear" # 唯一的动画名
const _MARKER_NAME: StringName = &"Mark" # 停留点标记名

enum State { IDLE, APPEARING, AT_MARK, DISAPPEARING } # 状态机：IDLE 待机 / APPEARING 弹出中 / AT_MARK 已停在标记点 / DISAPPEARING 收尾中

var _state: int = State.IDLE # 当前状态
var _mark_time: float = 0.0 # Mark 在动画里的时间点（单位：秒）；没有标记时退化为动画时长的一半

signal appeared # 弹到 Mark 并停住时发

signal dismissed # 消失动画播完、visible 已置 false 时发


# ================= 生命周期 =================
# 进树：先隐藏；读出 Mark 时间；接动画结束回调；关掉 _process，等弹出时再开
func _ready() -> void:
	visible = false
	var anim: Animation = _anim.get_animation(_ANIM_NAME)
	if anim != null and anim.has_marker(_MARKER_NAME):
		_mark_time = anim.get_marker_time(_MARKER_NAME) # 有标记就用标记的时间点
	else:
		_mark_time = (anim.length * 0.5) if anim != null else 0.0 # 没有标记就退化到动画中点（下面还会给一条警告）
		push_warning(
			"[PopUpToast] 缺少 marker '%s',_mark_time fallback=%.3f" % [str(_MARKER_NAME), _mark_time]
		)
	_anim.animation_finished.connect(_on_anim_finished) # 动画播完（收尾段结束）后交给 _on_anim_finished 收场
	set_process(false)


# ================= 对外接口 =================
# 设置文案（不会自动弹出，需要再调 pop_up）
func set_text(msg: String) -> void:
	_label.text = msg


# 从头播 Appear，并打开 _process 盯着它跑到 Mark
func pop_up() -> void:
	visible = true
	_state = State.APPEARING
	_anim.stop()
	_anim.play(_ANIM_NAME)
	set_process(true)


# 请求消失：从 Mark 处接着往下播收尾段，播完自动隐藏；已在收尾或尚未弹出则忽略
func dismiss() -> void:
	if _state == State.IDLE or _state == State.DISAPPEARING: # 重复调用直接吞掉，避免打断正在播的动画
		return
	_state = State.DISAPPEARING
	set_process(false)

	if _anim.current_animation != _ANIM_NAME: # 动画没在播就先起播，否则后面的 seek 无从谈起
		_anim.play(_ANIM_NAME)
	_anim.seek(_mark_time, true) # 光标跳到 Mark 停住点（下一行的 play 就从这里往下播）
	_anim.play(_ANIM_NAME)


# ================= 内部驱动 =================
# 只在 APPEARING 期跑：动画位置越过 Mark 就暂停并停在 Mark，转 AT_MARK、发 appeared、关 _process
func _process(_delta: float) -> void:
	if _state != State.APPEARING:
		return
	if _anim.current_animation == _ANIM_NAME and _anim.current_animation_position >= _mark_time:
		_anim.pause()
		_anim.seek(_mark_time, true)
		_state = State.AT_MARK
		set_process(false)
		appeared.emit()


# 只在 DISAPPEARING 期响应动画播完：回到 IDLE、隐藏并发 dismissed
func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name != _ANIM_NAME:
		return
	if _state != State.DISAPPEARING:
		return
	_state = State.IDLE
	visible = false
	dismissed.emit()
