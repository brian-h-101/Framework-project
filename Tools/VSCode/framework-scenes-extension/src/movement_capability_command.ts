import * as vscode from 'vscode';
import { relative } from 'node:path';
import { validateResourcePath } from './project_context';
import { runSceneEditing } from './scene_editing_bridge';
import { ensureWorkspace } from './scene_selection';
import { projectUri, SceneTreeProvider } from './scene_tree_provider';
import type { SceneTreeElement } from './scene_tree_provider';

const defaultProfile = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared/movement_2d.tres';
const environmentLabels = { physics_2d: '2D Physics', physics_3d: '3D Physics', grid: 'Grid' } as const;
type MovementEnvironment = keyof typeof environmentLabels;

interface MovementProfile {
	source_path: string;
	behavior_id: string;
	velocity_step_id: string;
	environment?: MovementEnvironment;
}

interface MovementController {
	source_path: string;
	kind: string;
}

interface MovementInspection {
	scene_path: string;
	body_path: string;
	current_configuration: string;
	current_controller: string;
	configurations: MovementProfile[];
	controllers: MovementController[];
}

interface MovementPlan {
	scene_path: string;
	body_path: string;
	configuration_path: string;
	controller_path: string;
	behavior_path: string;
	environment?: MovementEnvironment;
	binding_path: string;
	assign_configuration: boolean;
	assign_controller: boolean;
	attach_script: boolean;
	add_binding: boolean;
	input_actions: string[];
	dependency_hashes: Record<string, string>;
	token: string;
}

interface MovementOptions {
	configuration_path: string;
	controller_path: string;
	environment?: MovementEnvironment;
}

