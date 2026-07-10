class_name RateUsPageV2
extends RateUsPage











const _STAR_FILL_AT: float = 0.3


func _get_anim_name() -> StringName:
    return &"GenericPopupV2"


func on_show(_params: Dictionary = {}) -> void :
    _closing = false
    _select_stars(0)
    _anim.play_section_with_markers(_get_anim_name(), &"", &"Mark")
    while _anim.is_playing() and _anim.current_animation_position < _STAR_FILL_AT:
        await get_tree().process_frame
    _select_stars(5)






func get_dlg_extra() -> Dictionary:
    return {"dlg_star_ui": "dlg_star_ui_1"}
