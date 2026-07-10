extends Node
















const SUPPORTED_LANGS: Array[String] = [
    "en", "zh", "pt", "hi", "id", "in", "fil", "tl", "ru", "ja", "de", "fr", 
    "ko", "es", "az", "be", "hr", "cs", "da", "ar", "fi", "el", "hu", "fa", 
    "he", "iw", "it", "lt", "ms", "nl", "no", "nb", "pl", "ro", "sk", "sv", 
    "th", "tr", "uk", "uz", "vi", "af", "am", "bn", "bs", "ca", "gu", "is", 
    "kk", "km", "kn", "lo", "mk", "ml", "mn", "mr", "ne", "pa", "si", "sl", 
    "sr", "sw", "ta", "te", "ur", 
]




const SYS_LANG_ALIAS: Dictionary = {"tl": "fil", "in": "id", "iw": "he", "no": "nb"}


const FALLBACK_LOCALE: String = "en"


func apply_system_locale() -> void :


    var apply_loc: String = GameState.get_apply_locale()
    if apply_loc != "":
        TranslationServer.set_locale(apply_loc)
        return
    TranslationServer.set_locale(resolve_system_locale())



func resolve_system_locale() -> String:
    var sys_lang: String = OS.get_locale_language()
    if sys_lang in SUPPORTED_LANGS:
        return SYS_LANG_ALIAS[sys_lang] if SYS_LANG_ALIAS.has(sys_lang) else OS.get_locale()
    return FALLBACK_LOCALE


func set_locale(locale: String) -> void :
    TranslationServer.set_locale(locale)


func get_locale() -> String:
    return TranslationServer.get_locale()
