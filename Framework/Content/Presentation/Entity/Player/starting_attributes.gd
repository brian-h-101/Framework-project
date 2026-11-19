extends RefCounted

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
	return StartingAttributes.define(
		&"player",
		[
			"Attributes/Abilities/precognition.gd",
			"Attributes/Identity/identity.gd",
			"Attributes/Morality/morality.gd",
			"Attributes/Needs/needs.gd",
			"Attributes/Personality/personality.gd",
			"Attributes/PhysicalFeatures/physical_features.gd",
			"Attributes/Progression/progression.gd",
			"Attributes/Skills/skills.gd",
			"Attributes/Statistics/health.gd",
			"Attributes/Statistics/speed.gd",
			"Attributes/Supernatural/supernatural.gd",
			"Attributes/Talents/talents.gd",
			"BodyPart/Anatomy/anatomy.gd",
			"BodyPart/Forms/forms.gd",
			"BodyPart/Illness/illness.gd",
			"BodyPart/Injuries/injuries.gd",
			"BodyPart/Intrusions/intrusions.gd",
			"BodyPart/Treatments/treatments.gd",
			"Container/Crafting/crafting.gd",
			"Container/Equipment/equipment.gd",
			"Container/Ownership/ownership.gd",
			"Container/PersonalFinance/personal_finance.gd",
			"Container/Property/property.gd",
			"Container/Residency/residency.gd",
			"Container/Wallet/wallet.gd",
			"Container/inventory.gd",
			"Interactions/interactions.gd",
			"Narrative/Crime/crime.gd",
			"Narrative/DialogueReferences/dialogue_references.gd",
			"Narrative/Evidence/evidence.gd",
			"Narrative/Factions/factions.gd",
			"Narrative/Flags/flags.gd",
			"Narrative/Investigation/investigation.gd",
			"Narrative/Journal/journal.gd",
			"Narrative/Knowledge/knowledge.gd",
			"Narrative/LifeExperience/life_experience.gd",
			"Narrative/QuestProgress/quest_progress.gd",
			"Narrative/Relationships/relationships.gd",
			"Narrative/Reputation/reputation.gd",
			"State/AI/ai.gd",
			"State/Activities/activities.gd",
			"State/Combat/combat.gd",
			"State/Feeding/feeding.gd",
			"State/Frenzy/frenzy.gd",
			"State/GameplayRecords/gameplay_records.gd",
			"State/Goals/goals.gd",
			"State/Hunting/hunting.gd",
			"State/Obligations/obligations.gd",
			"State/Perception/perception.gd",
			"State/Schedules/schedules.gd",
			"State/Transformation/transformation.gd",
			"State/Travel/travel.gd",
			"StatusEffects/ActiveEffects/active_effects.gd",
			"StatusEffects/Modifiers/modifiers.gd",
		],
		{
			&"abilities": {
				"precognition": 5
			},
			&"activity": {
				"current": "idle"
			},
			&"ai": {
				"behavior_profile": "manual",
				"controller": "player"
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
				"jurisdiction_id": "village"
			},
			&"dialogue_references": {
				"default_dialogue_id": "player_intro",
				"known_dialogue_ids": ["player_intro"]
			},
			&"equipment": {
				"allowed_slot_types": ["hand", "body"],
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
				}
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
				"recovery_per_tick": 5,
				"threshold": 100
			},
			&"gameplay_records": {
				"counters": {
					"encounters_won": 0,
					"items_collected": 0,
					"locations_discovered": 1
				}
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
				"last_attempt_tick": -1,
				"preferred_region_ids": ["woodland"],
				"target_species": "game_animal"
			},
			&"identity": {
				"name": "Player"
			},
			&"illness": {
				"history": [{
					"id": "winter_cold",
					"recovered": true
				}]
			},
			&"injuries": {
				"active": [{
					"body_part": "left_arm",
					"id": "minor_bruise",
					"severity": 1,
					"treated": false
				}]
			},
			&"interactions": {
				"available": [&"strike"]
			},
			&"inventory": {
				"capacity": 10
			},
			&"investigation": {
				"active_case_id": "missing_supplies",
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
				}]
			},
			&"knowledge": {
				"facts": {
					"bridge_damaged": true
				},
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
				}]
			},
			&"ownership": {
				"can_transfer": true
			},
			&"perception": {
				"awareness": 30,
				"concealment": 10,
				"hearing_range": 5,
				"sight_range": 8
			},
			&"personal_finance": {
				"accounts": {
					"savings": {
						"balance": 100,
						"currency": "coin"
					}
				},
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
				"eye_color": "brown",
				"height_cm": 175
			},
			&"progression": {
				"level": 1,
				"next_level_experience": 100,
				"unspent_points": 3
			},
			&"property": {
				"owned": [{
					"id": "village_room",
					"share": 1,
					"type": "room"
				}]
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
				"available_form_ids": ["human"],
				"current_form_id": "human"
			},
			&"travel": {
				"current_location_id": "village_square",
				"known_location_ids": ["village_square"]
			},
			&"treatments": {
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
		}
	)
