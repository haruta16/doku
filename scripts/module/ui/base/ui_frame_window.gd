# 框架窗口基类：在 UIBaseWindow 上加层级 / 遮罩 / 开关动画等 Inspector 配置，以及 CloseBtn、返回键、埋点名等通用约定
class_name UIFrameWindow
extends UIBaseWindow

var _ui_name: String = "" # 注册名（UIManager 的 key），由 UIManager._create_and_cache 写入


# 取注册名
func get_ui_name() -> String:
	return _ui_name


# ---- 面板配置（Inspector 可调，部分会被 UIManager 读取） ----
@export_enum("Default:0", "Popup:100", "Notice:200", "Modal:300", "Tutorial:400", "Loading:500")
var ui_layer: int = UILayerConfig.LAYER_DEFAULT # 层级：决定 z_index 与堆栈分组，取 UILayerConfig 常量（0 默认 / 100 弹窗 / 200 通知 / 300 模态 / 400 教学 / 500 Loading）
@export var is_fullscreen: bool = false # 全屏窗口会遮挡下层窗口（下层收到 on_stack_bottom）
@export var show_mask: bool = false # 显示时是否叠一层半透明黑遮罩
@export var mask_opacity: float = 0.8 # 遮罩不透明度 0~1
@export var play_open_sound: bool = false # 打开时是否播 DLG_OPEN 音效
@export var open_anim_name: String = "" # 打开动画名；留空则播默认 GenericPopup 中 Mark 之前的那一段
@export var close_anim_name: String = "" # 关闭动画名；留空表示不播关闭动画（get_hide_anim_duration 也返回 0）


# ---- 堆栈钩子（由 UIManager 调用） ----
# 被遮挡后重新露出、恢复可见时调用
func on_stack_top() -> void:
	pass


# 被上层全屏窗口遮挡而隐藏时调用
func on_stack_bottom() -> void:
	pass


# 返回键（Android 返回 / ui_cancel）：优先点 CloseBtn，其次调子类的 _on_back_request；返回 true 表示事件已消费
func on_escape() -> bool:
	if _close_btn != null and is_instance_valid(_close_btn): # 场景里有 CloseBtn 就模拟一次点击，复用它的关闭逻辑
		_close_btn.emit_signal("pressed")
		return true
	if has_method("_on_back_request"): # 约定：子类实现 _on_back_request 即可接收返回键
		call("_on_back_request")
		return true
	return false


# 埋点用页面名；子类覆写，默认空字符串表示不上报
func get_scr_name() -> String:
	return ""


# 埋点用弹窗名；子类覆写
func get_dlg_name() -> String:
	return ""


# 弹窗埋点的附加字段；子类覆写
func get_dlg_extra() -> Dictionary:
	return {}


# ---- 开关动画 ----
const _DEFAULT_ANIM: StringName = &"GenericPopup" # 默认动画名：美术在场景里做好的通用弹窗动画
const _DEFAULT_MARKER: StringName = &"Mark" # 停留标记名：动画播到 Mark 就算「开完」，后面的段落留给关闭用


# 播打开动画；缺 AnimationPlayer 或找不到动画名时只 push_error，不阻断显示
func _play_open_animation() -> void:
	var anim := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		if not open_anim_name.is_empty():
			push_error(
				(
					"UIFrameWindow[%s]: open_anim_name='%s' configured but no AnimationPlayer found in subtree"
					% [_ui_name, open_anim_name]
				)
			)
		return
	if open_anim_name.is_empty():
		if anim.has_animation(_DEFAULT_ANIM):
			anim.play_section_with_markers(_DEFAULT_ANIM, &"", _DEFAULT_MARKER) # 播「开头 → Mark」这一段，Mark 之后的停留 / 收尾段留给关闭
	else:
		if anim.has_animation(open_anim_name):
			anim.play(open_anim_name)
		else:
			push_error(
				(
					"UIFrameWindow[%s]: open_anim_name='%s' not found in AnimationPlayer"
					% [_ui_name, open_anim_name]
				)
			)


# 播关闭动画并 await 播完；没配置关闭动画名就直接返回
func _play_close_animation() -> void:
	if close_anim_name.is_empty(): # 没配置关闭动画：立刻当作已播完
		return
	var anim := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		push_error(
			(
				"UIFrameWindow[%s]: close_anim_name='%s' configured but no AnimationPlayer found in subtree"
				% [_ui_name, close_anim_name]
			)
		)
		return
	if not anim.has_animation(close_anim_name):
		push_error(
			(
				"UIFrameWindow[%s]: close_anim_name='%s' not found in AnimationPlayer"
				% [_ui_name, close_anim_name]
			)
		)
		return
	anim.play(close_anim_name)
	await anim.animation_finished # 等动画真正播完，UIManager 才会继续后面的隐藏流程


# 打断正在播的关闭动画（关到一半又被 show 时由 UIManager 调）
func _abort_close_animation() -> void:
	var anim := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim != null and anim.is_playing():
		anim.stop(false)


# 估算关闭动画时长（单位：秒）：UIManager 用它决定遮罩淡出的节奏
func get_hide_anim_duration() -> float:
	for node in find_children("*", "AnimationPlayer", true, false): # 遍历子树里所有 AnimationPlayer，取第一个命中动画名的
		var anim := node as AnimationPlayer
		if not close_anim_name.is_empty():
			if anim.has_animation(close_anim_name):
				return anim.get_animation(close_anim_name).length # 配置了关闭动画名：返回整段时长
		elif anim.has_animation(_DEFAULT_ANIM):
			var a := anim.get_animation(_DEFAULT_ANIM)
			if a.has_marker(_DEFAULT_MARKER):
				return maxf(0.0, a.length - a.get_marker_time(_DEFAULT_MARKER)) # 默认动画：只算 Mark 标记之后剩下的时长
	return 0.0 # 没有可用动画：时长按 0 返回


# ---- 关闭按钮 ----
var _close_btn: BaseButton = null # 场景中名为 CloseBtn 的按钮，_do_create 时找一次并缓存


# 覆写创建流程：基类跑完后找到 CloseBtn，并保证「点它 = 关窗」只连一次
func _do_create() -> void:
	super._do_create() # 基类负责状态机、按钮音效与 on_create
	var btn : BaseButton = find_child("CloseBtn", true, false) as BaseButton
	if btn != null and _close_btn == null:
		_close_btn = btn

		if btn.pressed.get_connections().is_empty(): # 场景里已经连过信号的不重复连
			btn.pressed.connect(_on_close_btn_pressed)


# 覆写显示流程：先按需播开窗音效，再走基类流程，最后播打开动画
func _do_show(params: Dictionary = {}) -> void:
	if play_open_sound:
		SoundManager.play(SoundManager.Kind.DLG_OPEN)
	super._do_show(params) # 基类负责状态、定时器恢复与 on_show
	_play_open_animation()


# CloseBtn 的回调：交给 UIManager 按注册名关掉自己
func _on_close_btn_pressed() -> void:
	UIManager.hide_ui(_ui_name)
