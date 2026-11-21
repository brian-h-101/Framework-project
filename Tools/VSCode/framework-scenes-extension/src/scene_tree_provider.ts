import * as vscode from 'vscode';
import type { ProjectContext } from './project_context';
import { validateResourcePath } from './project_context';
import type { SceneGraph, SceneNode } from './scene_bridge';

export interface SceneTreeElement {
	path: string;
	revision: number;
}

export class SceneTreeProvider
	implements vscode.TreeDataProvider<SceneTreeElement>, vscode.Disposable {
	private readonly changes = new vscode.EventEmitter<void>();
	readonly onDidChangeTreeData = this.changes.event;
	private revision = 0;
	private graph: SceneGraph | undefined;
	private context: ProjectContext | undefined;

	clear(): void {
		this.revision++;
		this.graph = undefined;
		this.context = undefined;
		this.changes.fire();
	}

	setGraph(context: ProjectContext, graph: SceneGraph): void {
		this.revision++;
		this.context = context;
		this.graph = graph;
		this.changes.fire();
	}

	resolve(element: SceneTreeElement): {
		context: ProjectContext;
		graph: SceneGraph;
		node: SceneNode;
	} {
		if (!element || element.revision !== this.revision
			|| !this.context || !this.graph
			|| !Object.hasOwn(this.graph.nodes, element.path)) {
			throw new Error('Choose a current node in Framework Scenes.');
		}
		return {
			context: this.context,
			graph: this.graph,
			node: this.graph.nodes[element.path]
		};
	}

	getChildren(element?: SceneTreeElement): SceneTreeElement[] {
		if (!this.graph) {
			return [];
		}
		if (element && element.revision !== this.revision) {
			return [];
		}
		const paths = element
			? this.graph.nodes[element.path]?.children ?? []
			: [this.graph.root];
		return paths.map(path => ({ path, revision: this.revision }));
	}

	getTreeItem(element: SceneTreeElement): vscode.TreeItem {
		const { context, graph, node } = this.resolve(element);
		const item = new vscode.TreeItem(node.name, node.children.length > 0
			? (node.path === '.' ? vscode.TreeItemCollapsibleState.Expanded
				: vscode.TreeItemCollapsibleState.Collapsed)
			: vscode.TreeItemCollapsibleState.None);
		item.id = JSON.stringify([context.projectDirectory, graph.source_path, node.path]);
		item.description = node.type || 'Node';
		if (node.instance_path) {
			item.description += ` · ${node.instance_path.split('/').pop()}`;
		}
		item.contextValue = 'scene_node'
			+ (node.instance_path ? '_instance' : '')
			+ (node.base_scene_path ? '_inherited' : '')
			+ (node.script_path ? '_scripted' : '')
			+ (node.can_add ? '_add' : '')
			+ (node.can_rename ? '_rename' : '')
			+ (node.can_remove ? '_remove' : '')
			+ (node.can_attach_script ? '_attach_script' : '')
			+ (node.can_remove_script ? '_detach_script' : '')
			+ (node.is_entity && node.can_add ? '_attach_behavior' : '')
			+ (node.can_assign_movement ? '_assign_movement' : '');
		item.iconPath = new vscode.ThemeIcon(node.instance_path ? 'references' : 'symbol-class');
		item.resourceUri = projectUri(context, node.source_path);
		item.tooltip = `${node.name} (${node.type || 'Node'})\n`
			+ `Node: ${node.path}\nDeclared in: ${node.source_path}`
			+ `\nStructure belongs to: ${node.structural_scene}`
			+ (node.instance_path ? `\nInstance: ${node.instance_path}` : '')
			+ (node.base_scene_path ? `\nInherits: ${node.base_scene_path}` : '')
			+ (node.script_path ? `\nScript: ${node.script_path}` : '')
			+ (node.movement_configuration_path ? `\nMovement: ${node.movement_configuration_path}` : '')
			+ (node.automation_id ? `\nAutomation: ${node.automation_id}\n${node.automation_resource_path}` : '');
		item.command = {
			command: 'frameworkScenes.openDeclaration',
			title: 'Open Node Declaration',
			arguments: [element]
		};
		return item;
	}

	getParent(element: SceneTreeElement): SceneTreeElement | undefined {
		if (element.path === '.' || element.revision !== this.revision) {
			return undefined;
		}
		const index = element.path.lastIndexOf('/');
		return {
			path: index < 0 ? '.' : element.path.slice(0, index),
			revision: this.revision
		};
	}

	dispose(): void {
		this.clear();
		this.changes.dispose();
	}
}

export function projectUri(context: ProjectContext, resourcePath: string): vscode.Uri {
	validateResourcePath(resourcePath);
	return vscode.Uri.joinPath(vscode.Uri.file(context.projectDirectory), ...resourcePath.slice(6).split('/'));
}
