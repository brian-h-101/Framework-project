import * as vscode from 'vscode';
import type { LibraryCatalogue, LibraryEntry } from '../bridges/behavior_library_bridge';
import { promptValue } from '../resources/value_prompts';
import { nameError } from './library_paths';
import { pickExecutor } from '../resources/executor_picker';
import { argumentTypes } from '../resources/executor_metadata';

const TYPES = [
	{ label: 'Action', resourceKind: 'action' }, { label: 'Condition', resourceKind: 'condition' },
	{ label: 'Condition Group', resourceKind: 'condition_group' }, { label: 'Interaction', resourceKind: 'interaction' },
	{ label: 'Automation', resourceKind: 'automation' }
];

async function reference(catalogue: LibraryCatalogue, kind: string, optional = false): Promise<string | undefined> {
	const items = catalogue.entries.filter(entry => entry.kind === 'resource' && entry.valid && entry.resource_kind === kind)
		.map(entry => ({ label: entry.id!, description: entry.source_path, path: entry.source_path }));
	if (optional) { items.unshift({ label: 'No requirements', description: 'Always available when permitted', path: '' }); }
	if (!items.length) { void vscode.window.showInformationMessage(`Create a valid ${kind} Resource first.`); return; }
	return (await vscode.window.showQuickPick(items, { title: kind === 'interaction' ? 'Automation — Interaction' : kind === 'action' ? 'Interaction — Action' : 'Interaction — Requirements',
		matchOnDescription: true, ignoreFocusOut: true }))?.path;
}

async function numericValue(title: string): Promise<{ value_type: string; value_text: string } | undefined> {
	return promptValue({ kind: 'int', value_text: '10', allowed_types: ['int', 'float'], choices: [] }, title);
}

export async function creationDetails(catalogue: LibraryCatalogue): Promise<{ filename: string; request: Record<string, unknown> } | undefined> {
	const type = await vscode.window.showQuickPick(TYPES, { title: 'New Behavior Resource — Type', ignoreFocusOut: true });
	if (!type) { return; }
	const filename = await vscode.window.showInputBox({ title: `New ${type.label} — Filename`, value: 'new_resource.tres', ignoreFocusOut: true,
		validateInput: name => nameError(name) ?? (name.endsWith('.tres') ? undefined : 'Use a .tres filename.') });
	if (filename === undefined) { return; }
	const id = await vscode.window.showInputBox({ title: `New ${type.label} — Authored ID`, value: filename.slice(0, -5), ignoreFocusOut: true,
		validateInput: text => !text.trim() || text.includes('\0') ? 'Enter a nonempty authored ID.'
			: catalogue.entries.some(entry => entry.resource_kind === type.resourceKind && entry.id === text) ? 'This type already has that ID.' : undefined });
	if (id === undefined) { return; }
	const request: Record<string, unknown> = { resource_kind: type.resourceKind, id };
	if (type.resourceKind === 'action') {
		const behavior = await pickExecutor(catalogue.executors);
		if (behavior === undefined) { return; }
		request.behavior_id = behavior;
	} else if (type.resourceKind === 'automation') {
		const interaction = await reference(catalogue, 'interaction');
		if (interaction === undefined) { return; }
		request.interaction_path = interaction;
		for (const field of ['interval_seconds', 'cooldown_seconds']) {
			const value = await vscode.window.showInputBox({ title: `Automation — ${field.replaceAll('_', ' ')}`,
				value: '1', ignoreFocusOut: true, validateInput: text => !text.trim() || !Number.isFinite(Number(text))
					|| (field === 'interval_seconds' ? Number(text) <= 0 : Number(text) < 0) ? 'Enter a finite duration in seconds; interval must be positive and cooldown nonnegative.' : undefined });
			if (value === undefined) { return; }
			request[field] = Number(value);
		}
	} else if (type.resourceKind === 'condition') {
		const entity = await vscode.window.showQuickPick(['actor', 'target'], { title: 'Condition — Entity', ignoreFocusOut: true });
		if (!entity) { return; }
		const container = await vscode.window.showInputBox({ title: 'Condition — Container', value: 'health', ignoreFocusOut: true,
			validateInput: text => text.trim() ? undefined : 'Enter a container name.' });
		if (container === undefined) { return; }
		const path = await vscode.window.showInputBox({ title: 'Condition — Attribute Path', value: '["current"]', ignoreFocusOut: true,
			prompt: 'JSON array of attribute names. Nested path types can be edited afterward.', validateInput: text => {
				try { const array = JSON.parse(text); if (Array.isArray(array) && array.length && array.every(item => typeof item === 'string' && item.length)) { return; } } catch { /* Validation below. */ }
				return 'Enter a nonempty JSON array of attribute names.';
			} });
		if (path === undefined) { return; }
		const operator = await vscode.window.showQuickPick(['>=', '>', '==', '!=', '<=', '<'], { title: 'Condition — Operator', ignoreFocusOut: true });
		if (!operator) { return; }
		const value = await numericValue('Condition — Comparison Value');
		if (!value) { return; }
		const message = await vscode.window.showInputBox({ title: 'Condition — Rejection Message', value: 'The requirement is not met.', ignoreFocusOut: true });
		if (message === undefined) { return; }
		request.requirement = { entity, container, path: JSON.parse(path), operator, ...value, message };
	} else if (type.resourceKind === 'interaction') {
		const actionPath = await reference(catalogue, 'action');
		if (actionPath === undefined) { return; }
		const action = catalogue.entries.find(entry => entry.source_path === actionPath) as LibraryEntry;
		const args = [];
		for (const argument of action.argument_specs!) {
			const title = `Interaction — Argument: ${argument.name}`;
			if (!argument.required) {
				const choice = await vscode.window.showQuickPick(['Skip', 'Set value'], { title: `${title} (optional)`, ignoreFocusOut: true });
				if (!choice) { return; }
				if (choice === 'Skip') { continue; }
			}
			const value = await promptValue({ kind: argument.allowed_types[0], value_text: argument.numeric ? '10' : '',
				allowed_types: argumentTypes(argument), choices: [] }, title);
			if (!value) { return; }
			args.push({ name: argument.name, ...value });
		}
		const requirementsPath = await reference(catalogue, 'condition_group', true);
		if (requirementsPath === undefined) { return; }
		Object.assign(request, { action_path: actionPath, requirements_path: requirementsPath, arguments: args });
	}
	return { filename, request };
}
