class_name WBTalentCatalog
extends RefCounted

## Loads content/talents.json and answers catalog questions for the client:
## node lookup, spend validation, and grant composition. Mirrors the
## server-side rules in lobby-server/src/talents.rs — the server stays
## authoritative; this copy exists for UI state and the fake lobby client.

const DEFAULT_PATH := "res://content/talents.json"

var _document: Dictionary = {}
var _nodes_by_id: Dictionary = {}


func load_catalog(path: String = DEFAULT_PATH) -> bool:
	_document = {}
	_nodes_by_id = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return false
	_document = parsed as Dictionary
	if str(_document.get("schema", "")) != "warblade.talents.v1":
		_document = {}
		return false
	for branch: Dictionary in branches():
		for node: Dictionary in (branch.get("nodes", []) as Array):
			_nodes_by_id[str(node["id"])] = node
	return not _nodes_by_id.is_empty()


func is_loaded() -> bool:
	return not _nodes_by_id.is_empty()


func version() -> int:
	return int(_document.get("version", 0))


func branches() -> Array:
	return _document.get("branches", []) as Array


func node(node_id: String) -> Dictionary:
	return _nodes_by_id.get(node_id, {}) as Dictionary


func node_ids() -> Array:
	return _nodes_by_id.keys()


func respec_rules() -> Dictionary:
	return _document.get("respec", {}) as Dictionary


func talent_gated_effects() -> Array:
	var migration: Dictionary = _document.get("shop_migration", {}) as Dictionary
	return migration.get("talent_gated_effects", []) as Array


func applies_to_mode(mode: String) -> bool:
	return (_document.get("applies_to_modes", []) as Array).has(mode)


## Returns {"ok": true, "cost": int} or {"ok": false, "error": {code, message}}.
func validate_spend(owned: Dictionary, node_id: String) -> Dictionary:
	var entry := node(node_id)
	if entry.is_empty():
		return WBLobbyContract.error_result(
			WBLobbyContract.ERR_TALENT_UNKNOWN_NODE, "unknown talent node: " + node_id
		)
	if int(owned.get(node_id, 0)) > 0:
		return WBLobbyContract.error_result(
			WBLobbyContract.ERR_TALENT_ALREADY_OWNED, "talent already owned: " + node_id
		)
	for requirement: Variant in (entry.get("requires", []) as Array):
		if int(owned.get(str(requirement), 0)) <= 0:
			return WBLobbyContract.error_result(
				WBLobbyContract.ERR_TALENT_PREREQ_MISSING,
				"talent %s requires %s" % [node_id, str(requirement)]
			)
	return {"ok": true, "cost": int(entry.get("cost", 0))}


func spent_total(owned: Dictionary) -> int:
	var total := 0
	for node_id: Variant in owned.keys():
		if int(owned[node_id]) > 0 and _nodes_by_id.has(str(node_id)):
			total += int(node(str(node_id)).get("cost", 0))
	return total


## Composes {start_state, starting_rockets, shop_unlocks} for a set of owned
## nodes: MAX across int grants, OR across bools — the same rule the server
## applies, and the same rule the match composer uses against profile locks.
func compose_grants(owned: Dictionary) -> Dictionary:
	var start_state: Dictionary = {}
	var starting_rockets := 0
	var shop_unlocks: Array[String] = []
	for node_id: Variant in owned.keys():
		if int(owned[node_id]) <= 0 or not _nodes_by_id.has(str(node_id)):
			continue
		var entry := node(str(node_id))
		if str(entry.get("kind", "")) == "shop_unlock":
			var effect := str(entry.get("shop_effect", ""))
			if effect != "" and not shop_unlocks.has(effect):
				shop_unlocks.append(effect)
			continue
		var grants: Dictionary = entry.get("grants", {}) as Dictionary
		for key: Variant in grants.keys():
			var value: Variant = grants[key]
			if str(key) == "starting_rockets":
				starting_rockets = maxi(starting_rockets, int(value))
			elif value is bool:
				if bool(value):
					start_state[key] = true
			else:
				start_state[key] = maxi(int(start_state.get(key, 0)), int(value))
	shop_unlocks.sort()
	return {
		"start_state": start_state,
		"starting_rockets": starting_rockets,
		"shop_unlocks": shop_unlocks,
	}
