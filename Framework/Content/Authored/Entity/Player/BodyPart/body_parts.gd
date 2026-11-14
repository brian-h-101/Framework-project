extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const AnatomyData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Anatomy/anatomy.gd"
)
const InjuriesData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Injuries/injuries.gd"
)
const IllnessData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Illness/illness.gd"
)
const TreatmentsData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Treatments/treatments.gd"
)
const IntrusionsData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Intrusions/intrusions.gd"
)
const FormsData = preload(
	"res://Framework/Content/Authored/Entity/Player/BodyPart/Forms/forms.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		AnatomyData.defaults(),
		InjuriesData.defaults(),
		IllnessData.defaults(),
		TreatmentsData.defaults(),
		IntrusionsData.defaults(),
		FormsData.defaults(),
	])
