# 「玩法说明」整页版（注册名 UiName.HOW_TO_PLAY）：三张卡片各放一块只读演示棋盘，循环播放规则动画
# 打开时全局静音，任意点击即关闭；由正式对局页右上角的 info 按钮拉起
class_name HowToPlayPage
extends UIFrameWindow

# 关闭后广播，供调用方续接流程
signal closed # 本页自己只是隐藏，不做跳转

# 演示棋盘用的格子场景：只做展示，鼠标事件全部忽略
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

# ---- 演示棋盘尺寸与渲染参数 ----
const _ROWS: int = 3 # 演示棋盘行数
const _COLS: int = 5 # 演示棋盘列数
const _CELL_PX: float = 100.0 # 格子逻辑边长（像素）
const _RENDER_SLOT: float = 140.0 # 渲染间距（像素，含缝隙）
const _CELL_RAD: int = 7 # 格子圆角（像素）
const _BOARD_SCALE: float = 1.33 # 棋盘整体放大倍数

# ---- 三张卡片、标题与分隔线的版式（1080 宽设计稿坐标） ----
const _CARD_W: float = 717.0 # 卡片宽（像素）
const _CARD_H: float = 434.0 # 卡片高（像素）
const _CARD_X: float = 181.0 # 卡片左边距（像素）
const _CARD_TOP: Array = [403.0, 1021.0, 1640.0] # 三张卡片的上边距（像素）
const _BOARD_MARGIN_Y: float = 12.0 # 棋盘相对卡片顶部的内缩（像素）
const _TITLE_CENTER_DY: float = -70.0 # 标题相对卡片顶部的偏移（像素）

# ---- 两条分隔线的位置 ----
const _DIVIDER_TOP: Array = [863.0, 1488.0] # 两条分隔线的上边距（像素）
const _DIVIDER_X: float = 59.0 # 分隔线左边距（像素）
const _DIVIDER_W: float = 969.0 # 分隔线宽（像素）
const _DIVIDER_H: float = 16.0 # 分隔线高（像素）

# ---- 演示配色：直接取调色板里的固定下标 ----
const _PAL_BLUE: int = 8 # 调色板下标：蓝
const _PAL_PINK: int = 1 # 调色板下标：粉
const _PAL_YELLOW: int = 5 # 调色板下标：黄
var _palette: PackedColorArray = PackedColorArray() # 调色板缓存，首次使用时从 BoardView 取

# ---- 演示动画的时间轴（帧数按 60 FPS 折算成秒） ----
const _FPS: float = 60.0 # 时间轴基准帧率
const _CROSS_STEP_FRAMES: int = 5 # 同一波叉之间的间隔（帧）
const _START_DELAY_FRAMES: int = 6 # 开播前的等待（帧）
const _GAP_FRAMES: int = 12 # 两轮演示之间的间隔（帧）
const _GAP_LAST_FRAMES: int = 24 # 最后一轮结束后的停顿（帧）

# ---- 演示用到的格子动画名与兜底时长 ----
const _CROSS_ANIM: String = "CrossOutAppear_2" # 打叉出现动画
const _ERROR_ANIM: String = "ErrorAppear_2" # 错误格出现动画
const _DISAPPEAR_ANIM: String = "DemoDisappear" # 清场消失动画

const _LEN_CROSS: float = 0.35 # 打叉动画兜底时长（秒）
const _LEN_ERROR: float = 1.1 # 错误动画兜底时长（秒）

