import * as vscode from 'vscode';
import { relative } from 'node:path';
import {
	resourcePathInProject,
	type ProjectContext
} from '../workspace/project_context';
import {
	loadResourceCatalog,
	type ResourceKind
} from '../bridges/resource_catalog_bridge';

interface ResourcePickItem extends vscode.QuickPickItem {
	resourceUri: vscode.Uri;
}

export async function pickResource(
	context: ProjectContext,
	godotExecutable: string,
	kind: ResourceKind,
	output: vscode.OutputChannel,
	title: string
): Promise<vscode.Uri | undefined> {
	const ensureWorkspace = (): void => {
		const folders = vscode.workspace.workspaceFolders ?? [];

		const workspaceStillOpen = folders.some(
			folder =>
				folder.uri.scheme === 'file'
				&& relative(
					context.workspaceDirectory,
					folder.uri.fsPath
				) === ''
		);

		if (!vscode.workspace.isTrusted || !workspaceStillOpen) {
			throw new Error(
				'The project workspace folder changed. '
				+ 'Run the resource command again.'
			);
		}
	};

	ensureWorkspace();

	const projectUri = vscode.Uri.file(context.projectDirectory);

	output.appendLine(`[catalog] Loading ${kind} resources...`);

	const catalog = await loadResourceCatalog(
		context.projectDirectory,
		godotExecutable,
		message => output.appendLine(message)
	);

	ensureWorkspace();

	const items: ResourcePickItem[] = catalog.resources
		.filter(entry => entry.kind === kind)
		.map(entry => {
			const relativePath = entry.source_path.slice('res://'.length);

			return {
				label: relativePath.slice(relativePath.lastIndexOf('/') + 1),
				description: entry.id,
				detail: entry.source_path,
				resourceUri: vscode.Uri.joinPath(
					projectUri,
					...relativePath.split('/')
				)
			};
		});

	if (items.length === 0) {
		const kindLabel = kind.replace(/_/g, ' ');

		void vscode.window.showInformationMessage(
			`No ${kindLabel} resources are available.`
		);

		return;
	}

	const selected = await vscode.window.showQuickPick(items, {
		title,
		placeHolder: 'Search by file name, resource ID, or path.',
		matchOnDescription: true,
		matchOnDetail: true,
		canPickMany: false,
		ignoreFocusOut: true
	});

	if (!selected) {
		return;
	}

	ensureWorkspace();

	await resourcePathInProject(
		context,
		selected.resourceUri.fsPath
	);

	ensureWorkspace();

	return selected.resourceUri;
}
