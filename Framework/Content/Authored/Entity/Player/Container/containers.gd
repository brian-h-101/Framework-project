extends RefCounted

const ContentComposition = preload(
	"res://Framework/Content/Authored/Entity/Shared/content_composition.gd"
)
const InventoryData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/inventory.gd"
)
const EquipmentData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Equipment/equipment.gd"
)
const OwnershipData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Ownership/ownership.gd"
)
const WalletData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Wallet/wallet.gd"
)
const PersonalFinanceData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/PersonalFinance/personal_finance.gd"
)
const PropertyData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Property/property.gd"
)
const ResidencyData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Residency/residency.gd"
)
const CraftingData = preload(
	"res://Framework/Content/Authored/Entity/Player/Container/Crafting/crafting.gd"
)


static func defaults() -> Dictionary[StringName, Dictionary]:
	return ContentComposition.combine([
		InventoryData.defaults(),
		EquipmentData.defaults(),
		OwnershipData.defaults(),
		WalletData.defaults(),
		PersonalFinanceData.defaults(),
		PropertyData.defaults(),
		ResidencyData.defaults(),
		CraftingData.defaults(),
	])
