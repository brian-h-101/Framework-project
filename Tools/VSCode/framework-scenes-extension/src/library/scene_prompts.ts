import * as vscode from 'vscode';
import { nodeTypes } from '../scene_editing_bridge';
import { nameError } from './library_paths';
import { SCENE_ROOTS } from './scene_library_bridge';

const TEMPLATES = [
	{ label: '2D Map — Ground and Lighting', template: 'map_2d', root: SCENE_ROOTS[0] },
	{ label: 'Empty 2D Map', template: 'empty_2d', root: SCENE_ROOTS[0] },
	{ label: 'Empty 3D Map', template: 'empty_3d', root: SCENE_ROOTS[0] },
	{ label: 'Presentation — Native Root', template: 'presentation', root: SCENE_ROOTS[1] },
	{ label: 'Control Widget — Unshaded', template: 'control', root: SCENE_ROOTS[2] },
	{ label: 'HUD Parent — Unshaded CanvasLayer', template: 'hud', root: SCENE_ROOTS[2] }
];

export async function sceneDetails(folder: string, project: string, executable: string,
	report: (message: string) => void): Promise<{ filename: string; request: Record<string, unknown> } | undefined> {
	const choices = TEMPLATES.filter(item => folder === item.root || folder.startsWith(item.root + '/'));
	const template = await vscode.window.showQuickPick(choices, { title: 'New Scene — Template', ignoreFocusOut: true });
	if (!template) { return; }
	let rootType: string | undefined;
	if (template.template === 'presentation') {
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
	return name === undefined ? undefined : { filename, request: { template: template.template, node_name: name, root_type: rootType ?? '' } };
}
