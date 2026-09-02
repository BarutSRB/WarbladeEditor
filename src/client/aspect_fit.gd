class_name WBAspectFit
extends RefCounted

const LOGICAL_SIZE := Vector2(800.0, 600.0)


static func calculate(container_size: Vector2, logical_size: Vector2 = LOGICAL_SIZE) -> Rect2:
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	if logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var scale := minf(container_size.x / logical_size.x, container_size.y / logical_size.y)
	var fitted_size := logical_size * scale
	return Rect2((container_size - fitted_size) * 0.5, fitted_size)


static func logical_to_output(point: Vector2, output_rect: Rect2, logical_size: Vector2 = LOGICAL_SIZE) -> Vector2:
	if output_rect.size.x <= 0.0 or output_rect.size.y <= 0.0:
		return output_rect.position
	return output_rect.position + Vector2(
		point.x * output_rect.size.x / logical_size.x,
		point.y * output_rect.size.y / logical_size.y
	)


static func output_to_logical(point: Vector2, output_rect: Rect2, logical_size: Vector2 = LOGICAL_SIZE) -> Vector2:
	if output_rect.size.x <= 0.0 or output_rect.size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(
		(point.x - output_rect.position.x) * logical_size.x / output_rect.size.x,
		(point.y - output_rect.position.y) * logical_size.y / output_rect.size.y
	)
