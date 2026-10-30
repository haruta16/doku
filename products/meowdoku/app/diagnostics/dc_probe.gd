## 绘制调用探针：按运行帧和界面变化采集渲染指标，并写入本地 CSV 日志。
extends Node

const DEFAULT_CSV_PATH := "user://dc_probe.csv"
const CSV_HEADER := "tag,page,frames,dc_avg,dc_p50,dc_p95,dc_max,items_avg,fps_avg"

const WARMUP_FRAMES := 30

const MIN_FRAMES := 20

var _enabled: bool = false
var _tag: String = "untagged"
var _csv_path: String = DEFAULT_CSV_PATH
var _page: String = ""
var _warmup_left: int = 0
var _dc: PackedFloat32Array = PackedFloat32Array()
var _items_sum: float = 0.0
var _fps_sum: float = 0.0


func _ready() -> void:
	_enabled = not OS.has_feature("rel")
	if not _enabled:
		set_process(false)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dc-tag="):
			_tag = a.substr("--dc-tag=".length())
		elif a.begins_with("--dc-csv-path="):
			_set_csv_path(a.substr("--dc-csv-path=".length()))
	set_process(false)
	UIManager.events.window_shown.connect(_on_window_shown)
	UIManager.events.window_hidden.connect(_on_window_hidden)
	_log("probe armed, tag=%s, csv=%s" % [_tag, ProjectSettings.globalize_path(_csv_path)])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush()


func _process(_delta: float) -> void:
	if _warmup_left > 0:
		_warmup_left -= 1
		return
	_dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_items_sum += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_fps_sum += Performance.get_monitor(Performance.TIME_FPS)


func _on_window_shown(ui_name: String, _win: Object) -> void:
	_flush()
	_page = ui_name
	_warmup_left = WARMUP_FRAMES
	_dc = PackedFloat32Array()
	_items_sum = 0.0
	_fps_sum = 0.0
	set_process(true)


func _on_window_hidden(ui_name: String, _win: Object) -> void:
	if ui_name != _page:
		return
	_flush()
	set_process(false)


func _flush() -> void:
	if not _enabled or _page == "" or _dc.is_empty():
		_page = ""
		return
	var n: int = _dc.size()
	if n < MIN_FRAMES:
		_log("skip %s (仅 %d 帧，样本不足)" % [_page, n])
		_page = ""
		_dc = PackedFloat32Array()
		return
	var sorted: Array[float] = []
	sorted.assign(_dc)
	sorted.sort()
	var total: float = 0.0
	for v in sorted:
		total += v
	var row := (
		"%s,%s,%d,%.1f,%.0f,%.0f,%.0f,%.1f,%.1f"
		% [
			_tag,
			_page,
			n,
			total / n,
			sorted[int(n * 0.5)],
			sorted[mini(int(n * 0.95), n - 1)],
			sorted[n - 1],
			_items_sum / n,
			_fps_sum / n,
		]
	)
	_log(row)
	_append_csv(row)
	_page = ""
	_dc = PackedFloat32Array()


func _set_csv_path(candidate: String) -> void:
	if candidate.begins_with("user://") and candidate.get_file().get_extension() == "csv":
		_csv_path = candidate
		return
	_log("WARN 忽略不安全 dc CSV 路径：%s" % candidate)


## 首次写入表头；已有文件必须表头匹配才追加，避免不同探针版本混写列结构。
func _append_csv(row: String) -> void:
	var exists: bool = FileAccess.file_exists(_csv_path)
	var f: FileAccess = FileAccess.open(
		_csv_path, FileAccess.READ_WRITE if exists else FileAccess.WRITE
	)
	if f == null:
		_log("WARN 写不开 %s" % _csv_path)
		return
	if not exists:
		f.store_line(CSV_HEADER)
	else:
		var existing_header := f.get_line()
		if existing_header != CSV_HEADER:
			_log("WARN CSV 表头不兼容，拒绝追加：%s" % _csv_path)
			f.close()
			return
		f.seek_end()
	f.store_line(row)
	f.close()


func _log(msg: String) -> void:
	print("[DCPROBE] %s" % msg)
