## 全局模态遮罩的显示与交接。窗口选择、生命周期和层级栈由 UIWindowManager 决定。
## 只接收普通 Control 和透明度，不读取页面注册表，也不调用产品单例。
class_name UIModalMask
extends Node

var _primary: ColorRect
var _secondary: ColorRect
var _primary_tween: Tween
var _secondary_tween: Tween
var _requests: int = 0


func request_count() -> int:
	return _requests


## 新显示增加一个请求；关闭中重开仍是原请求，只恢复被中断的遮罩。
func show_for(parent: Node, opacity: float, reopening: bool) -> void:
	if not reopening:
		_requests += 1
	_promote_secondary()
	if not is_instance_valid(_primary):
		_primary = _create_rect(parent, "_GlobalMask")
	_stop_primary_tween()
	_primary.color = Color(0, 0, 0, opacity)
	_primary.visible = true


## 关闭开始时过渡，真正隐藏完成前仍保留请求数，允许中途重开。
func begin_close(next_window: Control, next_opacity: float, duration: float) -> void:
	if not is_instance_valid(_primary) or not _primary.visible:
		return
	if _requests <= 1 or not is_instance_valid(next_window):
		_fade_out(duration)
		return
	_stop_secondary_tween()
	if not is_instance_valid(_secondary):
		_secondary = _create_rect(_primary.get_parent(), "_GlobalMask2")
	_position_below(_secondary, next_window)
	_secondary.color = Color(0, 0, 0, 0)
	_secondary.visible = true
	_fade_out(duration)
	if duration <= 0.0:
		_secondary.color.a = next_opacity
		return
	_secondary_tween = create_tween()
	_secondary_tween.tween_property(_secondary, "color:a", next_opacity, duration)


## 仅由本次关闭成功的调用方释放；旧的异步关闭不得走到这里。
func finish_close(top_window: Control, top_opacity: float) -> void:
	_requests = maxi(0, _requests - 1)
	_promote_secondary()
	# 交接期间目标可能已关闭或刚从全屏遮挡恢复，必须以完成时的目标为准。
	restack(top_window, top_opacity)


## 将显示稳定到实际目标；没有可见模态时隐藏，但仍保留被遮挡窗口的请求。
func restack(window: Control, opacity: float) -> void:
	_stop_primary_tween()
	_stop_secondary_tween()
	if is_instance_valid(_secondary):
		_secondary.visible = false
	if not is_instance_valid(_primary):
		return
	if _requests == 0 or not is_instance_valid(window):
		_primary.visible = false
		return
	_primary.color = Color(0, 0, 0, opacity)
	_position_below(_primary, window)
	_primary.visible = true


func _create_rect(parent: Node, rect_name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.z_as_relative = false
	parent.add_child(rect)
	return rect


func _position_below(rect: ColorRect, window: Control) -> void:
	rect.z_index = window.z_index - 1
	var parent: Node = rect.get_parent()
	if parent != null and window.get_parent() == parent:
		var target: int = window.get_index()
		if rect.get_index() < target:
			target -= 1
		parent.move_child(rect, target)


func _fade_out(duration: float) -> void:
	_stop_primary_tween()
	if duration <= 0.0:
		_primary.visible = false
		return
	var fading: ColorRect = _primary
	_primary_tween = create_tween()
	_primary_tween.tween_property(fading, "color:a", 0.0, duration)
	_primary_tween.tween_callback(func() -> void:
		if is_instance_valid(fading):
			fading.visible = false
	)


## 完成或打断交叉淡化时，副遮罩接替主位；旧主位留待下一次复用。
func _promote_secondary() -> bool:
	if not is_instance_valid(_secondary) or not _secondary.visible:
		return false
	_stop_primary_tween()
	_stop_secondary_tween()
	var previous: ColorRect = _primary
	_primary = _secondary
	_secondary = previous
	if is_instance_valid(previous):
		previous.visible = false
	return true


func _stop_primary_tween() -> void:
	if _primary_tween != null and _primary_tween.is_valid():
		_primary_tween.kill()
	_primary_tween = null


func _stop_secondary_tween() -> void:
	if _secondary_tween != null and _secondary_tween.is_valid():
		_secondary_tween.kill()
	_secondary_tween = null


func _exit_tree() -> void:
	_stop_primary_tween()
	_stop_secondary_tween()
	# current_scene 可先于管理器释放；失效引用不能先放进类型化数组再校验。
	if is_instance_valid(_primary):
		_primary.queue_free()
	if is_instance_valid(_secondary):
		_secondary.queue_free()
