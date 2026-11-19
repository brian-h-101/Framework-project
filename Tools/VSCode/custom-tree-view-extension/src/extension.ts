import * as vscode from 'vscode';
import {
	ResourceTreeProvider,
	type ResourceTreeElement
} from './resource_tree_provider';
import { ResourceSelection } from './resource_selection';
import {
	assignConditionFromFiles,
	assignInteractionRequirementsFromFiles,
	assignInteractionActionFromFiles,
	assignInteractionResourceFromFiles
} from './condition_assignment_command';
import { ResourceDragAndDropController } from './resource_drag_and_drop';
import { editConditionFromFile } from './condition_editing_command';

export function activate(context: vscode.ExtensionContext): void {
	const output = vscode.window.createOutputChannel(
		'Custom Tree View Extension'
	);

	const provider = new ResourceTreeProvider();
	const selection = new ResourceSelection(provider, output);

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

					const item = provider.getTreeItem(element);

					if (
						!item.resourceUri
						|| (
							expectedKind !== undefined
							&& item.contextValue !== expectedKind
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

	const editorSelection = vscode.window.onDidChangeActiveTextEditor(
		editor => selection.follow(editor, pendingOperation)
	);

	context.subscriptions.push(
		view,
		refreshCommand,
		assignmentCommand,
		requirementsCommand,
		actionCommand,
		editingCommand,
		openCommand,
		editorSelection,
		selection,
		provider,
		output
	);

	output.appendLine('Custom Tree View Extension activated.');
	selection.follow(vscode.window.activeTextEditor);
}
