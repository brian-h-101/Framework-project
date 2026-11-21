import * as vscode from 'vscode';
import type { ExecutorDescriptor } from './executor_metadata';

export async function pickExecutor(executors: ExecutorDescriptor[] | undefined, current?: string): Promise<string | undefined> {
	if (!executors?.length) { throw new Error('Refresh to load registered executor behaviors.'); }
	return (await vscode.window.showQuickPick(executors.map(entry => ({ label: entry.label, description: entry.id,
		detail: entry.description + (entry.id === current ? ' (current)' : ''), id: entry.id })),
		{ title: 'Action — Executor Behavior', matchOnDescription: true, matchOnDetail: true, ignoreFocusOut: true }))?.id;
}
