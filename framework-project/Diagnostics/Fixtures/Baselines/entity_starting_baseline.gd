extends RefCounted


# Captured composed values before the shared-library consolidation.
# These expectations do not import the live authoring fragments.
static func definition(preset_id: StringName) -> Dictionary:
	match preset_id:
		&"enemy":
			return {
				"containers": {
					&"abilities": {
						"reflex": 12
					},
					&"activity": {
						"current": "guarding",
						"interrupted": false,
						"progress": 0,
						"started_tick": 0
					},
					&"ai": {
						"aggro_range": 4,
						"behavior_profile": "guard",
						"controller": "scripted",
						"target_entity_id": 0
					},
					&"anatomy": {
						"body_plan": "humanoid",
						"dominant_hand": "right",
						"parts": ["head", "torso", "left_arm", "right_arm", "left_hand", "right_hand", "left_leg", "right_leg"]
					},
					&"combat": {
						"armor": 2,
						"attack_cost": 1,
						"damage": 4,
						"defending": false,
						"range": 1,
						"team_id": "raiders"
					},
					&"crafting": {
						"known_recipe_ids": ["simple_bandage"],
						"recipes": {
							"simple_bandage": {
								"duration_ticks": 2,
								"ingredients": {
									"cloth": 2
								},
								"outputs": {
									"bandage": 1
								}
							}
						},
						"station_id": "workbench"
					},
					&"crime": {
						"bounty": 0,
						"jurisdiction_id": "outpost",
						"offenses": [],
						"wanted": false
					},
					&"dialogue_references": {
						"default_dialogue_id": "enemy_warning",
						"known_dialogue_ids": ["enemy_warning"],
						"last_node_id": ""
					},
					&"equipment": {
						"allowed_slot_types": ["hand", "body"],
						"modifier_ids": [],
						"slots": {
							"body": null,
							"main_hand": null,
							"off_hand": null
						}
					},
					&"evidence": {
						"discovered": {
							"footprints": {
								"confidence": 0.5,
								"source": "outpost_gate"
							}
						},
						"examined_ids": []
					},
					&"factions": {
						"memberships": {
							"raiders": {
								"rank": "scout",
								"standing": 10
							}
						}
					},
					&"feeding": {
						"diet": "omnivore",
						"last_meal_tick": 0,
						"preferred_food_ids": ["ration"],
						"satiation": 70
					},
					&"forms": {
						"definitions": {
							"human": {
								"body_plan": "humanoid",
								"display_name": "Human"
							}
						},
						"unlocked_ids": ["human"]
					},
					&"frenzy": {
						"active": false,
						"intensity": 0,
						"recovery_per_tick": 5,
						"threshold": 100
					},
					&"gameplay_records": {
						"counters": {
							"encounters_won": 0,
							"items_collected": 0,
							"locations_discovered": 1
						},
						"last_event": ""
					},
					&"goals": {
						"active_goal_id": "guard_post",
						"priorities": {
							"guard_post": 10,
							"rest": 3
						},
						"progress": {
							"guard_post": 0
						}
					},
					&"health": {
						"current": 100,
						"maximum": 100
					},
					&"hunting": {
						"active": false,
						"last_attempt_tick": -1,
						"preferred_region_ids": ["woodland"],
						"target_species": "game_animal",
						"tracks_found": 0
					},
					&"identity": {
						"name": "enemy"
					},
					&"illness": {
						"active": [],
						"history": [{
							"id": "winter_cold",
							"recovered": true
						}],
						"immunities": []
					},
					&"injuries": {
						"active": [{
							"body_part": "right_arm",
							"id": "minor_bruise",
							"severity": 1,
							"treated": false
						}],
						"healed_ids": []
					},
					&"interactions": {
						"available": []
					},
					&"intrusions": {
						"foreign_objects": [{
							"body_part": "left_hand",
							"id": "wood_splinter",
							"removable": true
						}],
						"installed": []
					},
					&"inventory": {
						"capacity": 6,
						"items": {
							"cloth": 2,
							"ration": 1
						}
					},
					&"investigation": {
						"active_case_id": "camp_security",
						"conclusions": [],
						"leads": {
							"outpost_gate": {
								"evidence_ids": ["footprints"],
								"status": "unexamined"
							}
						}
					},
					&"journal": {
						"entries": [{
							"id": "watch_started",
							"text": "Assigned to watch the outpost.",
							"tick": 0,
							"title": "On Watch"
						}],
						"pinned_entry_ids": []
					},
					&"knowledge": {
						"facts": {
							"camp_route_known": true
						},
						"last_updated_tick": 0,
						"learned_from": {
							"camp_route_known": "briefing"
						}
					},
					&"life_experience": {
						"background": "scout",
						"education": ["basic_literacy"],
						"employment": [{
							"role": "guard",
							"years": 3
						}],
						"milestones": ["first_patrol"]
					},
					&"modifiers": {
						"active": [{
							"id": "alert_awareness",
							"operation": "add",
							"source_effect_id": "alert",
							"target_attribute": "awareness",
							"target_container": "perception",
							"value": 5
						}]
					},
					&"morality": {
						"compassion": 20,
						"degeneration": 10,
						"integrity": 30,
						"outlook": "self_serving"
					},
					&"narrative": {
						"alarm_raised": false,
						"met_player": false,
						"surrendered": false
					},
					&"needs": {
						"fatigue": {
							"current": 25,
							"maximum": 100
						},
						"hunger": {
							"current": 30,
							"maximum": 100
						},
						"thirst": {
							"current": 20,
							"maximum": 100
						}
					},
					&"obligations": {
						"entries": [{
							"amount": 2,
							"currency": "coin",
							"due_tick": 24,
							"id": "daily_upkeep",
							"repeat_every_ticks": 24,
							"status": "pending"
						}],
						"last_completed_tick": 0
					},
					&"ownership": {
						"borrowed_item_keys": [],
						"can_transfer": true,
						"owned_item_keys": []
					},
					&"perception": {
						"awareness": 50,
						"concealment": 30,
						"hearing_range": 7,
						"sight_range": 6,
						"visible_entity_ids": []
					},
					&"personal_finance": {
						"accounts": {
							"savings": {
								"balance": 0,
								"currency": "coin"
							}
						},
						"debts": [],
						"income_per_day": 4,
						"upkeep_per_day": 2
					},
					&"personality": {
						"aggression": 75,
						"courage": 55,
						"curiosity": 30,
						"empathy": 20
					},
					&"physical_features": {
						"age": 35,
						"distinguishing_marks": ["scar_left_brow"],
						"eye_color": "grey",
						"height_cm": 182
					},
					&"progression": {
						"experience": 40,
						"level": 2,
						"next_level_experience": 200,
						"unspent_points": 0
					},
					&"property": {
						"owned": [],
						"rented": [{
							"id": "outpost_bunk",
							"rent_per_day": 2
						}]
					},
					&"quest_progress": {
						"quests": {
							"guard_post": {
								"objectives": {
									"intruders_spotted": 0
								},
								"reward_claimed": false,
								"stage": "active"
							}
						}
					},
					&"relationships": {
						"records": {
							"patrol_leader": {
								"affinity": 10,
								"trust": 20
							}
						}
					},
					&"reputation": {
						"standings": {
							"outpost": 10,
							"village": -10
						}
					},
					&"residency": {
						"permitted_zones": ["outpost"],
						"residence_id": "outpost_bunk",
						"status": "lodger"
					},
					&"schedule": {
						"current_stop_index": 0,
						"last_processed_tick": 0,
						"period_ticks": 24,
						"stops": [{
							"activity": "guarding",
							"location_id": "outpost_gate",
							"start_tick": 0
						}, {
							"activity": "resting",
							"location_id": "outpost_bunk",
							"start_tick": 8
						}, {
							"activity": "guarding",
							"location_id": "outpost_gate",
							"start_tick": 16
						}]
					},
					&"skills": {
						"medicine": {
							"experience": 0,
							"rank": 1
						},
						"stealth": {
							"experience": 10,
							"rank": 3
						},
						"survival": {
							"experience": 25,
							"rank": 3
						}
					},
					&"speed": {
						"current": 10,
						"maximum": 50
					},
					&"status_effects": {
						"active": [{
							"id": "alert",
							"remaining_ticks": 2,
							"source": "initial_state",
							"stacks": 1
						}]
					},
					&"supernatural": {
						"origin": "mortal",
						"resource": {
							"current": 0,
							"id": "none",
							"maximum": 0
						},
						"traits": []
					},
					&"talents": {
						"known": ["ambusher"],
						"ranks": {
							"ambusher": 1
						},
						"unspent_points": 0
					},
					&"transformation": {
						"active": false,
						"available_form_ids": ["human"],
						"cooldown_remaining": 0,
						"current_form_id": "human",
						"previous_form_id": ""
					},
					&"travel": {
						"current_location_id": "outpost_gate",
						"destination_id": "",
						"known_location_ids": ["outpost_gate"],
						"progress": 0,
						"vehicle_id": ""
					},
					&"treatments": {
						"active": [],
						"known": {
							"bandage": {
								"duration_ticks": 3,
								"healing_per_tick": 1,
								"target": "wound"
							},
							"rest": {
								"duration_ticks": 4,
								"recovery_per_tick": 2,
								"target": "fatigue"
							}
						}
					},
					&"wallet": {
						"balance": 8,
						"currency": "coin"
					}
				},
				"id": &"enemy"
			}
		&"player":
			return {
				"containers": {
					&"abilities": {
						"precognition": 5
					},
					&"activity": {
						"current": "idle",
						"interrupted": false,
						"progress": 0,
						"started_tick": 0
					},
					&"ai": {
						"aggro_range": 0,
						"behavior_profile": "manual",
						"controller": "player",
						"target_entity_id": 0
					},
					&"anatomy": {
						"body_plan": "humanoid",
						"dominant_hand": "right",
						"parts": ["head", "torso", "left_arm", "right_arm", "left_hand", "right_hand", "left_leg", "right_leg"]
					},
					&"combat": {
						"armor": 1,
						"attack_cost": 1,
						"damage": 6,
						"defending": false,
						"range": 1,
						"team_id": "travelers"
					},
					&"crafting": {
						"known_recipe_ids": ["simple_bandage"],
						"recipes": {
							"simple_bandage": {
								"duration_ticks": 2,
								"ingredients": {
									"cloth": 2
								},
								"outputs": {
									"bandage": 1
								}
							}
						},
						"station_id": "workbench"
					},
					&"crime": {
						"bounty": 0,
						"jurisdiction_id": "village",
						"offenses": [],
						"wanted": false
					},
					&"dialogue_references": {
						"default_dialogue_id": "player_intro",
						"known_dialogue_ids": ["player_intro"],
						"last_node_id": ""
					},
					&"equipment": {
						"allowed_slot_types": ["hand", "body"],
						"modifier_ids": [],
						"slots": {
							"body": null,
							"main_hand": null,
							"off_hand": null
						}
					},
					&"evidence": {
						"discovered": {
							"torn_note": {
								"confidence": 0.5,
								"source": "old_bridge"
							}
						},
						"examined_ids": []
					},
					&"factions": {
						"memberships": {
							"villagers": {
								"rank": "outsider",
								"standing": 5
							}
						}
					},
					&"feeding": {
						"diet": "omnivore",
						"last_meal_tick": 0,
						"preferred_food_ids": ["ration"],
						"satiation": 90
					},
					&"forms": {
						"definitions": {
							"human": {
								"body_plan": "humanoid",
								"display_name": "Human"
							},
							"wolf": {
								"body_plan": "quadruped",
								"display_name": "Wolf"
							}
						},
						"unlocked_ids": ["human"]
					},
					&"frenzy": {
						"active": false,
						"intensity": 0,
						"recovery_per_tick": 5,
						"threshold": 100
					},
					&"gameplay_records": {
						"counters": {
							"encounters_won": 0,
							"items_collected": 0,
							"locations_discovered": 1
						},
						"last_event": ""
					},
					&"goals": {
						"active_goal_id": "explore",
						"priorities": {
							"explore": 10,
							"rest": 5
						},
						"progress": {
							"explore": 0
						}
					},
					&"health": {
						"current": 150,
						"maximum": 150
					},
					&"hunting": {
						"active": false,
						"last_attempt_tick": -1,
						"preferred_region_ids": ["woodland"],
						"target_species": "game_animal",
						"tracks_found": 0
					},
					&"identity": {
						"name": "Player"
					},
					&"illness": {
						"active": [],
						"history": [{
							"id": "winter_cold",
							"recovered": true
						}],
						"immunities": []
					},
					&"injuries": {
						"active": [{
							"body_part": "left_arm",
							"id": "minor_bruise",
							"severity": 1,
							"treated": false
						}],
						"healed_ids": []
					},
					&"interactions": {
						"available": [&"strike"]
					},
					&"intrusions": {
						"foreign_objects": [],
						"installed": []
					},
					&"inventory": {
						"capacity": 10,
						"items": {}
					},
					&"investigation": {
						"active_case_id": "missing_supplies",
						"conclusions": [],
						"leads": {
							"old_bridge": {
								"evidence_ids": ["torn_note"],
								"status": "unexamined"
							}
						}
					},
					&"journal": {
						"entries": [{
							"id": "arrival",
							"text": "Reached the village.",
							"tick": 0,
							"title": "Arrival"
						}],
						"pinned_entry_ids": []
					},
					&"knowledge": {
						"facts": {
							"bridge_damaged": true
						},
						"last_updated_tick": 0,
						"learned_from": {
							"bridge_damaged": "observation"
						}
					},
					&"life_experience": {
						"background": "traveler",
						"education": ["basic_literacy"],
						"employment": [{
							"role": "courier",
							"years": 2
						}],
						"milestones": ["first_journey"]
					},
					&"modifiers": {
						"active": [{
							"id": "alert_awareness",
							"operation": "add",
							"source_effect_id": "alert",
							"target_attribute": "awareness",
							"target_container": "perception",
							"value": 5
						}]
					},
					&"morality": {
						"compassion": 75,
						"degeneration": 0,
						"integrity": 70,
						"outlook": "compassionate"
					},
					&"narrative": {
						"accepted_quest": false,
						"discovered_cave": false,
						"met_guard": false
					},
					&"needs": {
						"fatigue": {
							"current": 15,
							"maximum": 100
						},
						"hunger": {
							"current": 10,
							"maximum": 100
						},
						"thirst": {
							"current": 5,
							"maximum": 100
						}
					},
					&"obligations": {
						"entries": [{
							"amount": 2,
							"currency": "coin",
							"due_tick": 24,
							"id": "daily_upkeep",
							"repeat_every_ticks": 24,
							"status": "pending"
						}],
						"last_completed_tick": 0
					},
					&"ownership": {
						"borrowed_item_keys": [],
						"can_transfer": true,
						"owned_item_keys": []
					},
					&"perception": {
						"awareness": 30,
						"concealment": 10,
						"hearing_range": 5,
						"sight_range": 8,
						"visible_entity_ids": []
					},
					&"personal_finance": {
						"accounts": {
							"savings": {
								"balance": 100,
								"currency": "coin"
							}
						},
						"debts": [],
						"income_per_day": 10,
						"upkeep_per_day": 2
					},
					&"personality": {
						"aggression": 20,
						"courage": 65,
						"curiosity": 80,
						"empathy": 70
					},
					&"physical_features": {
						"age": 28,
						"distinguishing_marks": [],
						"eye_color": "brown",
						"height_cm": 175
					},
					&"progression": {
						"experience": 0,
						"level": 1,
						"next_level_experience": 100,
						"unspent_points": 3
					},
					&"property": {
						"owned": [{
							"id": "village_room",
							"share": 1,
							"type": "room"
						}],
						"rented": []
					},
					&"quest_progress": {
						"quests": {
							"delivery": {
								"objectives": {
									"supplies_delivered": 0
								},
								"reward_claimed": false,
								"stage": "not_started"
							}
						}
					},
					&"relationships": {
						"records": {
							"village_guard": {
								"affinity": 0,
								"trust": 0
							}
						}
					},
					&"reputation": {
						"standings": {
							"outpost": -5,
							"village": 0
						}
					},
					&"residency": {
						"permitted_zones": ["village"],
						"residence_id": "village_room",
						"status": "resident"
					},
					&"schedule": {
						"current_stop_index": 0,
						"last_processed_tick": 0,
						"period_ticks": 24,
						"stops": [{
							"activity": "idle",
							"location_id": "village_square",
							"start_tick": 0
						}, {
							"activity": "exploring",
							"location_id": "old_bridge",
							"start_tick": 8
						}, {
							"activity": "resting",
							"location_id": "village_room",
							"start_tick": 16
						}]
					},
					&"skills": {
						"medicine": {
							"experience": 0,
							"rank": 1
						},
						"stealth": {
							"experience": 10,
							"rank": 1
						},
						"survival": {
							"experience": 25,
							"rank": 2
						}
					},
					&"speed": {
						"current": 20,
						"maximum": 50
					},
					&"status_effects": {
						"active": [{
							"id": "alert",
							"remaining_ticks": 3,
							"source": "initial_state",
							"stacks": 1
						}]
					},
					&"supernatural": {
						"origin": "latent_psychic",
						"resource": {
							"current": 10,
							"id": "focus",
							"maximum": 10
						},
						"traits": ["premonition"]
					},
					&"talents": {
						"known": ["observant"],
						"ranks": {
							"observant": 1
						},
						"unspent_points": 1
					},
					&"transformation": {
						"active": false,
						"available_form_ids": ["human"],
						"cooldown_remaining": 0,
						"current_form_id": "human",
						"previous_form_id": ""
					},
					&"travel": {
						"current_location_id": "village_square",
						"destination_id": "",
						"known_location_ids": ["village_square"],
						"progress": 0,
						"vehicle_id": ""
					},
					&"treatments": {
						"active": [],
						"known": {
							"bandage": {
								"duration_ticks": 3,
								"healing_per_tick": 1,
								"target": "wound"
							},
							"rest": {
								"duration_ticks": 4,
								"recovery_per_tick": 2,
								"target": "fatigue"
							}
						}
					},
					&"wallet": {
						"balance": 25,
						"currency": "coin"
					}
				},
				"id": &"player"
			}
		&"town_guard":
			return {
				"containers": {
					&"health": {
						"current": 100,
						"maximum": 100
					},
					&"identity": {
						"name": "TownGuard"
					},
					&"interactions": {
						"available": []
					},
					&"speed": {
						"current": 20,
						"maximum": 50
					}
				},
				"id": &"town_guard"
			}
	return {}


