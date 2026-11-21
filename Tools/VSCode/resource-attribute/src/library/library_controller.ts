import * as vscode from 'vscode';
import { relative } from 'node:path';
import { resolveProjectContext, type ProjectContext } from '../workspace/project_context';
import { ensureWorkspace, godotExecutable, workspaceDirectories } from '../resources/attribute_selection';
import { LibraryService } from './library_service';
import type { LibraryTreeProvider, LibraryProject } from './library_tree_provider';

export class LibraryController implements vscode.Disposable {
	private request = 0;
	private disposed = false;
	private controller: AbortController | undefined;
	private timer: ReturnType<typeof setTimeout> | undefined;
	constructor(private readonly provider: LibraryTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly status: (message: string | undefined) => void) {}

	schedule(after?: Promise<void>): void {
		clearTimeout(this.timer);
		const current = this.request;
		this.timer = setTimeout(() => {
			void (async () => {
				await after?.catch(() => undefined);
				if (!this.disposed && current === this.request) { await this.refresh(); }
			})();
		}, 200);
	}
	workspaceChanged(after?: Promise<void>): void {
		this.request++; this.controller?.abort(); this.provider.clear(); this.schedule(after);
	}
	async refresh(): Promise<void> {
		if (this.disposed) { return; }
		clearTimeout(this.timer);
		this.controller?.abort();
		const controller = new AbortController(); this.controller = controller;
		const request = ++this.request;
		const current = (): boolean => !this.disposed && request === this.request;
		this.provider.clear(); this.status('Discovering authored libraries…');
		try {
			if (!vscode.workspace.isTrusted) { throw new Error('Authored Library requires a trusted workspace.'); }
			const roots = workspaceDirectories();
			const projectFiles = await vscode.workspace.findFiles('**/project.godot', '**/{.git,.godot,node_modules,out}/**');
			const contexts: ProjectContext[] = [];
			for (const file of projectFiles.filter(file => file.scheme === 'file').sort((a, b) => a.fsPath.localeCompare(b.fsPath))) {
				try {
					const context = await resolveProjectContext(file.fsPath, roots);
					if (!contexts.some(previous => relative(previous.projectDirectory, context.projectDirectory) === '')) { contexts.push(context); }
				} catch (error) { this.output.appendLine(`[library] Skipped project: ${String(error)}`); }
			}
			if (!current()) { return; }
			const projects: LibraryProject[] = [];
			const failures: string[] = [];
			for (const context of contexts) {
				if (!current()) { return; }
				try {
					ensureWorkspace(context);
					const service = new LibraryService(context, godotExecutable(context), message => this.output.appendLine(message));
					const catalogue = await service.catalogue(controller.signal);
					ensureWorkspace(context);
					projects.push({ context, catalogue });
				} catch (error) {
					if (!current()) { return; }
					const message = error instanceof Error ? error.message : String(error);
					failures.push(message); this.output.appendLine(`[library] ${context.projectDirectory}: ${message}`);
				}
			}
			if (!current()) { return; }
			for (const project of projects) { ensureWorkspace(project.context); }
			this.provider.setProjects(projects);
			this.status(failures.length ? failures.join('\n') : projects.length ? undefined
				: 'Open a Framework Godot project in this workspace and configure its Godot executable.');
			this.output.appendLine(`[library] Loaded ${projects.length} authored library/libraries.`);
		} catch (error) {
			if (current()) { this.status(error instanceof Error ? error.message : String(error)); }
		}
	}
	dispose(): void { this.disposed = true; this.request++; this.controller?.abort(); clearTimeout(this.timer); }
}
