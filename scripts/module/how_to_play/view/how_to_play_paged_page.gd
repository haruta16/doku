class_name HowToPlayPagedPage
extends UIFrameWindow

























signal closed

const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

const _SLOT: int = 108
const _CELL_GAP: int = 4
const _CELL_RAD: int = 8
const _BOARD_PX: float = 810.0
const _BOARD_TOP: float = 653.0

const _CLIP_TOP: float = 608.0
const _CLIP_W: float = 900.0



const _PAL_BLUE: int = 8
const _PAL_PINK: int = 1
const _PAL_YELLOW: int = 5
var _palette: PackedColorArray = PackedColorArray()


const _FPS: float = 60.0
const _CROSS_STEP_FRAMES: int = 6
const _START_DELAY_FRAMES: int = 6
const _HOLD_AFTER: float = 1.6



const _SLIDE_SEC: float = 16.0 / 60.0
const _SLIDE_DX: float = _CLIP_W








var _PAGES: Array = [
    {
        "colors": ["BBBY", "BBYY", "BBPY", "BBPY"], 
        "cat": Vector2i(0, 1), 
        "error": {"frame": 72, "cell": Vector2i(2, 0)}, 
        "cross_waves": [
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
        "cross_waves": [
            {"frame": 72, "cells": [Vector2i(0, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]}, 
            {"frame": 108, "cells": [Vector2i(1, 0), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4)]}, 
        ], 
        "caption": "GAME_RULE_ONE_PER_LINE", 
    }, 
    {
        "colors": ["PBBB", "PYBB", "PYBB", "PYYB"], 
        "cat": Vector2i(1, 1), 
        "error": {}, 
        "cross_waves": [
            {"frame": 72, "cells": [
                Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), 
                Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1), 
            ]}, 
        ], 
        "caption": "GAME_RULE_NO_TOUCH", 
    }, 
]

@onready var _holders: Array = [$Root / Content / BoardClip / Board1, $Root / Content / BoardClip / Board2, $Root / Content / BoardClip / Board3]
@onready var _caption: RichTextLabel = $Root / Content / Caption
@onready var _back_btn: Button = $Root / Content / ButtonRow / BackBtn
@onready var _main_btn: Button = $Root / Content / ButtonRow / MainBtn
@onready var _main_label: Label = $Root / Content / ButtonRow / MainBtn / Label
@onready var _anim: AnimationPlayer = $Root / AnimationPlayer





const _HIGHLIGHT_COLOR: String = "#d94848"
const _RULE_HIGHLIGHTS: Dictionary = {
    "GAME_RULE_ONE_PER_COLOR": {"en": "color", "zh": "颜色"}, 
    "GAME_RULE_ONE_PER_LINE": {"en": "column and row", "zh": "同行同列"}, 
    "GAME_RULE_NO_TOUCH": {"en": "adjacent", "zh": "相邻"}, 
}

var _cells: Array = []
var _board_rest_x: Array = []
var _slide_tween: Tween = null
var _built: bool = false
var _page: int = 0

var _demo_token: int = 0

var _closing: bool = false

func _ready() -> void :
    _center_content()
    _build_boards()




func _center_content() -> void :
    var c: = get_node_or_null("Root/Content") as Control
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

func on_show(_params: Dictionary = {}) -> void :
    _closing = false

    SoundManager.set_silent(true)
    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")
    _go_to_page(0, false)



func on_hide() -> void :
    if _closing:
        return
    _closing = true
    _stop_demo()
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished


func _on_back_request() -> void :
    _close()

func _on_close_btn_pressed() -> void :
    _close()


func _on_back_btn_pressed() -> void :
    if _page > 0:
        _go_to_page(_page - 1)


func _on_main_btn_pressed() -> void :
    if _page >= _PAGES.size() - 1:
        _close()
    else:
        _go_to_page(_page + 1)

func _close() -> void :
    closed.emit()
    UIManager.hide_ui(UiName.HOW_TO_PLAY_PAGED)

func _stop_demo() -> void :
    _demo_token += 1
    SoundManager.set_silent(false)

func _char_color(ch: String) -> Color:
    if _palette.is_empty():
        _palette = BoardView.resolve_region_palette()
    var idx: int = _PAL_BLUE
    match ch:
        "P": idx = _PAL_PINK
        "Y": idx = _PAL_YELLOW
    return _palette[idx] if idx < _palette.size() else Color(0.5, 0.5, 0.5)


