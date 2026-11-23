import type { ValueNode } from '../bridges/behavior_editing_bridge';
import { isConfigurationFieldType, type ConfigurationFieldType } from '../bridges/configuration_types';

export function field(row: ValueNode | undefined, label: string): ValueNode | undefined {
	return row?.children.find(child => child.label === label);
}

export function bindingAction(row: ValueNode | undefined): string | undefined {
	if (row?.path.length !== 2 || row.path[0].text !== 'Bindings' || row.path[1].kind !== 'index') {
		return;
	}
	const action = field(row, 'action');
	return action && (action.kind === 'String' || action.kind === 'StringName') ? action.value_text : undefined;
}

export function isCustomConfigurationField(row: ValueNode | undefined): row is ValueNode & { kind: ConfigurationFieldType } {
	return row?.path.length === 2 && row.path[0].text === 'Values' && row.path[1].kind === 'String'
		&& isConfigurationFieldType(row.kind);
}
