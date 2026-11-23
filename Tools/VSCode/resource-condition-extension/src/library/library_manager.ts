import * as vscode from 'vscode';
import { basename, join, relative } from 'node:path';
import { resolveProjectContext, isInside, type ProjectContext } from '../workspace/project_context';
import { isBehaviorPath, isBehaviorRoot, isProfilePath, type LibraryCatalogue, type LibraryEntry } from '../bridges/behavior_library_bridge';
import { LibraryService } from './library_service';
import { sha256, nameError } from './library_paths';
import { creationDetails } from './resource_prompts';

export function ensureWorkspace(context: ProjectContext): void {
	if (!vscode.workspace.isTrusted || !vscode.workspace.workspaceFolders?.some(folder => folder.uri.scheme === 'file'
		&& relative(context.workspaceDirectory, folder.uri.fsPath) === '')) {
		throw new Error('The trusted project workspace changed. Open Manage Behavior Library again.');
	}
}

interface Library { context: ProjectContext; catalogue: LibraryCatalogue; service: LibraryService }
interface Choice extends vscode.QuickPickItem { library: Library; entry: LibraryEntry }
const ACTIONS = [
	{ label: 'New Profile…', operation: 'profile', targetKind: 'profiles-root', description: 'Create a profile with Behavior, Executor, and Shared folders' },
	{ label: 'New Category…', operation: 'category', targetKind: 'behavior-root', description: 'Create directly beneath a profile’s Behavior folder' },
	{ label: 'New Subcategory…', operation: 'category', targetKind: 'folder', description: 'Create inside an existing category' },
	{ label: 'New Behavior Resource…', operation: 'resource', targetKind: 'directory', description: 'Create a Behavior with Configuration and Steps' },
	{ label: 'New Configuration Type…', operation: 'configuration-type', description: 'Define reusable configuration fields and defaults for a profile' },
	{ label: 'New Layout Preset…', operation: 'layout', layoutOperation: 'create', description: 'Author a reusable scene layout' },
	{ label: 'New Preset Subcategory…', operation: 'layout', layoutOperation: 'create_category', description: 'Create a folder inside Presets or an existing subcategory' },
	{ label: 'Delete Preset Subcategory…', operation: 'layout', layoutOperation: 'delete_category', description: 'Check references, then move a preset subcategory to the Recycle Bin' },
	{ label: 'New Configuration Resource…', operation: 'configuration', description: 'Create a configuration in a profile’s Shared folder' },
	{ label: 'New Movement Controller…', operation: 'controller', description: 'Create a reusable keyboard or AI movement controller' },
	{ label: 'Delete Profile…', operation: 'delete-profile', targetKind: 'profile', description: 'Check references, then move a profile and its contents to the Recycle Bin' },
	{ label: 'Delete Resource…', operation: 'delete-resource', targetKind: 'resource', description: 'Check references, then move to the Recycle Bin' },
	{ label: 'Delete Empty Category…', operation: 'delete-category', targetKind: 'empty', description: 'Move an empty category to the Recycle Bin' }
] as const;

export class LibraryManager {
	constructor(private readonly output: vscode.OutputChannel,
		private readonly changed: (uri: vscode.Uri, removed: boolean) => Promise<void>,
		private readonly createConfiguration: (operation: 'new_configuration' | 'new_configuration_type' | 'new_movement_controller') => Promise<void>,
		private readonly manageLayouts: (operation: 'create' | 'create_category' | 'delete_category') => Promise<void> = async () => undefined) {}

