extends RefCounted

const StartingAttributes = preload(
	"res://Framework/Env/Setup/starting_attributes.gd"
)


static func definition() -> Dictionary:
	return StartingAttributes.define(
		&"enemy",
		[
			"Attributes/Abilities/reflex.gd",
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
				"reflex": 12
			},
			&"activity": {
				"current": "guarding"
			},
			&"ai": {
				"aggro_range": 4,
				"behavior_profile": "guard",
				"controller": "scripted"
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
				"jurisdiction_id": "outpost"
			},
			&"dialogue_references": {
				"default_dialogue_id": "enemy_warning",
				"known_dialogue_ids": ["enemy_warning"]
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
					"footprints": {
						"confidence": 0.5,
						"source": "outpost_gate"
					}
				}
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
				"active_goal_id": "guard_post",
				"priorities": {
					"guard_post": 10,
					"rest": 3
				},
				"progress": {
					"guard_post": 0
				}
			},
			&"hunting": {
				"last_attempt_tick": -1,
				"preferred_region_ids": ["woodland"],
				"target_species": "game_animal"
			},
			&"identity": {
				"name": "enemy"
			},
			&"illness": {
				"history": [{
					"id": "winter_cold",
					"recovered": true
				}]
			},
			&"injuries": {
				"active": [{
					"body_part": "right_arm",
					"id": "minor_bruise",
					"severity": 1,
					"treated": false
				}]
			},
			&"intrusions": {
				"foreign_objects": [{
					"body_part": "left_hand",
					"id": "wood_splinter",
					"removable": true
				}]
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
				}]
			},
			&"knowledge": {
				"facts": {
					"camp_route_known": true
				},
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
				}]
			},
			&"ownership": {
				"can_transfer": true
			},
			&"perception": {
				"awareness": 50,
				"concealment": 30,
				"hearing_range": 7,
				"sight_range": 6
			},
			&"personal_finance": {
				"accounts": {
					"savings": {
						"balance": 0,
						"currency": "coin"
					}
				},
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
				"next_level_experience": 200
			},
			&"property": {
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
				"current": 10
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
				}
			},
			&"talents": {
				"known": ["ambusher"],
				"ranks": {
					"ambusher": 1
				}
			},
			&"transformation": {
				"available_form_ids": ["human"],
				"current_form_id": "human"
			},
			&"travel": {
				"current_location_id": "outpost_gate",
				"known_location_ids": ["outpost_gate"]
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
				"balance": 8,
				"currency": "coin"
			}
		}
	)
