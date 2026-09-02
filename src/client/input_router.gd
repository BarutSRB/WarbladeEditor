class_name WBInputRouter
extends RefCounted

const INPUT_LEFT := 1
const INPUT_RIGHT := 2
const INPUT_FIRE := 4
const INPUT_CONFIRM := 8
const INPUT_CANCEL := 16
const INPUT_READY := 32
const INPUT_UP := 64
const INPUT_DOWN := 128
const INPUT_SECONDARY := 256

const SEAT_ACTIONS: Array[Dictionary] = [
	{
		"left": "p1_left",
		"right": "p1_right",
		"up": "p1_up",
		"down": "p1_down",
		"fire": "p1_fire",
		"secondary": "p1_secondary",
		"confirm": "p1_confirm",
		"cancel": "p1_cancel",
	},
	{
		"left": "p2_left",
		"right": "p2_right",
		"up": "p2_up",
		"down": "p2_down",
		"fire": "p2_fire",
		"secondary": "p2_secondary",
		"confirm": "p2_confirm",
		"cancel": "p2_cancel",
	},
]


func mask_for_seat(seat: int) -> int:
	if seat < 0 or seat >= SEAT_ACTIONS.size():
		return 0
	var actions: Dictionary = SEAT_ACTIONS[seat]
	var mask := 0
	if Input.is_action_pressed(str(actions["left"])):
		mask |= INPUT_LEFT
	if Input.is_action_pressed(str(actions["right"])):
		mask |= INPUT_RIGHT
	if Input.is_action_pressed(str(actions["up"])):
		mask |= INPUT_UP
	if Input.is_action_pressed(str(actions["down"])):
		mask |= INPUT_DOWN
	if Input.is_action_pressed(str(actions["fire"])):
		mask |= INPUT_FIRE
	if Input.is_action_pressed(str(actions["secondary"])):
		mask |= INPUT_SECONDARY
	if Input.is_action_pressed(str(actions["confirm"])):
		mask |= INPUT_CONFIRM
	if Input.is_action_pressed(str(actions["cancel"])):
		mask |= INPUT_CANCEL
	return normalize_mask(mask)


static func normalize_mask(mask: int) -> int:
	var bounded := mask & (
		INPUT_LEFT
		| INPUT_RIGHT
		| INPUT_FIRE
		| INPUT_CONFIRM
		| INPUT_CANCEL
		| INPUT_READY
		| INPUT_UP
		| INPUT_DOWN
		| INPUT_SECONDARY
	)
	if (bounded & INPUT_LEFT) != 0 and (bounded & INPUT_RIGHT) != 0:
		bounded &= ~(INPUT_LEFT | INPUT_RIGHT)
	if (bounded & INPUT_UP) != 0 and (bounded & INPUT_DOWN) != 0:
		bounded &= ~(INPUT_UP | INPUT_DOWN)
	return bounded


static func seats_for_mode(mode: String) -> int:
	# Retail Time Trial (match mode 6) is single seat, like solo.
	return 1 if mode in ["solo", "time_trial"] else 2
