extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const CommonAttributes = preload(
	"res://Framework/Content/Authored/Entity/Shared/common_attributes.gd"
)
const IdentityData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Identity/identity.gd"
)
const StatisticsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Statistics/statistics.gd"
)
const NeedsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Needs/needs.gd"
)
const SkillsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Skills/skills.gd"
)
const ProgressionData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Progression/progression.gd"
)
const TalentsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Talents/talents.gd"
)
const AbilitiesData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Abilities/abilities.gd"
)
const PersonalityData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Personality/personality.gd"
)
const MoralityData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Morality/morality.gd"
)
const PhysicalFeaturesData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/PhysicalFeatures/physical_features.gd"
)
const SupernaturalData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Attributes/Supernatural/supernatural.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		CommonAttributes.defaults(),
		IdentityData.defaults(),
		StatisticsData.defaults(),
		NeedsData.defaults(),
		SkillsData.defaults(),
		ProgressionData.defaults(),
		TalentsData.defaults(),
		AbilitiesData.defaults(),
		PersonalityData.defaults(),
		MoralityData.defaults(),
		PhysicalFeaturesData.defaults(),
		SupernaturalData.defaults(),
	])
