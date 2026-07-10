class_name AdRewardRestoredPage
extends UIFrameWindow






signal collected(rewards: Array)
signal closed

@onready var _tool_group: HBoxContainer = $Root / Content / DialogRoot / ToolGroup
@onready var _reveal_slot: Control = $Root / Content / DialogRoot / ToolGroup / RevealBtn
@onready var _hint_slot: Control = $Root / Content / DialogRoot / ToolGroup / HintBtn
@onready var _undo_slot: Control = $Root / Content / DialogRoot / ToolGroup / UndoBtn
@onready var _anim: AnimationPlayer = $Root / AnimationPlayer


const _TOOL_SEPARATION_TRIPLE: int = 38
const _TOOL_SEPARATION_DOUBLE: int = 104


const _OBTAIN_TO_DISMISS_DELAY_FRAMES: int = 12

var _rewards: Array = []
var _closing: bool = false

func _ready() -> void :
    bind_press_release_scale($Root / Content / DialogRoot / CloseButton)


func on_show(params: Dictionary = {}) -> void :
    _closing = false
    _rewards = params.get("rewards", [])
    _render_rewards(_rewards)
    visible = true
    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")

func on_hide() -> void :

    visible = false


func get_dlg_name() -> String:
    return Tracker.Dlg.REWARD_FAIL



func _render_rewards(rewards: Array) -> void :
    _reveal_slot.visible = false
    _hint_slot.visible = false
    _undo_slot.visible = false
    for r in rewards:
        var slot: Control = _slot_for_kind(str(r.get("kind", "")))
        if slot == null:
            continue
        slot.visible = true
        var count: int = int(r.get("count", 1))
        slot.label_text = "x%d" % count

    var shown: int = int(_reveal_slot.visible) + int(_hint_slot.visible) + int(_undo_slot.visible)
    var sep: int = _TOOL_SEPARATION_TRIPLE if shown >= 3 else _TOOL_SEPARATION_DOUBLE
    _tool_group.add_theme_constant_override("separation", sep)

func _slot_for_kind(kind: String) -> Control:
    match kind:
        "hint": return _hint_slot
        "locate": return _reveal_slot
        "undo": return _undo_slot
        _: return null


func _on_collect_btn_tag_pressed() -> void :
    if _closing:
        return
    _closing = true
    Tracker.track_btn_click(Tracker.Btn.COLLECT, self)
    var snapshot: Array = _rewards.duplicate(true)


    var items: Array = []
    for r in _rewards:
        var kind: String = str(r.get("kind", ""))
        var count: int = int(r.get("count", 0))
        if kind == "" or count <= 0:
            continue
        items.append(AwardItem.make(kind, count))
    if not items.is_empty():
        AwardManager.dispatch(items, AwardManager.DisplayType.DIRECT, Tracker.PropSource.REWARD_FAIL_DLG)

    var slots: Array = [_reveal_slot, _hint_slot, _undo_slot].filter(
        func(s: Control) -> bool: return s.visible)
    for s in slots:
        s.play_obtain()
    if not slots.is_empty():
        await slots[0].obtain_finished

        for _i in _OBTAIN_TO_DISMISS_DELAY_FRAMES:
            await get_tree().process_frame
    await _play_dismiss()

    collected.emit(snapshot)

func _on_close_btn_pressed() -> void :
    close()
    closed.emit()

func close() -> void :
    if _closing:
        return
    _closing = true
    await _play_dismiss()


func _play_dismiss() -> void :
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished
    visible = false
