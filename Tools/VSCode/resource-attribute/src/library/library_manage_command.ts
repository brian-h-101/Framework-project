import * as vscode from 'vscode';
import { basename, dirname, relative } from 'node:path';
import { sha256 } from './library_paths';
import { isInside } from '../workspace/project_context';
import { ensureWorkspace } from '../resources/attribute_selection';
import { libraryUri, type LibraryChoice, type LibraryTreeProvider } from './library_tree_provider';
import type { LibraryCommands, LibraryOperation } from './library_commands';
import type { LibraryEntry } from '../bridges/attribute_library_bridge';

interface ManagementAction extends vscode.QuickPickItem {
	operation: LibraryOperation;
	kinds: LibraryEntry['kind'][];
	targetLabel: string;
	supportedOnly?: boolean;
	emptyOnly?: boolean;
	emptyMessage: string;
}
interface DestinationItem extends vscode.QuickPickItem { choice: LibraryChoice }

const ACTIONS: ManagementAction[] = [
	{ label: 'New Category…', description: 'Create directly beneath Authored', operation: 'category', kinds: ['root'], targetLabel: 'Project',
		emptyMessage: 'No authored libraries are available. Open a Framework project and configure its Godot executable.' },
	{ label: 'New Subcategory…', description: 'Create inside an existing category', operation: 'category', kinds: ['folder'], targetLabel: 'Parent Folder',
		emptyMessage: 'No categories are available. Create a category first.' },
	{ label: 'New Attribute Resource…', description: 'Create a container .tres file', operation: 'resource', kinds: ['root', 'folder'], targetLabel: 'Folder',
		emptyMessage: 'No authored libraries are available. Open a Framework project and configure its Godot executable.' },
	{ label: 'Delete Resource…', description: 'Check references, then move a Resource to the Recycle Bin', operation: 'delete-resource',
		kinds: ['resource'], targetLabel: 'Resource', supportedOnly: true, emptyMessage: 'No supported container Resources are available to delete.' },
	{ label: 'Delete Empty Category…', description: 'Move an empty category to the Recycle Bin', operation: 'delete-category',
		kinds: ['folder'], targetLabel: 'Empty Category', emptyOnly: true, emptyMessage: 'No empty categories are available to delete.' }
];

export class LibraryManageCommand {
	constructor(private readonly provider: LibraryTreeProvider, private readonly commands: Pick<LibraryCommands, 'execute'>,
		private readonly refresh: () => Promise<void>, private readonly output: vscode.OutputChannel) {}

	async execute(): Promise<void> {
		try {
			if (!vscode.workspace.isTrusted) { throw new Error('Library authoring requires a trusted workspace.'); }
			const active = vscode.window.activeTextEditor?.document.uri;
			const action = await vscode.window.showQuickPick(ACTIONS, { title: 'Manage Authored Library',
				placeHolder: 'Choose a create or delete operation', matchOnDescription: true, ignoreFocusOut: true });
			if (!action) { return; }
			await this.refresh();
			const entries = this.provider.getEntries();
			const emptyFingerprint = sha256(Buffer.from('[]'));
			const choices = entries.filter(({ entry }) => action.kinds.includes(entry.kind)
				&& (!action.supportedOnly || entry.supported) && (!action.emptyOnly || entry.fingerprint === emptyFingerprint));
			if (!choices.length) { void vscode.window.showInformationMessage(action.emptyMessage); return; }
			for (const choice of choices) { ensureWorkspace(choice.context); }
			const activeProject = active?.scheme === 'file' ? entries.filter(choice => isInside(choice.context.projectDirectory, active.fsPath))
				.sort((left, right) => right.context.projectDirectory.length - left.context.projectDirectory.length)[0]?.context.projectDirectory : undefined;
			const rank = (choice: LibraryChoice): number => {
				if (!activeProject || !active || relative(activeProject, choice.context.projectDirectory) !== '') { return 3; }
				const path = libraryUri(choice.context, choice.entry.source_path).fsPath;
				if (relative(path, active.fsPath) === '' || relative(path, dirname(active.fsPath)) === '') { return 0; }
				if (relative(dirname(path), dirname(active.fsPath)) === '') { return 1; }
				return 2;
			};
			choices.sort((left, right) => rank(left) - rank(right)
				|| left.context.projectDirectory.localeCompare(right.context.projectDirectory)
				|| left.entry.source_path.localeCompare(right.entry.source_path));
			const items: DestinationItem[] = choices.map(choice => ({
				label: choice.entry.name,
				description: `${basename(choice.context.projectDirectory)} · ${choice.entry.source_path.slice(6)}`,
				detail: choice.context.projectDirectory,
				choice
			}));
			const chosen = await vscode.window.showQuickPick(items, { title: `${action.label} — Choose ${action.targetLabel}`,
				placeHolder: 'Search names, project names, and paths', matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true });
			if (!chosen) { return; }
			const selected = this.provider.resolve(chosen.choice.element);
			ensureWorkspace(selected.context);
			await this.commands.execute(action.operation, chosen.choice.element);
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[manage-library] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}
}
