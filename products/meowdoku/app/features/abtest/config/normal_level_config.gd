## 实验配置 normal_level：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NormalLevelConfig

const VALUE_CONTROL: int = 0

const VALUE_BIG_BOARD: int = 11301

const VALUE_BIG_BOARD_AGGRESSIVE: int = 11302

const VALUE_HIGHER_STRATEGY: int = 11303

const VALUE_HIGHER_STRATEGY_AGGRESSIVE: int = 11304

const VALUE_REMOVE_DISPERSED: int = 11305

const VALUE_DEMOTE_RESTORE_ANY_ACTION: int = 11306

const VALUE_DEMOTE_RESTORE_TOOL_FREEZE: int = 11307

const VALUE_PACE_G1: int = 11308
const VALUE_PACE_G2: int = 11309
const VALUE_PACE_G3: int = 11310
const VALUE_PACE_G4: int = 11311

const VALUE_SERVER_REC: int = 11401

const VALUE_SERVER_REC_V2: int = 11515

const VALUE_SERVER_REC_ACTIVE: int = 11710
const VALUE_SERVER_REC_STANDBY: int = 11711

const VALUE_SERVER_REC_V3_ACTIVE: int = 11923

const VALUE_SERVER_REC_V3_STANDBY: int = 11924

const VALUE_SERVER_REC_V3_STANDBY_2: int = 11925

const REC_MODEL_ACTIVE: String = "active"
const REC_MODEL_STANDBY: String = "standby"
const REC_MODEL_STANDBY_2: String = "standby-2"

const VALUE_DIFF_DIFFICULTY_TAGGED: int = 11501
const VALUE_DIFF_DIFFICULTY_UNTAGGED: int = 11502
const VALUE_DIFF_DIFFICULTY_DECAY: int = 11503

const VALUE_CHAIN_PERIODIC: int = 11516

const VALUE_CHAIN_PROTECT: int = 11517

const VALUE_CHAIN_MAX_RANK_STREAK: int = 11518

const VALUE_SP_TT_ROTATION: int = 11509

const VALUE_LK_MOD_FREQ_BOOST: int = 11510

const VALUE_LK_MOD_DELIVERY_PACED: int = 11708

const VALUE_PRE_CAT_HIGH_RANK: int = 11511

const VALUE_PRE_CAT_SINGLE_REGION_1: int = 11512
const VALUE_PRE_CAT_SINGLE_REGION_2: int = 11513

const VALUE_ISOMORPHIC_DEDUP: int = 11504

const VALUE_PRE_CAT_HIDDEN_SINGLE_L1: int = 11514

const VALUE_GF_INSERT_SKIP: int = 11505
const VALUE_GF_HARD_SKIP: int = 11506
const VALUE_GF_INSERT_NOSKIP: int = 11507
const VALUE_GF_HARD_NOSKIP: int = 11508

const VALUE_GF_CONTROL: int = 0

const GF_GROUPS: Array[int] = [
	VALUE_GF_INSERT_SKIP,
	VALUE_GF_HARD_SKIP,
	VALUE_GF_INSERT_NOSKIP,
	VALUE_GF_HARD_NOSKIP,
]

const VALUE_SINGLE_REGION_ALL_ONE: int = 11706
const VALUE_SINGLE_REGION_ALTERNATE: int = 11707

const VALUE_V113_ROLLBACK_ALL: int = 11709

const VALUE_FUSION_BASE: int = 11900
const VALUE_RETURNEE_SPECIAL: int = 12001
const VALUE_RETURNEE_EASY: int = 12002
const VALUE_DIGIT_MILESTONES: int = 12004
const VALUE_HARD_R4_RATING: int = 12005
const VALUE_HARD_ALTERNATE_RATING: int = 12006

const VALUE_DAILY_FIRST_CEILING_MINUS_ONE: int = 12007
const VALUE_DAILY_FIRST_R4: int = 12008
const VALUE_DAILY_FIRST_COMBINED: int = 12009

