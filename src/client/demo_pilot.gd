class_name WBDemoPilot
extends RefCounted

## Attract-mode autopilot: drives seat 0 through the normal client input path
## from public snapshots only, never touching authority. The retail DEMO GAME
## menu item and idle attract start "the computer playing an early random
## level"; the pilot's steering itself is an intentional modernization and
## claims no retail routine.

const FP_ONE := 65536


static func input_for(snapshot: Dictionary) -> int:
	var phase := String(snapshot.get("phase", ""))
	var tick := int(snapshot.get("tick", 0))
	match phase:
		"shop":
			var shop: Dictionary = snapshot.get("shop", {})
			if tick > int(shop.get("input_guard_until_tick", 0)):
				return WBInputRouter.INPUT_READY
			return 0
		"rank_promotion":
			return WBInputRouter.INPUT_FIRE
		"credits":
			return WBInputRouter.INPUT_CONFIRM if tick % 2 == 0 else 0
		"level", "warp_malfunction", "bonus_mode":
			return _combat_input(snapshot, tick)
	return 0


static func _combat_input(snapshot: Dictionary, tick: int) -> int:
	var players := snapshot.get("players", []) as Array
	if players.is_empty():
		return 0
	var player := players[0] as Dictionary
	if not bool(player.get("alive", false)) or not bool(player.get("active", false)):
		return 0
	var player_x := int(player.get("x_fp", 0))
	var target_x := -1
	var boss := snapshot.get("boss", {}) as Dictionary
	if bool(boss.get("active", false)):
		target_x = int(float(boss.get("x", 0.0)) * FP_ONE)
	else:
		var lowest_y := -(1 << 60)
		for enemy_value in snapshot.get("enemies", []):
			var enemy := enemy_value as Dictionary
			if int(enemy.get("behavior_state_id", 0)) == 8:
				continue
			var enemy_y := int(enemy.get("y_fp", 0))
			if enemy_y >= -32 * FP_ONE and enemy_y < 350 * FP_ONE and enemy_y > lowest_y:
				lowest_y = enemy_y
				target_x = int(enemy.get("x_fp", 0))
	if target_x < 0:
		return 0
	var mask := 0
	var delta := target_x - player_x
	if delta < -4 * FP_ONE:
		mask |= WBInputRouter.INPUT_LEFT
	elif delta > 4 * FP_ONE:
		mask |= WBInputRouter.INPUT_RIGHT
	if absi(delta) <= 24 * FP_ONE and tick % 2 == 0:
		mask |= WBInputRouter.INPUT_FIRE
	return mask
