import * as vscode from 'vscode';
import { validateGraph, isPath, type ResourceGraph, type ResourceNode } from '../bridges/resource_bridge';
import type { ValueNode } from '../bridges/behavior_editing_bridge';
import { isExecutorScriptPath } from '../resources/executor_metadata';

export interface ResourceTreeElement {
	sourcePath: string;
	route: (string | number)[];
	ancestry: string[];
	cycle: boolean;
	revision: number;
	dataIndices?: number[];
	parentSource?: string;
	linkRole?: string;
	linkIndex?: number;
}

export interface ResolvedElement {
	graph: ResourceGraph;
	projectRoot: vscode.Uri;
	resource: ResourceNode;
	data?: ValueNode;
	uri: vscode.Uri;
}

export class ResourceTreeProvider
	implements vscode.TreeDataProvider<ResourceTreeElement>, vscode.Disposable {
	private readonly changes = new vscode.EventEmitter<ResourceTreeElement | undefined | null | void>();
	readonly onDidChangeTreeData = this.changes.event;
	private graph: ResourceGraph | undefined;
	private projectRoot: vscode.Uri | undefined;
	private revision = 0;
	private readonly elements = new Map<string, string>();

	clear(): void {
		this.revision++;
		this.elements.clear();
		this.graph = undefined;
		this.projectRoot = undefined;
		this.changes.fire(undefined);
	}

	setGraph(projectRoot: vscode.Uri, graph: ResourceGraph): void {
		validateGraph(graph);
		this.revision++;
		this.elements.clear();
		this.projectRoot = projectRoot;
		this.graph = graph;
		this.changes.fire(undefined);
	}

	resolve(element: ResourceTreeElement): ResolvedElement {
		if (!element || !this.graph || !this.projectRoot
			|| element.revision !== this.revision
			|| this.elements.get(JSON.stringify(element.route)) !== JSON.stringify(element)) {
			throw new Error('This resource row is stale. Refresh Framework Resources and retry.');
		}
		const resource = this.graph.nodes[element.sourcePath];
		if (!resource) { throw new Error('The resource is no longer in this tree.'); }
		let data: ValueNode | undefined;
		if (element.dataIndices) {
			data = resource.data;
			for (const index of element.dataIndices) { data = data.children[index]; }
		}
		return { graph: this.graph, projectRoot: this.projectRoot, resource, data,
			uri: resourceUri(this.projectRoot, resource.source_path) };
	}

	getTreeItem(element: ResourceTreeElement): vscode.TreeItem {
		const { resource, data, uri, graph } = this.resolve(element);
		const executor = graph.executors?.find(
			entry => entry.id === resource.behavior_id
		);
		const hasChildren = data ? data.children.length > 0
			: resource.links.length > 0 || resource.data.children.length > 0;
		const item = new vscode.TreeItem(data?.label ?? resource.source_path.split('/').at(-1)!,
			!element.cycle && hasChildren ? vscode.TreeItemCollapsibleState.Collapsed
				: vscode.TreeItemCollapsibleState.None);
		item.id = JSON.stringify(element.route);
		item.resourceUri = uri;
		item.iconPath = data ? new vscode.ThemeIcon(data.kind === 'Array' ? 'list-ordered'
			: data.kind === 'Dictionary' ? 'symbol-object' : 'symbol-field') : vscode.ThemeIcon.File;
		if (data) {
			item.contextValue = ['behavior_data', data.editable ? 'edit' : '',
				data.can_add ? 'add' : '', data.can_rename ? 'rename' : '',
				data.can_remove ? 'remove' : '', data.can_add_effect ? 'add_effect' : ''].filter(Boolean).join('|');
			item.description = `${data.kind}: ${data.value_text}`;
			item.tooltip = `${data.kind}: ${data.value_text}\nOwned by ${resource.source_path}`;
		} else {
			const flags = [element.cycle ? 'cycle' : resource.kind];
			if (!element.cycle) {
				if (resource.kind === 'action' && resource.supports_effects !== false) { flags.push('add_effect'); }
				if (element.linkRole === 'condition') { flags.push('condition_link'); }
				if (element.linkRole === 'requirements') { flags.push('requirements_link'); }
				if (resource.kind === 'action'
					&& isExecutorScriptPath(executor?.script_path)) {
					flags.push('open_executor');
				}
				if (resource.links.some(link => link.role === 'requirements')) { flags.push('has_requirements'); }
			}
			item.contextValue = flags.join('|');
			item.tooltip = `${resource.kind}: ${resource.id}\n${resource.source_path}`
				+ (element.parentSource ? `\nLinked from ${element.parentSource}` : '');
			if (resource.kind === 'condition_group') { item.description = `[${resource.operator?.toUpperCase()}]`; }
			if (resource.kind === 'action' && resource.behavior_id !== undefined) {
				item.description = `[${resource.behavior_id || 'missing behavior'}]`;
				item.tooltip += `\nExecutor: ${resource.behavior_id}\n${resource.behavior_error || ''}`;
				if (isExecutorScriptPath(executor?.script_path)) {
					item.tooltip += `\nScript: ${executor.script_path}`;
				}
			}
			if (resource.kind === 'condition') { item.description = `[${resource.operator} ${resource.value_text}]`; }
			if (element.cycle) { item.description = `${item.description ?? ''} [cycle]`.trim(); }
		}
		item.command = { command: 'vscode.open', title: 'Open Owning Resource', arguments: [uri] };
		return item;
	}

	getChildren(element?: ResourceTreeElement): ResourceTreeElement[] {
		if (!this.graph || element?.cycle) { return []; }
		if (!element) {
			return this.graph.roots.map(target => this.remember({
				sourcePath: target, route: [target], ancestry: [target], cycle: false, revision: this.revision
			}));
		}
		const { resource, data } = this.resolve(element);
		if (data) {
			return data.children.map((_, index) => this.dataChild(element, [...element.dataIndices!, index]));
		}
		return [
			...resource.links.map((link, index) => this.remember({
				sourcePath: link.target, route: [...element.route, 'link', index, link.target],
				ancestry: [...element.ancestry, link.target], cycle: element.ancestry.includes(link.target),
				revision: this.revision, parentSource: resource.source_path, linkRole: link.role, linkIndex: link.index
			})),
			...resource.data.children.map((_, index) => this.dataChild(element, [index]))
		];
	}

	private dataChild(parent: ResourceTreeElement, indices: number[]): ResourceTreeElement {
		const baseRoute = parent.dataIndices ? parent.route.slice(0, -parent.dataIndices.length - 1) : parent.route;
		return this.remember({ sourcePath: parent.sourcePath, route: [...baseRoute, 'data', ...indices],
			ancestry: parent.ancestry, cycle: false, revision: this.revision, dataIndices: indices });
	}

	private remember(element: ResourceTreeElement): ResourceTreeElement {
		this.elements.set(JSON.stringify(element.route), JSON.stringify(element));
		return element;
	}

	dispose(): void { this.clear(); this.changes.dispose(); }
}

export function resourceUri(project: vscode.Uri, source: string): vscode.Uri {
	if (!isPath(source)) { throw new Error(`Invalid resource source path: ${source}`); }
	return vscode.Uri.joinPath(project, ...source.slice(6).split('/'));
}
