## 关卡 JSON 输入页：校验手工输入的题目数据，通过后打开调试关卡。
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _input: TextEdit = $CenterPanel/Margin/VBox/InputBox # 粘贴 JSON 的文本框
@onready var _error_label: Label = $CenterPanel/Margin/VBox/ErrorLabel # 校验失败时的红字提示


## 每次打开都清掉上一次的错误提示
func on_show(_params: Dictionary = {}) -> void:
	_error_label.text = ""
	_error_label.visible = false # 默认隐藏


## CloseBtn：直接关页面
func _on_close_pressed() -> void:
	UIManager.hide_ui(UiName.LEVEL_JSON_INPUT)


## 解析并规范化输入数值，再以题库模式传入预建盘面和可选操作状态。
func _on_start_pressed() -> void:
	var raw: String = _input.text.strip_edges()
	if raw.is_empty():
		_show_error("输入为空")
		return

	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not parsed is Dictionary:
		_show_error("JSON 解析失败,请确认格式正确(应为单个 object)")
		return

	var entry: Dictionary = parsed
	var err: String = _validate(entry)
	if not err.is_empty():
		_show_error(err)
		return

	var sz: int = (
		int(entry["size"]) if entry.has("size") else int((entry["regionMap"] as Array).size())
	)
	var rank: int = int(entry.get("r", 0))
	var idx: int = int(entry.get("id", 0))

	var sol_1d: Array = []
	for v in entry["solution"]:
		sol_1d.append(int(v))

	var int_regions: Array = []
	for row_arr in entry["regionMap"]:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)

	var placed_cats: Array = []
	for pos in entry.get("placed_cats", []):
		placed_cats.append([int(pos[0]), int(pos[1])])
	var marks: Array = []
	for pos in entry.get("marks", []):
		marks.append([int(pos[0]), int(pos[1])])
	var errors: Array = []
	for pos in entry.get("errors", []):
		errors.append([int(pos[0]), int(pos[1])])

	print(
		(
			"[level_json] start sz=%d rank=%d id=%d cats=%d marks=%d errors=%d"
			% [sz, rank, idx, placed_cats.size(), marks.size(), errors.size()]
		)
	)
	UIManager.hide_ui(UiName.LEVEL_JSON_INPUT)
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
	if not placed_cats.is_empty() or not marks.is_empty() or not errors.is_empty():
		params["restore_state"] = {
			"placed_cats": placed_cats,
			"marks": marks,
			"errors": errors,
		}
	UIManager.show_ui(UiName.GAME, params)

	UIManager.hide_ui(UiName.HOME)


## 同时把错误写到界面和 warning 日志
func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	push_warning("[level_json_input] " + msg) # 日志带前缀方便过滤


## 逐项校验 JSON：返回空串表示通过，否则返回给用户看的中文原因
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
