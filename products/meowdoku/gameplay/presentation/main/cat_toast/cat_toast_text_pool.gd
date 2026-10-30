## 落猫鼓励文案池：按场景选择候选文本，供鼓励气泡展示。
class_name CatToastTextPool
extends Resource

@export_group("组1 短语文案")

@export var phrase_first_cat: Array[Texture2D] = []

@export var phrase_slow_place: Array[Texture2D] = []

@export var phrase_many_steps: Array[Texture2D] = []

@export var phrase_streak: Array[Texture2D] = []

@export_group("组2 单词文案")

@export var word_first_cat: Array[Texture2D] = []

@export var word_slow_place: Array[Texture2D] = []

@export var word_many_steps: Array[Texture2D] = []

@export var word_streak: Array[Texture2D] = []

@export_group("组3 固定文案")

@export var fixed_by_scene: Array[Texture2D] = []


func pick(group: int, scene: int, rng: RandomNumberGenerator = null) -> Texture2D:
	if CatToastConfig.is_fixed_text_for(group):
		if scene < 0 or scene >= fixed_by_scene.size():
			return null
		return fixed_by_scene[scene]
	var pool: Array[Texture2D] = _pool_for(group, scene)
	if pool.is_empty():
		return null
	return pool[CatToastJudge.roll(rng, pool.size())]


func _pool_for(group: int, scene: int) -> Array[Texture2D]:
	var is_word: bool = CatToastConfig.is_word_style_for(group)
	match scene:
		CatToastJudge.Scene.FIRST_CAT:
			return word_first_cat if is_word else phrase_first_cat
		CatToastJudge.Scene.SLOW_PLACE:
			return word_slow_place if is_word else phrase_slow_place
		CatToastJudge.Scene.MANY_STEPS:
			return word_many_steps if is_word else phrase_many_steps
		CatToastJudge.Scene.STREAK:
			return word_streak if is_word else phrase_streak
	var empty: Array[Texture2D] = []
	return empty
