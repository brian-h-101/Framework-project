extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const FlagsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Flags/flags.gd"
)
const JournalData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Journal/journal.gd"
)
const DialogueReferencesData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/DialogueReferences/dialogue_references.gd"
)
const QuestProgressData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/QuestProgress/quest_progress.gd"
)
const EvidenceData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Evidence/evidence.gd"
)
const InvestigationData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Investigation/investigation.gd"
)
const KnowledgeData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Knowledge/knowledge.gd"
)
const RelationshipsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Relationships/relationships.gd"
)
const ReputationData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Reputation/reputation.gd"
)
const FactionsData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Factions/factions.gd"
)
const CrimeData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/Crime/crime.gd"
)
const LifeExperienceData = preload(
	"res://Framework/Content/Authored/Entity/Enemy/Narrative/LifeExperience/life_experience.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		FlagsData.defaults(),
		JournalData.defaults(),
		DialogueReferencesData.defaults(),
		QuestProgressData.defaults(),
		EvidenceData.defaults(),
		InvestigationData.defaults(),
		KnowledgeData.defaults(),
		RelationshipsData.defaults(),
		ReputationData.defaults(),
		FactionsData.defaults(),
		CrimeData.defaults(),
		LifeExperienceData.defaults(),
	])