# ---- 三块演示棋盘的数据 ----
# 三张卡片依次讲：每色一只 / 同行同列 / 八邻接不相贴；colors 每行一个字符串，B 蓝 P 粉 Y 黄
# frame 是 60 FPS 下的帧号；error 为空字典表示这块不做错误示范
var _DEMOS: Array = [
	{
		"colors": ["BBBBP", "BBBPY", "BBPYP"],
		"cat_appear": [Vector2i(0, 1)],
		"cat_static": [Vector2i(2, 3)],
		"cross_static": [Vector2i(1, 4)],
		"error": {"frame": 72, "cell": Vector2i(2, 1)},
		"cross_waves":
		[
			{"frame": 134, "cells": [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 3)]},
			{"frame": 158, "cells": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)]},
			{"frame": 182, "cells": [Vector2i(2, 0)]},
		],
	},
	{
		"colors": ["PYPYP", "BBBBB", "PYPYP"],
		"cat_appear": [Vector2i(1, 2)],
		"cat_static": [],
		"cross_static": [],
		"error": {},
		"cross_waves":
		[
			{"frame": 72, "cells": [Vector2i(0, 2), Vector2i(2, 2)]},
			{
				"frame": 92,
				"cells": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 3), Vector2i(1, 4)]
			},
		],
	},
	{
		"colors": ["PPBBY", "PBBBP", "YBBPP"],
		"cat_appear": [Vector2i(1, 2)],
		"cat_static": [],
		"cross_static": [],
		"error": {},
		"cross_waves":
		[
			{
				"frame": 72,
				"cells":
				[
					Vector2i(2, 1),
					Vector2i(1, 1),
					Vector2i(0, 1),
					Vector2i(0, 2),
					Vector2i(0, 3),
					Vector2i(1, 3),
					Vector2i(2, 3),
					Vector2i(2, 2),
				]
			},
		],
	},
]

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _holders: Array = [$Root/Content/Board1, $Root/Content/Board2, $Root/Content/Board3] # 三块演示棋盘的挂载点
@onready var _cards: Array = [$Root/Content/Card1, $Root/Content/Card2, $Root/Content/Card3] # 三张背景卡片
@onready var _titles: Array = [$Root/Content/Title1, $Root/Content/Title2, $Root/Content/Title3] # 三行标题
@onready var _dividers: Array = [$Root/Content/Divider1, $Root/Content/Divider2] # 两条分隔线
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 页面级动画播放器（打开 / 收起）

# ---- 运行时状态 ----
var _cells: Array = [] # 三块棋盘的 CellView 二维数组
var _built: bool = false # 棋盘只搭一次，_ready 防重复

var _demo_token: int = 0 # 演示协程令牌：自增即让旧协程退出


# ================= 生命周期与版式 =================
# 摆好版式并搭出三块演示棋盘
func _ready() -> void:
	_center_content()
	_layout()
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


# 按设计稿坐标摆放三张卡片、标题、棋盘与分隔线
func _layout() -> void:
	var board_render_w: float = 4.0 * _RENDER_SLOT + _CELL_PX * _BOARD_SCALE
	for b in range(_CARD_TOP.size()):
		var top: float = _CARD_TOP[b]
		var card: Panel = _cards[b]
		card.position = Vector2(_CARD_X, top)
		card.size = Vector2(_CARD_W, _CARD_H)
		var title: Label = _titles[b]
		title.position = Vector2(0.0, top + _TITLE_CENTER_DY - 40.0)
		title.size = Vector2(1080.0, 80.0)
		var holder: Control = _holders[b]
		holder.scale = Vector2(_BOARD_SCALE, _BOARD_SCALE)
		holder.position = Vector2(_CARD_X + (_CARD_W - board_render_w) / 2.0, top + _BOARD_MARGIN_Y)

	for d in range(_DIVIDER_TOP.size()):
		var divider: NinePatchRect = _dividers[d]
		divider.position = Vector2(_DIVIDER_X, _DIVIDER_TOP[d])
		divider.size = Vector2(_DIVIDER_W, _DIVIDER_H)


# ================= 打开与关闭 =================
# 每次打开：全局静音 + 播开场动画，然后重启演示协程
func on_show(_params: Dictionary = {}) -> void:
	SoundManager.set_silent(true) # 与 _stop_demo 里的 false 成对

	_anim.play_section_with_markers("GenericPopup", &"", &"Mark") # 只播开场片段（到 Mark 为止）
	_demo_token += 1
	_run_demo(_demo_token) # 不 await：让演示自己跑，随时可被令牌打断


# 页面隐藏时停掉演示并恢复声音
func on_hide() -> void:
	_stop_demo()


# ESC 返回键（UIFrameWindow.on_escape 会调到这里）
func _on_back_request() -> void:
	_close()


