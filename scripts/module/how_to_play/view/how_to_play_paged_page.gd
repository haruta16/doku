# 分页版玩法说明（注册名 UiName.HOW_TO_PLAY_PAGED）：一页讲一条规则，共 3 页，底部按钮翻页
# 每页一块演示棋盘循环播动画；最后一页按钮变成「我知道了」并关闭本页
class_name HowToPlayPagedPage
extends UIFrameWindow

# 关闭后广播，供调用方（设置页）续接后续流程
signal closed # 本页自己只是隐藏，不做跳转

# 演示棋盘用的格子场景（只展示，不接收输入）
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

# ---- 演示棋盘尺寸与版式（设计稿坐标） ----
const _SLOT: int = 108 # 格子原生边长（像素）
const _CELL_GAP: int = 4 # 格子之间额外留的缝（像素）
const _CELL_RAD: int = 8 # 格子圆角（像素）
const _BOARD_PX: float = 810.0 # 棋盘渲染边长（像素），三页按格数缩放对齐
const _BOARD_TOP: float = 653.0 # 棋盘顶边（像素）

const _CLIP_TOP: float = 608.0 # 裁剪容器顶边（像素）
const _CLIP_W: float = 900.0 # 裁剪容器宽（像素），也是翻页滑动距离

# ---- 演示配色：直接取调色板里的固定下标 ----
const _PAL_BLUE: int = 8 # 调色板下标：蓝
const _PAL_PINK: int = 1 # 调色板下标：粉
const _PAL_YELLOW: int = 5 # 调色板下标：黄
var _palette: PackedColorArray = PackedColorArray() # 调色板缓存，首次使用时从 BoardView 取

# ---- 演示动画时间轴（帧数按 60 FPS 折算成秒） ----
const _FPS: float = 60.0 # 时间轴基准帧率
const _CROSS_STEP_FRAMES: int = 6 # 同一波叉之间的间隔（帧）
const _START_DELAY_FRAMES: int = 6 # 每轮开播前的等待（帧）
const _HOLD_AFTER: float = 1.6 # 演完一轮后停留多久（秒）再看下一轮

const _SLIDE_SEC: float = 16.0 / 60.0 # 翻页滑动时长（秒）
const _SLIDE_DX: float = _CLIP_W # 翻页滑动起始偏移（像素）= 一个容器宽

