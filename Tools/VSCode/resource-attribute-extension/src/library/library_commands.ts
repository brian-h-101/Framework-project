import * as vscode from 'vscode';
import { isInside } from '../workspace/project_context';
import { ensureWorkspace, godotExecutable } from '../resources/attribute_selection';
import type { AttributeSelection } from '../resources/attribute_selection';
import { checkedAuthoredPath, nameError } from './library_paths';
import { LibraryService } from './library_service';
import { libraryUri, type LibraryTreeProvider, type LibraryElement } from './library_tree_provider';

export type LibraryOperation = 'open' | 'category' | 'resource' | 'delete-resource' | 'delete-category';

export class LibraryCommands {
	constructor(private readonly provider: LibraryTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>, private readonly selection: AttributeSelection) {}

	async execute(operation: LibraryOperation, element: LibraryElement): Promise<void> {
		try {
			const { context, entry } = this.provider.resolve(element);
			const ready = async (deleting = false): Promise<void> => {
				this.provider.resolve(element); ensureWorkspace(context);
				if (deleting && vscode.workspace.textDocuments.some(document => document.isDirty && document.uri.scheme === 'file'
					&& isInside(context.projectDirectory, document.uri.fsPath)
					&& /\.(tres|tscn|res|scn|gd|godot|gdshader)$/.test(document.uri.path))) {
					throw new Error('Save or revert the project’s Resource, scene, and Godot script edits before checking deletion references.');
				}
			};
			await ready();
			if (operation === 'open') {
				if (entry.kind !== 'resource') { throw new Error('Choose a Resource file.'); }
				await checkedAuthoredPath(context, entry.source_path, 'file'); await ready();
				await vscode.window.showTextDocument(libraryUri(context, entry.source_path), { preview: true }); return;
			}
			const service = new LibraryService(context, godotExecutable(context), message => this.output.appendLine(message), ready);
			const trash = async (path: string): Promise<void> => {
				await vscode.workspace.fs.delete(vscode.Uri.file(path), { useTrash: true, recursive: false });
			};
			if (operation === 'category' || operation === 'resource') {
				if (!['root', 'folder'].includes(entry.kind)) { throw new Error('Choose an authored category.'); }
				const name = await vscode.window.showInputBox({ title: operation === 'category' ? 'New Category' : 'New Attribute Resource',
					prompt: `Create inside ${entry.source_path}`, value: operation === 'resource' ? 'new_attribute.tres' : '', ignoreFocusOut: true,
					validateInput: name => nameError(name) || (operation === 'resource' && !name.endsWith('.tres') ? 'Use a .tres filename.' : undefined) });
				if (name === undefined) { return; }
				if (operation === 'category') {
					const created = await service.createCategory(entry, name); this.output.appendLine(`[library] Created category: ${created}`);
				} else {
					const container = await vscode.window.showInputBox({ title: 'Initial Container Name', prompt: 'An empty StringName container will be created.',
						value: name.slice(0, -5), ignoreFocusOut: true, validateInput: text => text.trim() && !text.includes('\0') ? undefined : 'Enter a nonempty container name.' });
					if (container === undefined) { return; }
					const created = await service.createResource(entry, name, container);
					this.output.appendLine(`[library] Created Resource: ${created}`);
					await vscode.window.showTextDocument(libraryUri(context, created), { preview: false });
				}
			} else if (operation === 'delete-resource') {
				this.output.appendLine(`[library] Checking saved project references: ${entry.source_path}`);
				const preview = await service.previewDeletion(entry);
				if (preview.consumers.length) {
					const consumers = preview.consumers.map(consumer => consumer.source_path).join('\n');
					this.output.appendLine(`[library] Cannot delete ${entry.source_path}; referenced by:\n${consumers}`);
					const selected = await vscode.window.showWarningMessage('This Resource is still referenced. Unassign it before deleting.',
						{ modal: true, detail: consumers }, 'Show References');
					if (selected === 'Show References') { this.output.show(true); } return;
				}
				if (await vscode.window.showWarningMessage(`Move '${entry.name}' to the Recycle Bin?`,
					{ modal: true, detail: 'No saved project Resource, scene, or literal script reference was found.' }, 'Delete Resource') !== 'Delete Resource') { return; }
				await service.deleteResource(entry, preview, trash);
				this.selection.resourceRemoved(libraryUri(context, entry.source_path));
				this.output.appendLine(`[library] Moved Resource to Recycle Bin: ${entry.source_path}`);
			} else {
				if (entry.kind !== 'folder') { throw new Error('Choose an empty category beneath Authored.'); }
				if (await vscode.window.showWarningMessage(`Move the empty category '${entry.name}' to the Recycle Bin?`,
					{ modal: true }, 'Delete Category') !== 'Delete Category') { return; }
				await service.deleteEmptyCategory(entry, trash);
				this.output.appendLine(`[library] Moved empty category to Recycle Bin: ${entry.source_path}`);
			}
			await this.refresh();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[library] Error: ${message}`); void vscode.window.showErrorMessage(message);
		}
	}
}