const VALUE_FUSION_BASE_V121: int = 12100
const VALUE_ELO_V2_TIME: int = 12207
const VALUE_ELO_V2_BEHAVIOR: int = 12208
const VALUE_ELO_ORIGINAL_FUSION: int = 12210
const VALUE_PASS_TIME_DDA_STRATEGY: int = 12101
const VALUE_PASS_TIME_DDA_SIZE: int = 12102
const VALUE_V6_HARD_RATING: int = 12103
const VALUE_V6_R4_EARLY_MILD: int = 12104
const VALUE_V6_R4_EARLY_AGGRESSIVE: int = 12105

const VALUE_HARD_PREV_EASE: int = 12106

const VALUE_HARD_NEXT_EASE: int = 12107

const VALUE_HARD_BOTH_EASE: int = 12108

const VALUE_RATING_SORTED: int = 12201

const VALUE_RATING_SORTED_NO_STYLE: int = 12202

const VALUE_DYNAMIC_SIZE_LATE: int = 12203
const VALUE_ASSIST_TOOL_WIN_PROMOTE: int = 12209

const VALUE_SUPER_HARD_R4_ONLY: int = 12204
const VALUE_SUPER_HARD_LATE: int = 12205
const VALUE_SUPER_HARD_NEXT_SMALL: int = 12206

const FUSION_BASE_V121_GROUPS: Array[int] = [
	VALUE_FUSION_BASE_V121,
	VALUE_ELO_V2_TIME,
	VALUE_ELO_V2_BEHAVIOR,
	VALUE_PASS_TIME_DDA_STRATEGY,
	VALUE_PASS_TIME_DDA_SIZE,
	VALUE_V6_HARD_RATING,
	VALUE_V6_R4_EARLY_MILD,
	VALUE_V6_R4_EARLY_AGGRESSIVE,
	VALUE_HARD_PREV_EASE,
	VALUE_HARD_NEXT_EASE,
	VALUE_HARD_BOTH_EASE,
	VALUE_RATING_SORTED,
	VALUE_RATING_SORTED_NO_STYLE,
	VALUE_DYNAMIC_SIZE_LATE,
	VALUE_SUPER_HARD_R4_ONLY,
	VALUE_SUPER_HARD_LATE,
	VALUE_SUPER_HARD_NEXT_SMALL,
	VALUE_ASSIST_TOOL_WIN_PROMOTE,
]

const VALUE_DELAY_R4_NODE: int = 11704
const VALUE_RATING_TIERED: int = 11705

const VALUE_GOOD_FIRST_SHUFFLE: int = 11701
const VALUE_GOOD_FIRST_LEAD_R1: int = 11702
const VALUE_GOOD_FIRST_R4_RATIO: int = 11703

const VALUE_SUPER_HARD_UI_ONLY: int = 11806

const VALUE_SUPER_HARD_HARDER: int = 11807

const VALUE_DYNAMIC_SIZE_HARDER_SMALLER: int = 11801
const VALUE_DYNAMIC_SIZE_BY_DDA_RANK: int = 11802

const VALUE_SPECIAL_LAYOUT_V2_G1: int = 11803
const VALUE_SPECIAL_LAYOUT_V2_G2: int = 11804
const VALUE_SPECIAL_LAYOUT_V2_G3: int = 11805

const VALUE_ONEFISH_STATE_FIX: int = 11808
const VALUE_ONEFISH_STATE_FIX_KEEP_DFLD: int = 11809

const VALUE_ELO_FIXED_BAND: int = 11919
const VALUE_ELO_DDA_BAND: int = 11920

const VALUE_SINGLE_REGION_V3_RETEST_ALL_ONE: int = 11904
const VALUE_SINGLE_REGION_V3_RETEST_ALTERNATE: int = 11905

