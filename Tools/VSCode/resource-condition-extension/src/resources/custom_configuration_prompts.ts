import * as vscode from 'vscode';
import type { BehaviorEdit } from '../bridges/behavior_editing_bridge';
import { CONFIGURATION_FIELD_TYPES, CONFIGURATION_TYPE_SUFFIX, isConfigurationFieldType, isConfigurationIdentifier, type ConfigurationFieldType,
	type ConfigurationType } from '../bridges/configuration_types';
import { nameError } from '../library/library_paths';
import { scalarError } from './value_prompts';

export async function promptConfigurationField(title: string, type: ConfigurationFieldType, value: string): Promise<string | undefined> {
	if (type === 'bool') {
		return vscode.window.showQuickPick(value === 'false' ? ['false', 'true'] : ['true', 'false'],
			{ title, ignoreFocusOut: true });
	}
	return vscode.window.showInputBox({ title, value, ignoreFocusOut: true, validateInput: text => scalarError(type, text) });
}

export async function promptConfigurationType(request: BehaviorEdit): Promise<string | undefined> {
	const label = await vscode.window.showInputBox({ title: 'New Configuration Type — Label', ignoreFocusOut: true,
		validateInput: value => value.trim() && value.trim().length <= 100 ? undefined : 'Enter a label of 1–100 characters.' });
	if (label === undefined) { return; }
	const id = await vscode.window.showInputBox({ title: 'New Configuration Type — ID', ignoreFocusOut: true,
		value: label.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, ''),
		validateInput: value => isConfigurationIdentifier(value) && value !== 'movement'
			? nameError(value + CONFIGURATION_TYPE_SUFFIX) : 'Use a lower-case ID starting with a letter. The ID movement is reserved.' });
	if (id === undefined) { return; }
	const fields: NonNullable<BehaviorEdit['type_fields']> = [];
	while (fields.length < 64) {
		const name = await vscode.window.showInputBox({ title: 'Configuration Field — Name', ignoreFocusOut: true,
			validateInput: value => !isConfigurationIdentifier(value) ? 'Use a lower-case field name starting with a letter.'
				: fields.some(field => field.name === value) ? 'That field already exists.' : undefined });
		if (name === undefined) { return; }
		const type = await vscode.window.showQuickPick(CONFIGURATION_FIELD_TYPES,
			{ title: `Configuration Field — Type for ${name}`, ignoreFocusOut: true });
		if (!isConfigurationFieldType(type)) { return; }
		const defaultText = await promptConfigurationField(`Configuration Field — Default for ${name}`, type,
			type === 'int' || type === 'float' ? '0' : '');
		if (defaultText === undefined) { return; }
		fields.push({ name, type, value_text: defaultText });
		const next = await vscode.window.showQuickPick(fields.length === 64 ? ['Save Type'] : ['Add Field', 'Save Type'],
			{ title: `New Configuration Type — ${fields.length} field(s)`, ignoreFocusOut: true });
		if (next === undefined) { return; }
		if (next === 'Save Type') { break; }
	}
	request.type_id = id;
	request.type_label = label.trim();
	request.type_fields = fields;
	return id;
}

export async function promptCustomPreset(schema: ConfigurationType, request: BehaviorEdit): Promise<boolean> {
	const entries: [string, string][] = [];
	for (const field of schema.fields) {
		const text = await promptConfigurationField(`${schema.label} — ${field.name}`, field.type, field.default_text);
		if (text === undefined) { return false; }
		entries.push([field.name, text]);
	}
	request.configuration_schema_path = schema.source_path;
	request.configuration_values = Object.fromEntries(entries);
	request.expected_hashes[schema.source_path] = schema.content_hash;
	return true;
}
