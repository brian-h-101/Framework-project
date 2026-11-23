import * as vscode from 'vscode';
import { createHash } from 'node:crypto';
import { editAttributes } from '../bridges/attribute_bridge';
import type { AttributeEdit, KeySegment, ValueKind } from '../bridges/attribute_bridge';
import type { AttributeElement, AttributeTreeProvider } from '../tree/attribute_tree_provider';
import { projectUri } from '../tree/attribute_tree_provider';
import { attributePathInProject } from '../workspace/project_context';
import { ensureWorkspace, godotExecutable } from '../resources/attribute_selection';

export type EditOperation = 'set' | 'add' | 'rename' | 'remove';
const SCALARS: ValueKind[] = ['int', 'float', 'String', 'StringName', 'bool', 'Nil'];

export class AttributeCommands {
	private busy = false;

	constructor(private readonly provider: AttributeTreeProvider, private readonly output: vscode.OutputChannel,
		private readonly refresh: () => Promise<void>) {}

	async execute(operation: EditOperation, element: AttributeElement): Promise<void> {
		if (this.busy) { void vscode.window.showInformationMessage('An attribute edit is already in progress.'); return; }
		this.busy = true;
		try {
			const { context, graph, node } = this.provider.resolve(element);
			if ((operation === 'set' && !node.editable) || (operation === 'add' && !node.can_add)
				|| (['rename', 'remove'].includes(operation) && !node.mutable)
				|| (operation === 'rename' && node.path.at(-1)?.kind === 'index')) {
				throw new Error('This operation is unavailable for the selected entry.');
			}
			const uri = projectUri(context, graph.source_path);
			const ready = async (): Promise<void> => {
				this.provider.resolve(element);
				ensureWorkspace(context);
				if (vscode.workspace.textDocuments.some(document => document.isDirty
					&& document.uri.toString() === uri.toString())) {
					throw new Error('Save or revert the Resource text before editing its attributes.');
				}
				await attributePathInProject(context, uri.fsPath);
				const bytes = await vscode.workspace.fs.readFile(uri);
				if (createHash('sha256').update(bytes).digest('hex') !== graph.content_hash) {
					throw new Error('The resource file changed. Refresh and run the edit again.');
				}
				this.provider.resolve(element);
				ensureWorkspace(context);
				if (vscode.workspace.textDocuments.some(document => document.isDirty
					&& document.uri.toString() === uri.toString())) {
					throw new Error('The Resource gained unsaved text edits. Save or revert them first.');
				}
			};
			await ready();
			const edit: AttributeEdit = { operation, path: node.path, expected_hash: graph.content_hash };
			if (operation === 'remove') {
				const chosen = await vscode.window.showWarningMessage(
					`Remove '${node.label}'${node.children.length ? ' and all of its contents' : ''} from ${graph.source_path}?`,
					{ modal: true }, 'Remove Entry');
				if (chosen !== 'Remove Entry') { return; }
			} else if (operation === 'rename') {
				const key = await promptKey(node.path.length === 1, node.path.at(-1));
				if (!key) { return; }
				edit.key = key;
			} else {
				if (operation === 'add' && node.kind === 'Dictionary') {
					const key = await promptKey(node.path.length === 0);
					if (!key) { return; }
					edit.key = key;
				}
				const value = operation === 'add' && node.path.length === 0
					? { value_type: 'Dictionary' as const, value_text: '{}' }
					: await promptValue(operation === 'set' ? node.kind as ValueKind : undefined,
						operation === 'set' ? node.value_text : undefined, operation === 'add');
				if (!value) { return; }
				Object.assign(edit, value);
			}
			await ready();
			await editAttributes(context.projectDirectory, godotExecutable(context), graph.source_path, edit,
				message => this.output.appendLine(message));
			this.output.appendLine(`[attributes] Saved ${operation}: ${graph.source_path}`);
			await this.refresh();
		} catch (error) {
			const message = error instanceof Error ? error.message : String(error);
			this.output.appendLine(`[attribute-edit] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		} finally { this.busy = false; }
	}
}

async function promptKey(container: boolean, current?: KeySegment): Promise<KeySegment | undefined> {
	const available: KeySegment['kind'][] = container ? ['StringName', 'String'] : ['String', 'StringName', 'int'];
	const kinds = current && available.includes(current.kind)
		? [current.kind, ...available.filter(kind => kind !== current.kind)] : available;
	const choice = await vscode.window.showQuickPick(kinds, {
		title: container ? 'Container Name Type' : 'Attribute Key Type', ignoreFocusOut: true
	});
	const kind = available.find(value => value === choice);
	if (!kind) { return undefined; }
	const text = await vscode.window.showInputBox({
		title: current ? 'Rename Entry' : container ? 'Add Container' : 'Add Attribute',
		prompt: `Enter the ${kind} key.`, value: current?.text ?? '', ignoreFocusOut: true,
		validateInput: value => container && !value ? 'Container names cannot be empty.'
			: kind === 'int' ? numberError('int', value) : undefined
	});
	return text === undefined ? undefined : { kind, text };
}

async function promptValue(current: ValueKind | undefined, text: string | undefined,
	collections: boolean): Promise<{ value_type: ValueKind; value_text: string } | undefined> {
	const available: ValueKind[] = [...SCALARS, ...(collections ? ['Dictionary', 'Array'] as const : [])];
	const kinds = current ? [current, ...available.filter(kind => kind !== current)] : available;
	const choice = await vscode.window.showQuickPick(kinds, {
		title: 'Attribute Value Type', placeHolder: current ? `Current type: ${current}` : 'Choose a native Godot type',
		ignoreFocusOut: true
	});
	const kind = available.find(value => value === choice);
	if (!kind) { return undefined; }
	if (kind === 'Dictionary' || kind === 'Array' || kind === 'Nil') {
		return { value_type: kind, value_text: kind === 'Dictionary' ? '{}' : kind === 'Array' ? '[]' : 'null' };
	}
	if (kind === 'bool') {
		const choices = text === 'false' ? ['false', 'true'] : ['true', 'false'];
		const chosen = await vscode.window.showQuickPick(choices, { title: 'Boolean Value', ignoreFocusOut: true });
		return chosen === undefined ? undefined : { value_type: kind, value_text: chosen };
	}
	const value = await vscode.window.showInputBox({
		title: 'Attribute Value', prompt: `Enter a ${kind} value. Escape cancels.`, value: text ?? '', ignoreFocusOut: true,
		validateInput: input => kind === 'int' || kind === 'float' ? numberError(kind, input) : undefined
	});
	return value === undefined ? undefined : { value_type: kind, value_text: value };
}

export function numberError(kind: 'int' | 'float', text: string): string | undefined {
	const value = text.trim();
	if (kind === 'int') {
		if (!/^[+-]?\d+$/.test(value)) { return 'Enter an integer without decimals.'; }
		const integer = BigInt(value);
		return integer < -9223372036854775808n || integer > 9223372036854775807n
			? 'Integer is outside Godot’s signed 64-bit range.' : undefined;
	}
	return /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value) && Number.isFinite(Number(value))
		? undefined : 'Enter a finite decimal number.';
}
