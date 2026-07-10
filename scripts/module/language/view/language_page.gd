class_name LanguagePage
extends UIFrameWindow






const _OPTION_SCENE: PackedScene = preload("res://scripts/module/language/ui/language_option.tscn")







const _OPTIONS: Array[Dictionary] = [
    {"locale": "en", "native": "English", "key": "LANG_NAME_EN"}, 
    {"locale": "ja", "native": "日本語", "key": "LANG_NAME_JA"}, 
    {"locale": "es", "native": "Español", "key": "LANG_NAME_ES"}, 
    {"locale": "fr", "native": "Français", "key": "LANG_NAME_FR"}, 
    {"locale": "de", "native": "Deutsch", "key": "LANG_NAME_DE"}, 
    {"locale": "ru", "native": "Русский", "key": "LANG_NAME_RU"}, 
    {"locale": "pt", "native": "Português", "key": "LANG_NAME_PT"}, 
    {"locale": "ko", "native": "한국어", "key": "LANG_NAME_KO"}, 
    {"locale": "tr", "native": "Türkçe", "key": "LANG_NAME_TR"}, 
]



const _NATIVE_NAMES: Dictionary = {
    "en": "English", "zh": "简体中文", "pt": "Português", "hi": "हिन्दी", 
    "id": "Bahasa Indonesia", "fil": "Filipino", "ru": "Русский", "ja": "日本語", 
    "de": "Deutsch", "fr": "Français", "ko": "한국어", "es": "Español", 
    "az": "Azərbaycan", "be": "Беларуская", "hr": "Hrvatski", "cs": "Čeština", 
    "da": "Dansk", "ar": "العربية", "fi": "Suomi", "el": "Ελληνικά", 
    "hu": "Magyar", "fa": "فارسی", "he": "עברית", "it": "Italiano", 
    "lt": "Lietuvių", "ms": "Bahasa Melayu", "nl": "Nederlands", "nb": "Norsk", 
    "pl": "Polski", "ro": "Română", "sk": "Slovenčina", "sv": "Svenska", 
    "th": "ไทย", "tr": "Türkçe", "uk": "Українська", "uz": "Oʻzbek", 
    "vi": "Tiếng Việt", "af": "Afrikaans", "am": "አማርኛ", "bn": "বাংলা", 
    "bs": "Bosanski", "ca": "Català", "gu": "ગુજરાતી", "is": "Íslenska", 
    "kk": "Қазақ", "km": "ខ្មែរ", "kn": "ಕನ್ನಡ", "lo": "ລາວ", 
    "mk": "Македонски", "ml": "മലയാളം", "mn": "Монгол", "mr": "मराठी", 
    "ne": "नेपाली", "pa": "ਪੰਜਾਬੀ", "si": "සිංහල", "sl": "Slovenščina", 
    "sr": "Српски", "sw": "Kiswahili", "ta": "தமிழ்", "te": "తెలుగు", 
    "ur": "اردو", 
}

@onready var _scroll: ScrollContainer = $Root / Content / ScrollContainer
@onready var _options_list: VBoxContainer = $Root / Content / ScrollContainer / OptionsList
@onready var _yes_btn: Button = $Root / Content / YesBtn / Bg



@onready var _anim: AnimationPlayer = $Root / AnimationPlayer


var _display: Array[Dictionary] = []
var _option_nodes: Array[LanguageOption] = []
var _selected_index: int = -1



var _press_scroll_v: int = 0
const _SCROLL_TAP_TOLERANCE: int = 6



var _confirmed: bool = false


func on_create() -> void :



    for child in _options_list.get_children():
        _options_list.remove_child(child)
        child.queue_free()





    ScrollDragHelper.attach(_scroll, true)


