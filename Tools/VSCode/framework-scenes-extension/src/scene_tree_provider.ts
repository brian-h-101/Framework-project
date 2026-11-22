import * as vscode from 'vscode';
import type { ProjectContext } from './project_context';
import { validateResourcePath } from './project_context';
import type { SceneGraph, SceneNode } from './scene_bridge';

interface SceneTreePosition {
	path: string;
	revision: number;
}

export type SceneTreeElement = SceneTreePosition & (
	| { row?: undefined }
	| { row: 'properties' }
	| { row: 'property'; name: string }
);

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
		if (element?.row !== undefined) { throw new Error('Choose a current node in Framework Scenes.'); }
		return this.resolveNode(element);
	}

	private resolveNode(element: SceneTreeElement): { context: ProjectContext; graph: SceneGraph; node: SceneNode } {
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
		if (!element) { return [{ path: this.graph.root, revision: this.revision }]; }
		const node = this.graph.nodes[element.path];
		if (!node || element.row === 'property') { return []; }
		if (element.row === 'properties') {
			return (node.properties ?? []).map(property => ({
				path: node.path, revision: this.revision, row: 'property', name: property.name
			}));
		}
		const children: SceneTreeElement[] = node.children.map(path => ({ path, revision: this.revision }));
		if (node.properties?.length) { children.push({ path: node.path, revision: this.revision, row: 'properties' }); }
		return children;
	}

	getTreeItem(element: SceneTreeElement): vscode.TreeItem {
		const { context, graph, node } = this.resolveNode(element);
		const idParts = [context.projectDirectory, graph.source_path, node.path];
		if (element.row === 'properties') {
			const item = new vscode.TreeItem('Properties', vscode.TreeItemCollapsibleState.Collapsed);
			item.id = JSON.stringify([...idParts, 'properties']);
			item.description = String(node.properties?.length ?? 0);
			item.iconPath = new vscode.ThemeIcon('list-flat');
			item.contextValue = 'scene_properties';
			return item;
		}
		if (element.row === 'property') {
			const property = node.properties?.find(candidate => candidate.name === element.name);
			if (!property) { throw new Error('Choose a current property in Framework Scenes.'); }
			const item = new vscode.TreeItem(property.name, vscode.TreeItemCollapsibleState.None);
			item.id = JSON.stringify([...idParts, 'property', property.name]);
			const inherited = property.source_path !== graph.source_path;
			item.description = property.value + (inherited ? ' · inherited' : '');
			item.tooltip = `${property.name} (${property.type})\n${property.value}\nSaved in: ${property.source_path}`;
			item.iconPath = new vscode.ThemeIcon('symbol-property');
			item.contextValue = 'scene_property';
			return item;
		}
		const hasChildren = node.children.length > 0 || !!node.properties?.length;
		const item = new vscode.TreeItem(node.name, hasChildren
			? (node.path === '.' ? vscode.TreeItemCollapsibleState.Expanded
				: vscode.TreeItemCollapsibleState.Collapsed)
			: vscode.TreeItemCollapsibleState.None);
		item.id = JSON.stringify(idParts);
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
			+ (node.structural_scene === graph.source_path && node.type !== 'InstancePlaceholder' ? '_set_property' : '')
			+ (node.is_entity && node.can_add ? '_attach_behavior' : '')
			+ (node.is_entity && node.type !== 'InstancePlaceholder' ? '_configure_capabilities' : '')
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
			+ (node.movement_controller_path ? `\nController: ${node.movement_controller_path}` : '')
			+ (node.behavior_id ? `\nBehavior: ${node.behavior_id}\n${node.behavior_resource_path}` : '')
			+ (node.automation_id ? `\nAutomation: ${node.automation_id}\n${node.automation_resource_path}` : '');
		item.command = {
			command: 'frameworkScenes.openDeclaration',
			title: 'Open Node Declaration',
			arguments: [element]
		};
		return item;
	}

	getParent(element: SceneTreeElement): SceneTreeElement | undefined {
		if (element.revision !== this.revision) {
			return undefined;
		}
		if (element.row === 'property') { return { path: element.path, revision: this.revision, row: 'properties' }; }
		if (element.row === 'properties') { return { path: element.path, revision: this.revision }; }
		if (element.path === '.') { return undefined; }
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
