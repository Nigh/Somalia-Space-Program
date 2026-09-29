extends Node2D

const ARENA := Vector2(1500.0, 1050.0)
const STAGES := ["Mission", "Power & Heat", "Sensors & Stealth", "Weapons", "Guidance & EMP", "HACK", "Warp Arena"]
const WEAPONS := {
	"bullet": {"cost": 1.0, "heat": 3.0, "delay": 0.12, "damage": 5.0, "speed": 1000.0},
	"cannon": {"cost": 5.0, "heat": 15.0, "delay": 0.32, "damage": 18.0, "speed": 680.0},
	"pulse": {"cost": 8.0, "heat": 22.0, "delay": 0.4, "damage": 14.0, "speed": 850.0},
	"beam": {"cost": 2.4, "heat": 5.0, "delay": 0.08, "damage": 3.2, "speed": 0.0},
	"missile": {"cost": 16.0, "heat": 26.0, "delay": 1.6, "damage": 36.0, "speed": 220.0},
	"torpedo": {"cost": 22.0, "heat": 34.0, "delay": 2.8, "damage": 70.0, "speed": 100.0},
}

var ships: Array[CombatShip] = []
var projectiles: Array[CombatProjectile] = []
var player: CombatShip
var generator: CombatShip
var stage := ""
var state := "menu"
var wrap_enabled := false
var extraction := Vector2(0, -780)
var camera: Camera2D
var menu: Control
var hud: Control
var test_panel: Control
var status_label: Label
var info_label: Label
var message_label: Label
var instructions: Label
var message_time := 0.0
var effects: Array[Dictionary] = []
var test_target_index := 0
var test_modules := ["weapons", "engine", "gyro", "radar", "shield", "fire_control"]
var sound_players: Dictionary = {}
var sound_gates: Dictionary = {}