func on_show(_params: Dictionary = {}) -> void :
    _confirmed = false
    _display = _build_display()
    _ensure_option_nodes(_display.size())


    for i in range(_display.size()):
        var idx: = i

        connect_managed(_option_nodes[i].button_down, func() -> void : _press_scroll_v = _scroll.scroll_vertical)
        connect_managed(_option_nodes[i].pressed, func() -> void : _on_option_pressed(idx))
    connect_managed(_yes_btn.pressed, _on_yes_pressed)
    _refresh_labels()
    _selected_index = _resolve_current_index()
    _refresh_selection()



    _scroll.set_deferred("scroll_vertical", 0)


    _anim.play_section_with_markers("GenericPopup", &"", &"Mark")





func on_hide() -> void :
    if not _confirmed:
        Tracker.track_btn_click(Tracker.Btn.LANGUAGE_CANCEL, self)
    _anim.play_section_with_markers("GenericPopup", &"Mark", &"")
    await _anim.animation_finished




func get_dlg_name() -> String:
    return Tracker.Dlg.LANGUAGE_PICKER



func _build_display() -> Array[Dictionary]:
    var sys: String = LanguageManager.resolve_system_locale()
    var sys_main: String = sys.split("_")[0]
    var matched: int = -1
    for i in range(_OPTIONS.size()):
        if _OPTIONS[i]["locale"] == sys:
            matched = i
            break
    if matched == -1:
        for i in range(_OPTIONS.size()):
            if String(_OPTIONS[i]["locale"]).split("_")[0] == sys_main:
                matched = i
                break
    var list: Array[Dictionary] = []
    if matched != -1:
        list.append(_OPTIONS[matched])
        for i in range(_OPTIONS.size()):
            if i != matched:
                list.append(_OPTIONS[i])
    elif sys_main == "zh":





        list.append({"locale": "zh_CN", "native": _NATIVE_NAMES["zh"], "key": "LANG_NAME_ZH_CN"})
        for opt: Dictionary in _OPTIONS:
            list.append(opt)
    else:



        var native: String = _NATIVE_NAMES.get(sys_main, sys)
        var name_key: String = "LANG_NAME_" + sys_main.to_upper()
        list.append({"locale": sys, "native": native, "key": name_key})
        for opt: Dictionary in _OPTIONS:
            list.append(opt)
    return list



func _ensure_option_nodes(count: int) -> void :
    while _option_nodes.size() < count:
        var opt: = _OPTION_SCENE.instantiate() as LanguageOption
        _options_list.add_child(opt)
        _option_nodes.append(opt)
    for i in range(_option_nodes.size()):
        _option_nodes[i].visible = (i < count)




func _refresh_labels() -> void :
    for i in range(_display.size()):
        var opt: Dictionary = _display[i]
        var key: String = opt["key"]
        var subtitle: String = opt["native"]
        if key != "":
            var translated: String = tr(key)
            if translated != key:
                subtitle = translated
        _option_nodes[i].setup(opt["native"], subtitle)





func _resolve_current_index() -> int:
    var applied: String = GameState.get_apply_locale()
    if applied == "":
        applied = LanguageManager.resolve_system_locale()
    for i in range(_display.size()):
        if _display[i]["locale"] == applied:
            return i

    var main: String = applied.split("_")[0]
    for i in range(_display.size()):
        if String(_display[i]["locale"]).split("_")[0] == main:
            return i

    return -1


func _on_option_pressed(idx: int) -> void :
    if idx < 0 or idx >= _display.size():
        return

    if absi(_scroll.scroll_vertical - _press_scroll_v) > _SCROLL_TAP_TOLERANCE:
        return
    _selected_index = idx
    _refresh_selection()


func _on_yes_pressed() -> void :
    if _selected_index < 0 or _selected_index >= _display.size():
        return
    var locale: String = _display[_selected_index]["locale"]


    Tracker.track_btn_click(Tracker.Btn.LANGUAGE_CONFIRM, self)
    Tracker.track_user_property_ui_language(locale)
    _confirmed = true
    LanguageManager.set_locale(locale)
    GameState.set_apply_locale(locale)
    UIManager.hide_ui(get_ui_name())


func _refresh_selection() -> void :
    for i in range(_display.size()):
        _option_nodes[i].set_selected(i == _selected_index)
