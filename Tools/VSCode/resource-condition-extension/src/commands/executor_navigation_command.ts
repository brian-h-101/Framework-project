import * as vscode from 'vscode';
import { relative } from 'node:path';
import type {
	ResourceTreeProvider,
	ResourceTreeElement
} from '../tree/resource_tree_provider';
import { isExecutorScriptPath } from '../resources/executor_metadata';
import { resolveProjectContext } from '../workspace/project_context';
import { checkedProjectPath } from '../library/library_paths';

export async function openExecutorScript(
	provider: ResourceTreeProvider,
	element: ResourceTreeElement | undefined,
	output: vscode.OutputChannel
): Promise<void> {
	try {
		if (!element || element.cycle) {
			throw new Error('Choose an Action resource in Framework Resources.');
		}

		const selected = provider.resolve(element);

		if (!(selected.resource.kind === 'behavior' && selected.data?.sequence?.role === 'executor') && (selected.data || selected.resource.kind !== 'action')) {
			throw new Error('Choose the Action resource row.');
		}

		const executor = selected.graph.executors?.find(
			entry => entry.id === (selected.data?.sequence?.executor_id ?? selected.resource.behavior_id)
		);
		const source = executor?.script_path;

		if (!isExecutorScriptPath(source)) {
			throw new Error(
				'This Action has no available executor script. Refresh and retry.'
			);
		}

		const workspaceDirectories = (
			vscode.workspace.workspaceFolders ?? []
		)
			.filter(folder => folder.uri.scheme === 'file')
			.map(folder => folder.uri.fsPath);

		const context = await resolveProjectContext(
			selected.uri.fsPath,
			workspaceDirectories
		);

		if (relative(
			context.projectDirectory,
			selected.projectRoot.fsPath
		) !== '') {
			throw new Error('The resource project changed. Refresh and retry.');
		}

		const filePath = await checkedProjectPath(context, source);
		const scriptUri = vscode.Uri.file(filePath);
		const information = await vscode.workspace.fs.stat(scriptUri);

		if (information.type !== vscode.FileType.File) {
			throw new Error('The executor script must be an existing file.');
		}

		provider.resolve(element);

		await vscode.commands.executeCommand('vscode.open', scriptUri);
		output.appendLine(`[executor-navigation] Opened ${source}`);
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[executor-navigation] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}