# ---- 三页数据：颜色串 + 猫的位置 + 打叉波次 + 文案 key ----
# colors 每行一个字符串（B 蓝 P 粉 Y 黄）；error 为空字典表示这页不做错误示范
var _PAGES: Array = [
	{
		"colors": ["BBBY", "BBYY", "BBPY", "BBPY"],
		"cat": Vector2i(0, 1),
		"error": {"frame": 72, "cell": Vector2i(2, 0)},
		"cross_waves":
		[
			{"frame": 163, "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0)]},
			{"frame": 194, "cells": [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]},
			{"frame": 223, "cells": [Vector2i(0, 2)]},
		],
		"caption": "GAME_RULE_ONE_PER_COLOR",
	},
	{
		"colors": ["PBBBB", "PYBBB", "PYBBB", "PYBBB", "PBBBB"],
		"cat": Vector2i(1, 1),
		"error": {},
		"cross_waves":
		[
			{
				"frame": 72,
				"cells": [Vector2i(0, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
			},
			{
				"frame": 108,
				"cells": [Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4)]
			},
		],
		"caption": "GAME_RULE_ONE_PER_LINE",
	},
	{
		"colors": ["PBBB", "PYBB", "PYBB", "PYYB"],
		"cat": Vector2i(1, 1),
		"error": {},
		"cross_waves":
		[
			{
				"frame": 72,
				"cells":
				[
					Vector2i(2, 0),
					Vector2i(1, 0),
					Vector2i(0, 0),
					Vector2i(0, 1),
					Vector2i(0, 2),
					Vector2i(1, 2),
					Vector2i(2, 2),
					Vector2i(2, 1),
				]
			},
		],
		"caption": "GAME_RULE_NO_TOUCH",
	},
]

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _holders: Array = [
	$Root/Content/BoardClip/Board1, $Root/Content/BoardClip/Board2, $Root/Content/BoardClip/Board3
]
@onready var _caption: RichTextLabel = $Root/Content/Caption # 底部规则文案
@onready var _back_btn: Button = $Root/Content/ButtonRow/BackBtn # 上一页（第 1 页隐藏）
@onready var _main_btn: Button = $Root/Content/ButtonRow/MainBtn # 下一页 / 我知道了
@onready var _main_label: Label = $Root/Content/ButtonRow/MainBtn/Label # 主按钮上的文字
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 页面级动画播放器

# ---- 文案高亮：把规则关键词染红 ----
# _RULE_HIGHLIGHTS：文案 key → 各语言里要染红的关键词
const _HIGHLIGHT_COLOR: String = "#d94848"
const _RULE_HIGHLIGHTS: Dictionary = {
	"GAME_RULE_ONE_PER_COLOR": {"en": "color", "zh": "颜色"},
	"GAME_RULE_ONE_PER_LINE": {"en": "column and row", "zh": "同行同列"},
	"GAME_RULE_NO_TOUCH": {"en": "adjacent", "zh": "相邻"},
}

# ---- 运行时状态 ----
var _cells: Array = [] # 三页棋盘的 CellView 二维数组
var _board_rest_x: Array = [] # 每页棋盘的静止 X（翻页动画的落点）
var _slide_tween: Tween = null # 翻页滑动补间
var _built: bool = false # 棋盘只搭一次
var _page: int = 0 # 当前页号，从 0 开始

var _demo_token: int = 0 # 演示协程令牌：自增即让旧协程退出

var _closing: bool = false # 正在播关闭动画，避免动画重入


# ================= 生命周期与版式 =================
# 居中内容容器，并搭出三页棋盘
func _ready() -> void:
	_center_content()
	_build_boards()


# 把 Content 容器锚到屏幕中心（设计稿 1080×2400 坐标系）
func _center_content() -> void:
	var c := get_node_or_null("Root/Content") as Control
	if c == null:
		return
	c.anchor_left = 0.5
	c.anchor_top = 0.5
	c.anchor_right = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -540.0
	c.offset_top = -1200.0
	c.offset_right = 540.0
	c.offset_bottom = 1200.0


# ================= 打开、关闭与翻页 =================
# 每次打开：复位关闭标记、静音、播开场动画，并回到第 1 页
func on_show(_params: Dictionary = {}) -> void:
	_closing = false # 复位，允许收场动画再播一次

	SoundManager.set_silent(true) # 与 _stop_demo 里的 false 成对
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark") # 只播开场片段（到 Mark 为止）
	_go_to_page(0, false) # 打开时直接落在第 1 页，不播滑动


# 隐藏时反向播一遍开场动画（先停演示、恢复声音）
func on_hide() -> void:
	if _closing:
		return
	_closing = true # 防重入：收场动画只播一次
	_stop_demo()
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"") # 反向播：从 Mark 到片段结尾
	await _anim.animation_finished


# ESC 返回键：等同于关闭
func _on_back_request() -> void:
	_close()


# 右上角关闭按钮
func _on_close_btn_pressed() -> void:
	_close()


# 「上一页」按钮：已经在第 1 页则不动
func _on_back_btn_pressed() -> void:
	if _page > 0: # 第 1 页没有上一页
		_go_to_page(_page - 1)


# 「下一页 / 我知道了」按钮：最后一页改为关闭
func _on_main_btn_pressed() -> void:
	if _page >= _PAGES.size() - 1: # 最后一页：按钮变成「我知道了」
		_close()
	else:
		_go_to_page(_page + 1)


# 广播 closed 并让 UIManager 隐藏本页
func _close() -> void:
	closed.emit()
	UIManager.hide_ui(UiName.HOW_TO_PLAY_PAGED)


# 停演示：令牌自增 + 取消静音
func _stop_demo() -> void:
	_demo_token += 1 # 令牌变化 → 正在跑的演示协程自行退出
	SoundManager.set_silent(false) # 恢复声音


# ================= 演示棋盘搭建 =================
# 把颜色字符（B / P / Y）换成调色板里的颜色
func _char_color(ch: String) -> Color:
	if _palette.is_empty():
		_palette = BoardView.resolve_region_palette()
	var idx: int = _PAL_BLUE
	match ch:
		"P":
			idx = _PAL_PINK
		"Y":
			idx = _PAL_YELLOW
	return _palette[idx] if idx < _palette.size() else Color(0.5, 0.5, 0.5)


# 一次搭出三页棋盘：按格数缩放、垫白卡、逐格建 CellView
func _build_boards() -> void:
	if _built:
		return
	_built = true
	for p in range(_PAGES.size()):
		var holder: Control = _holders[p]
		var colors: Array = _PAGES[p]["colors"]
		var rows: int = colors.size()
		var cols: int = (colors[0] as String).length() # 列数取第一行字符串长度

		# 棋盘原生边长（像素，取行列为长边）
		var native: float = float(maxi(rows, cols) * _SLOT)
		# 统一缩放到 _BOARD_PX
		var board_scale: float = _BOARD_PX / native
		holder.scale = Vector2(board_scale, board_scale)

		var content_w: float = cols * _SLOT * board_scale

		# 水平居中，Y 用裁剪容器内的相对坐标
		holder.position = Vector2((_CLIP_W - content_w) / 2.0, _BOARD_TOP - _CLIP_TOP)
		# 记下静止位，翻页动画要回到这里
		_board_rest_x.append(holder.position.x)

		# 白卡外扩 14 像素（按缩放折算回原生坐标）
		var card_pad: float = 14.0 / board_scale
		var card := Panel.new()
		# 白卡只是背景，不吃输入
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.position = Vector2(-card_pad, -card_pad)
		card.size = Vector2(native + 2.0 * card_pad, native + 2.0 * card_pad)
		var card_sb := StyleBoxFlat.new()
		card_sb.bg_color = Color(1, 1, 0.992157, 1)
		card_sb.set_corner_radius_all(int(round(19.0 / board_scale)))
		card_sb.shadow_color = Color(0.898039, 0.827451, 0.764706, 0.1)
		card_sb.shadow_size = int(round(14.0 / board_scale))
		card_sb.shadow_offset = Vector2(0, 10.0 / board_scale)
		card.add_theme_stylebox_override("panel", card_sb)
		holder.add_child(card)
		var board_cells: Array = []
		for r in range(rows):
			var row_cells: Array = []
			for c in range(cols):
				var cell: CellView = _CELL_SCENE.instantiate() as CellView
				cell.position = Vector2(c * _SLOT + _CELL_GAP, r * _SLOT + _CELL_GAP)
				# 演示格子不吃输入
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
				holder.add_child(cell)
				cell.set_region_color(_char_color((colors[r] as String)[c]))
				cell.set_corner_radius(_CELL_RAD)
				# 初始全空，不播动画
				cell.change_state({"state": CellState.EMPTY, "play_anim": false})
				row_cells.append(cell)
			board_cells.append(row_cells)
		_cells.append(board_cells)


# 切到第 i 页：只显示当前棋盘、换文案与按钮，再重启演示
func _go_to_page(i: int, slide: bool = true) -> void:
	var prev: int = _page
	# 夹回合法页号
	_page = clampi(i, 0, _PAGES.size() - 1)
	for p in range(_holders.size()):
		# 一次只显示一页棋盘
		(_holders[p] as Control).visible = (p == _page)
	_caption.text = _build_rule_caption(_PAGES[_page]["caption"])
	_refresh_buttons()
	if slide:
		# 1 表示往右翻，-1 表示往左翻
		_animate_switch(1 if _page >= prev else -1)
	else:
		_clear_slide()
	# 换页即作废旧演示
	_demo_token += 1
	_run_demo(_demo_token, _page)


# 翻页滑动动画：新棋盘从一侧滑到静止位（缓出）
func _animate_switch(dir: int) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	var holder: Control = _holders[_page] as Control
	var rest_x: float = float(_board_rest_x[_page])
	# 先摆到屏幕外，再滑进来
	holder.position.x = rest_x + float(dir) * _SLIDE_DX
	_slide_tween = create_tween()
	(
		_slide_tween
		. tween_property(holder, "position:x", rest_x, _SLIDE_SEC)
		. set_trans(Tween.TRANS_QUART)
		. set_ease(Tween.EASE_OUT)
	)


# 取消滑动补间并直接把棋盘摆回静止位（打开时用）
func _clear_slide() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if _page < _board_rest_x.size():
		(_holders[_page] as Control).position.x = float(_board_rest_x[_page])


# 按当前页刷新按钮：第 1 页藏「上一页」，最后一页按钮改文案并右移
func _refresh_buttons() -> void:
	var is_first: bool = _page == 0
	var is_last: bool = _page == _PAGES.size() - 1
	_back_btn.visible = not is_first
	# 最后一页改文案
	_main_label.text = "HOW_TO_PLAY_GOT_IT" if is_last else "HOW_TO_PLAY_NEXT"
	if is_first:
		# 第 1 页没有「上一页」，按钮居中变宽
		_main_btn.offset_left = 260.0
		_main_btn.offset_right = 820.0
	else:
		_main_btn.offset_left = 365.0
		_main_btn.offset_right = 925.0


# 给规则文案做居中处理，并把当前语言的关键词染红
func _build_rule_caption(rule_key: String) -> String:
	var text: String = tr(rule_key)
	var lang: String = TranslationServer.get_locale().get_slice("_", 0)
	var map: Dictionary = _RULE_HIGHLIGHTS.get(rule_key, {})
	var kw: String = String(map.get(lang, ""))
	if kw != "" and text.contains(kw):
		text = text.replace(kw, "[color=%s]%s[/color]" % [_HIGHLIGHT_COLOR, kw])
	return "[center]%s[/center]" % text


# ================= 演示动画时间轴 =================
# 把某页棋盘所有格子复位成空
func _reset_page(page: int) -> void:
	for r in range(_cells[page].size()):
		for c in range((_cells[page][r] as Array).size()):
			(_cells[page][r][c] as CellView).change_state(
				{"state": CellState.EMPTY, "play_anim": false}
			)


# 循环播放某页演示：先摆猫，再按帧号依次打叉 / 标错误，播完停留后再来一遍
func _run_demo(token: int, page: int) -> void:
	var data: Dictionary = _PAGES[page]
	# 这一页用来示范的猫的位置
	var cat: Vector2i = data["cat"]

	var events: Array = []
	var err: Dictionary = data["error"]
	if not err.is_empty():
		# error = true 的格子落成 ERROR 状态
		events.append({"frame": int(err["frame"]), "cell": err["cell"], "error": true})
	for wave: Dictionary in data["cross_waves"]:
		var base: int = int(wave["frame"])
		var cells: Array = wave["cells"]
		for k in range(cells.size()):
			events.append(
				{"frame": base + k * _CROSS_STEP_FRAMES, "cell": cells[k], "error": false}
			)
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["frame"]) < int(b["frame"])
	)
	while token == _demo_token and visible:
		# 每轮重播前先清盘
		_reset_page(page)
		if not await _wait_frames(_START_DELAY_FRAMES, token):
			return
		# 播猫出现的动画
		_cell(page, cat).demo_cat(true)
		_ensure_cat_particles(token, page, cat)
		var last_frame: int = 0
		for e: Dictionary in events:
			var f: int = int(e["frame"])
			var dt: float = float(f - last_frame) / _FPS
			if dt > 0.0 and not await _wait(dt, token):
				return
			last_frame = f
			var c: CellView = _cell(page, e["cell"])
			# 错误示范用 ERROR 状态，普通排除用 MARK
			c.change_state({"state": CellState.ERROR if bool(e["error"]) else CellState.MARK})
		if not await _wait(_HOLD_AFTER, token):
			return


# ================= 小工具 =================
# 按页号和坐标取 CellView
func _cell(page: int, c: Vector2i) -> CellView:
	return _cells[page][c.x][c.y] as CellView


# 猫出现动画播到第 8 帧时，重启它自带的粒子特效
func _ensure_cat_particles(token: int, page: int, c: Vector2i) -> void:
	await get_tree().create_timer(8.0 / _FPS).timeout # 等猫出现动画走到第 8 帧
	if token != _demo_token or not visible:
		return
	var fx: Control = _cell(page, c).get_node_or_null("EffectCatIconAppear2") as Control
	if fx == null:
		return
	for child in fx.get_children():
		if child is CPUParticles2D:
			(child as CPUParticles2D).restart()


# 等待若干帧（按 60 FPS 折算成秒）
func _wait_frames(frames: int, token: int) -> bool:
	return await _wait(float(frames) / _FPS, token)


# 等待若干秒；返回 false 表示期间页面被关闭或换过页
func _wait(sec: float, token: int) -> bool:
	await get_tree().create_timer(sec).timeout
	return token == _demo_token and visible
