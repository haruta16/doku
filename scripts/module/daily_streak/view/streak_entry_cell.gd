extends UIChildWindow


@onready var _streak_entry_img: Control = $StreakEntryImg
@onready var _streak_txt: Label = $StreakTxt
@onready var _count_badge: Control = $CountBadge
@onready var _click_btn: Button = $ClickBtn





@onready var _state_checked: Control = $StreakEntryImg / StateChecked
@onready var _state_unchecked: Control = $StreakEntryImg / StateUnchecked
@onready var _count_txt: Label = $CountBadge / CountTxt




func on_create() -> void :

    StreakManager.streak_updated.connect(_on_streak_updated)

    _click_btn.button_down.connect( func() -> void : play_press_scale(self))
    _click_btn.button_up.connect( func() -> void : play_release_scale(self))


func on_show(_params: Dictionary = {}) -> void :

    _refresh()


func on_hide() -> void :
    pass


func on_destroy() -> void :
    pass


func _on_streak_updated(_data: StreakData) -> void :
    _refresh()



func _refresh() -> void :
    var checked_today: bool = not StreakManager.can_checkin_today()
    _state_checked.visible = checked_today
    _state_unchecked.visible = not checked_today
    _count_txt.text = str(StreakManager.get_data().current_streak)


func _on_click_pressed() -> void :
    Tracker.track_btn_click(Tracker.Btn.STREAK, self)
    VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
    StreakPage.open_main()
