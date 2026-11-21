import * as vscode from 'vscode';
import { basename, join, relative } from 'node:path';
import { resolveProjectContext, isInside, type ProjectContext } from '../project_context';
import type { LibraryCatalogue, LibraryEntry } from './scene_library_bridge';
import { LibraryService } from './library_service';
import { sha256, nameError } from './library_paths';
import { sceneDetails } from './scene_prompts';

export function ensureWorkspace(context: ProjectContext): void {
	if (!vscode.workspace.isTrusted || !vscode.workspace.workspaceFolders?.some(folder => folder.uri.scheme === 'file'
		&& relative(context.workspaceDirectory, folder.uri.fsPath) === '')) {
		throw new Error('The trusted project workspace changed. Open Manage Authored Library again.');
	}
}

interface Library { context: ProjectContext; catalogue: LibraryCatalogue; service: LibraryService }
interface Choice extends vscode.QuickPickItem { library: Library; entry: LibraryEntry }
const ACTIONS = [
	{ label: 'New Category…', operation: 'category', targetKind: 'root', description: 'Create beneath Maps, Presentation, or UI/HUD' },
	{ label: 'New Subcategory…', operation: 'category', targetKind: 'folder', description: 'Create inside an existing category' },
	{ label: 'New Scene…', operation: 'resource', targetKind: 'directory', description: 'Map, presentation, or HUD scene' },
	{ label: 'Delete Scene…', operation: 'delete-resource', targetKind: 'resource', description: 'Check references, then move to the Recycle Bin' },
	{ label: 'Delete Empty Category…', operation: 'delete-category', targetKind: 'empty', description: 'Move an empty category to the Recycle Bin' }
] as const;

export class LibraryManager {
	constructor(private readonly output: vscode.OutputChannel,
		private readonly changed: (uri: vscode.Uri, removed: boolean) => Promise<void>) {}

