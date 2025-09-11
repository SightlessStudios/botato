	extends "res://entities/units/movement_behaviors/player_movement_behavior.gd"

func get_movement()->Vector2:
	var options_node = $"/root/AutobattlerOptions"

	var enabled = options_node.enable_autobattler
	
	var item_weight = options_node.item_weight
	var projectile_weight = options_node.projectile_weight
	var tree_weight = options_node.tree_weight
	var boss_weight = options_node.boss_weight
	var bumper_weight = options_node.bumper_weight
	var egg_weight = options_node.egg_weight
	var bumper_distance = options_node.bumper_distance
	
#	print_debug("bumper distnace: ", bumper_distance)
#	print_debug("item_weight: ", item_weight)

	var player = get_parent()

	if not enabled and not CoopService.is_bot_by_index[player.player_index]:
		$"/root/Main/Camera".smoothing_enabled = false
		return .get_movement()

	var _entity_spawner = $"/root/Main/EntitySpawner"
	var _consumables_container = $"/root/Main/"._consumables
	var items_container = $"/root/Main/"._active_golds
	var projectiles_container = $"/root/Main/EnemyProjectiles"
	
	var char_name = RunData.get_player_character(0).name.to_lower()
	
	var is_soldier = char_name == "character_soldier"
	var is_streamer = char_name == "character_streamer"
	var is_bull = char_name == "character_bull"
	var is_masochist = char_name == "character_masochist"
	var is_lich = char_name == "character_lich"
	var is_vampire = char_name == "character_vampire"
	var is_druid = char_name == "character_druid"
	var is_builder = char_name == "character_builder"
	var is_pacifist = char_name == "character_pacifist"
	
	var weapon_range = 1_000
	var bumper_spacing = 50
	
	var max_health = float(player.max_stats.health)
	var current_health = float(player.current_stats.health)
	var low_hp = false
	var armor = float(player.current_stats.armor)
	var mitigation = 1.0
	if armor < 0:
		mitigation = (15 - 2 * armor) / (15 - armor)
	else:
		mitigation = 1 / ( 1 + ( armor / 15 ) )
	
	if is_bull:
		if current_health / max_health < .6:
			weapon_range = 1000
		else:
			weapon_range = 0

#	if is_lich:
#		if current_health / max_health > .4375:
#			weapon_range = 0	
#				Want to keep the lich healing constantly, which requires them to not be at full HP. Decided on keeping them just under 7/16ths (0.4375) Could possibly lower to 3/8ths (0.375) to stack sharp tooth more, but I think that strategy has hurt me more than helped.

	if is_lich:
		# Turn on Low HP flag when HP <= 7/16
		if current_health / max_health <= .4375:
			low_hp = true
		# Turn off Low HP flag when HP >+15/16
		if current_health / max_health >= .9375:
			low_hp = false
		if not low_hp:
			weapon_range = 0

	if is_builder:
		weapon_range = 1250

	if is_pacifist:
		must_run_away = true

	if is_masochist:
		if current_health / max_health > .4375:
			weapon_range = 0
				#	Want Masochist to constantly take managable amounts of damage. Let's keep them just under 4/8ths (.375) HP, or 7/16ths (0.4375) This would fully take advantage of the regen potion item whenever it appears.	

	if is_vampire:
		if current_health / max_health > 0.4375:
			weapon_range = 0
				#	This seems to work for the other redlining characters. Let's give it a shot.

#	if is_druid:
#		max_health = max_health + 10
#			This should trick the AI into still chasing down consumables at full HP for the druid.

	for weapon in player.current_weapons:
		#var max_range = weapon.stats.max_range
		var max_range = weapon.current_stats.max_range
		
		if max_range < weapon_range:
			weapon_range = max_range
	var preferred_distance_squared = weapon_range * weapon_range
	
	var move_vector = Vector2.ZERO
	
