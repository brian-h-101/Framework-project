import * as vscode from 'vscode';
import {
	ResourceTreeProvider,
	type ResourceTreeElement
} from './tree/resource_tree_provider';
import { ResourceSelection } from './resources/resource_selection';
import {
	assignConditionFromFiles,
	assignInteractionRequirementsFromFiles,
	assignInteractionActionFromFiles,
	assignInteractionResourceFromFiles
} from './commands/condition_assignment_command';
import { ResourceDragAndDropController } from './tree/resource_drag_and_drop';
import { editTreeEntry, type StructuralOperation } from './commands/behavior_editing_command';
import { editConditionFromFile } from './commands/condition_editing_command';
import { LibraryManager } from './library/library_manager';
import { openExecutorScript } from './commands/executor_navigation_command';

export function activate(context: vscode.ExtensionContext): void {
	const output = vscode.window.createOutputChannel(
		'Resource Condition Extension'
	);

	const provider = new ResourceTreeProvider();
	const selection = new ResourceSelection(provider, output, message => { view.message = message; });
	const library = new LibraryManager(output, async (uri, removed) => {
		if (removed) { selection.removed(uri); }
		else { await selection.refresh(); }
	});

	let pendingOperation: Promise<void> | undefined;

	function runOperation(
		operation: () => Promise<void>
	): Promise<void> {
		if (pendingOperation) {
			output.appendLine(
				'[bridge] A resource operation is already running.'
			);

			return pendingOperation;
		}

		pendingOperation = operation().finally(() => {
			pendingOperation = undefined;
		});

		return pendingOperation;
	}

	function withTreeResource(
		element: ResourceTreeElement | undefined,
		expectedKind: string | undefined,
		operation: (uri: vscode.Uri | undefined) => Promise<void>
	): Promise<void> {
		return runOperation(async () => {
			try {
				let uri: vscode.Uri | undefined;

				if (element !== undefined) {
					if (
						!element
						|| typeof element.sourcePath !== 'string'
						|| element.cycle
					) {
						throw new Error(
							'Choose a resource item in Framework Resources.'
						);
					}

					const resolved = provider.resolve(element);
					const item = provider.getTreeItem(element);

					if (
						!item.resourceUri
						|| (
							expectedKind !== undefined
							&& (resolved.data !== undefined || resolved.resource.kind !== expectedKind)
						)
					) {
						throw new Error(
							'This command is unavailable for the selected resource.'
						);
					}

					uri = item.resourceUri;
				}

				await operation(uri);
			} catch (error) {
				const message = error instanceof Error
					? error.message
					: String(error);

				output.appendLine(`[context] Error: ${message}`);
				void vscode.window.showErrorMessage(message);
			}
		});
	}

	const dragAndDropController = new ResourceDragAndDropController(
		provider,
		files => runOperation(() => {
			if ('interaction' in files) {
				return assignInteractionResourceFromFiles(
					output,
					() => selection.refresh(),
					files
				);
			}

			return assignConditionFromFiles(
				output,
				() => selection.refresh(),
				files
			);
		}),
		output
	);

	const view = vscode.window.createTreeView(
		'customTreeView.resources',
		{
			treeDataProvider: provider,
			showCollapseAll: true,
			dragAndDropController
		}
	);

	const refreshCommand = vscode.commands.registerCommand(
		'customTreeView.refresh',
		() => runOperation(
			() => selection.refresh()
		)
	);
	const manageLibraryCommand = vscode.commands.registerCommand('customTreeView.manageBehaviorLibrary',
		() => runOperation(() => library.execute()));

	const assignmentCommand = vscode.commands.registerCommand(
		'customTreeView.addConditionToGroup',
		(element?: ResourceTreeElement) => withTreeResource(
			element,
			'condition_group',
			uri => assignConditionFromFiles(
				output,
				() => selection.refresh(),
				uri ? { group: uri } : undefined
			)
		)
	);

	const requirementsCommand = vscode.commands.registerCommand(
		'customTreeView.setInteractionRequirements',
		(element?: ResourceTreeElement) => withTreeResource(
			element,
			'interaction',
			uri => assignInteractionRequirementsFromFiles(
				output,
				() => selection.refresh(),
				uri ? { interaction: uri } : undefined
			)
		)
	);

	const actionCommand = vscode.commands.registerCommand(
		'customTreeView.setInteractionAction',
		(element?: ResourceTreeElement) => withTreeResource(
			element,
			'interaction',
			uri => assignInteractionActionFromFiles(
				output,
				() => selection.refresh(),
				uri ? { interaction: uri } : undefined
			)
		)
	);

	const editingCommand = vscode.commands.registerCommand(
		'customTreeView.editCondition',
		(element?: ResourceTreeElement) => withTreeResource(
			element,
			'condition',
			uri => editConditionFromFile(
				output,
				() => selection.refresh(),
				uri
			)
		)
	);

	const openCommand = vscode.commands.registerCommand(
		'customTreeView.openResource',
		(element?: ResourceTreeElement) => withTreeResource(
			element,
			undefined,
			async uri => {
				if (!uri) {
					throw new Error(
						'Choose a resource item in Framework Resources.'
					);
				}

				await vscode.commands.executeCommand('vscode.open', uri);
			}
		)
	);

	const openExecutorCommand = vscode.commands.registerCommand(
		'customTreeView.openExecutorScript',
		(element?: ResourceTreeElement) => runOperation(
			() => openExecutorScript(provider, element, output)
		)
	);

	const structuralCommands = ([
		['setAutomationInteraction', 'set_interaction'],
		['setActionBehavior', 'set_behavior'], ['editValue', 'set'], ['addEntry', 'add'], ['renameEntry', 'rename'],
		['removeEntry', 'remove'], ['addEffect', 'add_effect'],
		['removeConditionFromGroup', 'remove_condition'], ['clearRequirements', 'clear_requirements']
	] as const).map(([name, operation]) => vscode.commands.registerCommand(
		'customTreeView.' + name,
		(element?: ResourceTreeElement) => runOperation(() => editTreeEntry(
			provider, element, operation as StructuralOperation, output, () => selection.refresh()
		))
	));
	const watcher = vscode.workspace.createFileSystemWatcher('**/*.{tres,gd,godot,tscn,res,scn,gdshader}');
	const changed = (uri: vscode.Uri): void => selection.changed(uri, pendingOperation);
	const subscriptions = [watcher, watcher.onDidChange(changed), watcher.onDidCreate(changed),
		watcher.onDidDelete(uri => selection.removed(uri, pendingOperation)), vscode.workspace.onDidSaveTextDocument(document => changed(document.uri)),
		vscode.workspace.onDidChangeTextDocument(() => selection.updateStatus()),
		vscode.workspace.onDidChangeWorkspaceFolders(() => selection.workspaceChanged(pendingOperation)),
		vscode.workspace.onDidChangeConfiguration(event => {
			if (event.affectsConfiguration('godotTools.editorPath.godot4')) { selection.workspaceChanged(pendingOperation); }
		})];

	const editorSelection = vscode.window.onDidChangeActiveTextEditor(
		editor => selection.follow(editor, pendingOperation)
	);

	context.subscriptions.push(
		...structuralCommands,
		...subscriptions,
		view,
		refreshCommand,
		manageLibraryCommand,
		assignmentCommand,
		requirementsCommand,
		actionCommand,
		editingCommand,
		openCommand,
		openExecutorCommand,
		editorSelection,
		selection,
		provider,
		output
	);

	output.appendLine('Resource Condition Extension activated.');
	selection.follow(vscode.window.activeTextEditor);
}
