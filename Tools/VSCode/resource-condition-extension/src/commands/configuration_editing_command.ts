import * as vscode from 'vscode';
import { lstat, open, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { draftConfiguration, editBehavior, type BehaviorEdit, type ValueNode } from '../bridges/behavior_editing_bridge';
import { isProfileSharedFolder } from '../bridges/behavior_library_bridge';
import { CONFIGURATION_TYPE_SUFFIX, loadConfigurationTypes, type ConfigurationType } from '../bridges/configuration_types';
import { loadResourceGraph, MOVEMENT_CONTROLLER_ROOT, type ResourceNode } from '../bridges/resource_bridge';
import { ensureWorkspace } from '../library/library_manager';
import { checkedBehaviorPath, checkedProjectPath, directoryFingerprint, missing, nameError, sha256 } from '../library/library_paths';
import { LibraryService } from '../library/library_service';
import { bindingAction, field, isCustomConfigurationField } from '../resources/configuration_fields';
import { promptConfigurationField, promptConfigurationType, promptCustomPreset } from '../resources/custom_configuration_prompts';
import { prepareEditGraph } from '../resources/edit_context';
import { pickResource } from '../resources/resource_picker';
import { resourceUri, ResourceTreeProvider, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { isInside, resolveProjectContext, resourcePathInProject, type ProjectContext } from '../workspace/project_context';

export type ConfigurationOperation = 'add_input_binding' | 'set_input_binding_keys' | 'remove_input_binding'
	| 'new_configuration' | 'new_configuration_type' | 'new_movement_controller' | 'set_movement_configuration' | 'set_custom_configuration_field';

const CONTROLS = 'res://Framework/Content/Configuration/Input/controls.tres';
const DIRECTIONS = ['left', 'right', 'up', 'down'];
interface ConfigurationChoice extends vscode.QuickPickItem { schema?: ConfigurationType }

export class ConfigurationCommands {
	constructor(private readonly provider: ResourceTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>) {}

	async execute(operation: ConfigurationOperation, element?: ResourceTreeElement): Promise<void> {
		try {
			const creatingType = operation === 'new_configuration_type';
			const creatingController = operation === 'new_movement_controller';
			const creating = creatingType || creatingController || operation === 'new_configuration';
			if (!creating && (!element || element.cycle)) { throw new Error('Choose a configuration row.'); }
			const selection = element ? this.provider.resolve(element) : undefined;
			if (selection && selection.resource.kind !== 'configuration') { throw new Error('Choose a configuration resource.'); }
			const context = await projectFor(selection?.uri);
			if (!context) { return; }
			const project = vscode.Uri.file(context.projectDirectory);
			const executableFor = () => vscode.workspace.getConfiguration('godotTools', project)
				.get<string>('editorPath.godot4')?.trim();
			const executable = executableFor();
			if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace.'); }
			const report = (message: string) => this.output.appendLine(message);
			const request: BehaviorEdit = { operation, expected_hashes: {}, catalog_paths: [], catalog_seed: '' };
			const ready = async (): Promise<void> => {
				if (element) { this.provider.resolve(element); }
				ensureWorkspace(context);
				if (executableFor() !== executable) { throw new Error('The configured Godot executable changed. Retry the operation.'); }
				const dirty = vscode.workspace.textDocuments.find(doc => doc.isDirty && doc.uri.scheme === 'file'
					&& isInside(context.projectDirectory, doc.uri.fsPath));
				if (dirty) { throw new Error('Save or revert project edits before changing a configuration.'); }
				for (const [path, hash] of Object.entries(request.expected_hashes)) {
					if (sha256(await readFile(await checkedProjectPath(context, path))) !== hash) {
						throw new Error(`Resource changed: ${path}. Refresh and retry.`);
					}
				}
				if (element) { this.provider.resolve(element); }
				ensureWorkspace(context);
			};
			await ready();

			let source: string;
			if (creatingController) {
				const parent = await checkedProjectPath(context, MOVEMENT_CONTROLLER_ROOT);
				request.expected_parent = await directoryFingerprint(parent);
				const filename = await promptMovementController(context, executable, report, request);
				if (!filename) { return; }
				source = MOVEMENT_CONTROLLER_ROOT + '/' + filename;
			} else if (creating) {
				const destination = await chooseProfileDestination(context, executable, report, creatingType ? 'Type' : 'Resource');
				if (!destination) { return; }
				const parent = await checkedProjectPath(context, destination);
				request.expected_parent = await directoryFingerprint(parent);
				let filename: string;
				if (creatingType) {
					const id = await promptConfigurationType(request);
					if (id === undefined) { return; }
					filename = id + CONFIGURATION_TYPE_SUFFIX;
					const error = nameError(filename);
					if (error) { throw new Error(error); }
					request.operation = 'draft_configuration_type';
				} else {
					const types = await loadConfigurationTypes(context.projectDirectory, executable, destination, report);
					const choices: ConfigurationChoice[] = [
						{ label: 'Movement', description: 'Reuse a movement Behavior and configure its velocity step and scale' },
						...types.map(schema => ({ label: schema.label, description: schema.id, detail: schema.source_path.slice(6), schema })),
					];
					const type = await vscode.window.showQuickPick(choices, { title: 'New Configuration Resource — Type',
						ignoreFocusOut: true, matchOnDescription: true, matchOnDetail: true });
					if (!type) { return; }
					const chosenName = await vscode.window.showInputBox({
						title: `New ${type.label} Configuration — Filename`, prompt: `Save in ${destination.slice(6)}`, ignoreFocusOut: true,
						validateInput: name => nameError(name) ?? (!name.endsWith('.tres') || name.endsWith(CONFIGURATION_TYPE_SUFFIX)
							? 'Use a .tres filename. The .type.tres suffix is for definitions.' : undefined)
					});
					if (!chosenName) { return; }
					filename = chosenName;
					if (type.schema) {
						request.operation = 'draft_custom_configuration';
						if (!await promptCustomPreset(type.schema, request)) { return; }
					} else {
						request.operation = 'draft_movement_configuration';
						if (!await promptMovement(context, executable, this.output, request)) { return; }
					}
				}
				source = destination + '/' + filename;
			} else {
				const selected = selection!;
				const graph = await prepareEditGraph(selected.graph, context.projectDirectory, executable, report);
				mergeHashes(request.expected_hashes, graph.dependency_hashes);
				source = selected.resource.source_path;
				await ready();
				if (operation === 'set_custom_configuration_field') {
					const { resource, data } = selected;
					if (resource.configuration_type !== 'custom' || !isCustomConfigurationField(data)) {
						throw new Error('Choose a field inside a custom configuration’s Values.');
					}
					request.field = data.path[1].text;
					const text = await promptConfigurationField(`Edit Configuration Value — ${request.field}`, data.kind, data.value_text);
					if (text === undefined) { return; }
					request.value_text = text;
				} else if (operation === 'set_movement_configuration') {
					if (selected.resource.configuration_type !== 'movement' || selected.data) {
						throw new Error('Choose the root of a Movement configuration.');
					}
					if (!await promptMovement(context, executable, this.output, request, selected.resource)) { return; }
				} else if (!await promptBinding(selected.resource, selected.data, request)) {
					return;
				}
			}

			request.catalog_seed = source;
			await ready();
			if (creating) {
				const draft = await draftConfiguration(context.projectDirectory, executable, source, request, report);
				await ready();
				await publishConfiguration(context, source, request.expected_parent!, draft, creatingController);
			} else {
				await editBehavior(context.projectDirectory, executable, source, request, report);
			}
			report(`[configuration] Saved ${source}.`);
			await this.refresh();
			if (creating) { await vscode.window.showTextDocument(resourceUri(project, source)); }
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[configuration] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}
}

async function chooseProfileDestination(context: ProjectContext, executable: string, report: (message: string) => void,
	kind: 'Resource' | 'Type'): Promise<string | undefined> {
	const catalogue = await new LibraryService(context, executable, report).profileCatalogue();
	ensureWorkspace(context);
	const destinations: { label: string; description: string; source: string }[] = [];
	for (const entry of catalogue.entries) {
		if (entry.kind !== 'folder') { continue; }
		const source = entry.source_path + '/Shared';
		try {
			const path = await checkedProjectPath(context, source);
			if ((await lstat(path)).isDirectory()) {
				destinations.push({ label: entry.name, description: source.slice(6), source });
			}
		} catch (error) {
			if (!missing(error)) { report(`[configuration] Skipped ${source}. ${String(error)}`); }
		}
	}
	if (!destinations.length) {
		void vscode.window.showInformationMessage('Create a profile with a Shared folder in Manage Behavior Library first.');
		return;
	}
	return (await vscode.window.showQuickPick(destinations, { title: `New Configuration ${kind} — Profile`,
		placeHolder: 'Choose the profile that will own the file', matchOnDescription: true, ignoreFocusOut: true }))?.source;
}

export async function projectFor(selected: vscode.Uri | undefined): Promise<ProjectContext | undefined> {
	if (!vscode.workspace.isTrusted) { throw new Error('Resource authoring requires a trusted workspace.'); }
	const folders = (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath);
	if (selected) { return resolveProjectContext(selected.fsPath, folders); }
	const active = vscode.window.activeTextEditor?.document.uri;
	if (active?.scheme === 'file') {
		try { return await resolveProjectContext(active.fsPath, folders); } catch { /* Find a Framework project in the workspace. */ }
	}
	const files = await vscode.workspace.findFiles('**/project.godot', '**/{.git,.godot,node_modules,out}/**');
	const projects: { label: string; context: ProjectContext }[] = [];
	for (const file of files.filter(file => file.scheme === 'file')) {
		try {
			const context = await resolveProjectContext(file.fsPath, folders);
			projects.push({ label: context.projectDirectory, context });
		} catch { /* Only Framework projects can author configurations. */ }
	}
	if (projects.length === 0) { throw new Error('Open a Framework project workspace.'); }
	if (projects.length === 1) { return projects[0].context; }
	return (await vscode.window.showQuickPick(projects, { title: 'Choose a Framework Project' }))?.context;
}

async function promptBinding(resource: ResourceNode, data: ValueNode | undefined, request: BehaviorEdit): Promise<boolean> {
	if (resource.configuration_type !== 'input') { throw new Error('Choose an Input configuration.'); }
	const adding = request.operation === 'add_input_binding';
	let action: string | undefined;
	if (adding) {
		if (data?.path.length !== 1 || data.path[0].text !== 'Bindings') { throw new Error('Choose the Bindings row.'); }
		const existing = new Set(data.children.map(bindingAction));
		action = await vscode.window.showInputBox({
			title: 'New Input Action', ignoreFocusOut: true,
			validateInput: text => !text.trim() ? 'Enter an input action name.'
				: existing.has(text.trim()) ? 'That input action already exists.' : undefined
		});
		if (action === undefined) { return false; }
		action = action.trim();
	} else {
		action = bindingAction(data);
		if (action === undefined) { throw new Error('Choose an input binding.'); }
	}
	request.action = action;
	if (request.operation === 'remove_input_binding') {
		return await vscode.window.showWarningMessage(`Remove the ${action} input binding?`, { modal: true }, 'Remove Binding') === 'Remove Binding';
	}

	const current = new Set(field(data, 'keys')?.children.map(child => child.value_text));
	const known = resource.physical_keys ?? [];
	const items = known.map(key => ({ ...key, picked: current.has(key.code), description: key.code }));
	for (const code of current) {
		if (!known.some(key => key.code === code)) { items.push({ code, label: `Key code ${code}`, picked: true, description: code }); }
	}
	const keys = await vscode.window.showQuickPick(items, {
		title: `Physical Keys for ${action}`, canPickMany: true, ignoreFocusOut: true
	});
	if (!keys) { return false; }
	if (keys.length === 0) { throw new Error('Choose at least one physical key.'); }
	request.key_codes = keys.map(key => key.code);
	return true;
}

async function promptMovement(context: ProjectContext, executable: string, output: vscode.OutputChannel,
	request: BehaviorEdit, current?: ResourceNode): Promise<boolean> {
	const report = (message: string) => output.appendLine(message);
	const chosen = await pickResource(context, executable, 'behavior', output, 'Movement — Behavior');
	if (!chosen) { return false; }
	const source = await resourcePathInProject(context, chosen.fsPath);
	await checkedProjectPath(context, source);
	const graph = await loadResourceGraph(context.projectDirectory, executable, report, source, { mode: 'browse' });
	const behavior = graph.nodes[source];
	if (behavior?.kind !== 'behavior') { throw new Error('Choose a unified Behavior.'); }
	const configuration = field(behavior.data, 'Configuration');
	if (field(configuration, 'Trigger')?.value_text !== 'manual'
		|| field(configuration, 'Targeting')?.value_text !== 'self'
		|| Number(field(configuration, 'Cooldown Seconds')?.value_text) !== 0) {
		throw new Error('Movement requires a manual, self-targeted Behavior with zero cooldown.');
	}
	mergeHashes(request.expected_hashes, graph.dependency_hashes);
	const existingActions = field(current?.data, 'Input Actions');
	const steps = velocitySteps(behavior.data, !existingActions?.children.length);
	if (steps.length === 0) { throw new Error('Add a Movement executor step with lateral, forward and vertical arguments.'); }
	const currentStep = field(current?.data, 'Velocity Step')?.value_text;
	steps.sort((a, b) => Number(b.description === currentStep) - Number(a.description === currentStep));
	const step = await vscode.window.showQuickPick(steps, { title: 'Movement — Velocity Step', matchOnDescription: true, ignoreFocusOut: true });
	if (!step) { return false; }

	if (existingActions?.children.length) {
		const controlsGraph = await loadResourceGraph(context.projectDirectory, executable, report, CONTROLS);
		const controls = controlsGraph.nodes[CONTROLS];
		const actions = field(controls?.data, 'Bindings')?.children.map(bindingAction).filter(action => action !== undefined) ?? [];
		if (controls?.configuration_type !== 'input' || actions.length === 0) { throw new Error('Add input bindings to controls.tres first.'); }
		mergeHashes(request.expected_hashes, controlsGraph.dependency_hashes);
		const configured: Record<string, string> = {};
		for (const direction of DIRECTIONS) {
			const preferred = field(existingActions, direction)?.value_text ?? 'move_' + direction;
			const items = [...actions].sort((a, b) => Number(b === preferred) - Number(a === preferred));
			const action = await vscode.window.showQuickPick(items, { title: 'Movement — ' + direction + ' input action', ignoreFocusOut: true });
			if (action === undefined) { return false; }
			configured[direction] = action;
		}
		request.input_actions = configured;
	}
	const scaleField = field(current?.data, 'Native Units Per Gameplay Unit')?.label ?? 'Pixels Per Unit';
	const scale = await vscode.window.showInputBox({
		title: `Movement — ${scaleField}`, value: field(current?.data, scaleField)?.value_text ?? '10',
		ignoreFocusOut: true, validateInput: text => Number.isFinite(Number(text)) && Number(text) > 0
			? undefined : 'Enter a positive finite number.'
	});
	if (scale === undefined) { return false; }
	request.movement_behavior_path = source;
	request.velocity_step_id = step.description;
	request.pixels_per_unit = Number(scale);
	return true;
}

async function promptMovementController(context: ProjectContext, executable: string, report: (message: string) => void,
	request: BehaviorEdit): Promise<string | undefined> {
	const types = [{ label: 'Keyboard Movement', controller: 'keyboard' }, { label: 'AI Movement', controller: 'ai' }] as const;
	const type = await vscode.window.showQuickPick([...types], { title: 'New Movement Controller — Type', ignoreFocusOut: true });
	if (!type) { return; }
	const filename = await vscode.window.showInputBox({
		title: 'New Movement Controller — Filename', prompt: 'Save in Framework/Content/Gameplay/Controller', ignoreFocusOut: true,
		validateInput: name => nameError(name) ?? (!name.endsWith('.tres') ? 'Use a .tres filename.' : undefined)
	});
	if (!filename) { return; }
	if (type.controller === 'keyboard') {
		const graph = await loadResourceGraph(context.projectDirectory, executable, report, CONTROLS, { mode: 'browse' });
		const controls = graph.nodes[CONTROLS];
		const actions = field(controls?.data, 'Bindings')?.children
			.filter(binding => field(binding, 'keys')?.children.length).map(bindingAction)
			.filter(action => action !== undefined) ?? [];
		if (controls?.configuration_type !== 'input' || new Set(actions).size < DIRECTIONS.length) {
			throw new Error('Add at least four distinct input actions with bound keys to controls.tres.');
		}
		mergeHashes(request.expected_hashes, graph.dependency_hashes);
		const configured: Record<string, string> = {};
		for (const direction of DIRECTIONS) {
			const preferred = 'move_' + direction;
			const choices = actions.filter(action => !Object.values(configured).includes(action))
				.sort((left, right) => Number(right === preferred) - Number(left === preferred));
			const action = await vscode.window.showQuickPick(choices, { title: `Keyboard Movement — ${direction} input action`, ignoreFocusOut: true });
			if (!action) { return; }
			configured[direction] = action;
		}
		request.input_actions = configured;
	} else {
		const targeting = await vscode.window.showQuickPick(['nearest', 'selected'], { title: 'AI Movement — Targeting', ignoreFocusOut: true });
		if (!targeting) { return; }
		const unit = await vscode.window.showQuickPick(['gameplay_units', 'pixels'], { title: 'AI Movement — Distance Unit', ignoreFocusOut: true });
		if (!unit) { return; }
		const distance = await vscode.window.showInputBox({
			title: 'AI Movement — Stopping Distance', value: unit === 'gameplay_units' ? '4.8' : '48', ignoreFocusOut: true,
			validateInput: text => text.trim() && Number.isFinite(Number(text)) && Number(text) >= 0
				? undefined : 'Enter a finite, nonnegative distance.'
		});
		if (distance === undefined) { return; }
		request.targeting = targeting;
		request.distance_unit = unit;
		request.stopping_distance = Number(distance);
	}
	request.operation = 'draft_movement_controller';
	request.controller_kind = type.controller;
	return filename;
}

function velocitySteps(root: ValueNode, shared: boolean): { label: string; description: string }[] {
	const steps: { label: string; description: string }[] = [];
	const pending = [root];
	while (pending.length) {
		const row = pending.pop()!;
		const info = row.sequence;
		if (info?.role === 'step' && info.step_kind === 'action') {
			const executor = row.children.find(child => child.sequence?.role === 'executor');
			const argumentsRow = field(executor, 'arguments');
			const id = executor?.sequence?.executor_id;
			const semantic = ['lateral', 'forward', 'vertical'].every(axis => field(argumentsRow, axis));
			const planar = ['direction_x', 'direction_y'].every(axis => field(argumentsRow, axis));
			if ((semantic && (!shared || id === 'movement')) || (planar && (!shared || id === 'movement_2d'))) {
				steps.push({ label: row.label, description: info.step_id });
			}
		}
		pending.push(...row.children);
	}
	return steps;
}

function mergeHashes(expected: Record<string, string>, hashes: Record<string, string>): void {
	for (const [path, hash] of Object.entries(hashes)) {
		if (expected[path] && expected[path] !== hash) { throw new Error(`Resource changed: ${path}. Refresh and retry.`); }
		expected[path] = hash;
	}
}

async function publishConfiguration(context: ProjectContext, source: string, expectedParent: string,
	draft: { source_text: string; content_hash: string }, creatingController: boolean): Promise<void> {
	const folder = source.slice(0, source.lastIndexOf('/'));
	if (creatingController) {
		if (folder !== MOVEMENT_CONTROLLER_ROOT) { throw new Error('Choose the Gameplay/Controller folder.'); }
	} else {
		if (!isProfileSharedFolder(folder)) { throw new Error('Choose a profile’s Shared folder.'); }
		const profile = folder.slice(0, folder.lastIndexOf('/'));
		await checkedBehaviorPath(context, profile + '/Behavior', 'directory');
	}
	const parent = await checkedProjectPath(context, folder);
	if (await directoryFingerprint(parent) !== expectedParent) { throw new Error('The destination folder changed. Retry creation.'); }
	const filename = source.slice(folder.length + 1);
	if (nameError(filename) || sha256(Buffer.from(draft.source_text, 'utf8')) !== draft.content_hash) {
		throw new Error('The configuration draft failed verification.');
	}
	const path = join(parent, filename);
	const handle = await open(path, 'wx');
	const owned = await handle.stat();
	try {
		await handle.writeFile(draft.source_text, 'utf8');
		await handle.sync();
	} catch (error) {
		await handle.close();
		const current = await lstat(path);
		if (!current.isSymbolicLink() && current.ino === owned.ino && current.dev === owned.dev) { await unlink(path); }
		throw error;
	}
	await handle.close();
}
