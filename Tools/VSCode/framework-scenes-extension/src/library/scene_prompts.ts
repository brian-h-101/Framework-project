import * as vscode from 'vscode';
import { nodeTypes } from '../scene_editing_bridge';
import { validateResourcePath } from '../project_context';
import { nameError } from './library_paths';
import { libraryRequest, SCENE_ROOTS } from './scene_library_bridge';

const DEFINITION_CATEGORIES = ['Entity', 'Items', 'Objects'];
const AUTHORED_ROOT = 'res://Framework/Content/Gameplay/Authored/';
const DEFAULT_FRAGMENTS = [
	'Entity/Attributes/Identity/identity.tres',
	'Entity/Attributes/Statistics/health.tres',
	'Entity/Attributes/Statistics/speed.tres'
];

const TEMPLATES = [
	{ label: '2D Map — Ground and Lighting', template: 'map_2d', root: SCENE_ROOTS[0] },
	{ label: 'Empty 2D Map', template: 'empty_2d', root: SCENE_ROOTS[0] },
	{ label: 'Empty 3D Map', template: 'empty_3d', root: SCENE_ROOTS[0] },
	{ label: 'Entity Presentation — With Starting Attributes', template: 'entity_presentation', root: SCENE_ROOTS[1] },
	{ label: 'Presentation — Native Root', template: 'presentation', root: SCENE_ROOTS[1] },
	{ label: 'Control Widget — Unshaded', template: 'control', root: SCENE_ROOTS[2] },
	{ label: 'HUD Parent — Unshaded CanvasLayer', template: 'hud', root: SCENE_ROOTS[2] }
];

export async function sceneDetails(folder: string, project: string, executable: string,
	report: (message: string) => void): Promise<{ filename: string; request: Record<string, unknown> } | undefined> {
	const parts = folder.slice(SCENE_ROOTS[1].length + 1).split('/');
	const isDefinitionFolder = folder.startsWith(SCENE_ROOTS[1] + '/') && parts.length === 2
		&& DEFINITION_CATEGORIES.includes(parts[0]);
	const choices = TEMPLATES.filter(item => (folder === item.root || folder.startsWith(item.root + '/'))
		&& (item.template !== 'entity_presentation' || isDefinitionFolder));
	const template = await vscode.window.showQuickPick(choices, { title: 'New Scene — Template', ignoreFocusOut: true });
	if (!template) { return; }
	let rootType: string | undefined;
	if (template.template === 'presentation' || template.template === 'entity_presentation') {
		rootType = await vscode.window.showQuickPick(await nodeTypes(project, executable, report),
			{ title: 'Presentation — Native Root Type', placeHolder: 'Search Node, Node2D, Node3D, or another native type', ignoreFocusOut: true });
		if (!rootType) { return; }
	}
	const filename = await vscode.window.showInputBox({ title: 'New Scene — Filename', value: 'new_scene.tscn', ignoreFocusOut: true,
		validateInput: name => nameError(name) ?? (name.endsWith('.tscn') ? undefined : 'Use a .tscn filename.') });
	if (filename === undefined) { return; }
	const suggested = filename.slice(0, -5).split(/[^a-zA-Z0-9]+/).filter(Boolean).map(part => part[0].toUpperCase() + part.slice(1)).join('') || 'Scene';
	const name = await vscode.window.showInputBox({ title: 'New Scene — Root Node Name', value: /^[A-Za-z_]/.test(suggested) ? suggested : 'Scene' + suggested,
		ignoreFocusOut: true, validateInput: text => /^[A-Za-z_][A-Za-z0-9_]*$/.test(text) ? undefined : 'Use a node identifier beginning with a letter or underscore.' });
	if (name === undefined) { return; }
	const request: Record<string, unknown> = { template: template.template, node_name: name, root_type: rootType ?? '' };
	if (template.template === 'entity_presentation') {
		const id = await vscode.window.showInputBox({
			title: 'Entity Presentation — Definition ID',
			value: name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase(),
			ignoreFocusOut: true,
			validateInput: value => /^[a-z_][a-z0-9_]*$/.test(value) ? undefined : 'Use a lowercase identifier with letters, digits, and underscores.'
		});
		if (id === undefined) { return; }
		const fragments = await selectFragments(project, executable, report, parts[0] === 'Entity');
		if (fragments === undefined) { return; }
		request.definition_id = id;
		request.fragments = fragments;
	}
	return { filename, request };
}

async function selectFragments(project: string, executable: string, report: (message: string) => void,
	entityDefaults: boolean): Promise<string[] | undefined> {
	const paths = await libraryRequest(project, executable, 'attribute-fragments', undefined, {}, report);
	if (!Array.isArray(paths) || !paths.every(path => typeof path === 'string' && path.startsWith(AUTHORED_ROOT))) {
		throw new Error('Godot returned an invalid attribute fragment list.');
	}
	const choices = paths.map((path: string) => {
		validateResourcePath(path, '.tres');
		const relative = path.slice(AUTHORED_ROOT.length);
		return {
			label: relative.split('/').at(-1)!,
			description: relative,
			picked: entityDefaults && DEFAULT_FRAGMENTS.includes(relative),
			path
		};
	});
	const selected = await vscode.window.showQuickPick(choices, {
		title: 'Entity Presentation — Starting Attribute Fragments',
		placeHolder: 'Select shared fragments for the new preset',
		canPickMany: true,
		matchOnDescription: true,
		ignoreFocusOut: true
	});
	return selected?.map(item => item.path);
}
