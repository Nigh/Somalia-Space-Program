extends Control

const FRIEND := Color("62e7e2")
const HOSTILE := Color("ff735c")
const TORPEDO := Color("ffc46b")
var game: Node2D
var minimap: Control
var status_panel: Control
var weapon_buttons: Array[Button] = []
var font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap = Control.new()
	minimap.position = Vector2(1010, 514)
	minimap.size = Vector2(250, 190)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.clip_contents = true
	minimap.tooltip_text = "V: free view. Click or drag to pan. Cyan: your ship. Red: detected enemy. Gold: torpedo. White box: view."
	minimap.draw.connect(_draw_minimap)
	minimap.gui_input.connect(_map_input)
	add_child(minimap)
	status_panel = Control.new()
	status_panel.position = Vector2(16, 14)
	status_panel.size = Vector2(610, 118)
	status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	status_panel.draw.connect(_draw_status)
	add_child(status_panel)
	for index in 6:
		var button := Button.new()
		button.position = Vector2(356 + index * 40, 31)
		button.size = Vector2(38, 48)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "%d: %s" % [index + 1, game.WEAPONS.keys()[index].to_upper()]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("1a535c") if state.contains("pressed") else Color("112c3b")
			style.border_color = FRIEND if state != "normal" else Color("31515d")
			style.set_border_width_all(2 if state.contains("pressed") else 1)
			button.add_theme_stylebox_override(state, style)
		button.pressed.connect(func() -> void:
			if is_instance_valid(game.player):
				game.player.weapon = game.player.loadout[index])
		button.draw.connect(func() -> void: _draw_weapon_icon(button, index))
		status_panel.add_child(button)
		weapon_buttons.append(button)


func _process(_delta: float) -> void:
	queue_redraw()
	minimap.queue_redraw()
	status_panel.queue_redraw()
	if is_instance_valid(game.player):
		for index in weapon_buttons.size():
			weapon_buttons[index].set_pressed_no_signal(game.player.weapon == game.player.loadout[index])


func map_bounds() -> Rect2:
	if game.wrap_enabled:
		return Rect2(game.player.global_position - game.ARENA, game.ARENA * 2.0)
	var bounds := Rect2(-4000, -2250, 8000, 4500)
	if game.stage == "Torpedo Sniping":
		bounds = Rect2(-9000, -9500, 18000, 11000)
	return bounds.expand(game.player.global_position - Vector2(500, 500)).expand(game.player.global_position + Vector2(500, 500))


func map_area() -> Rect2:
	var bounds := map_bounds()
	var scale_factor := minf(226.0 / bounds.size.x, 128.0 / bounds.size.y)
	var area_size := bounds.size * scale_factor
	return Rect2(Vector2(125, 94) - area_size * 0.5, area_size)


func map_position(world: Vector2) -> Vector2:
	var bounds := map_bounds()
	if game.wrap_enabled:
		world = game.player.global_position + game.offset_to(game.player.global_position, world)
	return map_area().position + (world - bounds.position) / bounds.size * map_area().size


func map_world(at: Vector2) -> Vector2:
	return map_bounds().position + (at - map_area().position) / map_area().size * map_bounds().size


func _map_input(event: InputEvent) -> void:
	if game.state != "playing" or not is_instance_valid(game.player):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		game.map_dragging = event.pressed
		if event.pressed and game.free_camera and map_area().has_point(event.position):
			game.camera.position = map_world(event.position)
			game.camera.force_update_scroll()
		minimap.accept_event()
	elif event is InputEventMouseMotion and game.map_dragging and game.free_camera:
		game.camera.position = map_world(event.position.clamp(map_area().position, map_area().end))
		game.camera.force_update_scroll()
		minimap.accept_event()


func screen_position(world: Vector2) -> Vector2:
	if game.wrap_enabled:
		world = game.camera.global_position + game.offset_to(game.camera.global_position, world)
	return game.get_global_transform_with_canvas() * world


func edge_position(point: Vector2) -> Vector2:
	var direction := point - size * 0.5
	# Keep bearings in the outer battlefield margin, clear of the HUD and map.
	var right := size.x - 28.0
	if game.test_panel.visible or point.y > size.y * 0.5:
		right = minimap.position.x - 20.0
	var horizontal := right - size.x * 0.5 if direction.x > 0 else size.x * 0.5 - 28.0
	var vertical := size.y * 0.5 - 150.0
	var ratio := maxf(absf(direction.x) / horizontal, absf(direction.y) / vertical)
	return size * 0.5 + direction / maxf(ratio, 1.0)