static func category(
	preset_id: StringName,
	category_name: String
) -> Dictionary[StringName, Dictionary]:
	var category_keys: Dictionary = {
		"Attributes": [&"abilities", &"health", &"identity", &"morality", &"needs", &"personality", &"physical_features", &"progression", &"skills", &"speed", &"supernatural", &"talents"],
		"BodyPart": [&"anatomy", &"forms", &"illness", &"injuries", &"intrusions", &"treatments"],
		"Container": [&"crafting", &"equipment", &"inventory", &"ownership", &"personal_finance", &"property", &"residency", &"wallet"],
		"Interactions": [&"interactions"],
		"Narrative": [&"crime", &"dialogue_references", &"evidence", &"factions", &"investigation", &"journal", &"knowledge", &"life_experience", &"narrative", &"quest_progress", &"relationships", &"reputation"],
		"State": [&"activity", &"ai", &"combat", &"feeding", &"frenzy", &"gameplay_records", &"goals", &"hunting", &"obligations", &"perception", &"schedule", &"transformation", &"travel"],
		"StatusEffects": [&"modifiers", &"status_effects"],
	}
	var containers: Dictionary = definition(preset_id)["containers"]
	var selected: Dictionary[StringName, Dictionary] = {}
	for container_id in category_keys[category_name]:
		if containers.has(container_id):
			selected[container_id] = containers[container_id].duplicate(true)
	return selected
