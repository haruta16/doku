# 关卡 JSON 粘贴页：把一段含 regionMap / solution 的 JSON 直接灌进 GAME 页开局，用来复现线上题目与残局
# 只在非 rel 的构建里注册（UIRegistry._DEV_PAGES）；由作弊面板的 level_json 命令打开
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _input: TextEdit = $CenterPanel/Margin/VBox/InputBox # 粘贴 JSON 的文本框
@onready var _error_label: Label = $CenterPanel/Margin/VBox/ErrorLabel # 校验失败时的红字提示


# 每次打开都清掉上一次的错误提示
func on_show(_params: Dictionary = {}) -> void:
	_error_label.text = ""
	_error_label.visible = false # 默认隐藏


# CloseBtn：直接关页面
func _on_close_pressed() -> void:
	UIManager.hide_ui(UiName.LEVEL_JSON_INPUT)


# StartBtn：解析并校验 JSON，通过就带 prebuilt / restore_state 打开 GAME 页
func _on_start_pressed() -> void:
	var raw: String = _input.text.strip_edges()
	if raw.is_empty():
		_show_error("输入为空")
		return

	# 只接受单个 JSON object
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not parsed is Dictionary:
		_show_error("JSON 解析失败,请确认格式正确(应为单个 object)") # 数组或 null 都算失败
		return

	# 走到这里 parsed 一定是 Dictionary，转成带类型的局部变量
	var entry: Dictionary = parsed
	var err: String = _validate(entry)
	if not err.is_empty():
		_show_error(err)
		return

	# size 缺省时取 regionMap 行数；r=关卡序号、id=题库下标
	var sz: int = (
		int(entry["size"]) if entry.has("size") else int((entry["regionMap"] as Array).size())
	)
	var rank: int = int(entry.get("r", 0)) # 难度档 rank，缺省 0
	var idx: int = int(entry.get("id", 0)) # 题库下标，缺省 0

	# solution 是「每行猫所在列」的一维数组，逐项转 int
	var sol_1d: Array = []
	for v in entry["solution"]:
		sol_1d.append(int(v))

	# regionMap 转成纯 int 的二维数组
	var int_regions: Array = []
	for row_arr in entry["regionMap"]:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)

	# 可选的初始棋盘状态：已放的猫 / 叉 / 错标，用于复现残局
	var placed_cats: Array = []
	for pos in entry.get("placed_cats", []):
		placed_cats.append([int(pos[0]), int(pos[1])])
	var marks: Array = []
	for pos in entry.get("marks", []):
		marks.append([int(pos[0]), int(pos[1])])
	var errors: Array = []
	for pos in entry.get("errors", []):
		errors.append([int(pos[0]), int(pos[1])])

	# 打一行日志，方便和线上反馈对照
	print(
		(
			"[level_json] start sz=%d rank=%d id=%d cats=%d marks=%d errors=%d"
			% [sz, rank, idx, placed_cats.size(), marks.size(), errors.size()]
		)
	)
	# 先关掉本页再开游戏页
	UIManager.hide_ui(UiName.LEVEL_JSON_INPUT)
	# bank_mode 加 prebuilt_* 是 GAME 页现成的题库入口，正好复用
	var params: Dictionary = {
		"bank_mode": true,
		"bank_size": sz,
		"bank_rank": rank,
		"bank_index": idx,
		"bank_total": 1,
		"prebuilt_regions": int_regions,
		"prebuilt_solution": sol_1d,
		"level_seed": int(entry.get("seed", idx)),
	}
	# 只有提供了棋盘状态才带 restore_state
	if not placed_cats.is_empty() or not marks.is_empty() or not errors.is_empty():
		params["restore_state"] = {
			"placed_cats": placed_cats,
			"marks": marks,
			"errors": errors,
		}
	UIManager.show_ui(UiName.GAME, params)


# 同时把错误写到界面和 warning 日志
func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	push_warning("[level_json_input] " + msg) # 日志带前缀方便过滤


# 逐项校验 JSON：返回空串表示通过，否则返回给用户看的中文原因
func _validate(entry: Dictionary) -> String:
	# 两个必填字段
	if not entry.has("regionMap"):
		return "缺少字段:regionMap"
	if not entry.has("solution"):
		return "缺少字段:solution"

	var rm: Variant = entry["regionMap"]
	if not rm is Array or (rm as Array).is_empty():
		return "regionMap 必须是非空二维数组"

	# size 缺省时取 regionMap 行数
	var sz: int = int(entry["size"]) if entry.has("size") else (rm as Array).size()
	if sz <= 0:
		return "size 非法:%d" % sz
	# regionMap 的行数必须等于 size
	if (rm as Array).size() != sz:
		return "regionMap 行数应为 %d,实际 %d" % [sz, (rm as Array).size()]

	# 逐行检查列数
	for r in range(sz):
		var row: Variant = (rm as Array)[r]
		if not row is Array or (row as Array).size() != sz:
			return "regionMap 第 %d 行列数应为 %d" % [r, sz]

	# solution 长度必须等于 size，且每项都落在 [0,size) 内
	var sol: Variant = entry["solution"]
	if not sol is Array or (sol as Array).size() != sz:
		return "solution 长度应为 %d,实际 %d" % [sz, (sol as Array).size() if sol is Array else -1]
	for r in range(sz):
		var col: int = int((sol as Array)[r])
		if col < 0 or col >= sz:
			return "solution[%d]=%d 越界(应在 [0,%d))" % [r, col, sz]

	return ""