const VALUE_SINGLE_REGION_V3_ALTERNATE_CONSERVATIVE: int = 11906
const VALUE_SINGLE_REGION_V3_BY_DDA: int = 11907
const VALUE_SINGLE_REGION_V3_BY_STRATEGY: int = 11908
const VALUE_SINGLE_REGION_V3_BY_PRECAT: int = 11909

const VALUE_TOOL_NO_DEMOTE: int = 11910
const VALUE_CHANNEL_ASSIST_TOOL_NO_DEMOTE: int = 11911
const VALUE_DAILY_WINCOUNT_RAISE: int = 11912
const VALUE_DAILY_WINCOUNT_RAISE_D2: int = 11913
const VALUE_DAILY_WINCOUNT_RAISE_STRONG: int = 11914
const VALUE_DAILY_WINCOUNT_RAISE_STRONG_D2: int = 11915
const VALUE_TOOL_HOARD_PRESSURE: int = 11916
const VALUE_FULLHP_RANK: int = 11917
const VALUE_LOWER_PROMOTE_THRESHOLD_15_50: int = 11918

const VALUE_CLIMAX_LATE: int = 11901
const VALUE_CLIMAX_EARLY: int = 11902
const VALUE_CLIMAX_BOTH: int = 11903

const VALUE_SP_TT_RETEST: int = 11921
const VALUE_LK_MOD_REMOVED: int = 11922

const VALUE_IOS_DIFFICULTY_RHYTHM_LATE: int = 11951
const VALUE_IOS_DIFFICULTY_RHYTHM_EARLY: int = 11952
const VALUE_IOS_DIFFICULTY_RHYTHM_BOTH: int = 11953
const VALUE_IOS_SINGLE_REGION_V3_RETEST_ALL_ONE: int = 11954
const VALUE_IOS_SINGLE_REGION_V3_RETEST_ALTERNATE: int = 11955
const VALUE_IOS_SINGLE_REGION_V3_ALTERNATE_CONSERVATIVE: int = 11956
const VALUE_IOS_SINGLE_REGION_V3_BY_DDA: int = 11957
const VALUE_IOS_SINGLE_REGION_V3_BY_STRATEGY: int = 11958
const VALUE_IOS_SINGLE_REGION_V3_BY_PRECAT: int = 11959
const VALUE_IOS_TOOL_NO_DEMOTE: int = 11960
const VALUE_IOS_CHANNEL_ASSIST_TOOL_NO_DEMOTE: int = 11961
const VALUE_IOS_DAILY_WINCOUNT_RAISE: int = 11962
const VALUE_IOS_DAILY_WINCOUNT_RAISE_D2: int = 11963
const VALUE_IOS_DAILY_WINCOUNT_RAISE_STRONG: int = 11964
const VALUE_IOS_DAILY_WINCOUNT_RAISE_STRONG_D2: int = 11965
const VALUE_IOS_TOOL_HOARD_PRESSURE: int = 11966
const VALUE_IOS_FULLHP_RANK: int = 11967
const VALUE_IOS_LOWER_PROMOTE_THRESHOLD_15_50: int = 11968
const VALUE_IOS_ELO_FIXED_BAND: int = 11969
const VALUE_IOS_ELO_DDA_BAND: int = 11970
const VALUE_IOS_SP_TT_RETEST: int = 11971
const VALUE_IOS_LK_MOD_REMOVED: int = 11972

const DENSITY_THRESHOLD: float = 0.7

const _SIZE_1_10_BIG_BOARD: Array[int] = [4, 5, 6, 7, 8, 6, 8, 8, 10, 8]
const _SIZE_1_10_BIG_BOARD_AGGRESSIVE: Array[int] = [4, 6, 8, 9, 10, 10, 9, 10, 10, 10]


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_level"
	default_value = VALUE_CONTROL


func get_pace_group() -> int:
	return 3 if value() == VALUE_PACE_G3 else 0


