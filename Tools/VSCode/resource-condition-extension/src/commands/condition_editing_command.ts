import * as vscode from 'vscode';
import { relative, sep } from 'node:path';
import { resolveProjectContext } from '../workspace/project_context';
import {
	getConditionComparison,
	setConditionComparison
} from '../bridges/condition_editing_bridge';

export async function editConditionFromFile(
	output: vscode.OutputChannel,
	refresh: () => Promise<void>,
	resource?: vscode.Uri
): Promise<void> {
	try {
		if (!vscode.workspace.isTrusted) {
			throw new Error(
				'Condition editing requires a trusted workspace.'
			);
		}

		const selected = resource
			? [resource]
			: await vscode.window.showOpenDialog({
				defaultUri: vscode.window.activeTextEditor?.document.uri,
				title: 'Select the condition to edit',
				openLabel: 'Edit Condition',
				canSelectFiles: true,
				canSelectFolders: false,
				canSelectMany: false,
				filters: {
					'Godot resources': ['tres']
				}
			});

		if (!selected?.length) {
			return;
		}

		const uri = selected[0];

		if (uri.scheme !== 'file') {
			throw new Error('Choose a local .tres condition file.');
		}

		const folders = vscode.workspace.workspaceFolders ?? [];

		const context = await resolveProjectContext(
			uri.fsPath,
			folders
				.filter(folder => folder.uri.scheme === 'file')
				.map(folder => folder.uri.fsPath)
		);

		const ensureReady = (): void => {
			const currentFolders = vscode.workspace.workspaceFolders ?? [];

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
					+ 'Run the editing command again.'
				);
			}

			const dirtyDocument = vscode.workspace.textDocuments.find(
				document =>
					document.isDirty
					&& document.uri.toString() === uri.toString()
			);

			if (dirtyDocument) {
				throw new Error(
					`Save or revert '${uri.fsPath}' before editing it.`
				);
			}
		};

		ensureReady();

		const projectUri = vscode.Uri.file(context.projectDirectory);

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
			throw new Error('Choose a project-relative .tres resource.');
		}

		const conditionPath = `res://${relativePath}`;
		const originalBytes = await vscode.workspace.fs.readFile(uri);

		ensureReady();

		output.appendLine(
			`[condition-editing] Reading ${conditionPath}...`
		);

		const current = await getConditionComparison(
			context.projectDirectory,
			executable,
			conditionPath,
			message => output.appendLine(message)
		);

		ensureReady();

		const operators = ['==', '!=', '>', '>=', '<', '<='];

		const operator = await vscode.window.showQuickPick(
			[
				current.operator,
				...operators.filter(item => item !== current.operator)
			],
			{
				title: 'Edit Condition — Operator (1/4)',
				placeHolder: `Current operator: ${current.operator}`,
				ignoreFocusOut: true
			}
		);

		if (operator === undefined) {
			return;
		}

		const typeOptions = current.value_type === 'int'
			? ['int', 'float']
			: ['float', 'int'];

		const valueType = await vscode.window.showQuickPick(
			typeOptions,
			{
				title: 'Edit Condition — Numeric Type (2/4)',
				placeHolder: `Current type: ${current.value_type}`,
				ignoreFocusOut: true
			}
		);

		if (valueType !== 'int' && valueType !== 'float') {
			return;
		}

		const valueText = await vscode.window.showInputBox({
			title: 'Edit Condition — Value (3/4)',
			prompt: `Enter the comparison value as ${valueType}.`,
			value: current.value_text,
			ignoreFocusOut: true,
			validateInput: text =>
				text.trim().length === 0
					? 'Enter a numeric value.'
					: undefined
		});

		if (valueText === undefined) {
			return;
		}

		const message = await vscode.window.showInputBox({
			title: 'Edit Condition — Message (4/4)',
			prompt: 'Press Enter to save the comparison; Escape cancels.',
			value: current.message,
			ignoreFocusOut: true
		});

		if (message === undefined) {
			return;
		}

		ensureReady();

		const latestBytes = await vscode.workspace.fs.readFile(uri);

		if (
			latestBytes.length !== originalBytes.length
			|| originalBytes.some(
				(originalByte, index) =>
					originalByte !== latestBytes[index]
			)
		) {
			throw new Error(
				'The condition file changed while editing. Run the command again.'
			);
		}

		ensureReady();

		const result = await setConditionComparison(
			context.projectDirectory,
			executable,
			conditionPath,
			{
				operator,
				value_type: valueType,
				value_text: valueText,
				message
			},
			text => output.appendLine(text)
		);

		output.appendLine(
			`[condition-editing] Saved ${result.condition_path}; `
			+ `${result.operator} ${result.value_text} `
			+ `(${result.value_type}).`
		);

		void vscode.window.showInformationMessage(
			'Condition comparison saved.'
		);

		await refresh();
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[condition-editing] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}
