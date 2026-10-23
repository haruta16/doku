## 事件名字表：统一跨模块的域与动作命名，供 EventBus 注册和订阅。
class_name EventName
extends RefCounted

const SETTING_TOGGLE: String = "setting.toggle"

const SOUND_PLAY: String = "sound.play"

const SOUND_STOP: String = "sound.stop"

const SOUND_SILENT: String = "sound.silent"

const SOUND_BGM: String = "sound.bgm"

const VIBRATE_PLAY: String = "vibrate.play"

const GAME_CELL: String = "game.cell"

const GAME_BOARD_BATCH: String = "game.board_batch"

const GAME_BOARD_HEAL: String = "game.board_heal"

const LOG_ERROR: String = "log.error"

const LOG_WARNING: String = "log.warning"

const LOG_PRINT: String = "log.print"

const TRACK_EVENT: String = "track.event"

const UI_SHOW: String = "ui.show"

const UI_HIDE: String = "ui.hide"

const UI_BACK_KEY: String = "ui.back_key"

const UI_TAP_BLOCKED: String = "ui.tap_blocked"

const UI_SHOW_SKIPPED: String = "ui.show_skipped"

const UI_HIDE_SKIPPED: String = "ui.hide_skipped"

const UI_HIDE_ABORTED: String = "ui.hide_aborted"

const UI_OCCLUSION: String = "ui.occlusion"

const UI_ASYNC_LOAD: String = "ui.async_load"

const UI_MASK: String = "ui.mask"

const UI_Z_COMPACT: String = "ui.z_compact"

const AB_DYE: String = "ab.dye"

const AB_TAG: String = "ab.tag"

const INPUT_TAP: String = "input.tap"

const AD_NOT_READY: String = "ad.not_ready"
