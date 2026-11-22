import * as vscode from 'vscode';
import { NODE_PROPERTY_TYPES, type NodeProperty, type SceneEdit } from './scene_editing_bridge';

type PropertyChange = Pick<SceneEdit, 'property_name' | 'property_type' | 'property_value'>;
interface PropertyItem extends vscode.QuickPickItem { property?: NodeProperty }

const EXAMPLES: Partial<Record<NodeProperty['type'], string>> = {
	Vector2: 'Enter X, Y. Example: 320, 360',
	Vector2i: 'Enter integer X, Y. Example: 32, 32',
	Vector3: 'Enter X, Y, Z. Example: 1, 2, 3',
	Vector3i: 'Enter integer X, Y, Z. Example: 1, 2, 3',
	Color: 'Enter red, green, blue, alpha. Example: 0.2, 0.6, 1, 1',
	PackedVector2Array: 'Enter X, Y pairs. Example: -16, -16, 16, -16, 16, 16, -16, 16'
};

export async function promptNodeProperty(nodeName: string, properties: NodeProperty[]): Promise<PropertyChange | undefined> {
	const items = properties.map(property => ({
		label: property.name,
		description: property.type + (property.saved ? ' · Saved in this scene' : ''),
		detail: property.saved ? property.value : undefined,
		property
	}));
	const custom = { label: 'Add Custom Metadata…', description: 'Set a typed metadata key on this node' };
	const picked = await vscode.window.showQuickPick<PropertyItem>([...items, custom], {
		title: `Set Node Property — ${nodeName}`, matchOnDescription: true, ignoreFocusOut: true
	});
	if (!picked) { return; }
	let property: NodeProperty;
	if (picked.property) {
		property = picked.property;
	} else {
		const key = await vscode.window.showInputBox({
			title: 'Custom Metadata Key', ignoreFocusOut: true,
			validateInput: value => /^[A-Za-z_][A-Za-z0-9_]*$/.test(value) ? undefined : 'Enter a Godot identifier.'
		});
		if (key === undefined) { return; }
		const name = 'metadata/' + key;
		const existing = properties.find(item => item.name === name);
		if (existing) {
			property = existing;
		} else {
			const type = await vscode.window.showQuickPick(NODE_PROPERTY_TYPES.map(valueType => ({ label: valueType, valueType })), {
				title: 'Custom Metadata Type', ignoreFocusOut: true
			});
			if (!type) { return; }
			property = { name, type: type.valueType, saved: false, value: '' };
		}
	}
	const title = `Set ${property.name} (${property.type})`;
	const value = property.type === 'bool'
		? await vscode.window.showQuickPick(property.value === 'false' ? ['false', 'true'] : ['true', 'false'],
			{ title, ignoreFocusOut: true })
		: await vscode.window.showInputBox({
			title, value: property.value, prompt: EXAMPLES[property.type], ignoreFocusOut: true
		});
	return value === undefined ? undefined : {
		property_name: property.name, property_type: property.type, property_value: value
	};
}
