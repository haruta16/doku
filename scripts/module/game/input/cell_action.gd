# 棋盘操作数据包（命令对象）：一次改格请求的全部参数，输入层产出、页面解释执行
class_name CellAction
extends RefCounted

# 动作类型：SET_STATE 直接设格子状态 / DOUBLE_TAP 双击（页面据此判答案或记错） / SET_DRAFT 改草稿
enum Kind {
	SET_STATE,
	DOUBLE_TAP,
	SET_DRAFT,
}

# ---- 目标与内容 ----
var kind: int = Kind.SET_STATE # 动作类型，见 Kind
var row: int = -1 # 目标行号，-1 表示未指定
var col: int = -1 # 目标列号，-1 表示未指定
var state: int = CellState.EMPTY # 目标状态，取 CellState 常量
var before: int = CellState.EMPTY # 改动前的状态，用于撤销与步数记录
# ---- 表现、记录与反馈开关（下游按需读取） ----
var play_anim: bool = true # 是否播放落子/标记动画
var show_cat_visual: bool = true # 是否显示猫的贴图
var record: bool = true # 是否计入步数历史
var vibrate: int = -1 # 震动等级，-1 表示不震动
var source: int = BoardView.ChangeSource.USER_ACTION # 改动来源，见 BoardView.ChangeSource


# 造一个 SET_STATE 动作：把 (r,c) 从 before_state 改成 target
static func set_cell(
	r: int,
	c: int,
	before_state: int,
	target: int,
	vib: int = -1,
	do_record: bool = true,
	src: int = BoardView.ChangeSource.USER_ACTION
) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.SET_STATE
	a.row = r
	a.col = c
	a.before = before_state
	a.state = target
	a.vibrate = vib
	a.record = do_record
	a.source = src
	return a


# 造一个 DOUBLE_TAP 动作：只带坐标，具体含义由页面判定
static func double_tap(r: int, c: int) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.DOUBLE_TAP
	a.row = r
	a.col = c
	return a


# 造一个 SET_DRAFT 动作：把格子草稿设为 mark
static func set_draft(r: int, c: int, mark: int) -> CellAction:
	var a := CellAction.new()
	a.kind = Kind.SET_DRAFT
	a.row = r
	a.col = c
	a.state = mark
	return a
