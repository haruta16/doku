## Meowdoku 的 UI 装配入口：注册产品页面、资源绑定、声音、埋点和安全区规则。
## 窗口缓存、层级、遮罩与生命周期由独立的 UIWindowManager 负责。
extends UIWindowManager

var _tracker_observer: UITrackerObserver


func _ready() -> void:
	configure(UIRegistry.build_registry(), _play_ui_sound, ContentSceneBindings.apply)
	super._ready()
	_tracker_observer = UITrackerObserver.new(events)


func _play_ui_sound(cue: StringName) -> void:
	match cue:
		UIBaseWindow.SOUND_BUTTON_CLICK:
			SoundManager.play(SoundManager.Kind.BTN_CLICK)
		UIBaseWindow.SOUND_WINDOW_OPEN:
			SoundManager.play(SoundManager.Kind.DLG_OPEN)


# ================= 刘海屏 / 安全区适配 =================
const _SAFE_TOP_GROUP: StringName = &"_safe_top" # 需要贴顶部安全区的节点分组名（.tscn 里挂 group）
const _SAFE_BOTTOM_GROUP: StringName = &"_safe_bottom" # 需要贴底部安全区的节点分组名
const _SAFE_BASELINE_META: StringName = &"_safe_area_baseline" # 一次记录两条边，双边适配也共用同一基线
const _COLLAPSE_WHEN_TOP_SAFE_GROUP: StringName = &"_collapse_when_top_safe" # 顶部有刘海时应该收起来的分组名
const _COLLAPSE_BASELINE_META: StringName = &"_collapse_when_top_safe_baseline" # 这类节点 可见性 / 最小高度 / 垂直尺寸标志 的基线 meta 键

## 只对这几个页面做安全区适配，弹窗等其它页面自己处理
const _SAFE_AREA_PAGES: Array[StringName] = [
	&"home",
	&"game",
	&"daily_game",
	&"win",
	&"fail",
	&"setting",
	&"bank",
]


## 系统安全区是屏幕像素，Control.offset 是父布局单位；不能直接相加。
func _apply_safe_area(page_name: String, node: Node) -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	_apply_safe_area_rect(page_name, node, Rect2(DisplayServer.get_display_safe_area()))


## 单独接收系统矩形，便于在桌面回归中验证真实的窗口/画布缩放。
## 分组应挂在可自行布局的 Control 上，Container 的直接孩子由容器控制，不应标记。
func _apply_safe_area_rect(page_name: String, node: Node, safe_screen_rect: Rect2) -> void:
	if not _SAFE_AREA_PAGES.has(StringName(page_name)):
		return
	var viewport: Viewport = node.get_viewport()
	var screen_rect: Rect2 = viewport.get_screen_transform() * viewport.get_visible_rect()
	var top_pixels: float = 0.0
	var bottom_pixels: float = 0.0
	if safe_screen_rect.has_area():
		# 已有窗口偏移或黑边先抵扣；超出可视区域的负 inset 不移动页面。
		top_pixels = clampf(safe_screen_rect.position.y - screen_rect.position.y, 0.0, screen_rect.size.y)
		bottom_pixels = clampf(screen_rect.end.y - safe_screen_rect.end.y, 0.0, screen_rect.size.y)
	# 零 inset 也要遍历：缓存页面必须恢复 offset 和顶部占位的基线。
	for n in node.find_children("*", "Control", true, false):
		var c := n as Control
		var use_top: bool = c.is_in_group(_SAFE_TOP_GROUP)
		var use_bottom: bool = c.is_in_group(_SAFE_BOTTOM_GROUP)
		if use_top or use_bottom:
			if not c.has_meta(_SAFE_BASELINE_META):
				c.set_meta(_SAFE_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_BASELINE_META)
			var top_inset: float = _screen_y_to_layout(c, top_pixels) if use_top else 0.0
			var bottom_inset: float = _screen_y_to_layout(c, bottom_pixels) if use_bottom else 0.0
			if is_equal_approx(c.anchor_top, c.anchor_bottom):
				# 固定高度整体平移；上下拉伸的节点分别缩进两条边。
				c.offset_top = baseline.x + top_inset - bottom_inset
				c.offset_bottom = baseline.y + top_inset - bottom_inset
			else:
				c.offset_top = baseline.x + top_inset
				c.offset_bottom = baseline.y - bottom_inset
		# _collapse_when_top_safe 组：有刘海就直接隐藏并清零高度给内容腾地方，没刘海恢复基线
		if c.is_in_group(_COLLAPSE_WHEN_TOP_SAFE_GROUP):
			if not c.has_meta(_COLLAPSE_BASELINE_META):
				c.set_meta(
					_COLLAPSE_BASELINE_META,
					[c.visible, c.custom_minimum_size.y, c.size_flags_vertical]
				)
			var baseline: Array = c.get_meta(_COLLAPSE_BASELINE_META)
			if top_pixels > 0.0:
				c.visible = false
				c.custom_minimum_size.y = 0.0
				c.size_flags_vertical = 0
			else:
				c.visible = bool(baseline[0])
				c.custom_minimum_size.y = float(baseline[1])
				c.size_flags_vertical = int(baseline[2])


## 当前安全区布局沿屏幕竖轴排列。去除自身变换后，剩下的是 offset 所在父坐标系。
## 包括窗口拉伸、CanvasLayer 和父 Control 缩放，不受本节点的 pivot/scale 干扰。
func _screen_y_to_layout(control: Control, pixels: float) -> float:
	var local_transform: Transform2D = control.get_transform()
	if is_zero_approx(local_transform.determinant()):
		return 0.0
	var control_to_screen: Transform2D = (
		control.get_viewport().get_screen_transform() * control.get_global_transform_with_canvas()
	)
	var parent_to_screen: Transform2D = control_to_screen * local_transform.affine_inverse()
	if is_zero_approx(parent_to_screen.determinant()):
		return 0.0
	var screen_to_parent: Transform2D = parent_to_screen.affine_inverse()
	return screen_to_parent.y.y * pixels
