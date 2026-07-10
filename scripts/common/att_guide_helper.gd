class_name AttGuideHelper
extends Object

















const _SOURCE: String = "splash_scr"










static func try_show_and_wait_dialog_close() -> void :
    var is_test: bool = UniKitManager.debug_force_editor_test
    var att_status: int = UniKitManager.get_att_status()
    var can_request_att: bool = (att_status == UniKitManager.ATT_STATUS_NOT_DETERMINED)





    if ABTestManager.att_dlg_logic.should_skip_custom_guide():
        if can_request_att:
            UniKitManager.show_att_alert(_SOURCE)
            await UniKitManager.att_dismissed
        _reset_debug_flag_if_test(is_test)
        return




    if not GameState.has_shown_att_guide():

        var guide_page: String = "pre_att_guide_v2" if ABTestManager.att_dlg_logic.is_custom_guide_restyled() else "pre_att_guide"
        var page: Node = UIManager.show_ui(guide_page)
        if page == null:


            if not is_test:
                GameState.mark_att_guide_shown()
            if can_request_att:
                UniKitManager.show_att_alert(_SOURCE)
                await UniKitManager.att_dismissed
            _reset_debug_flag_if_test(is_test)
            return
        await page.continued
        UIManager.hide_ui(guide_page)

        if not is_test:
            GameState.mark_att_guide_shown()



    if can_request_att:
        UniKitManager.show_att_alert(_SOURCE)
        await UniKitManager.att_dismissed
    _reset_debug_flag_if_test(is_test)



static func _reset_debug_flag_if_test(is_test: bool) -> void :
    if is_test:
        UniKitManager.debug_force_editor_test = false
