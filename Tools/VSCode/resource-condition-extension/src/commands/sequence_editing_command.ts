import * as vscode from 'vscode';
import { prepareEditGraph } from '../resources/edit_context';
import { createHash } from 'node:crypto';
import { relative } from 'node:path';
import { ResourceTreeProvider, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { editBehavior, type BehaviorEdit } from '../bridges/behavior_editing_bridge';
import { resolveProjectContext, isInside } from '../workspace/project_context';
import { promptValue } from '../resources/value_prompts';
import { pickExecutor } from '../resources/executor_picker';
import { argumentTypes } from '../resources/executor_metadata';
import { pickResource } from '../resources/resource_picker';

export async function editSequence(provider: ResourceTreeProvider, element: ResourceTreeElement | undefined,
	operation: string, output: vscode.OutputChannel, refresh: () => Promise<void>): Promise<void> {
	try {
		if (!element || element.cycle) { throw new Error('Choose a Behavior row.'); }
		const selected = provider.resolve(element);
		const { resource, projectRoot, data } = selected;
		let graph = selected.graph;
		if (resource.kind !== 'behavior') { throw new Error('Choose a unified Behavior Resource.'); }
		const row = data?.sequence ?? { role: 'root', step_id: '' };
		const folders = () => (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath);
		const context = await resolveProjectContext(selected.uri.fsPath, folders());
		const ready = async (): Promise<void> => {
			provider.resolve(element);
			const current = await resolveProjectContext(selected.uri.fsPath, folders());
			if (!vscode.workspace.isTrusted || relative(context.projectDirectory, projectRoot.fsPath) !== ''
				|| relative(current.projectDirectory, context.projectDirectory) !== '' || !folders().some(folder => relative(folder, context.workspaceDirectory) === '')) {
				throw new Error('The trusted project workspace changed. Refresh and retry.');
			}
			if (vscode.workspace.textDocuments.some(doc => doc.isDirty && doc.uri.scheme === 'file' && isInside(context.projectDirectory, doc.uri.fsPath))) {
				throw new Error('Save or revert project edits before changing a Behavior.');
			}
			for (const [path, hash] of Object.entries({ ...graph.dependency_hashes, ...graph.executor_snapshot?.hashes })) {
				if (createHash('sha256').update(await vscode.workspace.fs.readFile(vscode.Uri.joinPath(projectRoot, ...path.slice(6).split('/')))).digest('hex') !== hash) {
					throw new Error(`Resource changed: ${path}. Refresh and retry.`);
				}
			}
		};
		await ready();
		const executable = vscode.workspace.getConfiguration('godotTools', projectRoot).get<string>('editorPath.godot4')?.trim();
		if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace.'); }
		graph = await prepareEditGraph(graph, context.projectDirectory, executable, message => output.appendLine(message));
		await ready();
		const request: BehaviorEdit = { operation: 'sequence_' + operation, step_id: row.step_id,
			expected_hashes: graph.dependency_hashes, catalog_paths: graph.catalog_paths,
			catalog_seed: graph.roots[0], executor_snapshot: graph.executor_snapshot };
		if (operation === 'add_action' || operation === 'add_group') {
			if (!['root', 'steps'].includes(row.role) && !(row.role === 'step' && row.step_kind === 'group')) { throw new Error('Choose Steps or a Group step.'); }
			request.operation = 'sequence_add';
			request.step_kind = operation === 'add_action' ? 'action' : 'group';
			request.new_id = await vscode.window.showInputBox({ title: 'New Step - Stable ID', ignoreFocusOut: true,
				validateInput: value => /^[a-z][a-z0-9_]*$/.test(value) ? undefined : 'Use lowercase letters, digits and underscores.' });
			if (request.new_id === undefined) { return; }
			request.label = await vscode.window.showInputBox({ title: 'New Step - Display Label', value: request.new_id, ignoreFocusOut: true });
			if (request.label === undefined) { return; }
		} else if (operation === 'rename') {
			if (row.role !== 'step') { throw new Error('Choose a step.'); }
			request.label = await vscode.window.showInputBox({ title: 'Rename Step - Display Label', value: String(row.label ?? ''), ignoreFocusOut: true,
				prompt: 'The stable step ID stays unchanged.' });
			if (request.label === undefined) { return; }
		} else if (operation === 'remove' || operation === 'move_up' || operation === 'move_down') {
			if (row.role !== 'step') { throw new Error('Choose a step.'); }
			if (operation === 'remove') {
				if (await vscode.window.showWarningMessage(`Remove '${row.step_id}' and all its child steps from this Behavior?`, { modal: true }, 'Remove Step') !== 'Remove Step') { return; }
			} else { request.operation = 'sequence_move'; request.direction = operation === 'move_up' ? -1 : 1; }
		} else if (operation === 'configure') {
			if (row.role !== 'configuration') { throw new Error('Choose a Configuration field.'); }
			request.field = typeof row.field === 'string' ? row.field : await vscode.window.showQuickPick(['trigger', 'event_id', 'targeting', 'interval_seconds', 'cooldown_seconds'], { title: 'Behavior - Configuration' });
			if (!request.field) { return; }
			const choices = request.field === 'trigger' ? ['manual', 'event', 'interval'] : request.field === 'targeting' ? ['nearest', 'selected', 'self'] : [];
			const value = await promptValue({ kind: choices.length ? 'String' : request.field === 'event_id' ? 'StringName' : 'float',
				value_text: String(row.value_text ?? ''), allowed_types: choices.length ? ['String'] : request.field === 'event_id' ? ['StringName'] : ['float', 'int'], choices }, 'Behavior - ' + request.field);
			if (!value) { return; } Object.assign(request, value);
		} else if (operation === 'remove_condition') {
			if (row.role !== 'condition') { throw new Error('Choose a condition row.'); }
			if (await vscode.window.showWarningMessage('Remove this requirement from the step?', { modal: true }, 'Remove Requirement') !== 'Remove Requirement') { return; }
			request.condition_index = Number(row.condition_index);
		} else if (operation === 'assign_condition') {
			if (row.role !== 'requirements') { throw new Error('Choose a step Requirements row.'); }
			const chosen = await pickResource(context, executable, 'condition', output, 'Step - Existing Condition');
			if (!chosen) { return; }
			request.operation = 'sequence_condition';
			request.condition_path = 'res://' + relative(context.projectDirectory, chosen.fsPath).split('\\').join('/');
		} else if (operation === 'condition') {
			if (!['requirements', 'condition'].includes(row.role)) { throw new Error('Choose Requirements or a condition.'); }
			if (row.role === 'condition') { request.condition_index = Number(row.condition_index); }
			request.condition_id = await vscode.window.showInputBox({ title: 'Step Condition - ID', value: typeof row.condition_id === 'string' ? row.condition_id : 'condition_' + Date.now(), ignoreFocusOut: true });
			if (request.condition_id === undefined) { return; }
			const entity = await vscode.window.showQuickPick(['actor', 'target'], { title: 'Condition - Entity' }); if (!entity) { return; }
			const container = await vscode.window.showInputBox({ title: 'Condition - Container', value: 'health', ignoreFocusOut: true }); if (!container) { return; }
			const path = await vscode.window.showInputBox({ title: 'Condition - Attribute Path', value: '["current"]', ignoreFocusOut: true,
				validateInput: text => { try { const a = JSON.parse(text); if (Array.isArray(a) && a.length && a.every(v => typeof v === 'string' || Number.isSafeInteger(v))) { return; } } catch {} return 'Enter a JSON array of names or integer indexes.'; } }); if (!path) { return; }
			const value = await promptValue({ kind: 'int', value_text: '0', allowed_types: ['int', 'float', 'bool'], choices: [] }, 'Condition - Value'); if (!value) { return; }
			const operator = await vscode.window.showQuickPick(value.value_type === 'bool' ? ['==', '!='] : ['==', '!=', '>', '>=', '<', '<='], { title: 'Condition - Operator' }); if (!operator) { return; }
			request.requirement = { entity, container, path: JSON.parse(path), operator, ...value };
		}
		if (operation === 'executor' || operation === 'add_action') {
			if (operation === 'executor' && row.role !== 'executor' && row.role !== 'argument' && !(row.role === 'step' && row.step_kind === 'action')) { throw new Error('Choose an Action step Executor.'); }
			request.executor_id = await pickExecutor(graph.executors, typeof row.executor_id === 'string' ? row.executor_id : undefined);
			if (!request.executor_id) { return; }
			request.arguments = [];
			for (const spec of graph.executors?.find(item => item.id === request.executor_id)?.arguments ?? []) {
				const value = await promptValue({ kind: spec.allowed_types[0], value_text: '', allowed_types: argumentTypes(spec), choices: [] }, 'Executor - ' + spec.name);
				if (!value) { return; } request.arguments.push({ name: spec.name, ...value });
			}
		}
		await ready();
		await editBehavior(context.projectDirectory, executable, resource.source_path, request, message => output.appendLine(message));
		output.appendLine(`[sequence] Saved ${resource.source_path}: ${operation}.`);
		await refresh();
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		output.appendLine(`[sequence] Error: ${message}`); void vscode.window.showErrorMessage(message);
	}
}
