class_name SwipeZoneDebugOverlay
extends Control








var _slot: int = 0
var _padding: int = 0
var _n: int = 0
var _enabled: bool = false
var _lock: Dictionary = {}

func _ready() -> void :
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    z_index = 100


func configure(slot_px: int, padding: int, puzzle_size: int) -> void :
    _slot = slot_px
    _padding = padding
    _n = puzzle_size
    _lock = {}
    queue_redraw()


func set_enabled(on: bool) -> void :
    _enabled = on
    queue_redraw()


func set_zone(lock: Dictionary) -> void :
    _lock = lock
    if _enabled:
        queue_redraw()


func _draw() -> void :
    if not _enabled or _lock.is_empty():
        return
    var extent: float = _padding * 2 + _slot * _n
    var idx: int = _lock["value"]
    var tol: float = _lock["tol"]
    var core0: float = _padding + idx * _slot
    var core1: float = _padding + (idx + 1) * _slot
    var band0: float = core0 - tol
    var band1: float = core1 + tol
    var fill: = Color(0.1, 0.9, 0.35, 0.16)
    var core: = Color(0.1, 0.9, 0.35, 0.3)
    var edge: = Color(0.1, 1.0, 0.45, 0.95)
    if _lock["axis"] == SwipeAxisGuard.Axis.ROW:
        draw_rect(Rect2(0.0, band0, extent, band1 - band0), fill)
        draw_rect(Rect2(0.0, core0, extent, core1 - core0), core)
        draw_line(Vector2(0.0, band0), Vector2(extent, band0), edge, 3.0)
        draw_line(Vector2(0.0, band1), Vector2(extent, band1), edge, 3.0)
    else:
        draw_rect(Rect2(band0, 0.0, band1 - band0, extent), fill)
        draw_rect(Rect2(core0, 0.0, core1 - core0, extent), core)
        draw_line(Vector2(band0, 0.0), Vector2(band0, extent), edge, 3.0)
        draw_line(Vector2(band1, 0.0), Vector2(band1, extent), edge, 3.0)
