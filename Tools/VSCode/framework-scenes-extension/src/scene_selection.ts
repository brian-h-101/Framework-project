import * as vscode from 'vscode';
import { relative } from 'node:path';
import { loadSceneGraph } from './scene_bridge';
import { isInside, resolveProjectContext, scenePathInProject } from './project_context';
import type { ProjectContext } from './project_context';
import { projectUri } from './scene_tree_provider';
import type { SceneTreeProvider } from './scene_tree_provider';

export function workspaceDirectories(): string[] {
	return (vscode.workspace.workspaceFolders ?? [])
		.filter(folder => folder.uri.scheme === 'file')
		.map(folder => folder.uri.fsPath);
}

export function ensureWorkspace(context: ProjectContext): void {
	if (!vscode.workspace.isTrusted) {
		throw new Error('Scene loading requires a trusted workspace.');
	}
	if (!workspaceDirectories().some(root => relative(root, context.workspaceDirectory) === '')) {
		throw new Error('The project workspace folder changed. Open the scene again.');
	}
}

export class SceneSelection implements vscode.Disposable {
	private selectedUri: vscode.Uri | undefined;
	private request = 0;
	private disposed = false;
	private controller: AbortController | undefined;
	private timer: ReturnType<typeof setTimeout> | undefined;
	private dependencies = new Set<string>();

	constructor(
		private readonly provider: SceneTreeProvider,
		private readonly output: vscode.OutputChannel,
		private readonly status: (message: string | undefined) => void
	) {}

	follow(editor: vscode.TextEditor | undefined, after?: Promise<void>): void {
		const uri = editor?.document.uri;
		if (this.disposed || !uri || uri.scheme !== 'file' || !uri.path.endsWith('.tscn')) {
			return;
		}
		if (this.selectedUri?.toString() === uri.toString()) {
			this.updateStatus();
			return;
		}
		this.selectedUri = uri;
		this.dependencies = new Set([uri.toString()]);
		this.scheduleRefreshAfter(after);
	}

	affects(uri: vscode.Uri): boolean {
		return this.dependencies.has(uri.toString());
	}

	scheduleRefresh(uri: vscode.Uri, after?: Promise<void>): void {
		if (this.disposed || !this.affects(uri)) {
			return;
		}
		clearTimeout(this.timer);
		const request = this.request;
		this.timer = setTimeout(() => {
			void (async () => {
				await after?.catch(() => undefined);
				if (!this.disposed && request === this.request) { await this.refresh(); }
			})();
		}, 150);
	}

	scheduleRefreshAfter(after?: Promise<void>): void {
		this.request++;
		this.controller?.abort();
		this.provider.clear();
		const request = this.request;
		void (async () => {
			await after?.catch(() => undefined);
			if (!this.disposed && request === this.request) { await this.refresh(); }
		})();
	}

	removed(uri: vscode.Uri, after?: Promise<void>): void {
		if (uri.toString() !== this.selectedUri?.toString()) { this.scheduleRefresh(uri, after); return; }
		this.request++;
		this.controller?.abort();
		clearTimeout(this.timer);
		this.selectedUri = undefined;
		this.dependencies.clear();
		this.provider.clear();
		this.status(undefined);
	}

	updateStatus(): void {
		if (this.disposed) {
			return;
		}
		const dirty = vscode.workspace.textDocuments.some(document =>
			document.isDirty && this.affects(document.uri));
		this.status(dirty ? 'Showing saved scene data. Save scene edits to refresh.' : undefined);
	}

	workspaceChanged(after?: Promise<void>): void {
		if (!this.selectedUri || this.disposed) {
			return;
		}
		if (!workspaceDirectories().some(root => isInside(root, this.selectedUri!.fsPath))) {
			this.request++;
			this.controller?.abort();
			clearTimeout(this.timer);
			this.provider.clear();
			this.selectedUri = undefined;
			this.dependencies.clear();
			this.status(undefined);
			return;
		}
		this.scheduleRefreshAfter(after);
	}

	async refresh(): Promise<void> {
		if (this.disposed || !this.selectedUri) {
			return;
		}
		clearTimeout(this.timer);
		const uri = this.selectedUri;
		const request = ++this.request;
		this.controller?.abort();
		const controller = new AbortController();
		this.controller = controller;
		const current = (): boolean => !this.disposed && request === this.request;
		this.provider.clear();
		this.status('Loading saved scene hierarchy…');
		try {
			if (!vscode.workspace.isTrusted) {
				throw new Error('Scene loading requires a trusted workspace.');
			}
			const context = await resolveProjectContext(uri.fsPath, workspaceDirectories());
			if (!current()) {
				return;
			}
			ensureWorkspace(context);
			const scenePath = await scenePathInProject(context, uri.fsPath);
			if (!current()) {
				return;
			}
			ensureWorkspace(context);
			const projectRoot = vscode.Uri.file(context.projectDirectory);
			const executable = vscode.workspace.getConfiguration('frameworkScenes', projectRoot)
				.get<string>('godotExecutable')?.trim()
				|| vscode.workspace.getConfiguration('godotTools', projectRoot)
					.get<string>('editorPath.godot4')?.trim();
			if (!executable) {
				throw new Error('Configure frameworkScenes.godotExecutable or godotTools.editorPath.godot4 in Workspace settings.');
			}
			this.output.appendLine(`[scene-bridge] Project: ${context.projectDirectory}`);
			this.output.appendLine(`[scene-bridge] Loading ${scenePath}...`);
			const graph = await loadSceneGraph(context.projectDirectory, executable, scenePath,
				message => { if (current()) { this.output.appendLine(message); } }, controller.signal);
			if (!current()) {
				return;
			}
			ensureWorkspace(context);
			this.dependencies = new Set(Object.keys(graph.dependency_hashes).map(path => projectUri(context, path).toString()));
			this.provider.setGraph(context, graph);
			this.updateStatus();
			this.output.appendLine(`[scene-bridge] Loaded ${Object.keys(graph.nodes).length} node(s).`);
		} catch (error) {
			if (!current()) {
				return;
			}
			const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : undefined;
			const message = code === 'ENOENT'
				? 'Godot could not be started. Set frameworkScenes.godotExecutable to the full Godot console executable path in Workspace settings.'
				: error instanceof Error ? error.message : String(error);
			this.provider.clear();
			this.status(message);
			this.output.appendLine(`[scene-bridge] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}

	dispose(): void {
		this.disposed = true;
		this.request++;
		this.controller?.abort();
		clearTimeout(this.timer);
		this.dependencies.clear();
	}
}
