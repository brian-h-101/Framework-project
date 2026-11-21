import * as vscode from 'vscode';
import { basename } from 'node:path';
import { AUTHORED_ROOT, validateCatalogue, type LibraryCatalogue, type LibraryEntry } from '../bridges/attribute_library_bridge';
import { validateResourcePath, type ProjectContext } from '../workspace/project_context';

export interface LibraryElement { project: string; source: string; revision: number }
export interface LibraryProject { context: ProjectContext; catalogue: LibraryCatalogue }
export interface LibraryChoice { context: ProjectContext; entry: LibraryEntry; element: LibraryElement }

export class LibraryTreeProvider implements vscode.TreeDataProvider<LibraryElement>, vscode.Disposable {
	private readonly changes = new vscode.EventEmitter<void>();
	readonly onDidChangeTreeData = this.changes.event;
	private revision = 0;
	private projects: LibraryProject[] = [];
	private entries = new Map<string, { context: ProjectContext; entry: LibraryEntry }>();

	clear(): void { this.revision++; this.projects = []; this.entries.clear(); this.changes.fire(); }
	setProjects(projects: LibraryProject[]): void {
		this.clear();
		for (const project of projects) {
			validateCatalogue(project.catalogue);
			for (const entry of project.catalogue.entries) {
				const key = JSON.stringify([project.context.projectDirectory, entry.source_path]);
				if (this.entries.has(key)) { throw new Error('The authored library contains a duplicate project.'); }
				this.entries.set(key, { context: project.context, entry });
			}
		}
		this.projects = projects;
		this.changes.fire();
	}
	resolve(element: LibraryElement): { context: ProjectContext; entry: LibraryEntry } {
		const selected = element && this.entries.get(JSON.stringify([element.project, element.source]));
		if (!selected || element.revision !== this.revision) { throw new Error('Choose a current category or Resource in Authored Library.'); }
		return selected;
	}
	getEntries(): LibraryChoice[] {
		return [...this.entries.values()].map(({ context, entry }) => ({
			context: { ...context }, entry: { ...entry }, element: this.element(context, entry.source_path)
		}));
	}
	getChildren(element?: LibraryElement): LibraryElement[] {
		if (!element) { return this.projects.map(project => this.element(project.context, AUTHORED_ROOT)); }
		if (element.revision !== this.revision) { return []; }
		const { context, entry } = this.resolve(element);
		if (!['root', 'folder'].includes(entry.kind)) { return []; }
		return [...this.entries.values()].filter(item => item.context.projectDirectory === context.projectDirectory
			&& item.entry.parent_path === entry.source_path)
			.sort((left, right) => {
				const folders = Number(right.entry.kind === 'folder') - Number(left.entry.kind === 'folder');
				return folders || left.entry.name.localeCompare(right.entry.name);
			}).map(item => this.element(context, item.entry.source_path));
	}
	getParent(element: LibraryElement): LibraryElement | undefined {
		if (element.revision !== this.revision) { return undefined; }
		const { context, entry } = this.resolve(element);
		return entry.parent_path ? this.element(context, entry.parent_path) : undefined;
	}
	getTreeItem(element: LibraryElement): vscode.TreeItem {
		const { context, entry } = this.resolve(element);
		const directory = entry.kind === 'root' || entry.kind === 'folder';
		const item = new vscode.TreeItem(entry.kind === 'root' ? `${basename(context.projectDirectory)} · Authored` : entry.name,
			directory ? entry.kind === 'root' ? vscode.TreeItemCollapsibleState.Expanded
				: vscode.TreeItemCollapsibleState.Collapsed : vscode.TreeItemCollapsibleState.None);
		item.id = JSON.stringify([context.projectDirectory, entry.source_path]);
		item.contextValue = 'library_' + entry.kind + (entry.kind === 'resource' && entry.supported ? '_supported' : '');
		item.resourceUri = libraryUri(context, entry.source_path);
		item.iconPath = new vscode.ThemeIcon(directory ? 'folder' : entry.kind === 'blocked' ? 'lock' : entry.supported ? 'symbol-namespace' : 'file');
		item.tooltip = entry.source_path + '\n' + context.projectDirectory
			+ (entry.kind === 'blocked' ? '\nLinked paths and nested projects are not authorable.' : '');
		if (entry.kind === 'root') { item.description = context.projectDirectory; }
		if (entry.kind === 'resource') {
			item.description = entry.supported ? 'Container Resource' : 'Other Resource';
			item.command = { command: 'resourceAttribute.openLibraryResource', title: 'Open Resource', arguments: [element] };
		}
		return item;
	}
	private element(context: ProjectContext, source: string): LibraryElement {
		return { project: context.projectDirectory, source, revision: this.revision };
	}
	dispose(): void { this.clear(); this.changes.dispose(); }
}

export function libraryUri(context: ProjectContext, source: string): vscode.Uri {
	validateResourcePath(source);
	return vscode.Uri.joinPath(vscode.Uri.file(context.projectDirectory), ...source.slice(6).split('/'));
}