#	var consumable_weight = (1.0 - (current_health / max_health) ) * 2
	var consumable_weight = (1.0 - pow( ( current_health * 10 ) / (  ( max_health * 10 ) + 5 ), 2)) * 2
	# Eat consumables, weighted by missing hp
	for consumable in _consumables_container:
		var consumable_pos = consumable.position
		var consumable_to_player = consumable_pos - player.position
		var squared_distance_to_consumable = consumable_to_player.length_squared()
		
		var to_add = (consumable_to_player.normalized() / squared_distance_to_consumable) * 10 * consumable_weight
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
	
	# Go towards "items" (gold pickups)
	var item_weight_squared = item_weight * abs(item_weight)
	for item in items_container:
		var item_pos = item.position
		var item_to_player = item_pos - player.position
		var squared_distance_to_item = item_to_player.length_squared()
		
		var to_add = (item_to_player.normalized() / squared_distance_to_item) * item_weight_squared
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
			
	# Go towards "neutrals" (trees)
	var tree_weight_squared = tree_weight * abs(tree_weight)
	for neutral in _entity_spawner.neutrals:
		var neutral_pos = neutral.position
		var neutral_to_player = neutral_pos - player.position
		var squared_distance_to_neutral = neutral_to_player.length_squared()
		
		var to_add = (neutral_to_player.normalized() / squared_distance_to_neutral) * tree_weight_squared
		
		# Weigh down nearby trees to keep from getting stuck on them
		if squared_distance_to_neutral < (preferred_distance_squared / 2):
			to_add = to_add * -1

		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
			
	# Go away from projectiles
	var projectile_weight_squared = projectile_weight * abs(projectile_weight)
	for projectile in projectiles_container.get_children():
		if not projectile._hitbox or not projectile._hitbox.active:
			continue
		var projectile_shape = projectile._hitbox._collision.shape
		var extra_range = 0
		if projectile_shape is CircleShape2D:
			extra_range = projectile_shape.radius
		elif projectile_shape is RectangleShape2D:
			extra_range = projectile_shape.extents.x
			if projectile_shape.extents.y > extra_range:
				extra_range = projectile_shape.extents.y
		
		var projectile_pos = projectile.position
		var projectile_to_player = projectile_pos - player.position
		var extra_range_squared = extra_range * abs(extra_range)
		var squared_distance_to_item = projectile_to_player.length_squared() - extra_range_squared
		if squared_distance_to_item < 0:
			squared_distance_to_item = .001
		
		var to_add = (projectile_to_player.normalized() / squared_distance_to_item) * -1 * projectile_weight_squared
		if squared_distance_to_item > 250_000:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
	
	var shooting_anyone = false
	var must_run_away = false
	var egg_weight_squared = egg_weight * abs(egg_weight)
	
	# Move towards distant enemies, away from nearby ones.  Determined by weapons range.
	for enemy in _entity_spawner.enemies:
		var is_egg = enemy._attack_behavior is SpawningAttackBehavior
		var enemy_to_player = enemy.position - player.position
		var squared_distance_to_enemy = (enemy_to_player).length_squared()
		
		var to_add = (enemy_to_player.normalized() / squared_distance_to_enemy)
		
		if enemy.stats.base_drop_chance == 1:
			to_add = to_add * egg_weight_squared * 4
		
		if squared_distance_to_enemy < preferred_distance_squared:
			shooting_anyone = true
			to_add = to_add * -1
			if enemy._current_attack_behavior is ChargingAttackBehavior:
				if enemy._move_locked:
					enemy_to_player = enemy._current_attack_behavior._charge_direction.tangent()
					to_add = to_add * 4
			
		if squared_distance_to_enemy < (preferred_distance_squared / 4):
			must_run_away = true
			
		if is_egg:
			to_add = to_add * egg_weight_squared
		
		move_vector = move_vector + to_add
		
	# Move towards distant enemies, away from nearby ones.  Determined by weapons range.
	var boss_weight_squared = boss_weight * abs(boss_weight)
	for boss in _entity_spawner.bosses:
		var boss_to_player = boss.position - player.position
		var squared_distance_to_boss = (boss_to_player).length_squared()
		
		var to_add = (boss_to_player.normalized() / squared_distance_to_boss) * boss_weight_squared
		if squared_distance_to_boss < preferred_distance_squared:
			shooting_anyone = true
			to_add = to_add * -1
			if boss._current_attack_behavior is ChargingAttackBehavior:
				if boss._move_locked:
					squared_distance_to_boss = squared_distance_to_boss / 4
					boss_to_player = boss._current_attack_behavior._charge_direction.tangent()
			
		if squared_distance_to_boss < (preferred_distance_squared / 4):
			must_run_away = true
		
		move_vector = move_vector + to_add
		
	
	var far_corner = ZoneService.current_zone_max_position
	var map_corners = [Vector2(0,0), Vector2(0, far_corner.y), Vector2(far_corner.x, 0), Vector2(far_corner.x, far_corner.y)]
	var corner_distance = 300
	var square_corner_distance = corner_distance * corner_distance
	
	for corner in map_corners:
		var corner_to_player = corner - player.position
		var squared_distance_to_corner = corner_to_player.length_squared()
		
		var to_add = (corner_to_player.normalized() / squared_distance_to_corner) * -2
		if squared_distance_to_corner > square_corner_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
	
	var bumper_x = 0
	var square_bumper_distance = bumper_distance * bumper_distance
	
	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, 0)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var to_add = (Vector2(-1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		
		bumper_x = bumper_x + bumper_spacing
		
	bumper_x = 0
	while bumper_x < far_corner.x:
		var bumper_position = Vector2(bumper_x, far_corner.y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var to_add = (Vector2(1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		
		bumper_x = bumper_x + bumper_spacing
		
	var bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(0, bumper_y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var to_add = (Vector2(1,1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		
		bumper_y = bumper_y + bumper_spacing
		
	bumper_y = 0
	while bumper_y < far_corner.y:
		var bumper_position = Vector2(far_corner.x, bumper_y)
		
		var squared_distance = (bumper_position - player.position).length_squared()
		
		var to_add = (Vector2(-1,-1).normalized() / squared_distance) * bumper_weight
		if squared_distance > square_bumper_distance:
			to_add = Vector2.ZERO
		if not is_nan(to_add.x) and not is_nan(to_add.y):
			move_vector = move_vector + to_add
		
		bumper_y = bumper_y + bumper_spacing
		
# Trying to get soldier to make a tactical retreat, rather than just run away. Implementing a random chance the must run away state gets turned off.
	if is_soldier:
		must_run_away = true
		if must_run_away and randi_range(1, 100) > 1:
			return Vector2.ZERO
	
	if (shooting_anyone and not must_run_away) and is_soldier:
		return Vector2.ZERO
		
	return move_vector.normalized()
