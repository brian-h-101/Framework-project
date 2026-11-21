import * as vscode from 'vscode';
import { loadResourceGraph } from '../bridges/resource_bridge';
import type { ResourceTreeProvider } from '../tree/resource_tree_provider';
import { relative, sep } from 'node:path';
import { resolveProjectContext } from '../workspace/project_context';

export class ResourceSelection implements vscode.Disposable {
	private selectedUri: vscode.Uri | undefined;
	private requestId = 0;
	private disposed = false;
	private dependencies = new Set<string>();
	private timer: ReturnType<typeof setTimeout> | undefined;
	private unsupported = false;
	private projectUri: vscode.Uri | undefined;

	constructor(
		private readonly provider: ResourceTreeProvider,
		private readonly output: vscode.OutputChannel,
		private readonly status: (message: string | undefined) => void = () => undefined
	) {}

	follow(
		editor: vscode.TextEditor | undefined,
		after?: Promise<void>
	): void {
		const uri = editor?.document.uri;

		if (
			this.disposed
			|| !uri
			|| uri.scheme !== 'file'
			|| !uri.path.endsWith('.tres')
		) {
			return;
		}

		this.selectedUri = uri;

		const request = ++this.requestId;
		this.provider.clear();

		void this.loadAfter(uri, request, after);
	}

	async refresh(): Promise<void> {
		if (this.disposed) {
			return;
		}

		const uri = this.selectedUri;
		const request = ++this.requestId;

		this.provider.clear();

		if (uri) {
			await this.load(uri, request);
		}
	}

	changed(uri: vscode.Uri, after?: Promise<void>): void {
		if (this.disposed || !this.selectedUri || uri.path.split('/').at(-1)?.startsWith('.')) { return; }
		const tracked = this.dependencies.has(uri.toString()) || uri.toString() === this.selectedUri.toString()
			|| (this.projectUri && uri.path.startsWith(this.projectUri.path + '/') && /\.(gd|godot|tres|tscn|res|scn|gdshader)$/.test(uri.path))
			|| uri.path.includes('/Framework/Content/Behavior/')
			|| uri.path.startsWith(this.selectedUri.path.slice(0, this.selectedUri.path.lastIndexOf('/') + 1));
		if (!tracked) { return; }
		clearTimeout(this.timer);
		const request = this.requestId;
		this.timer = setTimeout(() => {
			void (async () => {
				await after?.catch(() => undefined);
				if (this.isCurrent(request)) { await this.refresh(); }
			})();
		}, 150);
	}

	removed(uri: vscode.Uri, after?: Promise<void>): void {
		if (uri.toString() !== this.selectedUri?.toString()) { this.changed(uri, after); return; }
		clearTimeout(this.timer);
		this.requestId++;
		this.selectedUri = undefined;
		this.dependencies.clear();
		this.unsupported = false;
		this.provider.clear();
		this.status('Open a framework .tres file to view its relationships.');
	}

	workspaceChanged(after?: Promise<void>): void {
		this.provider.clear();
		const request = ++this.requestId;
		if (this.selectedUri) { void this.loadAfter(this.selectedUri, request, after); }
	}

	updateStatus(): void {
		if (this.unsupported) {
			this.status('Open an action, interaction, condition, or condition-group Resource in Framework Resources.');
			return;
		}
		const dirty = vscode.workspace.textDocuments.some(document => document.isDirty
			&& (this.dependencies.has(document.uri.toString()) || document.uri.toString() === this.selectedUri?.toString()));
		this.status(dirty ? 'Showing saved data. Save or revert related resources before editing.' : undefined);
	}

	private async loadAfter(
		uri: vscode.Uri,
		request: number,
		after?: Promise<void>
	): Promise<void> {
		await after?.catch(() => undefined);

		if (this.isCurrent(request)) {
			await this.load(uri, request);
		}
	}

	private isCurrent(request: number): boolean {
		return !this.disposed && request === this.requestId;
	}

	private async load(
		uri: vscode.Uri,
		request: number
	): Promise<void> {
		try {
			if (!this.isCurrent(request)) {
				return;
			}

			if (!vscode.workspace.isTrusted) {
				throw new Error(
					'Resource loading requires a trusted workspace.'
				);
			}

			const folders = vscode.workspace.workspaceFolders ?? [];

			const context = await resolveProjectContext(
				uri.fsPath,
				folders
					.filter(folder => folder.uri.scheme === 'file')
					.map(folder => folder.uri.fsPath)
			);

			if (!this.isCurrent(request)) {
				return;
			}

			const ensureWorkspace = (): void => {
				const currentFolders =
					vscode.workspace.workspaceFolders ?? [];

				const workspaceStillOpen = currentFolders.some(
					folder =>
						folder.uri.scheme === 'file'
						&& relative(
							context.workspaceDirectory,
							folder.uri.fsPath
						) === ''
				);

				if (
					!vscode.workspace.isTrusted
					|| !workspaceStillOpen
				) {
					throw new Error(
						'The project workspace folder changed. '
						+ 'Open the resource again.'
					);
				}
			};

			ensureWorkspace();

			const relativePath = relative(
				context.projectDirectory,
				uri.fsPath
			).split(sep).join('/');

			if (
				!relativePath.endsWith('.tres')
				|| relativePath.split('/').some(segment =>
					!segment
					|| segment === '.'
					|| segment === '..'
					|| segment.includes(':')
				)
			) {
				throw new Error(
					'Choose a project-relative .tres resource.'
				);
			}

			const projectUri = vscode.Uri.file(
				context.projectDirectory
			);

			const executable = vscode.workspace
				.getConfiguration('godotTools', projectUri)
				.get<string>('editorPath.godot4')
				?.trim();

			if (!executable) {
				throw new Error(
					'Configure godotTools.editorPath.godot4 '
					+ 'for this workspace first.'
				);
			}

			const resourcePath = `res://${relativePath}`;

			this.output.appendLine(
				`[bridge] Project: ${context.projectDirectory}`
			);

			this.output.appendLine(
				`[bridge] Loading ${resourcePath}...`
			);

			const graph = await loadResourceGraph(
				context.projectDirectory,
				executable,
				message => {
					if (this.isCurrent(request)) {
						this.output.appendLine(message);
					}
				},
				resourcePath
			);

			if (!this.isCurrent(request)) {
				return;
			}

			ensureWorkspace();
			this.projectUri = projectUri;
			this.dependencies = new Set(Object.keys({ ...graph.dependency_hashes, ...graph.executor_snapshot?.hashes }).map(path =>
				vscode.Uri.joinPath(projectUri, ...path.slice(6).split('/')).toString()));
			this.unsupported = graph.supported === false;
			if (this.unsupported) {
				this.provider.clear();
				this.updateStatus();
				this.output.appendLine(`[bridge] Selected Resource is handled by another schema: ${resourcePath}`);
				return;
			}
			this.provider.setGraph(projectUri, graph);
			this.updateStatus();

			this.output.appendLine(
				`[bridge] Loaded ${resourcePath}; `
				+ `${Object.keys(graph.nodes).length} resource(s).`
			);
		} catch (error) {
			if (!this.isCurrent(request)) {
				return;
			}

			this.provider.clear();

			const message = error instanceof Error
				? error.message
				: String(error);

			this.dependencies.clear();
			this.unsupported = false;
			this.status(message);
			this.output.appendLine(`[bridge] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}

	dispose(): void {
		clearTimeout(this.timer);
		this.dependencies.clear();
		this.disposed = true;
		this.requestId++;
		this.selectedUri = undefined;
	}
}