func _ready() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.85, 0.85)
	camera.enabled = true
	add_child(camera)
	for name in ["shot", "hit", "emp"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load("res://audio/%s.wav" % name)
		audio.volume_db = -12.0
		add_child(audio)
		sound_players[name] = audio
	_build_ui()
	show_menu()


func show_menu() -> void:
	_clear_world()
	state = "menu"
	stage = ""
	menu.visible = true
	hud.visible = false
	test_panel.visible = false
	camera.position = Vector2.ZERO
	queue_redraw()


func start_stage(selected: String) -> void:
	_clear_world()
	stage = selected
	state = "playing"
	wrap_enabled = selected == "Warp Arena"
	menu.visible = false
	hud.visible = true
	test_panel.visible = selected != "Mission"
	player = _spawn_ship(Vector2(0, 250), true)
	player.rotation = 0.0
	match selected:
		"Mission":
			var first := _spawn_ship(Vector2(-260, -350))
			first.hp = 65.0
			var second := _spawn_ship(Vector2(300, -500))
			second.hp = 65.0
			second.weapon = "pulse"
			set_message("INTERCEPT: neutralize both raiders, then jump at the extraction marker.")
		"Power & Heat":
			_spawn_ship(Vector2(0, -420), false)
			set_message("Hold fire, thrust and shield. Watch power and per-module heat.")
		"Sensors & Stealth":
			var hot := _spawn_ship(Vector2(-260, -260), false)
			hot.ai_enabled = false
			hot.stealth_on = true
			hot.thrust_input = 1.0
			var cold := _spawn_ship(Vector2(300, -300), false)
			cold.ai_enabled = false
			cold.stealth_on = true
			cold.has_optical = false
			cold.has_radar = false
			cold.has_ir = false
			cold.has_ir = false
			set_message("Toggle optical, radar and IR. Stealth hides from optical/radar; heat reveals IR.")
		"Weapons":
			for x in [-340, 0, 340]:
				var target := _spawn_ship(Vector2(x, -420), false)
				target.ai_enabled = false
				target.hp = 220.0
				target.shield_on = x == 0
			set_message("Compare cannon, pulse, beam, missile and torpedo against shielded targets.")
		"Guidance & EMP":
			var target := _spawn_ship(Vector2(0, -450), false)
			target.weapon = "missile"
			set_message("Missiles need fire-control radar; EMP interrupts electronics and guidance.")
		"HACK":
			var target := _spawn_ship(Vector2(0, -30), false)
			target.weapon = "missile"
			set_message("Approach within 350 units, then press R to disable the selected module.")
		"Warp Arena":
			generator = _spawn_ship(Vector2(0, -460), false)
			generator.hp = 250.0
			generator.energy = 100.0
			_spawn_ship(Vector2(380, -280))
			set_message("Space wraps at the border. Destroy the generator to escape by jump.")
	_update_visibility()
	queue_redraw()


func _spawn_ship(at: Vector2, is_player := false) -> CombatShip:
	var ship := CombatShip.new()
	ship.game = self
	ship.player = is_player
	ship.position = at
	ship.destroyed.connect(_on_ship_destroyed)
	add_child(ship)
	ships.append(ship)
	if not is_player and is_instance_valid(player):
		ship.ai_target = player
	return ship


func _clear_world() -> void:
	for ship in ships:
		if is_instance_valid(ship):
			ship.queue_free()
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	ships.clear()
	projectiles.clear()
	effects.clear()
	player = null
	generator = null
	wrap_enabled = false


func _physics_process(delta: float) -> void:
	if state != "playing" or not is_instance_valid(player):
		return
	player.thrust_input = 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	player.turn_input = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	player.brake_input = Input.is_key_pressed(KEY_S)
	player.fire_input = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() == null
	for ship in ships:
		if is_instance_valid(ship):
			wrap_entity(ship)
	for i in range(ships.size() - 1, -1, -1):
		if not is_instance_valid(ships[i]) or ships[i].hp <= 0.0:
			ships.remove_at(i)
	for i in range(projectiles.size() - 1, -1, -1):
		if not is_instance_valid(projectiles[i]) or projectiles[i].is_queued_for_deletion():
			projectiles.remove_at(i)
	# ponytail: pair scan is enough for the small test arenas; use spatial queries if projectile counts grow.
	for i in projectiles.size():
		var a := projectiles[i]
		if not is_instance_valid(a) or a.kind != "missile" and a.kind != "torpedo":
			continue
		for j in projectiles.size():
			var b := projectiles[j]
			if i == j or not is_instance_valid(b) or b.owner_ship.player == a.owner_ship.player:
				continue
			if (b.kind == "bullet" or b.kind == "cannon") and offset_to(a.global_position, b.global_position).length() < 16.0:
				flash(a.global_position, Color("ffba71"), 35.0)
				a.queue_free()
				b.queue_free()
				break
	if stage == "Mission" and _enemies_left() == 0 and player.global_position.distance_to(extraction) < 150.0:
		set_message("Extraction reached. Press SPACE to jump.")
	_update_visibility()
	queue_redraw()


func _process(delta: float) -> void:
	if state != "playing":
		return
	if is_instance_valid(player):
		camera.global_position = camera.global_position.lerp(player.global_position, minf(1.0, delta * 5.0))
		_update_hud()
	message_time = maxf(0.0, message_time - delta)
	if message_time <= 0.0:
		message_label.text = ""
	for effect in effects:
		effect.time -= delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return effect.time > 0.0)
	for name in sound_gates.keys():
		sound_gates[name] = maxf(0.0, sound_gates[name] - delta)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		show_menu()
		return
	if state != "playing" or not is_instance_valid(player):
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		player.weapon = player.loadout[event.keycode - KEY_1]
	elif event.keycode == KEY_Q:
		player.shield_on = not player.shield_on
	elif event.keycode == KEY_F:
		player.stealth_on = not player.stealth_on
	elif event.keycode == KEY_E:
		_activate_emp()
	elif event.keycode == KEY_R:
		_hack_target()
	elif event.keycode == KEY_SHIFT:
		_blink()
	elif event.keycode == KEY_SPACE:
		_jump()
	elif event.keycode == KEY_O:
		player.has_optical = not player.has_optical
	elif event.keycode == KEY_P:
		player.has_radar = not player.has_radar
	elif event.keycode == KEY_I:
		player.has_ir = not player.has_ir
	elif event.keycode == KEY_TAB:
		test_target_index = (test_target_index + 1) % test_modules.size()
	elif event.keycode == KEY_BACKSPACE and stage != "Mission":
		start_stage(stage)


