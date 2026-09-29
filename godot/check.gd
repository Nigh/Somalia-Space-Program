extends SceneTree


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var game: Node2D = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for stage in game.STAGES:
		game.start_stage(stage)
		await process_frame
		assert(is_instance_valid(game.player), "%s did not spawn a player" % stage)
		assert(game.ships.size() >= 2, "%s did not spawn a target" % stage)
		for i in 4:
			await physics_frame
	game.start_stage("Sensors & Stealth")
	await process_frame
	var hot: CombatShip = game.ships[1]
	var cold: CombatShip = game.ships[2]
	assert(not game.can_fire_control(game.player, hot), "stealth must break radar lock")
	assert(game.can_detect(game.player, hot), "IR must reveal a hot stealth target")
	assert(not game.can_detect(game.player, cold), "cold stealth target must be hidden")
	game.player.has_ir = false
	assert(not game.can_detect(game.player, hot), "IR toggle must change detection")
	hot.take_damage(1.0, "kinetic")
	assert(not hot.stealth_on, "a hit must break stealth")
	game.start_stage("Power & Heat")
	await process_frame
	var before: float = game.player.energy
	assert(game.player.spend("cannon", 10.0, 110.0), "weapon should spend power")
	assert(game.player.energy < before and not game.player.module_ready("cannon"), "overheat must lock weapon")
	game.player.shield_on = true
	game.player.take_damage(20.0, "kinetic")
	assert(game.player.hp == 120.0, "shield must absorb a valid hit")
	game.start_stage("Weapons")
	await process_frame
	for weapon in game.player.loadout:
		game.player.weapon = weapon
		game.player.energy = 100.0
		game.player.heat.clear()
		game.player.overheated.clear()
		game.fire_weapon(game.player)
		for i in 8:
			await physics_frame
	assert(game.projectiles.size() > 0, "projectile weapons must spawn")
	game.start_stage("HACK")
	await process_frame
	game.test_target_index = 0
	game._hack_target()
	assert(game.ships[1].disabled.has("weapons"), "HACK must disable a selected module")
	game.test_target_index = 5
	game._hack_target()
	assert(game.ships[1].fire_control_spoof, "HACK must spoof fire control")
	game.start_stage("Guidance & EMP")
	await process_frame
	game.player.weapon = "missile"
	game.fire_weapon(game.player)
	assert(game.projectiles.size() == 1, "missile must launch with radar lock")
	var missile: CombatProjectile = game.projectiles[0]
	var last_fix := missile.aim_point
	game.player.has_radar = false
	game.ships[1].global_position += Vector2(200, 0)
	await physics_frame
	assert(missile.aim_point == last_fix, "missile must keep last fix after radar loss")
	game._activate_emp()
	assert(missile.is_queued_for_deletion(), "EMP must stop a nearby missile")
	game.start_stage("Weapons")
	await process_frame
	var shooter: CombatShip = game.ships[1]
	shooter.global_position = Vector2(0, 250)
	shooter.rotation = 0.0
	shooter.weapon = "beam"
	var incoming := CombatProjectile.new()
	incoming.game = game
	incoming.owner_ship = game.player
	incoming.kind = "missile"
	incoming.position = Vector2(0, 100)
	incoming.velocity = Vector2.ZERO
	game.add_child(incoming)
	game.projectiles.append(incoming)
	game.fire_weapon(shooter)
	assert(incoming.is_queued_for_deletion(), "beam must intercept a guided projectile")
	game.start_stage("Mission")
	await process_frame
	for enemy in game.ships.slice(1):
		enemy.take_damage(500.0, "kinetic")
	game.player.global_position = game.extraction
	game._jump()
	assert(game.state == "won", "mission must finish at extraction after combat")
	game.start_stage("Warp Arena")
	await process_frame
	assert(game.offset_to(Vector2(1490, 0), Vector2(-1490, 0)).length() == 20.0, "wrap distance failed")
	var seam_target: CombatShip = game._spawn_ship(Vector2(-1490, 0), false)
	seam_target.ai_enabled = false
	var seam_shot := CombatProjectile.new()
	seam_shot.game = game
	seam_shot.owner_ship = game.player
	seam_shot.kind = "cannon"
	seam_shot.position = Vector2(1470, 0)
	seam_shot.velocity = Vector2(400, 0)
	game.add_child(seam_shot)
	seam_shot._physics_process(0.1)
	assert(seam_target.hp < 120.0, "projectile must hit across the wrap seam")
	game._jump()
	assert(game.state == "playing" and game.player.emp_timer > 0.0, "generator must interrupt jump")
	game.generator.take_damage(500.0, "kinetic")
	await process_frame
	game.player.emp_timer = 0.0
	game._jump()
	assert(game.state == "won", "destroying generator must allow escape")
	print("Combat MVP checks passed")
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	quit()
