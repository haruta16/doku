extends UIFrameWindow

const SCENE_PATH: = "res://scripts/module/award/ui/award_page.tscn"
const UI_NAME: = UiName.AWARD

const _GIFT_CELL_SCENE: PackedScene = preload("res://scripts/module/daily_streak/ui/streak_gift_cell.tscn")
const _AWARD_CELL_SCENE: PackedScene = preload("res://scripts/module/award/ui/other/award_cell.tscn")
const _AD_PLACEMENT: String = Tracker.Placement.REWARD
const _AD_POS: String = Tracker.AdPos.STREAK_X2_REWARD


@onready var _award_panel: Control = $AwardPanel
@onready var _gift_open_content: Control = $GiftCenter / GiftOpenContent
@onready var _double_collect_btn: Control = $AwardPanel / DoubleBtnGroup / DoubleCollectBtn
@onready var _collect_btn: Control = $AwardPanel / DoubleBtnGroup / CollectBtn

@onready var _cell_slots: Array[Control] = [
    $AwardPanel / AwardContent / CellSlot1, 
    $AwardPanel / AwardContent / CellSlot2, 
]




var _on_persisted: Callable = Callable()
var _streak_uid: int = -1


@onready var _double_badge: GameAdBadge = $AwardPanel / DoubleBtnGroup / DoubleCollectBtn / Badge
@onready var _anim: AnimationPlayer = $AnimationPlayer


var _ad_settled: bool = false




func on_create() -> void :
    pass


func on_show(params: Dictionary = {}) -> void :
    pass


func on_hide() -> void :


    if _on_persisted.is_valid():
        var cb: Callable = _on_persisted
        _on_persisted = Callable()
        cb.call()
    _streak_uid = -1
    _clear_gift_cells()


func on_destroy() -> void :
    pass






func setup_streak_gift(items: Array, uid: int, on_persisted: Callable) -> void :
    _clear_gift_cells()


    var cell: = create_child(_GIFT_CELL_SCENE)
    if cell:
        cell.reparent(_gift_open_content, false)

    if _anim and _anim.has_animation(&"Appear"):
        _anim.play(&"Appear")

    _render_award_cells(items)
    _streak_uid = uid
    _on_persisted = on_persisted

    var ad_ready: bool = UniKitManager.is_reward_valid(_AD_PLACEMENT, _AD_POS)
    _double_collect_btn.visible = ad_ready
    if ad_ready:

        _double_badge.show_ad()
    _collect_btn.visible = true


func _clear_gift_cells() -> void :
    if _gift_open_content == null:
        return
    for c in _gift_open_content.get_children():
        c.queue_free()




func _render_award_cells(items: Array) -> void :
    for i in range(_cell_slots.size()):
        var slot: Control = _cell_slots[i]
        if slot == null:
            continue
        _clear_award_cells(slot)
        var has_item: bool = i < items.size()
        slot.visible = has_item
        if not has_item:
            continue
        var it = items[i]

        var cell: = create_child(_AWARD_CELL_SCENE, {"kind": str(it.kind), "count": int(it.count)})
        if cell:
            cell.reparent(slot, false)



func _clear_award_cells(slot: Control) -> void :
    for c in slot.get_children():
        if c.has_method("set_award"):
            c.queue_free()




func _on_collect_pressed() -> void :

    UIManager.hide_ui(UiName.AWARD)


func _on_collect_double_pressed() -> void :

    var show_id: = UniKitManager.gen_show_id()
    if not UniKitManager.is_reward_ready(_AD_PLACEMENT, _AD_POS, show_id):
        return
    _ad_settled = false




    if not UniKitManager.ad_rewarded.is_connected(_on_ad_rewarded):
        connect_managed_once(UniKitManager.ad_rewarded, _on_ad_rewarded)
    if not UniKitManager.ad_closed.is_connected(_on_reward_ad_failed):
        connect_managed_once(UniKitManager.ad_closed, _on_reward_ad_failed)
    if not UniKitManager.ad_error_occurred.is_connected(_on_reward_ad_error):
        connect_managed_once(UniKitManager.ad_error_occurred, _on_reward_ad_error)
    UniKitManager.show_reward(_AD_PLACEMENT, _AD_POS, show_id)


func _on_ad_rewarded(placement_id: String) -> void :
    if placement_id != _AD_PLACEMENT or _ad_settled:
        return
    _ad_settled = true
    if _streak_uid >= 0:


        AwardManager.double_award(_streak_uid)
    UIManager.hide_ui(UiName.AWARD)




func _on_reward_ad_failed(placement_id: String) -> void :
    if placement_id != _AD_PLACEMENT or _ad_settled:
        return
    _ad_settled = true
    UIManager.hide_ui(UiName.AWARD)



func _on_reward_ad_error(placement_id: String, _msg: String) -> void :
    _on_reward_ad_failed(placement_id)