func fire_weapon(ship: CombatShip) -> void:
	var name := ship.weapon
	var data: Dictionary = WEAPONS[name]
	var locked_target: CombatShip
	if name == "missile":
		locked_target = _nearest_target(ship, 1100.0, true)
		if not is_instance_valid(locked_target):
			if ship.player:
				set_message("MISSILE: no fire-control lock.")
			return
	if not ship.module_ready("weapons") or not ship.spend(name, data.cost, data.heat):
		return
	var direction := Vector2.UP.rotated(ship.rotation)
	if ship.player:
		var aim := get_global_mouse_position() - ship.global_position
		if aim.length() > 0.0:
			direction = aim.normalized()
	ship.cooldowns[name] = data.delay
	play_sound("shot")
	if name == "beam":
		var start := ship.global_position + direction * 28.0
		var distance := 760.0
		var hit_ship: CombatShip
		var hit_projectile: CombatProjectile
		for target in ships:
			if not is_instance_valid(target) or target.player == ship.player:
				continue
			var relative := offset_to(start, target.global_position)
			var forward := relative.dot(direction)
			if forward > 0.0 and forward < distance and (relative - direction * forward).length() < 22.0:
				distance = forward
				hit_ship = target
				hit_projectile = null
		for shot in projectiles:
			if not is_instance_valid(shot) or not is_instance_valid(shot.owner_ship) or shot.owner_ship.player == ship.player \
				or shot.kind != "missile" and shot.kind != "torpedo":
				continue
			var relative := offset_to(start, shot.global_position)
			var forward := relative.dot(direction)
			if forward > 0.0 and forward < distance and (relative - direction * forward).length() < 14.0:
				distance = forward
				hit_projectile = shot
				hit_ship = null
		if is_instance_valid(hit_ship):
			hit_ship.take_damage(data.damage * (0.65 if not ship.player else 1.0), "energy")
		elif is_instance_valid(hit_projectile):
			flash(hit_projectile.global_position, Color("8ee7ff"), 30.0)
			hit_projectile.queue_free()
		effects.append({"from": start, "to": start + direction * distance, "time": 0.1, "beam": true})
		return
	var projectile := CombatProjectile.new()
	projectile.game = self
	projectile.owner_ship = ship
	projectile.kind = name
	projectile.damage = data.damage * (0.65 if not ship.player else 1.0)
	projectile.position = ship.global_position + direction * 29.0
	projectile.velocity = direction * data.speed + ship.linear_velocity * 0.5
	projectile.lifetime = 4.5 if name == "missile" else 5.0 if name == "torpedo" else 2.0
	projectile.aim_point = get_global_mouse_position() if ship.player else ship.ai_target.global_position
	if name == "missile":
		projectile.target = locked_target
		projectile.aim_point = projectile.target.global_position
	elif name == "torpedo":
		projectile.fuse = maxf(1.2, projectile.global_position.distance_to(projectile.aim_point) / 330.0)
	add_child(projectile)
	projectiles.append(projectile)


func _nearest_target(from: CombatShip, radius: float, needs_lock := false) -> CombatShip:
	var best: CombatShip
	var distance := radius
	for ship in ships:
		if not is_instance_valid(ship) or ship == from or ship.player == from.player:
			continue
		if needs_lock and not can_fire_control(from, ship):
			continue
		var current := offset_to(from.global_position, ship.global_position).length()
		if current < distance:
			distance = current
			best = ship
	return best


func can_detect(observer: CombatShip, target: CombatShip) -> bool:
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return false
	var distance := offset_to(observer.global_position, target.global_position).length()
	return (observer.has_optical and observer.module_ready("optical") and not target.stealth_on and distance < observer.visual_radius) \
		or (observer.has_radar and observer.module_ready("radar") and not target.stealth_on and distance < observer.radar_radius) \
		or (observer.has_ir and observer.module_ready("ir") and target.is_hot() and distance < observer.ir_radius)


func can_fire_control(observer: CombatShip, target: CombatShip) -> bool:
	return observer.has_radar and observer.has_fire_control and observer.module_ready("radar") \
		and observer.module_ready("fire_control") and not target.stealth_on \
		and offset_to(observer.global_position, target.global_position).length() < observer.radar_radius


func offset_to(from: Vector2, to: Vector2) -> Vector2:
	var offset := to - from
	if wrap_enabled:
		offset.x = wrapf(offset.x + ARENA.x, 0.0, ARENA.x * 2.0) - ARENA.x
		offset.y = wrapf(offset.y + ARENA.y, 0.0, ARENA.y * 2.0) - ARENA.y
	return offset