# 全局输入：本页是最上层可见窗口时，任意点击都关闭
func _input(event: InputEvent) -> void:
	if not visible or not _is_topmost_visible_page():
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if is_press:
		get_viewport().set_input_as_handled()
		_close()


# 对外广播 closed，并让 UIManager 隐藏本页
func _close() -> void:
	closed.emit()
	UIManager.hide_ui(UiName.HOW_TO_PLAY)


# 判断自己是不是同级里最上层且可见的窗口（避免抢了下层弹窗的点击）
func _is_topmost_visible_page() -> bool:
	if not is_inside_tree():
		return false
	var parent := get_parent()
	if parent == null:
		return true
	for sibling in parent.get_children():
		if sibling == self or not (sibling is UIFrameWindow):
			continue
		var s := sibling as Control
		if s.visible and s.z_index > z_index:
			return false
	return true


# 停演示：令牌自增让协程退出，并恢复声音
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


# 一次搭出三块演示棋盘的所有格子（初始全空）
func _build_boards() -> void:
	if _built:
		return
	_built = true
	var slot_unscaled: float = _RENDER_SLOT / _BOARD_SCALE # 先按格子原生尺寸排布，最后整体缩放
	for b in range(_DEMOS.size()):
		var holder: Control = _holders[b]
		var colors: Array = _DEMOS[b]["colors"]
		var board_cells: Array = []
		for r in range(_ROWS):
			var row_cells: Array = []
			for c in range(_COLS):
				var cell: CellView = _CELL_SCENE.instantiate() as CellView
				cell.position = Vector2(c * slot_unscaled, r * slot_unscaled)
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE # 演示格子不吃输入
				holder.add_child(cell)
				cell.set_region_color(_char_color((colors[r] as String)[c]))
				cell.set_corner_radius(_CELL_RAD)
				cell.change_state({"state": CellState.EMPTY, "play_anim": false}) # 初始全空，不播动画
				row_cells.append(cell)
			board_cells.append(row_cells)
		_cells.append(board_cells)


# ================= 演示动画时间轴 =================
# 演示主循环：先把后两块摆成完成态，再逐块循环播放动画
func _run_demo(token: int) -> void:
	_reset_all()

	for i in range(1, _DEMOS.size()):
		_fill_demo_complete(i) # 后两块先摆成完成态，轮到它们时再重播一遍
	if not await _wait_frames(_START_DELAY_FRAMES, token):
		return
	if not await _play_demo(0, token):
		return
	var cur: int = 0
	while token == _demo_token and visible:
		var nxt: int = (cur + 1) % _DEMOS.size()
		var gap: int = _GAP_LAST_FRAMES if cur == _DEMOS.size() - 1 else _GAP_FRAMES # 最后一轮多停一会儿
		if not await _wait_frames(gap, token):
			return
		if not await _clear_board(nxt, token):
			return
		if not await _play_demo(nxt, token):
			return
		cur = nxt


# 播一块棋盘的演示：把各格动画按帧号排序后依次触发；返回 false 表示被中断
func _play_demo(idx: int, token: int) -> bool:
	var demo: Dictionary = _DEMOS[idx]

	for c: Vector2i in demo["cat_appear"]:
		_cell(idx, c).demo_cat(true) # true = 播出现动画（带动效）
	for c: Vector2i in demo["cat_static"]:
		_cell(idx, c).demo_cat(false) # false = 直接摆好
	for c: Vector2i in demo["cross_static"]:
		_cell(idx, c).demo_play(_CROSS_ANIM, true) # true = 停在动画最后一帧（定格）

	var events: Array = []
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		events.append({"frame": int(err["frame"]), "cell": err["cell"], "anim": _ERROR_ANIM})
	for wave: Dictionary in demo["cross_waves"]:
		var base: int = int(wave["frame"])
		var cells: Array = wave["cells"]
		for k in range(cells.size()):
			events.append(
				{"frame": base + k * _CROSS_STEP_FRAMES, "cell": cells[k], "anim": _CROSS_ANIM}
			)
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["frame"]) < int(b["frame"])
	)

	var last_frame: int = 0
	var demo_end_sec: float = 0.0
	for e: Dictionary in events:
		var f: int = int(e["frame"])
		var dt: float = float(f - last_frame) / _FPS
		if dt > 0.0 and not await _wait(dt, token):
			return false
		last_frame = f
		_cell(idx, e["cell"]).demo_play(e["anim"])
		demo_end_sec = maxf(demo_end_sec, float(f) / _FPS + _anim_len(e["anim"]))
	var tail: float = demo_end_sec - float(last_frame) / _FPS
	if tail > 0.0 and not await _wait(tail, token):
		return false
	return true


