import * as vscode from 'vscode';
import { relative } from 'node:path';
import { inspectAttributes } from '../bridges/attribute_bridge';
import { isInside, resolveProjectContext, attributePathInProject } from '../workspace/project_context';
import type { ProjectContext } from '../workspace/project_context';
import type { AttributeTreeProvider } from '../tree/attribute_tree_provider';

export function workspaceDirectories(): string[] {
	return (vscode.workspace.workspaceFolders ?? []).filter(folder => folder.uri.scheme === 'file')
		.map(folder => folder.uri.fsPath);
}

export function ensureWorkspace(context: ProjectContext): void {
	if (!vscode.workspace.isTrusted) { throw new Error('Attribute authoring requires a trusted workspace.'); }
	if (!workspaceDirectories().some(root => relative(root, context.workspaceDirectory) === '')) {
		throw new Error('The project workspace folder changed. Open the Resource again.');
	}
}

export function godotExecutable(context: ProjectContext): string {
	const root = vscode.Uri.file(context.projectDirectory);
	const value = vscode.workspace.getConfiguration('resourceAttribute', root).get<string>('godotExecutable')?.trim()
		|| vscode.workspace.getConfiguration('godotTools', root).get<string>('editorPath.godot4')?.trim();
	if (!value) {
		throw new Error('Configure resourceAttribute.godotExecutable or godotTools.editorPath.godot4 in Workspace settings.');
	}
	return value;
}

export class AttributeSelection implements vscode.Disposable {
	private selected: vscode.Uri | undefined;
	private request = 0;
	private disposed = false;
	private controller: AbortController | undefined;
	private timer: ReturnType<typeof setTimeout> | undefined;
	private unsupported = false;

	constructor(private readonly provider: AttributeTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly status: (message: string | undefined) => void) {}

	follow(editor: vscode.TextEditor | undefined): void {
		const uri = editor?.document.uri;
		if (this.disposed || !uri || uri.scheme !== 'file' || !uri.path.endsWith('.tres')) { return; }
		if (this.selected?.toString() === uri.toString()) { this.updateStatus(); return; }
		this.selected = uri;
		void this.refresh();
	}

	scheduleRefresh(uri: vscode.Uri): void {
		if (this.disposed || uri.toString() !== this.selected?.toString()) { return; }
		clearTimeout(this.timer);
		this.timer = setTimeout(() => void this.refresh(), 150);
	}

	resourceRemoved(uri: vscode.Uri): void {
		if (uri.toString() !== this.selected?.toString()) { return; }
		this.request++; this.controller?.abort(); clearTimeout(this.timer);
		this.selected = undefined; this.unsupported = false; this.provider.clear();
		this.status('The selected Resource was deleted. Choose another Resource in Authored Library.');
	}

	updateStatus(): void {
		if (this.disposed) { return; }
		const dirty = vscode.workspace.textDocuments.some(document => document.isDirty
			&& document.uri.toString() === this.selected?.toString());
		this.status(dirty ? 'Showing saved values. Save or revert text edits before editing attributes.'
			: this.unsupported ? 'Open a container fragment Resource from Content/Authored.' : undefined);
	}

	workspaceChanged(): void {
		if (this.disposed || !this.selected) { return; }
		if (!vscode.workspace.isTrusted || !workspaceDirectories().some(root => isInside(root, this.selected!.fsPath))) {
			this.request++;
			this.controller?.abort();
			clearTimeout(this.timer);
			this.selected = undefined;
			this.provider.clear();
			this.status(undefined);
			return;
		}
		void this.refresh();
	}

	async refresh(): Promise<void> {
		if (this.disposed || !this.selected) { return; }
		clearTimeout(this.timer);
		const uri = this.selected;
		const request = ++this.request;
		this.controller?.abort();
		const controller = new AbortController();
		this.controller = controller;
		const current = (): boolean => !this.disposed && request === this.request;
		this.provider.clear();
		this.status('Loading saved attribute containers…');
		try {
			const context = await resolveProjectContext(uri.fsPath, workspaceDirectories());
			if (!current()) { return; }
			ensureWorkspace(context);
			const source = await attributePathInProject(context, uri.fsPath);
			if (!current()) { return; }
			ensureWorkspace(context);
			this.output.appendLine(`[attributes] Reading ${source}...`);
			const graph = await inspectAttributes(context.projectDirectory, godotExecutable(context), source,
				message => { if (current()) { this.output.appendLine(message); } }, controller.signal);
			if (!current()) { return; }
			ensureWorkspace(context);
			this.unsupported = !graph.supported;
			this.provider.setGraph(context, graph);
			this.updateStatus();
		} catch (error) {
			if (!current()) { return; }
			const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : undefined;
			const message = code === 'ENOENT'
				? 'Godot could not be started. Set resourceAttribute.godotExecutable to the full Godot console executable path.'
				: error instanceof Error ? error.message : String(error);
			this.provider.clear();
			this.status(message);
			this.output.appendLine(`[attributes] Error: ${message}`);
		}
	}

	dispose(): void {
		this.disposed = true;
		this.request++;
		this.controller?.abort();
		clearTimeout(this.timer);
	}
}
