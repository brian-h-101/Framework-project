import * as vscode from 'vscode';
import { lstat, open, readFile, unlink } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { draftMovementConfiguration, editBehavior, type BehaviorEdit, type ValueNode } from '../bridges/behavior_editing_bridge';
import { loadResourceGraph, type ResourceNode } from '../bridges/resource_bridge';
import { ensureWorkspace } from '../library/library_manager';
import { checkedProjectPath, directoryFingerprint, nameError, sha256 } from '../library/library_paths';
import { bindingAction, field } from '../resources/configuration_fields';
import { prepareEditGraph } from '../resources/edit_context';
import { pickResource } from '../resources/resource_picker';
import { resourceUri, ResourceTreeProvider, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { isInside, resolveProjectContext, resourcePathInProject, type ProjectContext } from '../workspace/project_context';

export type ConfigurationOperation = 'add_input_binding' | 'set_input_binding_keys' | 'remove_input_binding'
	| 'draft_movement_configuration' | 'set_movement_configuration';

const CONTROLS = 'res://Framework/Content/Configuration/Input/controls.tres';
const MOVEMENT_FOLDER = 'res://Framework/Content/Gameplay/Profiles/Movement/Shared';
const DIRECTIONS = ['left', 'right', 'up', 'down'];

export class ConfigurationCommands {
	constructor(private readonly provider: ResourceTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>) {}

	async execute(operation: ConfigurationOperation, element?: ResourceTreeElement): Promise<void> {
		try {
			const creating = operation === 'draft_movement_configuration';
			const editingMovement = operation === 'set_movement_configuration';
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
			if (creating) {
				const category = await vscode.window.showQuickPick([{
					label: 'Movement', description: MOVEMENT_FOLDER.slice('res://'.length)
				}], { title: 'New Configuration Resource — Profile Category' });
				if (!category) { return; }
				const filename = await vscode.window.showInputBox({
					title: 'New Shared Movement Profile — Filename', ignoreFocusOut: true,
					validateInput: name => nameError(name) ?? (name.endsWith('.tres') ? undefined : 'Use a .tres filename.')
				});
				if (!filename) { return; }
				const destination = await checkedProjectPath(context, MOVEMENT_FOLDER);
				request.expected_parent = await directoryFingerprint(destination);
				source = MOVEMENT_FOLDER + '/' + filename;
			} else {
				const selected = selection!;
				const graph = await prepareEditGraph(selected.graph, context.projectDirectory, executable, report);
				mergeHashes(request.expected_hashes, graph.dependency_hashes);
				source = selected.resource.source_path;
				await ready();
			}
			request.catalog_seed = source;

			if (!creating && !editingMovement) {
				if (!selection || !await promptBinding(selection.resource, selection.data, request)) { return; }
			} else {
				if (!creating && (selection?.resource.configuration_type !== 'movement' || selection.data)) {
					throw new Error('Choose the root of a Movement configuration.');
				}
				if (!await promptMovement(context, executable, this.output, request, creating ? undefined : selection?.resource)) { return; }
			}

			await ready();
			if (creating) {
				const draft = await draftMovementConfiguration(context.projectDirectory, executable, source, request, report);
				await ready();
				await publishMovement(context, source, request.expected_parent!, draft);
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

async function projectFor(selected: vscode.Uri | undefined): Promise<ProjectContext | undefined> {
	if (!vscode.workspace.isTrusted) { throw new Error('Configuration authoring requires a trusted workspace.'); }
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

async function publishMovement(context: ProjectContext, source: string, expectedParent: string,
	draft: { source_text: string; content_hash: string }): Promise<void> {
	const parent = await checkedProjectPath(context, MOVEMENT_FOLDER);
	if (await directoryFingerprint(parent) !== expectedParent) { throw new Error('The Movement directory changed. Retry creation.'); }
	const filename = source.slice(MOVEMENT_FOLDER.length + 1);
	if (nameError(filename) || sha256(Buffer.from(draft.source_text, 'utf8')) !== draft.content_hash) {
		throw new Error('The Movement configuration draft failed verification.');
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
