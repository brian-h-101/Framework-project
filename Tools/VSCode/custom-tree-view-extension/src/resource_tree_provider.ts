import * as vscode from 'vscode';
import type { ResourceGraph } from './resource_bridge';

export interface ResourceTreeElement {
	sourcePath: string;
	route: (string | number)[];
	ancestry: string[];
	cycle: boolean;
}

export class ResourceTreeProvider
	implements vscode.TreeDataProvider<ResourceTreeElement>, vscode.Disposable {

	private readonly changes = new vscode.EventEmitter<
		ResourceTreeElement | undefined | null | void
	>();

	readonly onDidChangeTreeData = this.changes.event;

	private graph: ResourceGraph | undefined;
	private projectRoot: vscode.Uri | undefined;

	clear(): void {
		this.graph = undefined;
		this.projectRoot = undefined;
		this.changes.fire(undefined);
	}

	setGraph(projectRoot: vscode.Uri, graph: ResourceGraph): void {
		if (new Set(graph.roots).size !== graph.roots.length) {
			throw new Error('The resource graph contains duplicate roots.');
		}

		for (const [sourcePath, node] of Object.entries(graph.nodes)) {
			if (
				!node
				|| typeof node.id !== 'string'
				|| typeof node.kind !== 'string'
				|| node.source_path !== sourcePath
				|| !Array.isArray(node.links)
				|| node.links.some(link =>
					!link
					|| typeof link.role !== 'string'
					|| typeof link.target !== 'string'
				)
			) {
				throw new Error(`Malformed resource node: ${sourcePath}`);
			}

			if (
				(
					node.kind === 'condition_group'
					|| node.kind === 'condition'
				)
				&& typeof node.operator !== 'string'
			) {
				throw new Error(`Missing condition operator: ${sourcePath}`);
			}

			if (
				node.kind === 'condition'
				&& typeof node.value_text !== 'string'
			) {
				throw new Error(`Missing condition value: ${sourcePath}`);
			}

			resourceUri(projectRoot, sourcePath);
		}

		for (const root of graph.roots) {
			if (!Object.hasOwn(graph.nodes, root)) {
				throw new Error(`Missing root resource: ${root}`);
			}
		}

		for (const node of Object.values(graph.nodes)) {
			for (const link of node.links) {
				if (!Object.hasOwn(graph.nodes, link.target)) {
					throw new Error(`Missing linked resource: ${link.target}`);
				}
			}
		}

		this.projectRoot = projectRoot;
		this.graph = graph;
		this.changes.fire(undefined);
	}

	getTreeItem(element: ResourceTreeElement): vscode.TreeItem {
		const node = this.graph?.nodes[element.sourcePath];

		if (!node || !this.projectRoot) {
			return new vscode.TreeItem(element.sourcePath);
		}

		const label = node.source_path.slice(
			node.source_path.lastIndexOf('/') + 1
		);

		const item = new vscode.TreeItem(
			label,
			!element.cycle && node.links.length > 0
				? vscode.TreeItemCollapsibleState.Collapsed
				: vscode.TreeItemCollapsibleState.None
		);

		const uri = resourceUri(this.projectRoot, node.source_path);

		item.id = JSON.stringify(element.route);
		item.resourceUri = uri;
		item.iconPath = vscode.ThemeIcon.File;
		item.contextValue = element.cycle ? 'cycle' : node.kind;
		item.tooltip = `${node.kind}: ${node.id}\n${node.source_path}`;

		if (node.kind === 'condition_group') {
			item.description = `[${node.operator?.toUpperCase() ?? ''}]`;
		} else if (node.kind === 'condition') {
			item.description = `[${node.operator} ${node.value_text}]`;
		}

		if (element.cycle) {
			item.description = `${item.description ?? ''} [cycle]`.trim();
		}

		item.command = {
			command: 'vscode.open',
			title: 'Open Resource',
			arguments: [uri]
		};

		return item;
	}

	getChildren(element?: ResourceTreeElement): ResourceTreeElement[] {
		if (!this.graph || element?.cycle) {
			return [];
		}

		const ancestry = element?.ancestry ?? [];

		const links = element
			? this.graph.nodes[element.sourcePath]?.links ?? []
			: this.graph.roots.map(target => ({
				role: 'root',
				target
			}));

		return links.map((link, index) => ({
			sourcePath: link.target,
			route: element
				? [...element.route, index, link.target]
				: [link.target],
			ancestry: [...ancestry, link.target],
			cycle: ancestry.includes(link.target)
		}));
	}

	dispose(): void {
		this.changes.dispose();
		this.graph = undefined;
		this.projectRoot = undefined;
	}
}

function resourceUri(
	projectRoot: vscode.Uri,
	sourcePath: string
): vscode.Uri {
	if (
		!sourcePath.startsWith('res://')
		|| !sourcePath.endsWith('.tres')
	) {
		throw new Error(`Invalid resource source path: ${sourcePath}`);
	}

	const segments = sourcePath.slice('res://'.length).split('/');

	if (segments.some(segment =>
		!segment
		|| segment === '.'
		|| segment === '..'
		|| /[\\:\0]/.test(segment)
	)) {
		throw new Error(`Invalid resource source path: ${sourcePath}`);
	}

	return vscode.Uri.joinPath(projectRoot, ...segments);
}
