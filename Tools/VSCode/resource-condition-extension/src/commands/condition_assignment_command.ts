import * as vscode from 'vscode';
import { relative } from 'node:path';
import {
	resolveProjectContext,
	resourcePathInProject,
	type ProjectContext
} from '../workspace/project_context';
import {
	addConditionToGroup,
	setInteractionRequirements,
	setInteractionAction,
	resolveInteractionSource
} from '../bridges/condition_assignment_bridge';
import { pickResource } from '../resources/resource_picker';

export interface ConditionAssignmentFiles {
	group: vscode.Uri;
	condition: vscode.Uri;
}
export interface InteractionRequirementsFiles {
	interaction: vscode.Uri;
	group: vscode.Uri;
}

export interface InteractionActionFiles {
	interaction: vscode.Uri;
	action: vscode.Uri;
}

export interface InteractionResourceFiles {
	interaction: vscode.Uri;
	resource: vscode.Uri;
}

export async function assignConditionFromFiles(
	output: vscode.OutputChannel,
	refresh: () => Promise<void>,
	files?: Partial<ConditionAssignmentFiles>
): Promise<void> {
	try {
		if (!vscode.workspace.isTrusted) {
			throw new Error(
				'Condition assignment requires a trusted workspace.'
			);
		}

		const options: vscode.OpenDialogOptions = {
			defaultUri: vscode.window.activeTextEditor?.document.uri,
			canSelectFiles: true,
			canSelectFolders: false,
			canSelectMany: false,
			filters: {
				'Godot resources': ['tres']
			}
		};

		const groups = files?.group
			? [files.group]
			: await vscode.window.showOpenDialog({
				...options,
				title: 'Select the destination condition group',
				openLabel: 'Choose Group'
			});

		if (!groups?.length) {
			return;
		}

		const context = await contextForResource(groups[0]);
		const executable = executableFor(context);

		const condition = files?.condition ?? await pickResource(
			context,
			executable,
			'condition',
			output,
			'Select the condition to assign'
		);

		if (!condition) {
			return;
		}

		const conditions = [condition];

		const groupPath = await resourcePathFor(context, groups[0]);
		const conditionPath = await resourcePathFor(context, conditions[0]);

		const selectedUris = new Set([
			groups[0].toString(),
			conditions[0].toString()
		]);

		const dirtyDocument = vscode.workspace.textDocuments.find(
			document =>
				document.isDirty
				&& selectedUris.has(document.uri.toString())
		);

		if (dirtyDocument) {
			throw new Error(
				`Save or revert '${dirtyDocument.uri.fsPath}' `
				+ 'before assigning a condition.'
			);
		}

		output.appendLine(
			`[assignment] Adding ${conditionPath} to ${groupPath}...`
		);

		const result = await addConditionToGroup(
			context.projectDirectory,
			executable,
			groupPath,
			conditionPath,
			message => output.appendLine(message)
		);

		output.appendLine(
			`[assignment] Saved ${result.group_path}; `
			+ `conditions: ${result.condition_count}.`
		);

		void vscode.window.showInformationMessage(
			'Condition assigned to group.'
		);

		await refresh();
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[assignment] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}

export async function assignInteractionRequirementsFromFiles(
	output: vscode.OutputChannel,
	refresh: () => Promise<void>,
	files?: Partial<InteractionRequirementsFiles>
): Promise<void> {
	try {
		if (!vscode.workspace.isTrusted) {
			throw new Error(
				'Requirements assignment requires a trusted workspace.'
			);
		}

		const options: vscode.OpenDialogOptions = {
			canSelectFiles: true,
			canSelectFolders: false,
			canSelectMany: false,
			filters: {
				'Godot resources': ['tres']
			}
		};

		const interactions = files?.interaction
			? [files.interaction]
			: await vscode.window.showOpenDialog({
				...options,
				defaultUri: vscode.window.activeTextEditor?.document.uri,
				title: 'Select the destination interaction',
				openLabel: 'Choose Interaction'
			});

		if (!interactions?.length) {
			return;
		}

		const context = await contextForResource(interactions[0]);
		const executable = executableFor(context);

		const group = files?.group ?? await pickResource(
			context,
			executable,
			'condition_group',
			output,
			'Select the condition group to assign'
		);

		if (!group) {
			return;
		}

		const groups = [group];

		const interactionPath = await resourcePathFor(
			context,
			interactions[0]
		);

		const groupPath = await resourcePathFor(context, groups[0]);

		const selectedUris = new Set([
			interactions[0].toString(),
			groups[0].toString()
		]);

		const dirtyDocument = vscode.workspace.textDocuments.find(
			document =>
				document.isDirty
				&& selectedUris.has(document.uri.toString())
		);

		if (dirtyDocument) {
			throw new Error(
				`Save or revert '${dirtyDocument.uri.fsPath}' `
				+ 'before assigning interaction requirements.'
			);
		}

		output.appendLine(
			`[requirements] Setting ${groupPath} on ${interactionPath}...`
		);

		const result = await setInteractionRequirements(
			context.projectDirectory,
			executable,
			interactionPath,
			groupPath,
			message => output.appendLine(message)
		);

		output.appendLine(
			`[requirements] Saved ${result.interaction_path}; `
			+ `requirements: ${result.group_path}.`
		);

		void vscode.window.showInformationMessage(
			'Interaction requirements assigned.'
		);

		await refresh();
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[requirements] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}

export async function assignInteractionActionFromFiles(
	output: vscode.OutputChannel,
	refresh: () => Promise<void>,
	files?: Partial<InteractionActionFiles>
): Promise<void> {
	try {
		if (!vscode.workspace.isTrusted) {
			throw new Error(
				'Action assignment requires a trusted workspace.'
			);
		}

		const options: vscode.OpenDialogOptions = {
			canSelectFiles: true,
			canSelectFolders: false,
			canSelectMany: false,
			filters: {
				'Godot resources': ['tres']
			}
		};

		const interactions = files?.interaction
			? [files.interaction]
			: await vscode.window.showOpenDialog({
				...options,
				defaultUri: vscode.window.activeTextEditor?.document.uri,
				title: 'Select the destination interaction',
				openLabel: 'Choose Interaction'
			});

		if (!interactions?.length) {
			return;
		}

		const context = await contextForResource(interactions[0]);
		const executable = executableFor(context);

		const action = files?.action ?? await pickResource(
			context,
			executable,
			'action',
			output,
			'Select the action to assign'
		);

		if (!action) {
			return;
		}

		const actions = [action];

		const interactionPath = await resourcePathFor(
			context,
			interactions[0]
		);

		const actionPath = await resourcePathFor(context, actions[0]);

		const selectedUris = new Set([
			interactions[0].toString(),
			actions[0].toString()
		]);

		const dirtyDocument = vscode.workspace.textDocuments.find(
			document =>
				document.isDirty
				&& selectedUris.has(document.uri.toString())
		);

		if (dirtyDocument) {
			throw new Error(
				`Save or revert '${dirtyDocument.uri.fsPath}' `
				+ 'before assigning an interaction action.'
			);
		}

		output.appendLine(
			`[action-assignment] Setting ${actionPath} `
			+ `on ${interactionPath}...`
		);

		const result = await setInteractionAction(
			context.projectDirectory,
			executable,
			interactionPath,
			actionPath,
			message => output.appendLine(message)
		);

		output.appendLine(
			`[action-assignment] Saved ${result.interaction_path}; `
			+ `action: ${result.action_path}.`
		);

		void vscode.window.showInformationMessage(
			'Interaction action assigned.'
		);

		await refresh();
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[action-assignment] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}

export async function assignInteractionResourceFromFiles(
	output: vscode.OutputChannel,
	refresh: () => Promise<void>,
	files: InteractionResourceFiles
): Promise<void> {
	try {
		if (!vscode.workspace.isTrusted) {
			throw new Error(
				'Resource assignment requires a trusted workspace.'
			);
		}

		const context = await contextForResource(files.interaction);
		const executable = executableFor(context);

		const interactionPath = await resourcePathFor(
			context,
			files.interaction
		);

		const resourcePath = await resourcePathFor(
			context,
			files.resource
		);

		const selectedUris = new Set([
			files.interaction.toString(),
			files.resource.toString()
		]);

		const dirtyDocument = vscode.workspace.textDocuments.find(
			document =>
				document.isDirty
				&& selectedUris.has(document.uri.toString())
		);

		if (dirtyDocument) {
			throw new Error(
				`Save or revert '${dirtyDocument.uri.fsPath}' `
				+ 'before assigning a resource.'
			);
		}

		output.appendLine(
			`[drop] Resolving ${resourcePath} `
			+ `for ${interactionPath}...`
		);

		const result = await resolveInteractionSource(
			context.projectDirectory,
			executable,
			interactionPath,
			resourcePath,
			message => output.appendLine(message)
		);

		await resourcePathFor(context, files.interaction);
		await resourcePathFor(context, files.resource);
		ensureWorkspace(context);

		output.appendLine(
			`[drop] Source kind: ${result.kind}.`
		);

		if (result.kind === 'action') {
			await assignInteractionActionFromFiles(
				output,
				refresh,
				{
					interaction: files.interaction,
					action: files.resource
				}
			);
		} else {
			await assignInteractionRequirementsFromFiles(
				output,
				refresh,
				{
					interaction: files.interaction,
					group: files.resource
				}
			);
		}
	} catch (error) {
		const message = error instanceof Error
			? error.message
			: String(error);

		output.appendLine(`[drop] Error: ${message}`);
		void vscode.window.showErrorMessage(message);
	}
}

async function contextForResource(
	uri: vscode.Uri
): Promise<ProjectContext> {
	if (!vscode.workspace.isTrusted || uri.scheme !== 'file') {
		throw new Error(
			'Choose a local resource in a trusted workspace.'
		);
	}

	const folders = vscode.workspace.workspaceFolders ?? [];

	const context = await resolveProjectContext(
		uri.fsPath,
		folders
			.filter(folder => folder.uri.scheme === 'file')
			.map(folder => folder.uri.fsPath)
	);

	ensureWorkspace(context);

	return context;
}

function ensureWorkspace(context: ProjectContext): void {
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
			+ 'Run the assignment again.'
		);
	}
}

function executableFor(context: ProjectContext): string {
	ensureWorkspace(context);

	const executable = vscode.workspace
		.getConfiguration(
			'godotTools',
			vscode.Uri.file(context.projectDirectory)
		)
		.get<string>('editorPath.godot4')
		?.trim();

	if (!executable) {
		throw new Error(
			'Configure godotTools.editorPath.godot4 '
			+ 'for this workspace first.'
		);
	}

	return executable;
}

async function resourcePathFor(
	context: ProjectContext,
	uri: vscode.Uri
): Promise<string> {
	ensureWorkspace(context);

	if (uri.scheme !== 'file') {
		throw new Error('Choose a local .tres resource.');
	}

	const resourcePath = await resourcePathInProject(
		context,
		uri.fsPath
	);

	ensureWorkspace(context);

	return resourcePath;
}
