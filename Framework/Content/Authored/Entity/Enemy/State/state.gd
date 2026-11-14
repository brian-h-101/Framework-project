extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const ActivitiesData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Activities/activities.gd"
)
const SchedulesData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Schedules/schedules.gd"
)
const ObligationsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Obligations/obligations.gd"
)
const GoalsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Goals/goals.gd"
)
const AIData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/AI/ai.gd"
)
const PerceptionData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Perception/perception.gd"
)
const CombatData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Combat/combat.gd"
)
const TravelData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Travel/travel.gd"
)
const TransformationData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Transformation/transformation.gd"
)
const FeedingData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Feeding/feeding.gd"
)
const HuntingData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Hunting/hunting.gd"
)
const FrenzyData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/Frenzy/frenzy.gd"
)
const GameplayRecordsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/State/GameplayRecords/gameplay_records.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		ActivitiesData.defaults(),
		SchedulesData.defaults(),
		ObligationsData.defaults(),
		GoalsData.defaults(),
		AIData.defaults(),
		PerceptionData.defaults(),
		CombatData.defaults(),
		TravelData.defaults(),
		TransformationData.defaults(),
		FeedingData.defaults(),
		HuntingData.defaults(),
		FrenzyData.defaults(),
		GameplayRecordsData.defaults(),
	])
