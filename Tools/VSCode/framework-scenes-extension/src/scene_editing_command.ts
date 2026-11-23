import * as vscode from 'vscode';
import { createHash } from 'node:crypto';
import { relative, sep } from 'node:path';
import { editScene, nodeTypes, inspectScript, inspectNodeProperties, isLayoutPresetPath, LAYOUT_PRESET_FOLDER, LAYOUT_SUFFIX, resolveLayout } from './scene_editing_bridge';
import type { SceneEdit, SceneOperation } from './scene_editing_bridge';
import { loadSceneGraph } from './scene_bridge';
import { loadResourceCatalog } from './resource_catalog_bridge';
import { loadMovementConfigurations } from './movement_configuration_bridge';
import { SceneTreeProvider, projectUri } from './scene_tree_provider';
import type { SceneTreeElement } from './scene_tree_provider';
import { ensureWorkspace } from './scene_selection';
import { promptNodeProperty } from './scene_property_prompt';
import { pickSceneInstance } from './scene_instance_picker';
import { scenePathInProject, isInside, resolveProjectContext, validateResourcePath } from './project_context';

export class SceneEditingCommands {
	private busy = false;
	constructor(private readonly provider: SceneTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>) {}

	async execute(operation: SceneOperation | 'add_layout', element: SceneTreeElement): Promise<void> {
		if (this.busy) { void vscode.window.showInformationMessage('A scene edit is already in progress.'); return; }
		this.busy = true;
		try {
			const { context, graph, node } = this.provider.resolve(element);
			if ((operation.startsWith('add_') && !node.can_add) || (operation === 'rename' && !node.can_rename)
				|| (operation === 'remove' && !node.can_remove)) {
				throw new Error('Open the structure source scene to edit this node. The scene root is protected.');
			}
			if (operation === 'attach_behavior' && (!node.is_entity || !node.can_add)) {
				throw new Error('Choose an editable entity root to attach behavior.');
			}
			if (operation === 'assign_movement' && !node.can_assign_movement) {
				throw new Error('Open the movement body’s structure source scene to assign its configuration.');
			}
			if (operation === 'set_property' && (node.structural_scene !== graph.source_path || node.type === 'InstancePlaceholder')) {
				throw new Error('Open the structure source scene to set properties on this node.');
			}
			if ((operation === 'attach_script' && !node.can_attach_script)
				|| (operation === 'remove_script' && !node.can_remove_script)) {
				throw new Error('Choose a locally owned node. Remove an existing script before attaching another; use Open Structure Source for shared nodes.');
			}
			const root = vscode.Uri.file(context.projectDirectory);
			const executable = vscode.workspace.getConfiguration('frameworkScenes', root).get<string>('godotExecutable')?.trim()
				|| vscode.workspace.getConfiguration('godotTools', root).get<string>('editorPath.godot4')?.trim();
			if (!executable) { throw new Error('Configure frameworkScenes.godotExecutable or godotTools.editorPath.godot4 in Workspace settings.'); }
			const hashes = { ...graph.dependency_hashes };
			let layoutHashes: Record<string, string> = {};
			const readHash = async (source: string): Promise<string> => {
				const uri = projectUri(context, source);
				const actual = await resolveProjectContext(uri.fsPath, [context.workspaceDirectory]);
				if (relative(context.projectDirectory, actual.projectDirectory) !== '') {
					throw new Error('Choose a dependency from the same Godot project.');
				}
				const bytes = await vscode.workspace.fs.readFile(uri);
				return createHash('sha256').update(bytes).digest('hex');
			};
			const dirty = (): boolean => vscode.workspace.textDocuments.some(document => document.isDirty
				&& document.uri.scheme === 'file' && Object.keys({ ...hashes, ...layoutHashes }).some(source =>
					relative(document.uri.fsPath, projectUri(context, source).fsPath) === ''));
			const ready = async (): Promise<void> => {
				this.provider.resolve(element);
				ensureWorkspace(context);
				if (dirty()) { throw new Error('Save or revert text edits in this scene and its dependencies first.'); }
				for (const [source, hash] of Object.entries({ ...hashes, ...layoutHashes })) {
					if (await readHash(source) !== hash) {
						throw new Error(`Scene dependency changed: ${source}. Refresh and run the command again.`);
					}
				}
				this.provider.resolve(element);
				ensureWorkspace(context);
				if (dirty()) { throw new Error('A scene dependency gained unsaved text edits. Save or revert them first.'); }
			};
			await ready();
			const request: SceneEdit = { operation: operation === 'add_layout' ? 'add_instance' : operation, path: node.path, expected_hashes: hashes };
			if (operation === 'set_property') {
				const properties = await inspectNodeProperties(context.projectDirectory, executable, graph.source_path,
					node.path, text => this.output.appendLine(text));
				const change = await promptNodeProperty(node.name, properties);
				if (!change) { return; }
				Object.assign(request, change);
			} else if (operation === 'remove') {
				const descendants = Object.keys(graph.nodes).filter(path => path.startsWith(node.path + '/')).length;
				const chosen = await vscode.window.showWarningMessage(
					`Remove '${node.name}' and ${descendants} descendant(s) from ${graph.source_path}? Connections to the subtree are also removed.`,
					{ modal: true }, 'Remove Node');
				if (chosen !== 'Remove Node') { return; }
			} else if (operation === 'attach_script' || operation === 'remove_script') {
				let script = node.script_path;
				if (operation === 'attach_script') {
					const uris = await vscode.workspace.findFiles('**/*.gd', '**/{.git,.godot,node_modules,out}/**');
					const items = uris.filter(uri => uri.scheme === 'file' && isInside(context.projectDirectory, uri.fsPath))
						.map(uri => ({ label: uri.path.slice(uri.path.lastIndexOf('/') + 1),
							description: vscode.workspace.asRelativePath(uri, true), uri }))
						.sort((left, right) => left.description.localeCompare(right.description));
					if (!items.length) { void vscode.window.showInformationMessage('No project GDScript files are available.'); return; }
					const chosen = await vscode.window.showQuickPick(items, {
						title: 'Attach Script', placeHolder: `Search .gd files for ${node.name} (${node.type})`,
						matchOnDescription: true, ignoreFocusOut: true
					});
					if (!chosen) { return; }
					script = 'res://' + relative(context.projectDirectory, chosen.uri.fsPath).split('\\').join('/');
					validateResourcePath(script, '.gd');
				}
				if (script) {
					const inspectedHash = await readHash(script);
					if (hashes[script] && hashes[script] !== inspectedHash) { throw new Error('Script changed. Refresh and retry.'); }
					hashes[script] = inspectedHash;
					await ready();
					const inspected = await inspectScript(context.projectDirectory, executable, script, node.type,
						text => this.output.appendLine(text));
					for (const [source, hash] of Object.entries(inspected.dependency_hashes)) {
						if (hashes[source] && hashes[source] !== hash) { throw new Error(`Script dependency changed: ${source}. Refresh and retry.`); }
						hashes[source] = hash;
					}
					await ready();
				}
				if (operation === 'attach_script') {
					request.script_path = script;
				} else {
					const chosen = await vscode.window.showWarningMessage(
						`Remove the attached script from '${node.name}'? Saved node properties are retained.`,
						{ modal: true }, 'Remove Script');
					if (chosen !== 'Remove Script') { return; }
				}
			} else if (operation === 'assign_movement') {
				const required = [node.script_path];
				if (node.movement_configuration_path) {
					required.push(node.movement_configuration_path.split('::')[0]);
				}
				for (const source of required) {
					const hash = await readHash(source);
					if (hashes[source] && hashes[source] !== hash) { throw new Error(`Dependency changed: ${source}. Refresh and retry.`); }
					hashes[source] = hash;
				}
				await ready();
				this.output.appendLine('[catalog] Loading movement configurations...');
				const configurations = await loadMovementConfigurations(context.projectDirectory, executable,
					text => this.output.appendLine(text));
				await ready();
				const items = configurations
					.filter(entry => entry.source_path !== node.movement_configuration_path
						&& (entry.body_type === undefined || entry.body_type === node.type))
					.map(entry => ({ label: entry.source_path.split('/').pop()!, description: entry.action_id,
						detail: `${entry.source_path} · ${entry.behavior_id}`, entry }));
				if (items.length === 0) {
					void vscode.window.showInformationMessage('No other movement configurations are compatible with this body.');
					return;
				}
				const chosen = await vscode.window.showQuickPick(items, {
					title: 'Assign Movement Configuration', placeHolder: 'Search configuration names, Action IDs, behavior IDs, or paths',
					matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true
				});
				if (!chosen) { return; }
				for (const [source, hash] of Object.entries(chosen.entry.dependency_hashes)) {
					if (hashes[source] && hashes[source] !== hash) { throw new Error(`Movement dependency changed: ${source}. Refresh and retry.`); }
					hashes[source] = hash;
				}
				request.movement_configuration = chosen.entry.source_path;
			} else {
				let suggested = node.name;
				if (operation === 'add_node') {
					const types = await nodeTypes(context.projectDirectory, executable, text => this.output.appendLine(text));
					const chosen = await vscode.window.showQuickPick(types, {
						title: 'Add Child Node — Type', placeHolder: 'Search native Godot node types', ignoreFocusOut: true
					});
					if (!chosen) { return; }
					request.node_type = chosen;
					suggested = chosen;
				} else if (operation === 'add_instance' || operation === 'add_layout') {
					let scene: string;
					if (operation === 'add_layout') {
						const files = await vscode.workspace.findFiles(new vscode.RelativePattern(root, LAYOUT_PRESET_FOLDER + '/**/*' + LAYOUT_SUFFIX));
						const options = files.filter(file => file.scheme === 'file' && isInside(context.projectDirectory, file.fsPath))
							.map(file => {
								const source = 'res://' + relative(context.projectDirectory, file.fsPath).split(sep).join('/');
								return { label: source.slice(('res://' + LAYOUT_PRESET_FOLDER + '/').length, -LAYOUT_SUFFIX.length), description: source };
							}).filter(item => isLayoutPresetPath(item.description))
							.sort((a, b) => a.label.localeCompare(b.label));
						if (!options.length) {
							void vscode.window.showInformationMessage('Create and build a Layout Preset in Framework Resources first.');
							return;
						}
						const chosen = await vscode.window.showQuickPick(options, { title: 'Add Layout Preset', matchOnDescription: true, ignoreFocusOut: true });
						if (!chosen) { return; }
						await ready();
						const layout = await resolveLayout(context.projectDirectory, executable, chosen.description, text => this.output.appendLine(text));
						request.layout_path = chosen.description;
						request.layout_hashes = layoutHashes = layout.dependency_hashes;
						scene = layout.scene_path;
					} else {
						const chosen = await pickSceneInstance(context, graph.source_path);
						if (!chosen) { return; }
						scene = await scenePathInProject(context, chosen.fsPath);
					}
					ensureWorkspace(context);
					const candidate = await loadSceneGraph(context.projectDirectory, executable, scene,
						text => this.output.appendLine(text));
					for (const [source, hash] of Object.entries(candidate.dependency_hashes)) {
						if ((hashes[source] && hashes[source] !== hash) || (layoutHashes[source] && layoutHashes[source] !== hash)) { throw new Error('A shared scene dependency changed. Refresh and retry.'); }
						hashes[source] = hash;
					}
					request.instance_scene = scene;
					suggested = candidate.nodes['.'].name;
				} else if (operation === 'attach_behavior') {
					const required = new Set<string>([
						'res://Framework/Content/Universal/Interaction/based/Legacy/interaction_behavior.gd',
						'res://Framework/Content/Universal/Interaction/based/Legacy/automation_behavior.gd'
					]);
					const pending = [node.path];

					while (pending.length > 0) {
						const path = pending.pop()!;
						const current = graph.nodes[path];
						if (path !== node.path && current.is_entity) {
							continue;
						}
						if (current.interaction_id && current.interaction_resource_path) {
							required.add(current.interaction_resource_path.split('::')[0]);
						}
						if (current.behavior_id && current.behavior_resource_path) { required.add(current.behavior_resource_path.split('::')[0]); }
						if (current.automation_id && current.automation_resource_path) { required.add(current.automation_resource_path.split('::')[0]); }
						pending.push(...current.children);
					}

					for (const source of required) {
						const hash = await readHash(source);
						if (hashes[source] && hashes[source] !== hash) {
							throw new Error(`Dependency changed: ${source}. Refresh and retry.`);
						}
						hashes[source] = hash;
					}

					await ready();
					this.output.appendLine('[catalog] Loading Behavior resources...');
					const catalog = await loadResourceCatalog(context.projectDirectory, executable,
						text => this.output.appendLine(text));
					const candidates = catalog.resources
						.filter(entry => entry.kind === 'behavior' || entry.kind === 'interaction' || entry.kind === 'automation')
						.sort((left, right) => left.source_path.localeCompare(right.source_path));
					const items = await Promise.all(candidates.map(async entry => ({
						label: entry.source_path.split('/').pop()!,
						description: `${entry.kind}: ${entry.id}`,
						resourceKind: entry.kind,
						detail: entry.source_path,
						id: entry.id,
						source_path: entry.source_path,
						content_hash: await readHash(entry.source_path)
					})));

					await ready();
					if (items.length === 0) {
						void vscode.window.showInformationMessage('No Behavior resources are available.');
						return;
					}
					const chosen = await vscode.window.showQuickPick(items, {
						title: 'Attach Behavior Resource',
						placeHolder: 'Search by file name, behavior ID, or path',
						matchOnDescription: true,
						matchOnDetail: true,
						ignoreFocusOut: true
					});
					if (!chosen) { return; }
					if (hashes[chosen.source_path] && hashes[chosen.source_path] !== chosen.content_hash) {
						throw new Error('The selected behavior Resource changed. Refresh and retry.');
					}
					hashes[chosen.source_path] = chosen.content_hash;
					if (chosen.resourceKind === 'behavior') {
						const binding = 'res://Framework/Content/Universal/Interaction/based/Bindings/behavior_binding.gd';
						hashes[binding] = await readHash(binding);
						request.behavior_resource = chosen.source_path;
					}
					else if (chosen.resourceKind === 'automation') { request.automation_resource = chosen.source_path; }
					else { request.interaction_resource = chosen.source_path; }
					suggested = chosen.id.split('_')
						.map(part => part.charAt(0).toUpperCase() + part.slice(1))
						.join('') + 'Behavior';
				}
				const name = await vscode.window.showInputBox({
					title: operation === 'rename' ? 'Rename Node' : 'New Node Name',
					prompt: 'Enter a unique sibling name.', value: suggested, ignoreFocusOut: true,
					validateInput: text => !text.trim() ? 'A node name is required.'
						: /[:@/"%\\\r\n]/.test(text) || text === '.' || text === '..' ? 'Enter a valid Godot node name.' : undefined
				});
				if (name === undefined) { return; }
				request.name = name;
			}
			await ready();
			const result = await editScene(context.projectDirectory, executable, graph.source_path, request,
				text => this.output.appendLine(text));
			this.output.appendLine(`[scene-editing] Saved ${result.operation}: ${result.scene_path} (${result.path}${result.new_path ? ' → ' + result.new_path : ''})`);
			await this.refresh();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[scene-editing] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		} finally { this.busy = false; }
	}
}
