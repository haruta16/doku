## 过期残局门禁：识别需要丢弃或重选的难关残局，供页面恢复流程使用。
class_name StaleEndgameGate
extends RefCounted

const SUPER_HARD_STALE_RANK: int = 3


static func super_hard_stale_rank(level_num: int, snapshot_kind: int) -> int:
	if snapshot_kind != LevelKind.MAIN:
		return 0
	if not ABTestManager.normal_level.is_super_hard_stale_fixed_rank_active():
		return 0
	if not LevelSelector.is_super_hard_level(level_num):
		return 0
	return SUPER_HARD_STALE_RANK


static func is_pending_stale_discard() -> bool:
	var nes: NormalEndgameSaveConfig = ABTestManager.normal_endgame_save
	if not (nes.is_stale_restart_current() or nes.is_stale_new_easier()):
		return false
	if GameState.get_login_gap_days() < nes.returnee_gap_days():
		return false
	if GameState.is_stale_endgame_discarded():
		return false
	return true
