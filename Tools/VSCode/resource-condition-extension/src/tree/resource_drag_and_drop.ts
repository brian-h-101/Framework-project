import * as vscode from 'vscode';

import type {
	ResourceTreeElement,
	ResourceTreeProvider
} from './resource_tree_provider';

import type {
	ConditionAssignmentFiles,
	InteractionResourceFiles
} from '../commands/condition_assignment_command';

export class ResourceDragAndDropController
	implements vscode.TreeDragAndDropController<ResourceTreeElement> {

	readonly dragMimeTypes = [
		'text/uri-list'
	];

	readonly dropMimeTypes = [
		'text/uri-list',
		'application/vnd.code.tree.customtreeview.resources'
	];

	constructor(
		private readonly provider: ResourceTreeProvider,
		private readonly assign: (
			files: ConditionAssignmentFiles | InteractionResourceFiles
		) => Promise<void>,
		private readonly output: vscode.OutputChannel
	) {}

	handleDrag(
		source: readonly ResourceTreeElement[],
		dataTransfer: vscode.DataTransfer,
		token: vscode.CancellationToken
	): void {
		if (
			token.isCancellationRequested
			|| source.length !== 1
			|| source[0].cycle
		) {
			return;
		}

		let item: vscode.TreeItem;
		try { item = this.provider.getTreeItem(source[0]); } catch { return; }
		const kind = item.contextValue?.split('|')[0];

		if (
			!item.resourceUri
			|| (
				kind !== 'condition'
				&& kind !== 'condition_group'
				&& kind !== 'action'
			)
		) {
			return;
		}

		dataTransfer.set(
			'text/uri-list',
			new vscode.DataTransferItem(item.resourceUri.toString())
		);
	}

	async handleDrop(
		target: ResourceTreeElement | undefined,
		dataTransfer: vscode.DataTransfer,
		token: vscode.CancellationToken
	): Promise<void> {
		try {
			if (token.isCancellationRequested) {
				return;
			}

			if (!target || target.cycle) {
				throw new Error(
					'Drop onto a condition group or interaction.'
				);
			}

			const destination = this.provider.getTreeItem(target);
			const kind = destination.contextValue?.split('|')[0];

			if (
				!destination.resourceUri
				|| (
					kind !== 'condition_group'
					&& kind !== 'interaction'
				)
			) {
				throw new Error(
					'Drop onto a condition group or interaction.'
				);
			}

			const transfer = dataTransfer.get('text/uri-list');

			if (!transfer) {
				throw new Error(
					'The drop does not contain a resource file.'
				);
			}

			const text = await transfer.asString();

			if (token.isCancellationRequested) {
				return;
			}

			const entries = text
				.split(/\r?\n/)
				.map(line => line.trim())
				.filter(line => line && !line.startsWith('#'));

			if (entries.length !== 1) {
				throw new Error(
					'Drag exactly one .tres resource at a time.'
				);
			}

			const sourceUri = vscode.Uri
				.parse(entries[0], true)
				.with({
					query: '',
					fragment: ''
				});

			if (
				sourceUri.scheme !== 'file'
				|| !sourceUri.path.endsWith('.tres')
			) {
				throw new Error('Drop a local .tres resource file.');
			}

			if (token.isCancellationRequested) {
				return;
			}

			this.provider.getTreeItem(target);
			if (kind === 'condition_group') {
				await this.assign({
					group: destination.resourceUri,
					condition: sourceUri
				});
			} else {
				await this.assign({
					interaction: destination.resourceUri,
					resource: sourceUri
				});
			}
		} catch (error) {
			if (token.isCancellationRequested) {
				return;
			}

			const message = error instanceof Error
				? error.message
				: String(error);

			this.output.appendLine(`[drop] Error: ${message}`);
			void vscode.window.showErrorMessage(message);
		}
	}
}