export async function configureMovementCapability(
	provider: SceneTreeProvider, element: SceneTreeElement, output: vscode.OutputChannel,
	refresh: () => Promise<void>
): Promise<void> {
	try {
		const { context, graph, node } = provider.resolve(element);
		if (!node.is_entity) { throw new Error('Choose an entity root in Framework Scenes.'); }
		const ready = (paths: string[]): void => {
			provider.resolve(element);
			ensureWorkspace(context);
			const uris = paths.map(path => projectUri(context, path));
			if (vscode.workspace.textDocuments.some(document => document.isDirty && document.uri.scheme === 'file'
				&& uris.some(uri => relative(document.uri.fsPath, uri.fsPath) === ''))) {
				throw new Error('Save or revert unsaved edits to the scene and movement resources, then retry.');
			}
		};
		ready(Object.keys(graph.dependency_hashes));
		const root = vscode.Uri.file(context.projectDirectory);
		const executable = vscode.workspace.getConfiguration('frameworkScenes', root).get<string>('godotExecutable')?.trim()
			|| vscode.workspace.getConfiguration('godotTools', root).get<string>('editorPath.godot4')?.trim();
		if (!executable) { throw new Error('Configure frameworkScenes.godotExecutable or godotTools.editorPath.godot4 in Workspace settings.'); }
		const run = (operation: string, request?: object): Promise<unknown> =>
			runSceneEditing(context.projectDirectory, executable, [operation, graph.source_path, node.path],
				request, message => output.appendLine(message));
		const inspection = readInspection(await run('inspect-movement'));
		ready([graph.source_path, inspection.scene_path]);
		const capability = await vscode.window.showQuickPick([{
			label: 'Movement',
			description: inspection.current_controller ? fileName(inspection.current_controller) : 'Choose a movement controller',
			detail: inspection.body_path
		}], { title: `Configure Capabilities for ${node.name}` });
		if (!capability) { return; }
		const options = await pickMovement(inspection);
		if (!options) { return; }
		ready([graph.source_path, inspection.scene_path, options.configuration_path, options.controller_path]);
		const plan = readPlan(await run('plan-movement', options), inspection, options);
		for (const [path, hash] of Object.entries(graph.dependency_hashes)) {
			if (plan.dependency_hashes[path] !== hash) {
				throw new Error('The selected scene changed. Refresh Framework Scenes and retry.');
			}
		}
		const paths = Object.keys(plan.dependency_hashes);
		ready(paths);
		if (!plan.assign_configuration && !plan.assign_controller && !plan.attach_script && !plan.add_binding) {
			void vscode.window.showInformationMessage(`Movement is already configured on ${node.name}.`);
			return;
		}
		const confirmation = await vscode.window.showInformationMessage(
			`Configure movement for ${node.name}?`, { modal: true, detail: reviewDetails(plan) }, 'Apply Movement'
		);
		if (confirmation !== 'Apply Movement') { return; }
		ready(paths);
		const applied = await run('apply-movement', { ...options, token: plan.token });
		if (!isRecord(applied) || applied.scene_path !== plan.scene_path || typeof applied.changed !== 'boolean') {
			throw new Error('Malformed movement result. Refresh the scene and check its state.');
		}
		output.appendLine(`[movement] Configured ${plan.scene_path} (${plan.body_path}).`);
		await refresh();
		void vscode.window.showInformationMessage(`Movement is configured on ${node.name}.`);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		output.appendLine(`[movement] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}

async function pickMovement(inspection: MovementInspection): Promise<MovementOptions | undefined> {
	if (!inspection.configurations.length) {
		throw new Error('Author a shared Movement profile in Framework Resources, then run Configure Capabilities again.');
	}
	if (!inspection.controllers.length) {
		throw new Error('Add a keyboard or AI movement controller resource under Framework/Content/Gameplay/Controller.');
	}
	const currentProfile = inspection.configurations.find(profile => profile.source_path === inspection.current_configuration);
	const preferredEnvironment = currentProfile?.environment ?? 'physics_2d';
	const environments = [...new Set(inspection.configurations.map(profile => profile.environment ?? 'physics_2d'))];
	let environment = environments[0];
	if (environments.length > 1) {
		const choices = environments.map(id => ({ label: environmentLabels[id], id }))
			.sort((left, right) => Number(right.id === preferredEnvironment) - Number(left.id === preferredEnvironment));
		const choice = await vscode.window.showQuickPick(choices, { title: 'Select Movement Environment' });
		if (!choice) { return; }
		environment = choice.id;
	}
	const compatible = inspection.configurations.filter(profile => (profile.environment ?? 'physics_2d') === environment);
	const behaviorIds = [...new Set(compatible.map(profile => profile.behavior_id))];
	let behaviorId = behaviorIds[0];
	if (behaviorIds.length > 1) {
		const choices = behaviorIds.map(id => ({ label: id }))
			.sort((left, right) => Number(right.label === currentProfile?.behavior_id) - Number(left.label === currentProfile?.behavior_id));
		const choice = await vscode.window.showQuickPick(choices, { title: 'Select Shared Movement Behavior' });
		if (!choice) { return; }
		behaviorId = choice.label;
	}
	const profiles = compatible.filter(profile => profile.behavior_id === behaviorId).map(profile => ({
		label: fileName(profile.source_path),
		description: profile.source_path === inspection.current_configuration ? `${profile.behavior_id} · Current profile` : profile.behavior_id,
		detail: `${profile.velocity_step_id} · ${profile.source_path}`,
		path: profile.source_path,
		environment: profile.environment
	}));
	const preferred = profiles.find(profile => profile.path === inspection.current_configuration)
		?? profiles.find(profile => profile.path === defaultProfile);
	const ordered = preferred ? [preferred, ...profiles.filter(profile => profile !== preferred)] : profiles;
	const profile = profiles.length === 1 ? profiles[0] : await vscode.window.showQuickPick(ordered, {
		title: 'Select Shared Movement Profile', matchOnDetail: true
	});
	if (!profile) { return; }
	const controller = await vscode.window.showQuickPick(inspection.controllers.map(entry => ({
		label: fileName(entry.source_path),
		description: `${entry.kind === 'ai' ? 'AI' : entry.kind}${entry.source_path === inspection.current_controller ? ' · Current' : ''}`,
		detail: entry.source_path,
		path: entry.source_path
	})).sort((left, right) => Number(right.path === inspection.current_controller)
		- Number(left.path === inspection.current_controller)), {
		title: `Movement Controller · ${profile.label}`, matchOnDescription: true, matchOnDetail: true
	});
	return controller ? { configuration_path: profile.path, controller_path: controller.path,
		...(profile.environment ? { environment: profile.environment } : {}) } : undefined;
}

function reviewDetails(plan: MovementPlan): string {
	const details = [
		`Scene  ${plan.scene_path}`,
		`Body  ${plan.body_path}`,
		`Environment  ${environmentLabels[plan.environment ?? 'physics_2d']}`,
		`Behavior  ${plan.behavior_path}`,
		`Shared profile  ${plan.configuration_path}`,
		`Controller  ${plan.controller_path}`,
		plan.add_binding ? `Add a Behavior binding for ${plan.behavior_path}` : `Reuse Behavior binding at ${plan.binding_path}`
	];
	if (plan.attach_script) { details.push('Attach the Movement 2D adapter'); }
	if (plan.input_actions.length) { details.push(`Reuse input actions  ${plan.input_actions.join(', ')}`); }
	return details.join('\n');
}

function readInspection(value: unknown): MovementInspection {
	if (!isRecord(value) || !isPath(value.scene_path, '.tscn') || typeof value.body_path !== 'string'
		|| (value.current_configuration !== '' && !isPath(value.current_configuration, '.tres'))
		|| (value.current_controller !== '' && !isPath(value.current_controller, '.tres'))
		|| !Array.isArray(value.configurations) || !value.configurations.every(profile => isRecord(profile)
			&& isPath(profile.source_path, '.tres') && typeof profile.behavior_id === 'string'
			&& typeof profile.velocity_step_id === 'string' && (profile.environment === undefined || isEnvironment(profile.environment)))
		|| !Array.isArray(value.controllers) || !value.controllers.every(controller => isRecord(controller)
			&& isPath(controller.source_path, '.tres') && typeof controller.kind === 'string' && controller.kind.length > 0)) {
		throw new Error('Malformed movement inspection.');
	}
	return value as unknown as MovementInspection;
}

function readPlan(value: unknown, inspection: MovementInspection, options: MovementOptions): MovementPlan {
	if (!isRecord(value) || value.scene_path !== inspection.scene_path || value.body_path !== inspection.body_path
		|| value.configuration_path !== options.configuration_path || value.controller_path !== options.controller_path
		|| (value.environment !== undefined && !isEnvironment(value.environment))
		|| (options.environment !== undefined && value.environment !== options.environment)
		|| !isPath(value.behavior_path, '.tres') || typeof value.binding_path !== 'string'
		|| !['assign_configuration', 'assign_controller', 'attach_script', 'add_binding'].every(key => typeof value[key] === 'boolean')
		|| !Array.isArray(value.input_actions) || !value.input_actions.every(action => typeof action === 'string')
		|| !isRecord(value.dependency_hashes) || !isHash(value.token)
		|| ![inspection.scene_path, options.configuration_path, options.controller_path, value.behavior_path]
			.every(path => Object.hasOwn(value.dependency_hashes as object, path))
		|| !Object.entries(value.dependency_hashes).every(([path, hash]) => isPath(path) && isHash(hash))) {
		throw new Error('Malformed movement plan.');
	}
	return value as unknown as MovementPlan;
}

function isEnvironment(value: unknown): value is MovementEnvironment {
	return typeof value === 'string' && Object.hasOwn(environmentLabels, value);
}

function isHash(value: unknown): boolean {
	return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
}

function isPath(path: unknown, extension?: string): path is string {
	if (typeof path !== 'string') { return false; }
	validateResourcePath(path, extension);
	return true;
}

function fileName(path: string): string {
	return path.slice(path.lastIndexOf('/') + 1);
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
