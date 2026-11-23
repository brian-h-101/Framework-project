import * as vscode from 'vscode';
import { relative } from 'node:path';
import { resolveProjectContext } from './project_context';
import { SceneTreeProvider, projectUri } from './scene_tree_provider';
import type { SceneTreeElement } from './scene_tree_provider';
import { SceneSelection, ensureWorkspace, workspaceDirectories } from './scene_selection';
import { declarationLine } from './scene_navigation';
import { SceneEditingCommands } from './scene_editing_command';
import { configureMovementCapability } from './movement_capability_command';
import { LibraryManager } from './library/library_manager';

export function activate(context: vscode.ExtensionContext): void {
	const output = vscode.window.createOutputChannel('Framework Scenes');
	const provider = new SceneTreeProvider();
	const view = vscode.window.createTreeView('frameworkScenes.scenes', {
		treeDataProvider: provider,
		showCollapseAll: true
	});
	const selection = new SceneSelection(provider, output, message => { view.message = message; });
	const editing = new SceneEditingCommands(provider, output, () => selection.refresh());
	let pendingOperation: Promise<void> | undefined;
	const library = new LibraryManager(output, async (uri, removed) => {
		if (removed) { selection.removed(uri, pendingOperation); }
		else { selection.scheduleRefresh(uri, pendingOperation); }
	});
	function runOperation(operation: () => Promise<void>): Promise<void> {
		if (pendingOperation) {
			output.appendLine('[scene-editing] A scene operation is already running.');
			return pendingOperation;
		}
		pendingOperation = operation().finally(() => { pendingOperation = undefined; });
		return pendingOperation;
	}

	async function navigate(element: SceneTreeElement, target: 'declaration' | 'structure' | 'instance' | 'base' | 'script'): Promise<void> {
		try {
			const resolved = provider.resolve(element);
			ensureWorkspace(resolved.context);
			const node = resolved.node;
			const path = target === 'declaration' ? node.source_path
				: target === 'structure' ? node.structural_scene
				: target === 'instance' ? node.instance_path
					: target === 'base' ? node.base_scene_path : node.script_path;
			if (!path) {
				throw new Error('The selected node has no file for this command.');
			}
			const uri = projectUri(resolved.context, path);
			const actual = await resolveProjectContext(uri.fsPath, workspaceDirectories());
			if (relative(resolved.context.projectDirectory, actual.projectDirectory) !== '') {
				throw new Error('The linked file belongs to a different Godot project.');
			}
			provider.resolve(element);
			ensureWorkspace(resolved.context);
			const document = await vscode.workspace.openTextDocument(uri);
			provider.resolve(element);
			ensureWorkspace(resolved.context);
			const line = target === 'declaration' || target === 'structure'
				? declarationLine(document.getText(), target === 'structure' ? node.structural_node_path : node.source_node_path) : undefined;
			await vscode.window.showTextDocument(document, {
				preview: true,
				selection: line === undefined ? undefined : new vscode.Range(line, 0, line, 0)
			});
		} catch (error) {
			report(error);
		}
	}

	function report(error: unknown): void {
		const message = error instanceof Error ? error.message : String(error);
		output.appendLine(`[scene-navigation] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}

	const findScene = vscode.commands.registerCommand('frameworkScenes.findScene', async () => {
		try {
			if (!vscode.workspace.isTrusted) {
				throw new Error('Scene discovery requires a trusted workspace.');
			}
			const uris = await vscode.workspace.findFiles('**/*.tscn', '**/{.git,.godot,node_modules,out}/**');
			const items = uris.filter(uri => uri.scheme === 'file').map(uri => ({
				label: uri.path.slice(uri.path.lastIndexOf('/') + 1),
				description: vscode.workspace.asRelativePath(uri, true),
				uri
			})).sort((left, right) => left.description.localeCompare(right.description));
			if (items.length === 0) {
				void vscode.window.showInformationMessage('No .tscn scenes were found in the opened workspace.');
				return;
			}
			const chosen = await vscode.window.showQuickPick(items, {
				title: 'Open a Godot Scene',
				placeHolder: 'Search scene names and paths',
				matchOnDescription: true,
				ignoreFocusOut: true
			});
			if (!chosen) {
				return;
			}
			const project = await resolveProjectContext(chosen.uri.fsPath, workspaceDirectories());
			ensureWorkspace(project);
			await vscode.window.showTextDocument(chosen.uri, { preview: true });
		} catch (error) {
			report(error);
		}
	});
	const watcher = vscode.workspace.createFileSystemWatcher('**/*.tscn');
	context.subscriptions.push(
		view, provider, selection, output, findScene, watcher,
		vscode.commands.registerCommand('frameworkScenes.refresh', () => runOperation(() => selection.refresh())),
		vscode.commands.registerCommand('frameworkScenes.manageAuthoredLibrary', () => runOperation(() => library.execute())),
		vscode.commands.registerCommand('frameworkScenes.openDeclaration', (node: SceneTreeElement) => navigate(node, 'declaration')),
		vscode.commands.registerCommand('frameworkScenes.openStructure', (node: SceneTreeElement) => navigate(node, 'structure')),
		vscode.commands.registerCommand('frameworkScenes.addNode', (node: SceneTreeElement) => runOperation(() => editing.execute('add_node', node))),
	vscode.commands.registerCommand('frameworkScenes.setNodeProperty', (node: SceneTreeElement) => runOperation(() => editing.execute('set_property', node))),
		vscode.commands.registerCommand('frameworkScenes.addInstance', (node: SceneTreeElement) => runOperation(() => editing.execute('add_instance', node))),
		vscode.commands.registerCommand('frameworkScenes.addLayoutPreset', (node: SceneTreeElement) => runOperation(() => editing.execute('add_layout', node))),
		vscode.commands.registerCommand('frameworkScenes.attachBehavior', (node: SceneTreeElement) => runOperation(() => editing.execute('attach_behavior', node))),
		vscode.commands.registerCommand('frameworkScenes.configureCapabilities', (node: SceneTreeElement) =>
			runOperation(() => configureMovementCapability(provider, node, output, () => selection.refresh()))),
		vscode.commands.registerCommand('frameworkScenes.assignMovement', (node: SceneTreeElement) => runOperation(() => editing.execute('assign_movement', node))),
		vscode.commands.registerCommand('frameworkScenes.attachScript', (node: SceneTreeElement) => runOperation(() => editing.execute('attach_script', node))),
		vscode.commands.registerCommand('frameworkScenes.removeScript', (node: SceneTreeElement) => runOperation(() => editing.execute('remove_script', node))),
		vscode.commands.registerCommand('frameworkScenes.renameNode', (node: SceneTreeElement) => runOperation(() => editing.execute('rename', node))),
		vscode.commands.registerCommand('frameworkScenes.removeNode', (node: SceneTreeElement) => runOperation(() => editing.execute('remove', node))),
		vscode.commands.registerCommand('frameworkScenes.openInstance', (node: SceneTreeElement) => navigate(node, 'instance')),
		vscode.commands.registerCommand('frameworkScenes.openBase', (node: SceneTreeElement) => navigate(node, 'base')),
		vscode.commands.registerCommand('frameworkScenes.openScript', (node: SceneTreeElement) => navigate(node, 'script')),
		vscode.window.onDidChangeActiveTextEditor(editor => selection.follow(editor, pendingOperation)),
		vscode.workspace.onDidSaveTextDocument(document => selection.scheduleRefresh(document.uri, pendingOperation)),
		vscode.workspace.onDidChangeTextDocument(() => selection.updateStatus()),
		vscode.workspace.onDidChangeWorkspaceFolders(() => selection.workspaceChanged(pendingOperation)),
		vscode.workspace.onDidChangeConfiguration(event => {
			if (event.affectsConfiguration('frameworkScenes.godotExecutable')
				|| event.affectsConfiguration('godotTools.editorPath.godot4')) {
				selection.scheduleRefreshAfter(pendingOperation);
			}
		}),
		watcher.onDidChange(uri => selection.scheduleRefresh(uri, pendingOperation)),
		watcher.onDidCreate(uri => selection.scheduleRefresh(uri, pendingOperation)),
		watcher.onDidDelete(uri => selection.removed(uri, pendingOperation))
	);
	output.appendLine('Framework Scenes activated.');
	selection.follow(vscode.window.activeTextEditor);
}
