import * as vscode from 'vscode';
import type { ResourceGraph } from '../bridges/resource_bridge';
import { ResourceBrowsePool } from '../bridges/resource_browse_bridge';
import type { ResourceTreeProvider } from '../tree/resource_tree_provider';
import { relative, sep } from 'node:path';
import { performance } from 'node:perf_hooks';
import { resolveProjectContext, isInside } from '../workspace/project_context';

interface CachedGraph { graph: ResourceGraph; project: vscode.Uri; workspace: string; executable: string }

export class ResourceSelection implements vscode.Disposable {
	private selectedUri?: vscode.Uri;
	private requestId = 0;
	private disposed = false;
	private dependencies = new Set<string>();
	private timer?: ReturnType<typeof setTimeout>;
	private unsupported = false;
	private projectUri?: vscode.Uri;
	private controller?: AbortController;
	private loading = false;
	private cache = new Map<string, CachedGraph>();

	constructor(private readonly provider: ResourceTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly status: (message: string | undefined) => void = () => undefined,
		private readonly browser = new ResourceBrowsePool()) {}

	follow(editor: vscode.TextEditor | undefined, after?: Promise<void>): void {
		const uri = editor?.document.uri;
		if (this.disposed || !uri || uri.scheme !== 'file' || !uri.path.endsWith('.tres')) { return; }
		const same = uri.toString() === this.selectedUri?.toString();
		if (same && !after && this.loading) { return; }
		const cached = this.cache.get(uri.toString());
		if (!after && cached && this.usable(cached)) {
			this.stopLoad(); this.selectedUri = uri; this.requestId++;
			this.cache.delete(uri.toString()); this.cache.set(uri.toString(), cached);
			if (!same) { this.publish(cached); } else { this.updateStatus(); }
			this.output.appendLine('[performance] Cache hit: ' + uri.path.split('/').at(-1));
			return;
		}
		this.stopLoad(); this.selectedUri = uri;
		const request = ++this.requestId;
		this.loading = true;
		if (!same) { this.provider.clear(); }
		this.status('Loading ' + uri.path.split('/').at(-1) + '...');
		void this.loadAfter(uri, request, after);
	}

	async refresh(): Promise<void> {
		if (this.disposed) { return; }
		this.invalidate(); this.stopLoad();
		const uri = this.selectedUri, request = ++this.requestId;
		if (uri) { this.loading = true; this.status('Updating saved Resource...'); await this.load(uri, request); }
	}

	changed(uri: vscode.Uri, after?: Promise<void>): void {
		if (this.disposed || uri.path.split('/').at(-1)?.startsWith('.')) { return; }
		if (!/\.(gd|godot|tres|tscn|res|scn|gdshader)$/.test(uri.path)) { return; }
		// Executor registration hooks may read arbitrary project files. Invalidate
		// conservatively within that project, including inactive cached resources.
		this.invalidate(uri);
		if (!this.selectedUri || (this.projectUri && !isInside(this.projectUri.fsPath, uri.fsPath))) { return; }
		this.stopLoad(); const request = ++this.requestId;
		this.status('Updating saved Resource...');
		this.timer = setTimeout(() => {
			void (async () => {
				await after?.catch(() => undefined);
				if (this.isCurrent(request) && this.selectedUri) { this.loading = true; await this.load(this.selectedUri, request); }
			})();
		}, 150);
	}

	removed(uri: vscode.Uri, after?: Promise<void>): void {
		if (!this.selectedUri || !isInside(uri.fsPath, this.selectedUri.fsPath)) { this.changed(uri, after); return; }
		this.invalidate(uri); this.stopLoad(); this.requestId++;
		this.selectedUri = undefined; this.dependencies.clear(); this.unsupported = false;
		this.provider.clear(); this.status('Open a framework .tres file to view its relationships.');
	}

	workspaceChanged(after?: Promise<void>): void {
		this.invalidate(); this.stopLoad(); this.projectUri = undefined;
		this.provider.clear(); const request = ++this.requestId;
		if (this.selectedUri) { this.loading = true; void this.loadAfter(this.selectedUri, request, after); }
	}

	updateStatus(): void {
		if (!vscode.workspace.isTrusted) {
			this.invalidate(); this.stopLoad(); this.requestId++; this.provider.clear();
			this.status('Resource loading requires a trusted workspace.'); return;
		}
		if (this.unsupported) { this.status('Open a Behavior, a related resource, a Presentation starting preset, or a supported configuration in Framework Resources.'); return; }
		const dirty = vscode.workspace.textDocuments.some(document => document.isDirty && (
			this.dependencies.has(document.uri.toString()) || document.uri.toString() === this.selectedUri?.toString()
			|| this.projectUri && document.uri.scheme === 'file' && isInside(this.projectUri.fsPath, document.uri.fsPath)));
		this.status(dirty ? 'Showing saved data. Save or revert related resources before editing.' : undefined);
	}

