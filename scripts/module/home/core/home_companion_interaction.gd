## 首页陪伴猫交互状态机：约束入场、待机、抚摸和喂食之间允许的状态转换。
extends RefCounted

enum Mode { NONE, CANDY, CANS, SATIETY, COSMETIC, INTERACT }
enum State { HIDDEN, ENTRANCE, NORMAL_IDLE, HUNGRY_IDLE, TOUCH, FEED_PENDING, FEED }

const NORMAL_IDLE_PROBABILITY: float = 0.6
const HUNGRY_THRESHOLD: float = 60.0

var mode: Mode = Mode.NONE
var state: State = State.HIDDEN
var first_feed_completed: bool = false


## 开始一轮首页入场，清理上次喂食标记并按业务模式选择隐藏或入场状态。
func begin_entry(next_mode: Mode) -> void:
	mode = next_mode
	first_feed_completed = false
	state = State.HIDDEN if mode == Mode.NONE else State.ENTRANCE


func end_entry() -> void:
	state = State.HIDDEN
	first_feed_completed = false


func is_unlimited_food() -> bool:
	return mode == Mode.CANDY or mode == Mode.INTERACT


## 饱食模式按 60 点阈值选择饥饿待机，其他可互动模式按随机值分流。
func enter_idle(random_roll: float, satiety: float) -> void:
	if mode == Mode.NONE or state == State.HIDDEN:
		return
	var hungry: bool = (
		satiety <= HUNGRY_THRESHOLD
		if mode == Mode.SATIETY
		else random_roll >= NORMAL_IDLE_PROBABILITY
	)
	if mode == Mode.COSMETIC:
		hungry = false

	if state == State.FEED and first_feed_completed and (is_unlimited_food() or mode == Mode.CANS):
		hungry = false
	state = State.HUNGRY_IDLE if hungry else State.NORMAL_IDLE


func request_touch() -> bool:
	if state != State.NORMAL_IDLE:
		return false
	state = State.TOUCH
	return true


## 只接受待机状态的喂食；需要罐头的模式先检查库存，再进入等待业务确认状态。
func request_feed(food_count: int) -> bool:
	if mode == Mode.NONE or mode == Mode.COSMETIC:
		return false
	if state != State.NORMAL_IDLE and state != State.HUNGRY_IDLE:
		return false
	if not is_unlimited_food() and food_count <= 0:
		return false
	state = State.FEED_PENDING
	return true


## 仅在等待确认且业务批准时转入喂食，库存扣减由外层服务负责。
func confirm_feed(approved: bool) -> bool:
	if state != State.FEED_PENDING or not approved:
		return false
	state = State.FEED
	return true


## 允许指定模式中断当前喂食并再次请求，仍需满足库存条件。
func request_next_feed(food_count: int) -> bool:
	if not can_interrupt_feed() or (not is_unlimited_food() and food_count <= 0):
		return false
	state = State.FEED_PENDING
	return true


func can_interrupt_feed() -> bool:
	return (
		state == State.FEED and (is_unlimited_food() or mode == Mode.CANS or mode == Mode.SATIETY)
	)


func complete_feed() -> void:
	if state == State.FEED:
		first_feed_completed = true
