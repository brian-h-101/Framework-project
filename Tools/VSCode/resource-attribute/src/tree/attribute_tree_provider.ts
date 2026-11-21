import * as vscode from 'vscode';
import type { AttributeGraph, AttributeNode, KeySegment } from '../bridges/attribute_bridge';
import type { ProjectContext } from '../workspace/project_context';
import { validateResourcePath } from '../workspace/project_context';

export interface AttributeElement { path: KeySegment[]; revision: number }

export class AttributeTreeProvider implements vscode.TreeDataProvider<AttributeElement>, vscode.Disposable {
	private readonly changes = new vscode.EventEmitter<void>();
	readonly onDidChangeTreeData = this.changes.event;
	private revision = 0;
	private graph: AttributeGraph | undefined;
	private context: ProjectContext | undefined;
	private nodes = new Map<string, AttributeNode>();

	clear(): void {
		this.revision++;
		this.graph = undefined;
		this.context = undefined;
		this.nodes.clear();
		this.changes.fire();
	}

	setGraph(context: ProjectContext, graph: AttributeGraph): void {
		this.clear();
		this.context = context;
		this.graph = graph;
		const add = (node: AttributeNode): void => {
			this.nodes.set(JSON.stringify(node.path), node);
			node.children.forEach(add);
		};
		if (graph.root) { add(graph.root); }
		this.changes.fire();
	}

	resolve(element: AttributeElement): { context: ProjectContext; graph: AttributeGraph; node: AttributeNode } {
		const node = element && this.nodes.get(JSON.stringify(element.path));
		if (!node || element.revision !== this.revision || !this.context || !this.graph) {
			throw new Error('Choose a current entry in Framework Attributes.');
		}
		return { context: this.context, graph: this.graph, node };
	}

	getChildren(element?: AttributeElement): AttributeElement[] {
		if (!this.graph?.root || (element && element.revision !== this.revision)) { return []; }
		const children = element ? this.resolve(element).node.children : [this.graph.root];
		return children.map(node => ({ path: node.path, revision: this.revision }));
	}

	getParent(element: AttributeElement): AttributeElement | undefined {
		if (element.path.length === 0 || element.revision !== this.revision) { return undefined; }
		return { path: element.path.slice(0, -1), revision: this.revision };
	}

	getTreeItem(element: AttributeElement): vscode.TreeItem {
		const { context, graph, node } = this.resolve(element);
		const item = new vscode.TreeItem(node.label, node.children.length
			? (node.path.length === 0 ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.Collapsed)
			: vscode.TreeItemCollapsibleState.None);
		item.id = JSON.stringify([context.projectDirectory, graph.source_path, node.path]);
		item.description = `${node.kind} · ${node.value_text.replace(/\s+/g, ' ').slice(0, 100)}`;
		item.contextValue = 'attribute'
			+ (node.path.length === 0 ? '_root' : '_entry')
			+ (node.editable ? '_edit' : '')
			+ (node.can_add ? '_add' : '')
			+ (node.mutable && node.path.at(-1)?.kind !== 'index' ? '_rename' : '')
			+ (node.mutable ? '_remove' : '');
		item.iconPath = new vscode.ThemeIcon(node.kind === 'Dictionary' ? 'symbol-namespace'
			: node.kind === 'Array' ? 'symbol-array' : 'symbol-field');
		item.resourceUri = projectUri(context, graph.source_path);
		item.tooltip = `${node.label} (${node.kind})\n${node.value_text}\n${graph.source_path}`
			+ (node.path.length ? `\nKey type: ${node.path.at(-1)?.kind}` : '')
			+ (!node.editable && !node.can_add && node.path.length > 1 ? '\nThis native value is displayed read-only.' : '');
		item.command = { command: 'resourceAttribute.openSource', title: 'Open Resource', arguments: [element] };
		return item;
	}

	dispose(): void { this.clear(); this.changes.dispose(); }
}

export function projectUri(context: ProjectContext, source: string): vscode.Uri {
	validateResourcePath(source, '.tres');
	return vscode.Uri.joinPath(vscode.Uri.file(context.projectDirectory), ...source.slice(6).split('/'));
}