	private usable(entry: CachedGraph): boolean {
		return vscode.workspace.isTrusted && (vscode.workspace.workspaceFolders ?? []).some(folder =>
			folder.uri.scheme === 'file' && relative(entry.workspace, folder.uri.fsPath) === '')
			&& vscode.workspace.getConfiguration('godotTools', entry.project).get<string>('editorPath.godot4')?.trim() === entry.executable;
	}

	private invalidate(uri?: vscode.Uri): void {
		for (const [key, entry] of this.cache) {
			if (!uri || isInside(entry.project.fsPath, uri.fsPath)) { this.cache.delete(key); }
		}
		this.browser.invalidate(uri?.fsPath);
	}

	private stopLoad(): void { clearTimeout(this.timer); this.controller?.abort(); this.controller = undefined; this.loading = false; }
	private isCurrent(request: number): boolean { return !this.disposed && request === this.requestId; }
	private async loadAfter(uri: vscode.Uri, request: number, after?: Promise<void>): Promise<void> {
		await after?.catch(() => undefined);
		if (this.isCurrent(request)) { await this.load(uri, request); }
	}

	private publish(entry: CachedGraph): void {
		this.projectUri = entry.project; this.unsupported = entry.graph.supported === false;
		this.dependencies = new Set(Object.keys({ ...entry.graph.dependency_hashes, ...entry.graph.executor_snapshot?.hashes })
			.map(source => vscode.Uri.joinPath(entry.project, ...source.slice(6).split('/')).toString()));
		if (this.unsupported) { this.provider.clear(); } else { this.provider.setGraph(entry.project, entry.graph); }
		this.updateStatus();
	}

	private async load(uri: vscode.Uri, request: number): Promise<void> {
		const start = performance.now();
		try {
			if (!this.isCurrent(request)) { return; }
			if (!vscode.workspace.isTrusted) { throw new Error('Resource loading requires a trusted workspace.'); }
			const folders = (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file').map(folder => folder.uri.fsPath);
			const context = await resolveProjectContext(uri.fsPath, folders);
			if (!this.isCurrent(request)) { return; }
			const project = vscode.Uri.file(context.projectDirectory);
			const executable = vscode.workspace.getConfiguration('godotTools', project).get<string>('editorPath.godot4')?.trim();
			if (!executable) { throw new Error('Configure godotTools.editorPath.godot4 for this workspace first.'); }
			const source = relative(context.projectDirectory, uri.fsPath).split(sep).join('/');
			if (!source.endsWith('.tres') || source.split('/').some(part => !part || part === '.' || part === '..' || part.includes(':'))) { throw new Error('Choose a project-relative .tres resource.'); }
			this.projectUri = project;
			const controller = new AbortController(); this.controller = controller;
			this.output.appendLine('[bridge] Loading res://' + source + '...');
			const graph = await this.browser.load(context.projectDirectory, executable, 'res://' + source,
				message => { if (this.isCurrent(request)) { this.output.appendLine(message); } }, controller.signal);
			if (!this.isCurrent(request)) { return; }
			const entry = { graph, project, workspace: context.workspaceDirectory, executable };
			if (!this.usable(entry)) { throw new Error('The trusted project workspace or Godot configuration changed. Open the resource again.'); }
			this.controller = undefined;
			this.cache.delete(uri.toString()); this.cache.set(uri.toString(), entry);
			while (this.cache.size > 32) { this.cache.delete(this.cache.keys().next().value!); }
			this.publish(entry);
			this.output.appendLine('[performance] Loaded ' + uri.path.split('/').at(-1) + ' in ' + Math.round(performance.now() - start) + ' ms; ' + Object.keys(graph.nodes).length + ' resource(s).');
		} catch (error) {
			if (!this.isCurrent(request) || (error instanceof Error && error.name === 'AbortError')) { return; }
			this.provider.clear(); this.dependencies.clear(); this.unsupported = false;
			const message = error instanceof Error ? error.message : String(error);
			this.status(message); this.output.appendLine('[bridge] Error: ' + message); void vscode.window.showErrorMessage(message);
		} finally { if (this.isCurrent(request)) { this.loading = false; this.controller = undefined; } }
	}

	dispose(): void { this.stopLoad(); this.cache.clear(); this.browser.dispose(); this.dependencies.clear(); this.disposed = true; this.requestId++; this.selectedUri = undefined; }
}
