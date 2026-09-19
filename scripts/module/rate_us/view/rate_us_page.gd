# 评星弹窗（旧版 UI）：五星可点可选可拖，关闭时回传 {star_count, is_submitted}
class_name RateUsPage
extends UIFrameWindow

# 关闭时发出；star_count=0 且 is_submitted=false 表示没评分直接关掉
signal closed(data: Dictionary)

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _star1: TextureRect = $Root/Content/Dialog/StarsRow/Star1 # 第 1 颗星（_ready 里组装成数组）
@onready var _star2: TextureRect = $Root/Content/Dialog/StarsRow/Star2
@onready var _star3: TextureRect = $Root/Content/Dialog/StarsRow/Star3
@onready var _star4: TextureRect = $Root/Content/Dialog/StarsRow/Star4
@onready var _star5: TextureRect = $Root/Content/Dialog/StarsRow/Star5
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 弹窗动画

# ---- 运行时状态 ----
var _stars: Array[TextureRect] # 五颗星的引用数组
var _star_lit_tex: Texture2D # 亮星贴图（取自 Star1）
var _star_dim_tex: Texture2D # 暗星贴图（取自 Star4）
var _selected_stars: int = 5 # 当前选中星数，默认 5
var _closing: bool = false # 关闭动画只播一次
var _dragging: bool = false # 鼠标按住拖选星中


# ================= 初始化 =================
# 组装星星数组与两套贴图，并给每颗星接鼠标事件
func _ready() -> void:
	_stars = [_star1, _star2, _star3, _star4, _star5]

	# 亮 / 暗两套贴图直接借星星自己的贴图
	_star_lit_tex = _star1.texture
	_star_dim_tex = _star4.texture
	# 每颗星：按下选中并进入拖拽，抬起结束拖拽
	for i in range(_stars.size()):
		var idx := i
		# idx 用局部副本捕获，避免闭包共享同一个 i
		_stars[i].gui_input.connect(
			func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
					if event.pressed:
						_dragging = true
						_select_stars(idx + 1)
					else:
						_dragging = false
		)
	# 关闭按钮的按下缩放
	bind_press_release_scale($Root/Content/Dialog/CloseBtn)


# 拖拽中：鼠标划过哪颗星就选到第几颗
func _input(event: InputEvent) -> void:
	# 没在拖拽就不处理
	if not _dragging:
		return
	# 松开左键结束拖拽
	if event is InputEventMouseButton and not event.pressed:
		_dragging = false
		return
	if event is InputEventMouseMotion:
		var star_idx: int = _star_index_at(event.global_position)
		if star_idx >= 0:
			_select_stars(star_idx + 1)


# 命中测试：返回鼠标下的星星下标，没命中返回 -1
func _star_index_at(global_pos: Vector2) -> int:
	for i in range(_stars.size()):
		var rect: Rect2 = _stars[i].get_global_rect()
		if rect.has_point(global_pos):
			return i
	return -1


# 打开：重置状态、默认五星、播开场动画段
func on_show(_params: Dictionary = {}) -> void:
	_closing = false
	# 旧 UI 默认给 5 星
	_select_stars(5)
	_anim.play_section_with_markers(_get_anim_name(), &"", &"Mark")


# 选中 n 颗星：前 n 颗用亮贴图，其余用暗贴图
func _select_stars(n: int) -> void:
	_selected_stars = n
	for i in range(_stars.size()):
		_stars[i].texture = _star_lit_tex if i < n else _star_dim_tex


# 点关闭：埋点后播关闭动画，回传「未提交」
func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	await _close_with_anim()
	closed.emit({"star_count": 0, "is_submitted": false})


# 点提交评分：埋点带星数，关闭后回传「已提交 + 星数」
func _on_rate_us_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.RATE_US, self, {"rate_star": _selected_stars})
	await _close_with_anim()
	closed.emit({"star_count": _selected_stars, "is_submitted": true})


# 播关闭动画段并等待（防重入：只播一次）
func _close_with_anim() -> void:
	if _closing:
		return
	_closing = true
	_anim.play_section_with_markers(_get_anim_name(), &"Mark", &"")
	await _anim.animation_finished


# 动画名：新版 UI 覆写成 GenericPopupV2
func _get_anim_name() -> StringName:
	return &"GenericPopup"


# 关闭动画时长 = 动画总长 − Mark 标记时刻，供 UIManager 安排真正隐藏
func get_hide_anim_duration() -> float:
	# 没有动画节点就没有时长
	if _anim == null:
		return 0.0
	var n := _get_anim_name()
	# 没有这条动画也返回 0
	if not _anim.has_animation(n):
		return 0.0
	var a := _anim.get_animation(n)
	# 没有 Mark 标记就按整条动画算
	return maxf(0.0, a.length - (a.get_marker_time(&"Mark") if a.has_marker(&"Mark") else 0.0))


# 埋点用弹窗名
func get_dlg_name() -> String:
	return Tracker.Dlg.RATE


# 埋点附加：旧版星 UI 标识
func get_dlg_extra() -> Dictionary:
	return {"dlg_star_ui": "dlg_star_ui_0"}
