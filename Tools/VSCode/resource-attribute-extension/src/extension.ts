import * as vscode from 'vscode';
import { LibraryTreeProvider, type LibraryElement } from './library/library_tree_provider';
import { LibraryController } from './library/library_controller';
import { LibraryCommands } from './library/library_commands';
import { LibraryManageCommand } from './library/library_manage_command';
import { AttributeTreeProvider, projectUri } from './tree/attribute_tree_provider';
import type { AttributeElement } from './tree/attribute_tree_provider';
import { AttributeSelection, ensureWorkspace, workspaceDirectories } from './resources/attribute_selection';
import { AttributeCommands } from './commands/attribute_commands';
import { attributePathInProject, resolveProjectContext } from './workspace/project_context';

export function activate(context: vscode.ExtensionContext): void {
	const output = vscode.window.createOutputChannel('Resource Attribute');
	let pendingOperation: Promise<void> | undefined;
	const run = (operation: () => Promise<void>): Promise<void> => {
		if (pendingOperation) { void vscode.window.showInformationMessage('An authoring operation is already running.'); return Promise.resolve(); }
		pendingOperation = Promise.resolve().then(operation).finally(() => { pendingOperation = undefined; });
		return pendingOperation;
	};
	const libraryProvider = new LibraryTreeProvider();
	const libraryView = vscode.window.createTreeView('resourceAttribute.library', { treeDataProvider: libraryProvider, showCollapseAll: true });
	const library = new LibraryController(libraryProvider, output, message => { libraryView.message = message; });
	const provider = new AttributeTreeProvider();
	const view = vscode.window.createTreeView('resourceAttribute.attributes', { treeDataProvider: provider, showCollapseAll: true });
	const selection = new AttributeSelection(provider, output, message => { view.message = message; });
	const commands = new AttributeCommands(provider, output, () => selection.refresh());
	const libraryCommands = new LibraryCommands(libraryProvider, output, () => library.refresh(), selection);
	const manageLibrary = new LibraryManageCommand(libraryProvider, libraryCommands, () => library.refresh(), output);
	const libraryRegistrations = ([['openLibraryResource', 'open'], ['newCategory', 'category'],
		['newSubcategory', 'category'], ['newAttributeResource', 'resource'],
		['deleteResource', 'delete-resource'], ['deleteCategory', 'delete-category']] as const).map(([name, operation]) =>
		vscode.commands.registerCommand('resourceAttribute.' + name, (element: LibraryElement) => run(() => libraryCommands.execute(operation, element))));
	const libraryWatcher = vscode.workspace.createFileSystemWatcher('**/Framework/Content/Gameplay/Authored/**');
	const projectWatcher = vscode.workspace.createFileSystemWatcher('**/project.godot');
	const refreshLibrary = (): void => library.schedule(pendingOperation);
	const librarySubscriptions = [libraryWatcher, projectWatcher,
		libraryWatcher.onDidCreate(refreshLibrary), libraryWatcher.onDidChange(refreshLibrary), libraryWatcher.onDidDelete(refreshLibrary),
		projectWatcher.onDidCreate(refreshLibrary), projectWatcher.onDidChange(refreshLibrary), projectWatcher.onDidDelete(refreshLibrary)];
	const report = (error: unknown): void => {
		const message = error instanceof Error ? error.message : String(error);
		output.appendLine(`[attributes] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	};
	const find = vscode.commands.registerCommand('resourceAttribute.findResource', async () => {
		try {
			if (!vscode.workspace.isTrusted) { throw new Error('Attribute discovery requires a trusted workspace.'); }
			const uris = await vscode.workspace.findFiles('**/Framework/Content/Gameplay/Authored/**/*.tres', '**/{.git,.godot,node_modules,out}/**');
			const items = uris.filter(uri => uri.scheme === 'file').map(uri => ({
				label: uri.path.slice(uri.path.lastIndexOf('/') + 1), description: vscode.workspace.asRelativePath(uri, true), uri
			})).sort((left, right) => left.description.localeCompare(right.description));
			const chosen = await vscode.window.showQuickPick(items, {
				title: 'Find an Attribute Resource', placeHolder: 'Search resource names and paths',
				matchOnDescription: true, ignoreFocusOut: true
			});
			if (!chosen) { return; }
			const project = await resolveProjectContext(chosen.uri.fsPath, workspaceDirectories());
			await attributePathInProject(project, chosen.uri.fsPath);
			ensureWorkspace(project);
			await vscode.window.showTextDocument(chosen.uri, { preview: true });
		} catch (error) { report(error); }
	});
	const open = vscode.commands.registerCommand('resourceAttribute.openSource', async (element: AttributeElement) => {
		try {
			const { context: project, graph } = provider.resolve(element);
			ensureWorkspace(project);
			const uri = projectUri(project, graph.source_path);
			await attributePathInProject(project, uri.fsPath);
			provider.resolve(element);
			ensureWorkspace(project);
			await vscode.window.showTextDocument(uri, { preview: true });
		} catch (error) { report(error); }
	});
	const watcher = vscode.workspace.createFileSystemWatcher('**/*.tres');
	context.subscriptions.push(libraryView, libraryProvider, library, ...libraryRegistrations, ...librarySubscriptions,
		vscode.commands.registerCommand('resourceAttribute.manageLibrary', () => run(() => manageLibrary.execute())),
		vscode.commands.registerCommand('resourceAttribute.refreshLibrary', () => run(() => library.refresh())),
		view, output, provider, selection, find, open, watcher,
		vscode.commands.registerCommand('resourceAttribute.refresh', () => selection.refresh()),
		vscode.commands.registerCommand('resourceAttribute.editValue', (element: AttributeElement) => run(() => commands.execute('set', element))),
		vscode.commands.registerCommand('resourceAttribute.addEntry', (element: AttributeElement) => run(() => commands.execute('add', element))),
		vscode.commands.registerCommand('resourceAttribute.renameEntry', (element: AttributeElement) => run(() => commands.execute('rename', element))),
		vscode.commands.registerCommand('resourceAttribute.removeEntry', (element: AttributeElement) => run(() => commands.execute('remove', element))),
		vscode.window.onDidChangeActiveTextEditor(editor => selection.follow(editor)),
		vscode.workspace.onDidSaveTextDocument(document => selection.scheduleRefresh(document.uri)),
		vscode.workspace.onDidChangeTextDocument(() => selection.updateStatus()),
		vscode.workspace.onDidChangeWorkspaceFolders(() => { selection.workspaceChanged(); library.workspaceChanged(pendingOperation); }),
		vscode.workspace.onDidChangeConfiguration(event => {
			if (event.affectsConfiguration('resourceAttribute.godotExecutable')
				|| event.affectsConfiguration('godotTools.editorPath.godot4')) { void selection.refresh(); library.schedule(pendingOperation); }
		}),
		watcher.onDidChange(uri => selection.scheduleRefresh(uri)),
		watcher.onDidCreate(uri => selection.scheduleRefresh(uri)),
		watcher.onDidDelete(uri => selection.resourceRemoved(uri))
	);
	output.appendLine('Resource Attribute activated.');
	selection.follow(vscode.window.activeTextEditor);
	void library.refresh();
}
