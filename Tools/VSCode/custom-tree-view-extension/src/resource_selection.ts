import * as vscode from 'vscode';
import { loadResourceGraph } from './resource_bridge';
import type { ResourceTreeProvider } from './resource_tree_provider';
import { relative, sep } from 'node:path';
import { resolveProjectContext } from './project_context';

export class ResourceSelection implements vscode.Disposable {
	private selectedUri: vscode.Uri | undefined;
	private requestId = 0;
	private disposed = false;

	constructor(
		private readonly provider: ResourceTreeProvider,
		private readonly output: vscode.OutputChannel
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
			this.provider.setGraph(projectUri, graph);

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

			this.output.appendLine(`[bridge] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}

	dispose(): void {
		this.disposed = true;
		this.requestId++;
		this.selectedUri = undefined;
	}
}