func wrap_entity(entity: Node2D) -> void:
	if not wrap_enabled:
		return
	var at := entity.global_position
	entity.global_position = Vector2(wrapf(at.x + ARENA.x, 0.0, ARENA.x * 2.0) - ARENA.x,
		wrapf(at.y + ARENA.y, 0.0, ARENA.y * 2.0) - ARENA.y)


func _update_visibility() -> void:
	if not is_instance_valid(player):
		return
	for ship in ships:
		if is_instance_valid(ship) and ship != player:
			ship.visible = player.has_optical and player.module_ready("optical") and not ship.stealth_on \
				and offset_to(player.global_position, ship.global_position).length() < player.visual_radius


func _on_ship_destroyed(ship: CombatShip) -> void:
	flash(ship.global_position, Color("ff8d64"), 100.0)
	play_sound("hit")
	if ship == player:
		_finish(false)
	elif ship == generator:
		generator = null
		set_message("Warp generator down. Press SPACE to escape.")
	elif stage == "Mission" and _enemies_left() == 0:
		set_message("Raiders neutralized. Fly to the extraction marker.")


func _enemies_left() -> int:
	var total := 0
	for ship in ships:
		if is_instance_valid(ship) and ship != player and ship.hp > 0.0:
			total += 1
	return total


func _finish(won: bool) -> void:
	state = "won" if won else "lost"
	set_message("MISSION COMPLETE — press ESC for menu." if won else "SHIP LOST — press ESC for menu.", 999.0)
	for ship in ships:
		if is_instance_valid(ship):
			ship.freeze = true
			ship.fire_input = false
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()


func _activate_emp() -> void:
	if player.emp_cooldown > 0.0 or not player.spend("emp", 28.0, 30.0):
		return
	player.emp_cooldown = 8.0
	player.emp_timer = 1.2
	for ship in ships:
		if is_instance_valid(ship) and ship != player and offset_to(player.global_position, ship.global_position).length() < 350.0:
			ship.emp_timer = 3.0
	for projectile in projectiles:
		if is_instance_valid(projectile) and offset_to(player.global_position, projectile.global_position).length() < 350.0:
			if projectile.kind == "missile":
				projectile.queue_free()
			elif projectile.kind == "torpedo" and projectile.age < 0.7:
				projectile.age = 0.7
	flash(player.global_position, Color("8fd8ff"), 350.0)
	play_sound("emp")
	set_message("EMP pulse: nearby electronics offline; your systems recover first.")


func _hack_target() -> void:
	var target := _nearest_target(player, 350.0)
	if not is_instance_valid(target) or not player.spend("hack", 22.0, 20.0):
		set_message("HACK requires a target within 350 units and available power.")
		return
	var module: String = test_modules[test_target_index]
	if module == "fire_control":
		target.fire_control_spoof = true
		target.hack_timer = 5.0
	else:
		target.disabled[module] = 5.0
	flash(target.global_position, Color("bb8aff"), 60.0)
	set_message("HACK: %s compromised for 5 seconds." % module.to_upper())


func _blink() -> void:
	if player.blink_cooldown > 0.0 or not player.spend("blink", 30.0, 20.0):
		return
	var displacement := get_global_mouse_position() - player.global_position
	if displacement.length() > 0.0:
		flash(player.global_position, Color("78dfff"), 45.0)
		player.global_position += displacement.limit_length(320.0)
		wrap_entity(player)
		flash(player.global_position, Color("78dfff"), 45.0)
		player.blink_cooldown = 5.0


func _jump() -> void:
	if player.emp_timer > 0.0:
		set_message("JUMP OFFLINE: electronics recovering from EMP.")
		return
	if stage == "Warp Arena" and is_instance_valid(generator):
		player.emp_timer = 1.5
		set_message("Generator field interrupts the jump and disables electronics.")
		return
	if stage == "Mission" and (_enemies_left() > 0 or player.global_position.distance_to(extraction) > 150.0):
		set_message("Clear the raiders and reach the extraction marker first.")
		return
	_finish(true)


func flash(at: Vector2, color: Color, radius: float) -> void:
	effects.append({"at": at, "color": color, "radius": radius, "time": 0.32})