func _build_boards() -> void :
    if _built:
        return
    _built = true
    for p in range(_PAGES.size()):
        var holder: Control = _holders[p]
        var colors: Array = _PAGES[p]["colors"]
        var rows: int = colors.size()
        var cols: int = (colors[0] as String).length()

        var native: float = float(maxi(rows, cols) * _SLOT)
        var board_scale: float = _BOARD_PX / native
        holder.scale = Vector2(board_scale, board_scale)

        var content_w: float = cols * _SLOT * board_scale

        holder.position = Vector2((_CLIP_W - content_w) / 2.0, _BOARD_TOP - _CLIP_TOP)
        _board_rest_x.append(holder.position.x)



        var card_pad: float = 14.0 / board_scale
        var card: = Panel.new()
        card.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.position = Vector2( - card_pad, - card_pad)
        card.size = Vector2(native + 2.0 * card_pad, native + 2.0 * card_pad)
        var card_sb: = StyleBoxFlat.new()
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
                cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
                holder.add_child(cell)
                cell.set_region_color(_char_color((colors[r] as String)[c]))
                cell.set_corner_radius(_CELL_RAD)
                cell.change_state({"state": CellState.EMPTY, "play_anim": false})
                row_cells.append(cell)
            board_cells.append(row_cells)
        _cells.append(board_cells)



func _go_to_page(i: int, slide: bool = true) -> void :
    var prev: int = _page
    _page = clampi(i, 0, _PAGES.size() - 1)
    for p in range(_holders.size()):
        (_holders[p] as Control).visible = (p == _page)
    _caption.text = _build_rule_caption(_PAGES[_page]["caption"])
    _refresh_buttons()
    if slide:
        _animate_switch(1 if _page >= prev else -1)
    else:
        _clear_slide()
    _demo_token += 1
    _run_demo(_demo_token, _page)



func _animate_switch(dir: int) -> void :
    if _slide_tween != null and _slide_tween.is_valid():
        _slide_tween.kill()
    var holder: Control = _holders[_page] as Control
    var rest_x: float = float(_board_rest_x[_page])
    holder.position.x = rest_x + float(dir) * _SLIDE_DX
    _slide_tween = create_tween()
    _slide_tween.tween_property(holder, "position:x", rest_x, _SLIDE_SEC)\
.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _clear_slide() -> void :
    if _slide_tween != null and _slide_tween.is_valid():
        _slide_tween.kill()
    if _page < _board_rest_x.size():
        (_holders[_page] as Control).position.x = float(_board_rest_x[_page])




func _refresh_buttons() -> void :
    var is_first: bool = _page == 0
    var is_last: bool = _page == _PAGES.size() - 1
    _back_btn.visible = not is_first
    _main_label.text = "HOW_TO_PLAY_GOT_IT" if is_last else "HOW_TO_PLAY_NEXT"
    if is_first:
        _main_btn.offset_left = 260.0
        _main_btn.offset_right = 820.0
    else:
        _main_btn.offset_left = 365.0
        _main_btn.offset_right = 925.0



func _build_rule_caption(rule_key: String) -> String:
    var text: String = tr(rule_key)
    var lang: String = TranslationServer.get_locale().get_slice("_", 0)
    var map: Dictionary = _RULE_HIGHLIGHTS.get(rule_key, {})
    var kw: String = String(map.get(lang, ""))
    if kw != "" and text.contains(kw):
        text = text.replace(kw, "[color=%s]%s[/color]" % [_HIGHLIGHT_COLOR, kw])
    return "[center]%s[/center]" % text


func _reset_page(page: int) -> void :
    for r in range(_cells[page].size()):
        for c in range((_cells[page][r] as Array).size()):

            (_cells[page][r][c] as CellView).change_state({"state": CellState.EMPTY, "play_anim": false})



func _run_demo(token: int, page: int) -> void :
    var data: Dictionary = _PAGES[page]
    var cat: Vector2i = data["cat"]

    var events: Array = []
    var err: Dictionary = data["error"]
    if not err.is_empty():
        events.append({"frame": int(err["frame"]), "cell": err["cell"], "error": true})
    for wave: Dictionary in data["cross_waves"]:
        var base: int = int(wave["frame"])
        var cells: Array = wave["cells"]
        for k in range(cells.size()):
            events.append({"frame": base + k * _CROSS_STEP_FRAMES, "cell": cells[k], "error": false})
    events.sort_custom( func(a: Dictionary, b: Dictionary) -> bool: return int(a["frame"]) < int(b["frame"]))
    while token == _demo_token and visible:
        _reset_page(page)
        if not await _wait_frames(_START_DELAY_FRAMES, token):
            return
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
            c.change_state({"state": CellState.ERROR if bool(e["error"]) else CellState.MARK})
        if not await _wait(_HOLD_AFTER, token):
            return

func _cell(page: int, c: Vector2i) -> CellView:
    return _cells[page][c.x][c.y] as CellView






func _ensure_cat_particles(token: int, page: int, c: Vector2i) -> void :
    await get_tree().create_timer(8.0 / _FPS).timeout
    if token != _demo_token or not visible:
        return
    var fx: Control = _cell(page, c).get_node_or_null("EffectCatIconAppear2") as Control
    if fx == null:
        return
    for child in fx.get_children():
        if child is CPUParticles2D:
            (child as CPUParticles2D).restart()


func _wait_frames(frames: int, token: int) -> bool:
    return await _wait(float(frames) / _FPS, token)


func _wait(sec: float, token: int) -> bool:
    await get_tree().create_timer(sec).timeout
    return token == _demo_token and visible
