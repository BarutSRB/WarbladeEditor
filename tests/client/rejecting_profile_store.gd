extends WBProfileStore


func _publish_temporary(_temporary_path: String, _canonical_path: String) -> Error:
	return ERR_CANT_CREATE