func play_sound(name: String) -> void:
	if sound_gates.get(name, 0.0) > 0.0:
		return
	sound_players[name].play()
	sound_gates[name] = 0.15


func set_message(value: String, duration := 5.0) -> void:
	message_label.text = value
	message_time = duration


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("081622e8")
	style.border_color = Color("348798")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	return style


func _add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("bce9ed"))
	button.add_theme_stylebox_override("normal", _panel_style())
	button.pressed.connect(action)
	parent.add_child(button)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	menu = PanelContainer.new()
	menu.position = Vector2(58, 52)
	menu.custom_minimum_size = Vector2(390, 0)
	menu.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(menu)
	var menu_box := VBoxContainer.new()
	menu.add_child(menu_box)
	var title := Label.new()
	title.text = "SOMALIA / SPACE PROGRAM"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("77e4e8"))
	menu_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "COMBAT SYSTEMS · WEB MVP\nChoose the mission or an isolated test range."
	subtitle.add_theme_color_override("font_color", Color("8baab5"))
	menu_box.add_child(subtitle)
	for selected in STAGES:
		_add_button(menu_box, selected, func() -> void: start_stage(selected))

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var top := PanelContainer.new()
	top.position = Vector2(16, 14)
	top.custom_minimum_size = Vector2(610, 88)
	top.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color("8fe8e6"))
	top_box.add_child(status_label)
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color("c6d5dd"))
	top_box.add_child(info_label)
	var bottom := PanelContainer.new()
	bottom.position = Vector2(16, 622)
	bottom.custom_minimum_size = Vector2(945, 82)
	bottom.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(bottom)
	instructions = Label.new()
	instructions.text = "W/S thrust/brake   A/D turn   MOUSE aim/fire   1–6 weapon   Q shield   F stealth\nE EMP   R HACK   TAB hack module   SHIFT blink   SPACE jump   O/P/I sensors   ESC menu"
	instructions.add_theme_color_override("font_color", Color("a7bfca"))
	bottom.add_child(instructions)
	message_label = Label.new()
	message_label.position = Vector2(215, 117)
	message_label.custom_minimum_size = Vector2(900, 50)
	message_label.add_theme_font_size_override("font_size", 17)
	message_label.add_theme_color_override("font_color", Color("ffd58b"))
	hud.add_child(message_label)

	test_panel = PanelContainer.new()
	test_panel.position = Vector2(1010, 15)
	test_panel.custom_minimum_size = Vector2(250, 0)
	test_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(test_panel)
	var test_box := VBoxContainer.new()
	test_panel.add_child(test_box)
	var test_title := Label.new()
	test_title.text = "TEST CONTROLS"
	test_title.add_theme_color_override("font_color", Color("78e7e5"))
	test_box.add_child(test_title)
	_add_button(test_box, "Reset scene", func() -> void: start_stage(stage))
	_add_button(test_box, "Restore power + cool", func() -> void:
		player.energy = 100.0
		player.heat.clear()
		player.overheated.clear())
	_add_button(test_box, "Toggle target stealth", func() -> void: _test_toggle_stealth())
	_add_button(test_box, "Toggle target shield", func() -> void: _test_toggle_shield())
	_add_button(test_box, "Toggle target heat", func() -> void: _test_toggle_heat())
	_add_button(test_box, "Toggle target radar", func() -> void: _test_toggle_radar())
	_add_button(test_box, "Target EMP", func() -> void: _test_target_emp())
	_add_button(test_box, "Spawn target", func() -> void: _spawn_ship(player.global_position + Vector2(0, -350)))
	_add_button(test_box, "Toggle wrap", func() -> void: wrap_enabled = not wrap_enabled)
	_add_button(test_box, "Next HACK module", func() -> void:
		test_target_index = (test_target_index + 1) % test_modules.size())


func _test_toggle_stealth() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.stealth_on = not target.stealth_on


func _test_toggle_shield() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.shield_on = not target.shield_on


func _test_toggle_heat() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.ai_enabled = false
		target.thrust_input = 0.0 if target.thrust_input > 0.0 else 1.0


func _test_toggle_radar() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.has_radar = not target.has_radar


func _test_target_emp() -> void:
	var target := _nearest_target(player, 1500.0)
	if is_instance_valid(target):
		target.emp_timer = 3.0


