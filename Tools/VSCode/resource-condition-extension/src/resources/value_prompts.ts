import * as vscode from 'vscode';
import type { DataPathPart, ValueNode } from '../bridges/behavior_editing_bridge';

export function scalarError(type: string, text: string): string | undefined {
	if (type === 'int') {
		if (!/^[+-]?\d+$/.test(text)) { return 'Enter an integer without decimals or exponents.'; }
		const value = BigInt(text);
		if (value < -(1n << 63n) || value >= 1n << 63n) { return 'Enter a signed 64-bit integer.'; }
	}
	if (type === 'float' && (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(text)
		|| !Number.isFinite(Number(text)))) { return 'Enter a finite number.'; }
	return undefined;
}

export async function promptKey(current?: DataPathPart): Promise<DataPathPart | undefined> {
	const types = ['String', 'StringName', 'int'];
	const kind = await vscode.window.showQuickPick(current
		? [current.kind, ...types.filter(type => type !== current.kind)] : types,
	{ title: 'Dictionary Key Type', ignoreFocusOut: true });
	if (kind !== 'String' && kind !== 'StringName' && kind !== 'int') { return; }
	const text = await vscode.window.showInputBox({ title: 'Dictionary Key', value: current?.text ?? '',
		ignoreFocusOut: true, validateInput: value => scalarError(kind, value) });
	return text === undefined ? undefined : { kind, text };
}

export async function promptValue(node?: Pick<ValueNode, 'kind' | 'value_text' | 'allowed_types' | 'choices'>,
	title = 'Value'): Promise<{ value_type: string; value_text: string } | undefined> {
	const available = node?.allowed_types.length ? node.allowed_types
		: ['int', 'float', 'String', 'StringName', 'bool', 'Nil', ...(node ? [] : ['Dictionary', 'Array'])];
	const types = node && available.includes(node.kind)
		? [node.kind, ...available.filter(type => type !== node.kind)] : available;
	const type = await vscode.window.showQuickPick(types, { title: title + ' Type', ignoreFocusOut: true });
	if (type === undefined) { return; }
	let text: string | undefined;
	if (type === 'Nil') { text = 'null'; }
	else if (type === 'Dictionary') { text = '{}'; }
	else if (type === 'Array') { text = '[]'; }
	else if (type === 'bool') {
		text = await vscode.window.showQuickPick(node?.value_text === 'false' ? ['false', 'true'] : ['true', 'false'],
			{ title: 'Boolean Value', ignoreFocusOut: true });
	} else if (node?.choices.length) {
		text = await vscode.window.showQuickPick(node.choices, { title, ignoreFocusOut: true });
	} else {
		text = await vscode.window.showInputBox({ title, value: node?.value_text ?? '',
			ignoreFocusOut: true, validateInput: value => scalarError(type, value) });
	}
	return text === undefined ? undefined : { value_type: type, value_text: text };
}

export async function promptEffect(): Promise<Record<string, unknown> | undefined> {
	const operation = await vscode.window.showQuickPick(['add', 'set'], { title: 'Add Effect — Operation', ignoreFocusOut: true });
	if (!operation) { return; }
	const entity = await vscode.window.showQuickPick(['target', 'actor'], { title: 'Add Effect — Entity', ignoreFocusOut: true });
	if (!entity) { return; }
	const container = await vscode.window.showInputBox({ title: 'Add Effect — Container', value: 'health', ignoreFocusOut: true,
		validateInput: text => text.trim() ? undefined : 'Enter a container name.' });
	if (container === undefined) { return; }
	const path = await vscode.window.showInputBox({ title: 'Add Effect — Attribute Path', value: '["current"]', ignoreFocusOut: true,
		prompt: 'Enter a JSON array of attribute names. Nested path entries can be edited afterward.',
		validateInput: text => {
			try {
				const parts = JSON.parse(text);
				if (Array.isArray(parts) && parts.length && parts.every(part => typeof part === 'string' && part.length)) { return; }
			} catch { /* Show one useful validation message. */ }
			return 'Enter a nonempty JSON array of attribute names.';
		} });
	if (path === undefined) { return; }
	const valueFrom = await vscode.window.showInputBox({ title: 'Add Effect — Argument', value: 'amount', ignoreFocusOut: true,
		prompt: 'Every interaction using this action must supply this argument.',
		validateInput: text => text.trim() ? undefined : 'Enter an argument name.' });
	return valueFrom === undefined ? undefined : { operation, entity, container, path: JSON.parse(path), value_from: valueFrom };
}
