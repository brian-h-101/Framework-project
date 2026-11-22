import * as vscode from 'vscode';
import { prepareEditGraph } from '../resources/edit_context';
import { relative } from 'node:path';
import { lstat, readFile, unlink } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { ResourceTreeProvider, resourceUri, type ResourceTreeElement } from '../tree/resource_tree_provider';
import { resolveProjectContext, isInside } from '../workspace/project_context';
import { LibraryService } from '../library/library_service';
import { ensureWorkspace } from '../library/library_manager';
import { creationDetails } from '../library/resource_prompts';
import { nameError } from '../library/library_paths';
import { loadResourceGraph } from '../bridges/resource_bridge';
import { isBehaviorPath } from '../bridges/behavior_library_bridge';
import { editBehavior, type BehaviorEdit } from '../bridges/behavior_editing_bridge';
import { relationships } from '../resources/resource_relationships';

export type ResourceOperation = 'open_owner' | 'new_resource' | 'create_link' | 'assign_resource'
	| 'replace_reference' | 'remove_reference' | 'rename_file' | 'delete_file';

export class ResourceStructureCommands {
	constructor(private readonly provider: ResourceTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly changed: (uri?: vscode.Uri, removed?: boolean) => Promise<void>) {}

	async execute(operation: ResourceOperation, element: ResourceTreeElement | undefined): Promise<void> {
		try {
			if (!element || element.cycle) { throw new Error('Choose a current resource row in Framework Resources.'); }
			const selected = this.provider.resolve(element);
			const { resource, data, projectRoot } = selected;
			let graph = selected.graph;
			if (operation === 'open_owner') {
				await vscode.commands.executeCommand('vscode.open', resourceUri(projectRoot, data ? resource.source_path : element.parentSource ?? resource.source_path));
				return;
			}
			if (data) { throw new Error('Choose a resource row; use the data-entry commands for fields.'); }
			const context = await resolveProjectContext(selected.uri.fsPath,
				(vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath));
			if (relative(context.projectDirectory, projectRoot.fsPath) !== '') { throw new Error('The Resource project changed. Refresh and retry.'); }
			const ready = async (): Promise<void> => {
				this.provider.resolve(element);
				ensureWorkspace(context);
				const current = await resolveProjectContext(selected.uri.fsPath,
					(vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath));
				if (relative(context.projectDirectory, current.projectDirectory) !== '') { throw new Error('The Resource project changed. Refresh and retry.'); }
				if (vscode.workspace.textDocuments.some(document => document.isDirty && document.uri.scheme === 'file'
					&& isInside(context.projectDirectory, document.uri.fsPath))) { throw new Error('Save or revert project text edits before changing Resource files and relationships.'); }
				for (const [source, hash] of Object.entries({ ...graph.dependency_hashes, ...graph.executor_snapshot?.hashes })) {
					if (createHash('sha256').update(await readFile(vscode.Uri.joinPath(projectRoot, ...source.slice(6).split('/')).fsPath)).digest('hex') !== hash) {
						throw new Error(`Resource changed: ${source}. Refresh and retry.`);
					}
				}
				this.provider.resolve(element);
				ensureWorkspace(context);
			};
			await ready();
			const executable = vscode.workspace.getConfiguration('godotTools', projectRoot).get<string>('editorPath.godot4')?.trim();
			if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace.'); }
			graph = await prepareEditGraph(graph, context.projectDirectory, executable, message => this.output.appendLine(message));
			await ready();
			const service = new LibraryService(context, executable, message => this.output.appendLine(message), ready);
			const catalogue = await service.catalogue();
			await ready();
			const entry = catalogue.entries.find(entry => entry.source_path === resource.source_path && entry.fingerprint === resource.content_hash);
			if (operation === 'rename_file' || operation === 'delete_file') {
				if (!entry) { throw new Error('File operations are available in each profile’s Behavior folder.'); }
				if (operation === 'rename_file') {
					const name = await vscode.window.showInputBox({ title: 'Rename Resource File', value: entry.name, ignoreFocusOut: true,
						prompt: 'The authored ID and UID are preserved. Supported project references will be updated.',
						validateInput: name => nameError(name) ?? (!name.endsWith('.tres') ? 'Use a .tres filename.' : undefined) });
					if (name === undefined || name === entry.name) { return; }
					await ready();
					const preview = await service.previewRename(entry, name);
					if (await vscode.window.showWarningMessage(`Rename ${entry.name} to ${name} and update ${preview.changes.length} referencing file(s)? The authored ID stays '${entry.id}'.`,
						{ modal: true }, 'Rename Resource') !== 'Rename Resource') { return; }
					await ready();
					const destination = await service.renameResource(entry, preview);
					await this.changed(selected.uri, true);
					await vscode.commands.executeCommand('vscode.open', resourceUri(projectRoot, destination));
				} else {
					const preview = await service.previewDeletion(entry);
					if (preview.consumers.length) {
						throw new Error('This Resource is referenced. Remove or replace its links first:\n' + preview.consumers.map(item => item.source_path).join('\n'));
					}
					if (await vscode.window.showWarningMessage(`Move ${entry.name} to the Recycle Bin?`, { modal: true }, 'Delete Resource') !== 'Delete Resource') { return; }
					await service.deleteResource(entry, preview, async path => vscode.workspace.fs.delete(vscode.Uri.file(path), { useTrash: true, recursive: false }));
					await this.changed(selected.uri, true);
				}
				return;
			}
			const linked = operation === 'replace_reference' || operation === 'remove_reference';
			const owner = linked && element.parentSource ? graph.nodes[element.parentSource] : resource;
			const available = relationships(owner.kind);
			const chosenRole = linked ? available.find(item => item.role === element.linkRole)
				: operation === 'new_resource' ? undefined : available.length === 1 ? available[0]
					: await vscode.window.showQuickPick(available, { title: 'Resource Relationship', ignoreFocusOut: true });
			if (operation !== 'new_resource' && !chosenRole) { return; }
			if (operation === 'remove_reference') {
				if (!element.parentSource || !chosenRole?.optional) { throw new Error('This reference is required. Replace it with another Resource.'); }
				if (await vscode.window.showWarningMessage(`Remove this ${chosenRole.label} link from ${owner.id}? The linked file is preserved.`, { modal: true }, 'Remove Reference') !== 'Remove Reference') { return; }
				await ready();
				const request: BehaviorEdit = { operation: chosenRole.role === 'condition' ? 'remove_condition' : 'clear_requirements',
					expected_hashes: graph.dependency_hashes, catalog_paths: graph.catalog_paths, catalog_seed: graph.roots[0], executor_snapshot: graph.executor_snapshot,
					condition_index: element.linkIndex, condition_path: resource.source_path };
				await editBehavior(context.projectDirectory, executable, owner.source_path, request, message => this.output.appendLine(message));
				await this.changed();
				return;
			}
			let target: string;
			let owned: { path: string; hash: string; ino: number; dev: number } | undefined;
			if (operation === 'new_resource' || operation === 'create_link') {
				const directories = catalogue.entries.filter(entry => entry.kind === 'folder' && isBehaviorPath(entry.source_path))
					.map(entry => ({ label: entry.name, description: entry.source_path, entry }));
				directories.sort((left, right) => Number(right.entry.source_path === owner.source_path.slice(0, owner.source_path.lastIndexOf('/')))
					- Number(left.entry.source_path === owner.source_path.slice(0, owner.source_path.lastIndexOf('/'))));
				const directory = await vscode.window.showQuickPick(directories, { title: 'New Resource — Category', matchOnDescription: true, ignoreFocusOut: true });
				if (!directory) { return; }
				const details = await creationDetails(catalogue, chosenRole?.resourceKind);
				if (!details) { return; }
				await ready();
				target = await service.createResource(directory.entry, details.filename, details.request, catalogue);
				const path = resourceUri(projectRoot, target).fsPath;
				const stat = await lstat(path);
				owned = { path, ino: stat.ino, dev: stat.dev, hash: createHash('sha256').update(await readFile(path)).digest('hex') };
				if (operation === 'new_resource') { await vscode.commands.executeCommand('vscode.open', resourceUri(projectRoot, target)); return; }
			} else {
				const candidates = catalogue.entries.filter(entry => entry.kind === 'resource' && entry.valid && entry.resource_kind === chosenRole!.resourceKind)
					.map(entry => ({ label: entry.name, description: entry.id, detail: entry.source_path, entry }));
				const chosen = await vscode.window.showQuickPick(candidates, { title: `Assign ${chosenRole!.label}`, matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true });
				if (!chosen) { return; }
				target = chosen.entry.source_path;
			}
			try {
				await ready();
				const fresh = await loadResourceGraph(context.projectDirectory, executable, message => this.output.appendLine(message), graph.roots[0]);
				await ready();
				const request: BehaviorEdit = { operation: 'set_reference', role: chosenRole!.role, target_path: target,
					expected_hashes: fresh.dependency_hashes, catalog_paths: fresh.catalog_paths, catalog_seed: fresh.roots[0], executor_snapshot: fresh.executor_snapshot,
					condition_index: linked ? element.linkIndex : -1, condition_path: linked ? resource.source_path : undefined };
				await editBehavior(context.projectDirectory, executable, owner.source_path, request, message => this.output.appendLine(message));
			} catch (error) {
				if (owned) {
					const current = await lstat(owned.path);
					if (!current.isSymbolicLink() && current.ino === owned.ino && current.dev === owned.dev
						&& createHash('sha256').update(await readFile(owned.path)).digest('hex') === owned.hash
						&& !vscode.workspace.textDocuments.some(document => document.isDirty && relative(document.uri.fsPath, owned!.path) === '')) {
						await unlink(owned.path);
					} else { throw new Error(`Link failed; the changed new Resource was retained at ${target}. ${String(error)}`); }
				}
				throw error;
			}
			this.output.appendLine(`[resource-structure] Linked ${target} to ${owner.source_path} (${chosenRole!.role}).`);
			await this.changed();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[resource-structure] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}
}