func _update_hud() -> void:
	status_label.text = "HULL %03d   POWER %03d   WEAPON %s" % [maxi(0, int(player.hp)), int(player.energy), player.weapon.to_upper()]
	var heat_value: float = player.heat.get(player.weapon, 0.0)
	var condition := "OVERLOAD" if player.energy < 25.0 else "READY"
	info_label.text = "%s  ·  HEAT %02d  ·  SHIELD %s  ·  STEALTH %s  ·  HACK %s" % [
		condition, int(heat_value), "ON" if player.shield_on else "OFF",
		"ON" if player.stealth_on else "OFF", test_modules[test_target_index].to_upper()]
	if stage == "Mission" and _enemies_left() == 0:
		info_label.text += "  ·  EXIT %dm" % int(player.global_position.distance_to(extraction))


func _draw() -> void:
	var grid_color := Color("184452")
	grid_color.a = 0.34
	for x in range(-2500, 2501, 100):
		draw_line(Vector2(x, -2200), Vector2(x, 2200), grid_color, 1.0)
	for y in range(-2200, 2201, 100):
		draw_line(Vector2(-2500, y), Vector2(2500, y), grid_color, 1.0)
	for i in 85:
		var point := Vector2(sin(float(i) * 42.17) * 2100.0, cos(float(i) * 17.31) * 1800.0)
		draw_circle(point, 1.2, Color("496675"))
	for i in 18:
		var center := Vector2(sin(float(i + 2) * 13.7) * 1700.0, cos(float(i + 4) * 7.3) * 1150.0)
		var radius := 28.0 + float(i % 5) * 10.0
		var points := PackedVector2Array()
		for corner in 7:
			var angle := TAU * float(corner) / 7.0
			points.append(center + Vector2.from_angle(angle) * radius * (0.8 + 0.18 * sin(float(i + corner) * 3.1)))
		draw_colored_polygon(points, Color("0b2029"))
		points.append(points[0])
		draw_polyline(points, Color("31515d"), 1.0)
	if state != "playing" or not is_instance_valid(player):
		return
	if wrap_enabled:
		draw_rect(Rect2(-ARENA, ARENA * 2.0), Color("4788a5"), false, 2.0)
	if stage == "Mission" and _enemies_left() == 0:
		draw_arc(extraction, 75.0, 0.0, TAU, 64, Color("71e8d9"), 3.0)
		draw_line(extraction + Vector2(-15, 0), extraction + Vector2(15, 0), Color("71e8d9"), 2.0)
	if player.has_radar and player.module_ready("radar"):
		draw_arc(player.global_position, player.radar_radius, 0.0, TAU, 96, Color("225969"), 1.0)
		for ship in ships:
			if is_instance_valid(ship) and ship != player and can_fire_control(player, ship):
				draw_rect(Rect2(ship.global_position - Vector2(16, 16), Vector2(32, 32)), Color("ff6673"), false, 1.5)
	if player.has_ir and player.module_ready("ir"):
		for ship in ships:
			if is_instance_valid(ship) and ship != player and ship.is_hot() \
				and offset_to(player.global_position, ship.global_position).length() < player.ir_radius:
				draw_arc(ship.global_position, 25.0, 0.0, TAU, 24, Color("ffae69"), 2.0)
	var cursor := get_global_mouse_position()
	draw_arc(cursor, 12.0, 0.0, TAU, 28, Color("92e5e5"), 1.5)
	draw_line(cursor + Vector2(-18, 0), cursor + Vector2(-8, 0), Color("92e5e5"), 1.5)
	draw_line(cursor + Vector2(8, 0), cursor + Vector2(18, 0), Color("92e5e5"), 1.5)
	for effect in effects:
		if effect.has("beam"):
			if wrap_enabled:
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						var shift := Vector2(dx * ARENA.x * 2.0, dy * ARENA.y * 2.0)
						draw_line(effect.from + shift, effect.to + shift, Color("98e8ff", effect.time * 10.0), 3.0)
			else:
				draw_line(effect.from, effect.to, Color("98e8ff", effect.time * 10.0), 3.0)
		else:
			draw_arc(effect.at, effect.radius * (1.0 - effect.time / 0.32), 0.0, TAU, 48,
				Color(effect.color, effect.time / 0.32), 2.0)