# 清场：先播消失动画，再复位格子状态
func _clear_board(idx: int, token: int) -> bool:
	var cells: Array = _clearable_cells(idx)
	if cells.is_empty():
		return true
	for c: Vector2i in cells:
		_cell(idx, c).demo_play(_DISAPPEAR_ANIM) # 全部格一起播消失动画
	if not await _wait(_anim_len(_DISAPPEAR_ANIM), token):
		return false
	for c: Vector2i in cells:
		_cell(idx, c).demo_clear() # 动画播完再复位，避免闪回
	return true


# 需要清场的格子 = 参与演示的格子去掉两块常驻格
func _clearable_cells(idx: int) -> Array:
	var demo: Dictionary = _DEMOS[idx]
	var skip: Dictionary = {}
	for c: Vector2i in demo["cat_static"]:
		skip[c] = true
	for c: Vector2i in demo["cross_static"]:
		skip[c] = true
	var out: Array = []
	for c: Vector2i in _content_cells(idx):
		if not skip.has(c):
			out.append(c)
	return out


# 把某块棋盘一次性摆成「已播完」的样子（静置展示用）
func _fill_demo_complete(idx: int) -> void:
	var demo: Dictionary = _DEMOS[idx]
	for c: Vector2i in demo["cat_appear"]:
		_cell(idx, c).demo_cat(false)
	for c: Vector2i in demo["cat_static"]:
		_cell(idx, c).demo_cat(false)
	for c: Vector2i in demo["cross_static"]:
		_cell(idx, c).demo_play(_CROSS_ANIM, true)
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		_cell(idx, err["cell"]).demo_play(_ERROR_ANIM, true)
	for wave: Dictionary in demo["cross_waves"]:
		for c: Vector2i in wave["cells"]:
			_cell(idx, c).demo_play(_CROSS_ANIM, true)


# 把三块棋盘的所有格子复位成空
func _reset_all() -> void:
	for b in range(_cells.size()):
		for r in range(_ROWS):
			for c in range(_COLS):
				(_cells[b][r][c] as CellView).demo_clear()


# 某块演示里出现过的所有格子坐标
func _content_cells(idx: int) -> Array:
	var demo: Dictionary = _DEMOS[idx]
	var out: Array = []
	out.append_array(demo["cat_appear"])
	out.append_array(demo["cat_static"])
	out.append_array(demo["cross_static"])
	var err: Dictionary = demo["error"]
	if not err.is_empty():
		out.append(err["cell"])
	for wave: Dictionary in demo["cross_waves"]:
		out.append_array(wave["cells"])
	return out


# ================= 小工具 =================
# 按棋盘序号和坐标取 CellView
func _cell(board: int, c: Vector2i) -> CellView:
	return _cells[board][c.x][c.y] as CellView


# 取某个演示动画的时长（秒）：优先问 CellView，拿不到再用常量兜底
func _anim_len(anim_name: String) -> float:
	if not _cells.is_empty():
		var v: float = (_cells[0][0][0] as CellView).demo_anim_length(anim_name)
		if v > 0.0:
			return v
	return _LEN_ERROR if anim_name == _ERROR_ANIM else _LEN_CROSS # 拿不到动画长度时的兜底


# 等待若干帧（按 60 FPS 折算成秒）
func _wait_frames(frames: int, token: int) -> bool:
	return await _wait(float(frames) / _FPS, token)


# 等待若干秒；返回 false 表示期间页面被关闭或重新打开过
func _wait(sec: float, token: int) -> bool:
	await get_tree().create_timer(sec).timeout
	return token == _demo_token and visible