	async execute(): Promise<void> {
		try {
			if (!vscode.workspace.isTrusted) { throw new Error('Behavior library authoring requires a trusted workspace.'); }
			const active = vscode.window.activeTextEditor?.document.uri;
			const action = await vscode.window.showQuickPick(ACTIONS, { title: 'Manage Behavior Library',
				placeHolder: 'Choose a create or delete operation', matchOnDescription: true, ignoreFocusOut: true });
			if (!action) { return; }
			if (action.operation === 'layout') { await this.manageLayouts(action.layoutOperation); return; }
			if (action.operation === 'controller') { await this.createConfiguration('new_movement_controller'); return; }
			if (action.operation === 'configuration' || action.operation === 'configuration-type') {
				await this.createConfiguration(action.operation === 'configuration-type' ? 'new_configuration_type' : 'new_configuration');
				return;
			}
			const profilesOnly = action.operation === 'profile' || action.operation === 'delete-profile';
			const libraries = await this.discover(profilesOnly);
			const emptyHash = sha256(Buffer.from('[]'));
			const choices: Choice[] = libraries.flatMap(library => library.catalogue.entries.filter(entry => {
				if (action.targetKind === 'profiles-root') { return entry.kind === 'root'; }
				if (action.targetKind === 'profile') { return entry.kind === 'folder' && isProfilePath(entry.source_path); }
				if (action.targetKind === 'resource') { return entry.kind === 'resource' && entry.supported; }
				if (entry.kind !== 'folder' || !isBehaviorPath(entry.source_path)) { return false; }
				if (action.targetKind === 'directory') { return true; }
				const isRoot = isBehaviorRoot(entry.source_path);
				if (action.targetKind === 'behavior-root') { return isRoot; }
				return !isRoot && (action.targetKind !== 'empty' || entry.fingerprint === emptyHash);
			})
				.map(entry => ({ label: entry.name, description: `${basename(library.context.projectDirectory)} · ${entry.source_path.slice(6)}`,
					detail: library.context.projectDirectory, library, entry })));
			const activeProject = active?.scheme === 'file' ? libraries.filter(item => isInside(item.context.projectDirectory, active.fsPath))
				.sort((a, b) => b.context.projectDirectory.length - a.context.projectDirectory.length)[0]?.context.projectDirectory : undefined;
			choices.sort((a, b) => Number(b.library.context.projectDirectory === activeProject) - Number(a.library.context.projectDirectory === activeProject)
				|| a.library.context.projectDirectory.localeCompare(b.library.context.projectDirectory) || a.entry.source_path.localeCompare(b.entry.source_path));
			if (!choices.length) {
				void vscode.window.showInformationMessage(libraries.length && action.operation === 'delete-profile'
					? 'No profiles are available to delete.'
					: 'No eligible entries. Open a Framework project with a configured Godot executable and check the library contents.');
				return;
			}
			const choice = await vscode.window.showQuickPick(choices, { title: `${action.label} — ${action.operation === 'delete-profile' ? 'Choose Profile' : action.operation === 'profile' ? 'Choose Project' : 'Choose Destination'}`,
				placeHolder: 'Search profiles, categories, resources, projects, and paths', matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true });
			if (!choice) { return; }
			const { context, service, catalogue } = choice.library;
			ensureWorkspace(context);
			let source = choice.entry.source_path;
			if (action.operation === 'profile') {
				const name = await vscode.window.showInputBox({ title: 'New Profile — Name',
					prompt: 'Create Behavior, Executor, and Shared folders inside this profile.',
					ignoreFocusOut: true, validateInput: nameError });
				if (name === undefined) { return; }
				source = await service.createProfile(choice.entry, name);
				void vscode.window.showInformationMessage(`Created profile ${name}.`);
			} else if (action.operation === 'category') {
				const name = await vscode.window.showInputBox({ title: 'New Category — Name', ignoreFocusOut: true, validateInput: nameError });
				if (name === undefined) { return; }
				source = await service.createCategory(choice.entry, name);
			} else if (action.operation === 'resource') {
				const details = await creationDetails(catalogue);
				if (!details) { return; }
				source = await service.createResource(choice.entry, details.filename, details.request, catalogue);
			} else {
				const profilePreview = action.operation === 'delete-profile' ? await service.previewProfileDeletion(choice.entry) : undefined;
				const resourcePreview = action.operation === 'delete-resource' ? await service.previewDeletion(choice.entry) : undefined;
				const preview = profilePreview ?? resourcePreview;
				if (preview?.consumers.length) {
					const references = preview.consumers.map(item => `${item.source_path} (${item.kind})`).join('\n');
					this.output.appendLine(`[library] Referenced by:\n${references}`);
					void vscode.window.showWarningMessage(`This ${profilePreview ? 'profile' : 'Resource'} is still referenced. Unassign its consumers first.`,
						{ modal: true, detail: references });
					return;
				}
				const contents = profilePreview ? `\n\nThis moves the entire profile, including all folders and ${profilePreview.file_count} file(s).` : '';
				if (await vscode.window.showWarningMessage(`Move ${choice.entry.name} to the Recycle Bin?`,
					{ modal: true, detail: `${context.projectDirectory}\n${source}${contents}` }, 'Move to Recycle Bin') !== 'Move to Recycle Bin') { return; }
				const trash = async (path: string): Promise<void> => {
					await vscode.workspace.fs.delete(vscode.Uri.file(path), { useTrash: true, recursive: Boolean(profilePreview) });
				};
				if (profilePreview) { await service.deleteProfile(choice.entry, profilePreview, trash); }
				else if (resourcePreview) { await service.deleteResource(choice.entry, resourcePreview, trash); }
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

	private async discover(profilesOnly: boolean): Promise<Library[]> {
		const roots = (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath);
		const files = await vscode.workspace.findFiles('**/project.godot', '**/{.git,.godot,node_modules,out}/**');
		const libraries: Library[] = [];
		for (const file of files.filter(file => file.scheme === 'file').sort((a, b) => a.fsPath.localeCompare(b.fsPath))) {
			try {
				const context = await resolveProjectContext(file.fsPath, roots);
				if (libraries.some(item => relative(item.context.projectDirectory, context.projectDirectory) === '')) { continue; }
				ensureWorkspace(context);
				const executable = vscode.workspace.getConfiguration('godotTools', vscode.Uri.file(context.projectDirectory))
					.get<string>('editorPath.godot4')?.trim();
				if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this project.'); }
				const ready = async (): Promise<void> => {
					ensureWorkspace(context);
					if (vscode.workspace.getConfiguration('godotTools', vscode.Uri.file(context.projectDirectory)).get<string>('editorPath.godot4')?.trim() !== executable) {
						throw new Error('The configured Godot executable changed. Retry the operation.');
					}
					const dirty = vscode.workspace.textDocuments.find(document => document.isDirty && document.uri.scheme === 'file'
						&& isInside(context.projectDirectory, document.uri.fsPath) && /\.(tres|tscn|res|scn|gd|godot|gdshader)$/.test(document.uri.fsPath));
					if (dirty) { throw new Error(`Save or revert ${dirty.fileName} before managing the Behavior library.`); }
				};
				const service = new LibraryService(context, executable, message => this.output.appendLine(message), ready);
				const catalogue = profilesOnly ? await service.profileCatalogue() : await service.catalogue();
				ensureWorkspace(context);
				libraries.push({ context, service, catalogue });
			} catch (error) { this.output.appendLine(`[library] ${file.fsPath}: ${String(error)}`); }
		}
		return libraries;
	}
}