func is_server_rec_active() -> bool:
	var group_value: int = value()
	return (
		group_value == VALUE_SERVER_REC_V2
		or group_value == VALUE_SERVER_REC_ACTIVE
		or group_value == VALUE_SERVER_REC_STANDBY
		or group_value == VALUE_SERVER_REC_V3_ACTIVE
		or group_value == VALUE_SERVER_REC_V3_STANDBY
		or group_value == VALUE_SERVER_REC_V3_STANDBY_2
	)


func get_rec_model_name() -> String:
	var v: int = value()
	if v == VALUE_SERVER_REC_ACTIVE or v == VALUE_SERVER_REC_V3_ACTIVE:
		return REC_MODEL_ACTIVE
	if v == VALUE_SERVER_REC_V3_STANDBY_2:
		return REC_MODEL_STANDBY_2
	if is_server_rec_active():
		return REC_MODEL_STANDBY
	return REC_MODEL_ACTIVE


func is_lk_mod_freq_boost_active() -> bool:
	return (
		(
			value()
			in [
				VALUE_LK_MOD_FREQ_BOOST,
				VALUE_SPECIAL_LAYOUT_V2_G1,
				VALUE_SPECIAL_LAYOUT_V2_G2,
				VALUE_ELO_ORIGINAL_FUSION
			]
		)
		or is_fusion_base_v121_active()
	)


func is_fusion_base_v121_active() -> bool:
	return value() in FUSION_BASE_V121_GROUPS


func is_elo_v2_active() -> bool:
	return value() in [VALUE_ELO_V2_TIME, VALUE_ELO_V2_BEHAVIOR]


func is_diff_difficulty_tagged_active() -> bool:
	return value() == VALUE_DIFF_DIFFICULTY_TAGGED


func is_diff_difficulty_untagged_active() -> bool:
	return value() == VALUE_DIFF_DIFFICULTY_UNTAGGED


func is_diff_difficulty_decay_active() -> bool:
	return value() == VALUE_DIFF_DIFFICULTY_DECAY


func is_chain_strategy_active() -> bool:
	return (
		value() == VALUE_CHAIN_PERIODIC
		or value() == VALUE_CHAIN_PROTECT
		or value() == VALUE_CHAIN_MAX_RANK_STREAK
	)


func is_pre_cat_high_rank_active() -> bool:
	return value() == VALUE_PRE_CAT_HIGH_RANK


func is_pre_cat_level_swap_active() -> bool:
	return (
		value() == VALUE_PRE_CAT_SINGLE_REGION_1
		or value() == VALUE_PRE_CAT_SINGLE_REGION_2
		or value() == VALUE_PRE_CAT_HIDDEN_SINGLE_L1
	)


func is_isomorphic_dedup_active() -> bool:
	return value() == VALUE_ISOMORPHIC_DEDUP


func is_super_hard_active() -> bool:
	return value() == VALUE_SUPER_HARD_UI_ONLY or is_super_hard_harder_active()


func is_super_hard_harder_active() -> bool:
	return (
		value() in [VALUE_SUPER_HARD_HARDER, VALUE_ELO_ORIGINAL_FUSION]
		or is_fusion_base_v121_active()
	)


func is_super_hard_stale_fixed_rank_active() -> bool:
	return value() in [VALUE_SUPER_HARD_R4_ONLY, VALUE_SUPER_HARD_LATE, VALUE_SUPER_HARD_NEXT_SMALL]


static func normalize_golden_fish(raw: int) -> int:
	return raw if raw in GF_GROUPS else VALUE_GF_CONTROL


func golden_fish_prev_group() -> int:
	var prev: int = get_prev_saved_group()
	return prev if prev < 0 else normalize_golden_fish(prev)


func is_onefish_state_fix() -> bool:
	var v: int = value()
	return v == VALUE_ONEFISH_STATE_FIX or v == VALUE_ONEFISH_STATE_FIX_KEEP_DFLD


func is_onefish_dfld_fix() -> bool:
	return value() == VALUE_ONEFISH_STATE_FIX
