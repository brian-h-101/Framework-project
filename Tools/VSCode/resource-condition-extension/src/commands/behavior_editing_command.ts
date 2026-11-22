import * as vscode from 'vscode';
import { prepareEditGraph } from '../resources/edit_context';
import { createHash } from 'node:crypto';
import { relative } from 'node:path';
import { editBehavior, type BehaviorEdit } from '../bridges/behavior_editing_bridge';
import { ResourceTreeProvider, resourceUri, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { resolveProjectContext } from '../workspace/project_context';
import { promptKey, promptValue, promptEffect } from '../resources/value_prompts';
import { pickExecutor } from '../resources/executor_picker';
import { argumentTypes } from '../resources/executor_metadata';
import { pickResource } from '../resources/resource_picker';
import { pickPresetFragments } from '../resources/preset_fragment_picker';

export type StructuralOperation = 'set' | 'add' | 'rename' | 'remove' | 'add_effect'
	| 'remove_condition' | 'clear_requirements' | 'set_behavior' | 'set_interaction'
	| 'set_fragments' | 'fragment_up' | 'fragment_down';

export async function editTreeEntry(
	provider: ResourceTreeProvider,
	element: ResourceTreeElement | undefined,
	operation: StructuralOperation,
	output: vscode.OutputChannel,
	refresh: () => Promise<void>
): Promise<void> {
	try {
		if (!element || element.cycle) { throw new Error('Choose an editable row in Framework Resources.'); }
		const selected = provider.resolve(element);
		const { data, resource, projectRoot } = selected;
		let graph = selected.graph;
		const context = await resolveProjectContext(selected.uri.fsPath,
			(vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath));
		if (relative(context.projectDirectory, projectRoot.fsPath) !== '') {
			throw new Error('The resource project changed. Refresh and retry.');
		}
		const ensureSession = (): void => {
			provider.resolve(element);
			if (!vscode.workspace.isTrusted || !(vscode.workspace.workspaceFolders ?? []).some(folder =>
				folder.uri.scheme === 'file' && relative(context.workspaceDirectory, folder.uri.fsPath) === '')) {
				throw new Error('The trusted project workspace changed. Refresh and retry.');
			}
		};
		const ensureReady = async (added: Record<string, string> = {}): Promise<void> => {
			ensureSession();
			for (const [path, expected] of Object.entries({ ...added, ...graph.dependency_hashes, ...graph.executor_snapshot?.hashes })) {
				const uri = vscode.Uri.joinPath(projectRoot, ...path.slice(6).split('/'));
				if (vscode.workspace.textDocuments.some(document => document.isDirty
					&& document.uri.scheme === 'file' && relative(uri.fsPath, document.uri.fsPath) === '')) {
					throw new Error(`Save or revert '${path}' before editing resources.`);
				}
				const actual = createHash('sha256').update(await vscode.workspace.fs.readFile(uri)).digest('hex');
				if (actual !== expected) { throw new Error(`Resource changed: ${path}. Refresh and retry.`); }
			}
			ensureSession();
		};
		await ensureReady();
		const executable = vscode.workspace.getConfiguration('godotTools', projectRoot)
			.get<string>('editorPath.godot4')?.trim();
		if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace first.'); }
		graph = await prepareEditGraph(graph, context.projectDirectory, executable, message => output.appendLine(message));
		await ensureReady();
		let source = resource.source_path;
		const request: BehaviorEdit = { operation, expected_hashes: graph.dependency_hashes,
			catalog_paths: graph.catalog_paths, catalog_seed: graph.roots[0], executor_snapshot: graph.executor_snapshot, step_id: data?.sequence?.step_id };
		const isPreset = resource.kind === 'starting_attributes';
		if (isPreset) { request.presentation_preset = true; }
		if (operation === 'set_fragments' || operation === 'fragment_up' || operation === 'fragment_down') {
			if (!isPreset || !resource.fragment_paths || (data && data.path[0]?.text !== 'Fragments')) {
				throw new Error('Choose an attribute fragment in a starting preset.');
			}
			request.operation = 'set_fragments';
			if (operation === 'set_fragments') {
				const selection = await pickPresetFragments(context.projectDirectory, executable, resource.fragment_paths,
					message => output.appendLine(message));
				if (!selection) { return; }
				request.fragment_paths = selection.paths;
				request.expected_hashes = { ...selection.hashes, ...graph.dependency_hashes };
			} else {
				const segment = data?.path[1];
				const index = segment?.kind === 'index' ? Number(segment.text) : -1;
				const next = index + (operation === 'fragment_up' ? -1 : 1);
				const paths = [...resource.fragment_paths];
				if (!Number.isInteger(index) || index < 0 || index >= paths.length || next < 0 || next >= paths.length) {
					throw new Error('Choose a fragment that can move in that direction.');
				}
				[paths[index], paths[next]] = [paths[next], paths[index]];
				request.fragment_paths = paths;
			}
		} else if (operation === 'set_interaction') {
			if (data || resource.kind !== 'automation') { throw new Error('Choose an Automation Resource.'); }
			const chosen = await pickResource(context, executable, 'interaction', output, 'Automation — Interaction');
			if (!chosen) { return; }
			request.interaction_path = 'res://' + relative(context.projectDirectory, chosen.fsPath).split('\\').join('/');
		} else if (operation === 'set_behavior' || (operation === 'set' && resource.kind === 'action' && data?.path.length === 1 && data.path[0].text === 'behavior_id')) {
			if (resource.kind !== 'action') { throw new Error('Choose an Action Resource.'); }
			request.behavior_id = await pickExecutor(graph.executors, resource.behavior_id);
			if (request.behavior_id === undefined) { return; }
			request.operation = 'set_behavior';
		} else if (operation === 'remove_condition') {
			if (data || element.linkRole !== 'condition' || !element.parentSource) {
				throw new Error('Choose a condition linked beneath a condition group.');
			}
			source = element.parentSource;
			request.condition_index = element.linkIndex;
			request.condition_path = resource.source_path;
			if (await vscode.window.showWarningMessage(
				`Remove '${resource.id}' from this group? Its .tres file and other groups stay intact.`,
				{ modal: true }, 'Remove Link') !== 'Remove Link') { return; }
		} else if (operation === 'clear_requirements') {
			if (data) { throw new Error('Choose an interaction or its requirements group.'); }
			if (element.linkRole === 'requirements' && element.parentSource) { source = element.parentSource; }
			else if (resource.kind !== 'interaction' || !resource.links.some(link => link.role === 'requirements')) {
				throw new Error('Choose an interaction with assigned requirements.');
			}
			if (await vscode.window.showWarningMessage(
				'Clear this interaction’s requirements? Invocation will no longer check this group. The group file is preserved.',
				{ modal: true }, 'Clear Requirements') !== 'Clear Requirements') { return; }
		} else if (operation === 'add_effect') {
			if ((resource.kind !== 'action' && resource.kind !== 'behavior') || resource.supports_effects === false || (data && !data.can_add_effect)) { throw new Error('Choose an action that supports attribute effects.'); }
			request.effect = await promptEffect();
			if (!request.effect) { return; }
		} else {
			if (!data || !(operation === 'set' ? data.editable : operation === 'add' ? data.can_add
				: operation === 'rename' ? data.can_rename : data.can_remove)) {
				throw new Error('This operation is unavailable for the selected entry.');
			}
			request.path = data.path;
			if (operation === 'add' && data.kind === 'Dictionary' || operation === 'rename') {
				request.key = await promptKey(operation === 'rename' ? data.path.at(-1) : undefined);
				if (!request.key) { return; }
			}
			if (operation === 'set' || operation === 'add') {
				const spec = operation === 'add' && resource.kind === 'interaction' && data.path.length === 1
					? resource.argument_specs?.find(spec => spec.name === request.key?.text) : undefined;
				const addsContainer = operation === 'add' && isPreset && data.path.length === 1 && data.path[0].text === 'Overrides';
				const container = { kind: 'Dictionary', value_text: '', allowed_types: ['Dictionary'], choices: [] };
				const value = await promptValue(operation === 'set' ? data : addsContainer ? container
					: spec ? { kind: spec.allowed_types[0], value_text: '', allowed_types: argumentTypes(spec), choices: [] } : undefined,
				isPreset && data.path[0]?.text === 'Effective Attributes' ? 'Override Value' : 'Value');
				if (!value) { return; }
				Object.assign(request, value);
			}
			if (operation === 'remove' && await vscode.window.showWarningMessage(
				`Remove '${data.label}' and its nested data from ${source.split('/').at(-1)}?`,
				{ modal: true }, 'Remove Entry') !== 'Remove Entry') { return; }
		}
		await ensureReady(request.expected_hashes);
		output.appendLine(`[structure] ${operation}: ${source}`);
		await editBehavior(context.projectDirectory, executable, source, request, message => output.appendLine(message));
		output.appendLine(`[structure] Saved ${source}.`);
		await refresh();
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		output.appendLine(`[structure] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}