func _draw() -> void:
	if not is_instance_valid(game.player):
		return
	var screen := Rect2(Vector2(24, 24), size - Vector2(48, 48))
	var bearing_labels: Array[Rect2] = []
	if game.camera.zoom.x < 0.35:
		var at := screen_position(game.player.global_position)
		var direction := Vector2.UP.rotated(game.player.rotation)
		draw_colored_polygon(PackedVector2Array([at + direction * 6, at - direction * 4 + direction.orthogonal() * 4, at - direction * 4 - direction.orthogonal() * 4]), FRIEND)
		draw_string(font, at + Vector2(10, 4), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FRIEND)
	for ship in game.ships:
		if not is_instance_valid(ship) or ship == game.player or ship.hp <= 0.0 or not game.can_fire_control(game.player, ship):
			continue
		var at := screen_position(ship.global_position)
		if ship.sentry:
			draw_arc(at, ship.fire_range * game.camera.zoom.x, 0, TAU, 128, Color("ff735c66"), 1.0, true)
		if screen.has_point(at):
			draw_rect(Rect2(at - Vector2(10, 10), Vector2(20, 20)), HOSTILE, false, 1.5)
			if ship.sentry:
				draw_string(font, at + Vector2(15, 5), "%dm" % roundi(game.offset_to(game.player.position, ship.position).length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HOSTILE)
		else:
			var edge := edge_position(at)
			var direction := (at - size * 0.5).normalized()
			var side := direction.orthogonal()
			draw_colored_polygon(PackedVector2Array([edge + direction * 10, edge - direction * 7 + side * 6, edge - direction * 7 - side * 6]), HOSTILE)
			var label := (edge - direction * 32 - Vector2(30, -5)).clamp(Vector2(8, 18), size - Vector2(88, 8))
			for previous in bearing_labels:
				if previous.intersects(Rect2(label - Vector2(0, 14), Vector2(80, 18))):
					label.y = previous.position.y - 6.0
			bearing_labels.append(Rect2(label - Vector2(0, 14), Vector2(80, 18)))
			draw_string(font, label, "%dm" % roundi(game.offset_to(game.player.position, ship.position).length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HOSTILE)
	if game.state != "playing" or game.get_viewport().gui_get_hovered_control() != null or game.camera_dragging:
		return
	var cursor := get_local_mouse_position()
	var color := FRIEND
	var blocked := false
	if game.player.weapon == "torpedo":
		var aim: Vector2 = game.weapon_aim(game.player)
		var distance: float = game.player.global_position.distance_to(aim)
		blocked = not game.torpedo_aim_valid(game.player, aim)
		color = HOSTILE if blocked else TORPEDO
		var text := "%dm" % roundi(distance)
		if blocked:
			text += "  TOO CLOSE / MIN 350m" if distance < game.TORPEDO_MIN_RANGE else "  OUT OF RANGE / MAX 12000m"
		var label := (cursor + Vector2(20, 24)).clamp(Vector2(8, 20), size - Vector2(330, 110))
		draw_string(font, label, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if distance < game.TORPEDO_MIN_RANGE:
			draw_arc(screen_position(game.player.position), game.TORPEDO_MIN_RANGE * game.camera.zoom.x, 0, TAU, 96, Color("ffc46b44"), 1.0, true)
	draw_arc(cursor, 12, 0, TAU, 32, color, 1.5, true)
	for side in [-1, 1]:
		draw_line(cursor + Vector2(side * 8, 0), cursor + Vector2(side * 19, 0), color, 1.5, true)
	if blocked:
		draw_line(cursor - Vector2(6, 6), cursor + Vector2(6, 6), color, 2.0, true)
		draw_line(cursor - Vector2(6, -6), cursor + Vector2(6, -6), color, 2.0, true)


func _draw_minimap() -> void:
	if not is_instance_valid(game.player):
		return
	minimap.draw_rect(Rect2(Vector2.ZERO, minimap.size), Color("081622f5"))
	minimap.draw_rect(Rect2(Vector2.ZERO, minimap.size), Color("348798"), false)
	minimap.draw_string(font, Vector2(12, 20), "TACTICAL MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FRIEND)
	minimap.draw_string(font, Vector2(12, 178), "CLICK TO PAN" if game.free_camera else "V: FREE VIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a7bfca"))
	var bounds := map_bounds()
	var area := map_area()
	var map_scale := area.size / bounds.size
	minimap.draw_rect(area, Color("16303d"), false)
	var center: Vector2 = game.camera.global_position
	if game.wrap_enabled:
		center = game.player.global_position + game.offset_to(game.player.global_position, center)
	var view_size: Vector2 = size / game.camera.zoom
	var view := Rect2(area.position + (center - view_size * 0.5 - bounds.position) * map_scale, view_size * map_scale)
	var shifts := [-1, 0, 1] if game.wrap_enabled else [0]
	for x in shifts:
		for y in shifts:
			var copy := Rect2(view.position + Vector2(x, y) * area.size, view.size).intersection(area)
			if copy.has_area():
				minimap.draw_rect(copy, Color("8fe8e61a"))
				minimap.draw_rect(copy, Color("bce9ed"), false)
	for ship in game.ships:
		if not is_instance_valid(ship) or ship.hp <= 0.0:
			continue
		if ship != game.player and not game.can_detect(game.player, ship):
			continue
		var at := map_position(ship.global_position)
		if not area.has_point(at):
			continue
		if ship.sentry:
			minimap.draw_arc(at, ship.fire_range * map_scale.x, 0, TAU, 64, Color("ff735c88"), 1.0, true)
		if ship.player:
			var direction := Vector2.UP.rotated(ship.rotation)
			minimap.draw_colored_polygon(PackedVector2Array([at + direction * 6, at - direction * 4 + direction.orthogonal() * 4, at - direction * 4 - direction.orthogonal() * 4]), FRIEND)
		else:
			minimap.draw_circle(at, 3.0, HOSTILE)
	for shot in game.projectiles:
		if is_instance_valid(shot) and not shot.is_queued_for_deletion() and shot.kind == "torpedo":
			var at := map_position(shot.global_position)
			if area.has_point(at):
				minimap.draw_line(at - shot.velocity.normalized() * 4, at + shot.velocity.normalized() * 4, TORPEDO, 2.0, true)


func _draw_status() -> void:
	if not is_instance_valid(game.player):
		return
	status_panel.draw_rect(Rect2(Vector2.ZERO, status_panel.size), Color("081622f5"))
	status_panel.draw_rect(Rect2(Vector2.ZERO, status_panel.size), Color("348798"), false)
	_draw_meter("HULL", game.player.hp, 120.0, 23.0, FRIEND)
	_draw_meter("POWER", game.player.energy, 100.0, 48.0, Color("8fd8ff"))
	_draw_meter("HEAT", game.player.heat.get(game.player.weapon, 0.0), 100.0, 73.0, TORPEDO)
	status_panel.draw_string(font, Vector2(356, 20), game.player.weapon.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FRIEND)
	var condition := "OVERHEATED" if game.player.overheated.has(game.player.weapon) else "LOW POWER" if game.player.energy < 25.0 else "READY"
	if game.player.emp_timer > 0.0 or game.player.disabled.has("weapons"):
		condition = "OFFLINE"
	status_panel.draw_string(font, Vector2(356, 100), condition, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TORPEDO if condition != "READY" else FRIEND)
	status_panel.draw_string(font, Vector2(12, 101), "SHIELD %s   STEALTH %s   HACK %s" % ["ON" if game.player.shield_on else "OFF", "ON" if game.player.stealth_on else "OFF", game.test_modules[game.test_target_index].to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c6d5dd"))


func _draw_meter(title: String, value: float, maximum: float, y: float, color: Color) -> void:
	status_panel.draw_string(font, Vector2(12, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c6d5dd"))
	var filled := clampf(value / maximum, 0.0, 1.0) * 24.0
	for index in 24:
		var cell := Rect2(70 + index * 8, y - 12, 6, 14)
		status_panel.draw_rect(cell, Color("1c3440"))
		cell.size.x *= clampf(filled - index, 0.0, 1.0)
		if cell.size.x > 0.0:
			status_panel.draw_rect(cell, color)
	status_panel.draw_string(font, Vector2(269, y), "%03d/%d" % [maxi(0, roundi(value)), roundi(maximum)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_weapon_icon(button: Button, index: int) -> void:
	var color := FRIEND if button.button_pressed else Color("a7bfca")
	var center := Vector2(19, 21)
	match index:
		0:
			for y in [-5, 0, 5]:
				button.draw_line(center + Vector2(-8, y), center + Vector2(6, y), color, 2.0, true)
		1:
			button.draw_line(center - Vector2(11, 0), center + Vector2(10, 0), color, 5.0, true)
			button.draw_line(center + Vector2(-7, -7), center + Vector2(-7, 7), color, 2.0, true)
		2:
			for x in range(-10, 11, 5):
				button.draw_line(center + Vector2(x, -5), center + Vector2(x, 5), color, 2.0, true)
		3:
			button.draw_line(center - Vector2(12, 0), center + Vector2(12, 0), color, 2.0, true)
			button.draw_circle(center - Vector2(8, 0), 4, color)
		4, 5:
			button.draw_colored_polygon(PackedVector2Array([center + Vector2(12, 0), center + Vector2(-6, -5), center + Vector2(-6, 5)]), color)
			if index == 4:
				button.draw_line(center + Vector2(-10, -8), center + Vector2(-10, 8), color, 2, true)
			else:
				button.draw_arc(center, 12, -0.7, 0.7, 12, color, 1, true)
	button.draw_string(font, Vector2(15, 42), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