	async execute(): Promise<void> {
		try {
			if (!vscode.workspace.isTrusted) { throw new Error('Scene library authoring requires a trusted workspace.'); }
			const active = vscode.window.activeTextEditor?.document.uri;
			const action = await vscode.window.showQuickPick(ACTIONS, { title: 'Manage Authored Library',
				placeHolder: 'Choose a create or delete operation', matchOnDescription: true, ignoreFocusOut: true });
			if (!action) { return; }
			const libraries = await this.discover();
			const emptyHash = sha256(Buffer.from('[]'));
			const choices: Choice[] = libraries.flatMap(library => library.catalogue.entries.filter(entry =>
				action.targetKind === 'directory' ? ['root', 'folder'].includes(entry.kind)
					: action.targetKind === 'empty' ? entry.kind === 'folder' && entry.fingerprint === emptyHash
						: entry.kind === action.targetKind && (entry.kind !== 'resource' || entry.supported))
				.map(entry => ({ label: entry.name, description: `${basename(library.context.projectDirectory)} · ${entry.source_path.slice(6)}`,
					detail: library.context.projectDirectory, library, entry })));
			const activeProject = active?.scheme === 'file' ? libraries.filter(item => isInside(item.context.projectDirectory, active.fsPath))
				.sort((a, b) => b.context.projectDirectory.length - a.context.projectDirectory.length)[0]?.context.projectDirectory : undefined;
			choices.sort((a, b) => Number(b.library.context.projectDirectory === activeProject) - Number(a.library.context.projectDirectory === activeProject)
				|| a.library.context.projectDirectory.localeCompare(b.library.context.projectDirectory) || a.entry.source_path.localeCompare(b.entry.source_path));
			if (!choices.length) { void vscode.window.showInformationMessage('No eligible entries. Create a category first, or open a Framework project and configure its Godot executable.'); return; }
			const choice = await vscode.window.showQuickPick(choices, { title: `${action.label} — Choose Destination`,
				placeHolder: 'Search category names, resources, projects, and paths', matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true });
			if (!choice) { return; }
			const { context, service, catalogue } = choice.library;
			ensureWorkspace(context);
			let source = choice.entry.source_path;
			if (action.operation === 'category') {
				const name = await vscode.window.showInputBox({ title: 'New Category — Name', ignoreFocusOut: true, validateInput: nameError });
				if (name === undefined) { return; }
				source = await service.createCategory(choice.entry, name);
			} else if (action.operation === 'resource') {
				const details = await sceneDetails(choice.entry.source_path, context.projectDirectory, service.executable, message => this.output.appendLine(message));
				if (!details) { return; }
				source = await service.createScene(choice.entry, details.filename, details.request, catalogue);
			} else {
				const preview = action.operation === 'delete-resource' ? await service.previewDeletion(choice.entry) : undefined;
				if (preview?.consumers.length) {
					const references = preview.consumers.map(item => `${item.source_path} (${item.kind})`).join('\n');
					this.output.appendLine(`[library] Referenced by:\n${references}`);
					void vscode.window.showWarningMessage('This scene is still referenced. Unassign its consumers first.',
						{ modal: true, detail: references });
					return;
				}
				if (await vscode.window.showWarningMessage(`Move ${choice.entry.name} to the Recycle Bin?`,
					{ modal: true, detail: `${context.projectDirectory}\n${source}` }, 'Move to Recycle Bin') !== 'Move to Recycle Bin') { return; }
				const trash = async (path: string): Promise<void> => {
					await vscode.workspace.fs.delete(vscode.Uri.file(path), { useTrash: true, recursive: false });
				};
				if (preview) { await service.deleteScene(choice.entry, preview, trash); }
				else { await service.deleteEmptyCategory(choice.entry, trash); }
			}
			const uri = vscode.Uri.file(join(context.projectDirectory, ...source.slice(6).split('/')));
			const removed = action.operation.startsWith('delete');
			this.output.appendLine(`[library] ${action.label} ${source}`);
			await this.changed(uri, removed);
			if (action.operation === 'resource') { await vscode.window.showTextDocument(uri); }
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[library] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}

	private async discover(): Promise<Library[]> {
		const roots = (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath);
		const files = await vscode.workspace.findFiles('**/project.godot', '**/{.git,.godot,node_modules,out}/**');
		const libraries: Library[] = [];
		for (const file of files.filter(file => file.scheme === 'file').sort((a, b) => a.fsPath.localeCompare(b.fsPath))) {
			try {
				const context = await resolveProjectContext(file.fsPath, roots);
				if (libraries.some(item => relative(item.context.projectDirectory, context.projectDirectory) === '')) { continue; }
				ensureWorkspace(context);
				const executable = executableFor(context);
				if (!executable) { throw new Error('Configure frameworkScenes.godotExecutable or godotTools.editorPath.godot4 for this project.'); }
				const ready = async (): Promise<void> => {
					ensureWorkspace(context);
					if (executableFor(context) !== executable) {
						throw new Error('The configured Godot executable changed. Retry the operation.');
					}
					const dirty = vscode.workspace.textDocuments.find(document => document.isDirty && document.uri.scheme === 'file'
						&& isInside(context.projectDirectory, document.uri.fsPath) && /\.(tres|tscn|res|scn|gd|godot|gdshader)$/.test(document.uri.fsPath));
					if (dirty) { throw new Error(`Save or revert ${dirty.fileName} before managing the Scene library.`); }
				};
				const service = new LibraryService(context, executable, message => this.output.appendLine(message), ready);
				const catalogue = await service.catalogue();
				ensureWorkspace(context);
				libraries.push({ context, service, catalogue });
			} catch (error) { this.output.appendLine(`[library] ${file.fsPath}: ${String(error)}`); }
		}
		return libraries;
	}
}

export function executableFor(context: ProjectContext): string | undefined {
	const root = vscode.Uri.file(context.projectDirectory);
	return vscode.workspace.getConfiguration('frameworkScenes', root).get<string>('godotExecutable')?.trim()
		|| vscode.workspace.getConfiguration('godotTools', root).get<string>('editorPath.godot4')?.trim();
}
