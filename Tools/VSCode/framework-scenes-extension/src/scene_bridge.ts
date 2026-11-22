import { execFile } from 'node:child_process';
import { validateResourcePath } from './project_context';

export interface SceneProperty {
	name: string;
	type: string;
	value: string;
	source_path: string;
}

export interface SceneNode {
	path: string;
	name: string;
	type: string;
	source_path: string;
	source_node_path: string;
	instance_path: string;
	base_scene_path: string;
	script_path: string;
	has_script: boolean;
	script_source_path: string;
	can_attach_script: boolean;
	can_remove_script: boolean;
	is_entity: boolean;
	interaction_resource_path: string;
	interaction_id: string;
	behavior_id?: string;
	behavior_resource_path?: string;
	automation_id?: string;
	automation_resource_path?: string;
	movement_configuration_path: string;
	movement_controller_path?: string;
	can_assign_movement: boolean;
	children: string[];
	structural_scene: string;
	structural_node_path: string;
	instance_boundary: string;
	can_add: boolean;
	can_rename: boolean;
	can_remove: boolean;
	properties?: SceneProperty[];
	references: Record<string, { source_path: string; paths: string[] }>;
}

export interface SceneGraph {
	version: 2;
	source_path: string;
	root: '.';
	nodes: Record<string, SceneNode>;
	dependencies: string[];
	dependency_hashes: Record<string, string>;
}

const RESULT_PREFIX = '[scene-graph] ';

export function loadSceneGraph(
	projectDirectory: string,
	godotExecutable: string,
	scenePath: string,
	report: (message: string) => void,
	signal?: AbortSignal
): Promise<SceneGraph> {
	validateResourcePath(scenePath, '.tscn');
	return new Promise((resolve, reject) => {
		execFile(godotExecutable, [
			'--headless', '--path', projectDirectory,
			'--script', 'res://Framework/Env/Authoring/Scenes/Inspection/scene_graph_export.gd',
			'--', scenePath
		], {
			cwd: projectDirectory,
			encoding: 'utf8',
			windowsHide: true,
			timeout: 30_000,
			maxBuffer: 16 * 1024 * 1024,
			signal
		}, (error, stdout, stderr) => {
			try {
				if (stderr.trim()) {
					report(stderr.trim());
				}
				const lines = stdout.split(/\r?\n/)
					.filter(line => line.startsWith(RESULT_PREFIX));
				if (lines.length !== 1) {
					throw error ?? new Error('Godot must return exactly one scene-graph result.');
				}
				const packet: unknown = JSON.parse(lines[0].slice(RESULT_PREFIX.length));
				if (!isRecord(packet) || typeof packet.ok !== 'boolean') {
					throw new Error('Invalid scene-graph response.');
				}
				if (!packet.ok) {
					throw new Error(typeof packet.error === 'string'
						? packet.error : 'The Godot scene exporter failed.');
				}
				if (error) {
					throw error;
				}
				if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
					throw new Error('Godot reported a scene inspection error. See Framework Scenes output.');
				}
				resolve(validateSceneGraph(packet.value, scenePath));
			} catch (failure) {
				reject(failure);
			}
		});
	});
}

export function validateSceneGraph(value: unknown, scenePath: string): SceneGraph {
	if (!isRecord(value) || value.version !== 2 || value.source_path !== scenePath
		|| value.root !== '.' || !isRecord(value.nodes)
		|| !Array.isArray(value.dependencies) || !isRecord(value.dependency_hashes)) {
		throw new Error('Unsupported or malformed scene graph.');
	}
	validateResourcePath(scenePath, '.tscn');
	if (Object.keys(value.nodes).length > 10_000) {
		throw new Error('The scene graph exceeds 10000 nodes.');
	}
	const dependencies = new Set<string>();
	for (const dependency of value.dependencies) {
		if (typeof dependency !== 'string' || dependencies.has(dependency)) {
			throw new Error('Invalid or duplicate scene dependency.');
		}
		validateResourcePath(dependency, '.tscn');
		dependencies.add(dependency);
	}
	if (!dependencies.has(scenePath)) {
		throw new Error('The selected scene is absent from its dependencies.');
	}
	for (const dependency of dependencies) {
		if (!Object.hasOwn(value.dependency_hashes, dependency)) {
			throw new Error('Missing scene dependency hash.');
		}
	}
	for (const [dependency, hash] of Object.entries(value.dependency_hashes)) {
		validateResourcePath(dependency, '.tscn');
		if (typeof hash !== 'string' || !/^[a-f0-9]{64}$/.test(hash)) {
			throw new Error('Malformed scene dependency hash.');
		}
	}
	for (const [path, node] of Object.entries(value.nodes)) {
		if (!isRecord(node) || node.path !== path
			|| !['name', 'type', 'source_path', 'source_node_path', 'instance_path',
				'base_scene_path', 'script_path', 'structural_scene', 'structural_node_path',
				'instance_boundary', 'interaction_resource_path', 'interaction_id', 'movement_configuration_path', 'script_source_path']
				.every(key => typeof node[key] === 'string')
			|| !['can_add', 'can_rename', 'can_remove', 'is_entity', 'can_assign_movement', 'has_script', 'can_attach_script', 'can_remove_script']
				.every(key => typeof node[key] === 'boolean')
			|| !isRecord(node.references)
			|| node.name === '' || !Array.isArray(node.children)
			|| !node.children.every(child => typeof child === 'string')
			|| new Set(node.children).size !== node.children.length) {
			throw new Error(`Malformed scene node: ${path}`);
		}
		validateNodePath(path);
		for (const key of ['automation_id', 'automation_resource_path', 'behavior_id', 'behavior_resource_path']) {
			if (node[key] !== undefined && typeof node[key] !== 'string') { throw new Error('Malformed Automation attachment metadata.'); }
		}
		if (node.behavior_resource_path) { validateResourcePath(node.behavior_resource_path as string, '.tres'); }
		if (node.automation_resource_path) { validateResourcePath(node.automation_resource_path as string, '.tres'); }
		validateNodePath(node.source_node_path as string);
		validateNodePath(node.structural_node_path as string);
		const local = node.structural_scene === scenePath;
		if (node.can_rename !== (local && path !== '.') || node.can_remove !== node.can_rename
			|| node.can_add !== ((local || path === '.') && node.type !== 'InstancePlaceholder')
			|| node.can_attach_script !== (local && node.type !== 'InstancePlaceholder' && !node.has_script)
			|| node.can_remove_script !== (local && node.has_script && node.script_source_path === scenePath)
			|| node.can_assign_movement !== (local && (
				(node.type === 'CharacterBody2D' && node.script_path === 'res://Framework/Content/Universal/Movement/based/Physics2D/movement_body_2d.gd')
				|| (node.type === 'CharacterBody3D' && node.script_path === 'res://Framework/Content/Universal/Movement/based/Physics3D/movement_body_3d.gd')
			))) {
			throw new Error(`Invalid structural capabilities: ${path}`);
		}
		if (node.instance_boundary !== '') { validateNodePath(node.instance_boundary as string); }
		if (node.properties !== undefined) {
			if (!Array.isArray(node.properties)) { throw new Error(`Invalid properties on scene node: ${path}`); }
			const names = new Set<string>();
			for (const property of node.properties) {
				if (!isRecord(property) || typeof property.name !== 'string' || !property.name || names.has(property.name)
					|| typeof property.type !== 'string' || !property.type || typeof property.value !== 'string'
					|| typeof property.source_path !== 'string' || !dependencies.has(property.source_path)) {
					throw new Error(`Invalid property preview on scene node: ${path}`);
				}
				names.add(property.name);
			}
		}
		for (const reference of Object.values(node.references)) {
			if (!isRecord(reference) || typeof reference.source_path !== 'string'
				|| !dependencies.has(reference.source_path) || !Array.isArray(reference.paths)
				|| !reference.paths.every(item => typeof item === 'string')) {
				throw new Error(`Invalid node reference metadata: ${path}`);
			}
		}
		for (const key of ['source_path', 'instance_path', 'base_scene_path', 'structural_scene'] as const) {
			const resource = node[key] as string;
			if (key === 'source_path' || key === 'structural_scene' || resource !== '') {
				validateResourcePath(resource, '.tscn');
				if (!dependencies.has(resource)) {
					throw new Error(`Missing scene dependency: ${resource}`);
				}
			}
		}
		if (node.script_path !== '') {
			validateResourcePath(node.script_path as string);
			if (!node.has_script) { throw new Error('Script path requires an attached script.'); }
		}
		if (node.script_source_path !== '') {
			validateResourcePath(node.script_source_path as string, '.tscn');
			if (!dependencies.has(node.script_source_path as string)) { throw new Error('Missing script declaration scene.'); }
		}
		if (node.movement_configuration_path !== '') {
			const resource = (node.movement_configuration_path as string).split('::')[0];
			validateResourcePath(resource);
		}
		if (node.movement_controller_path !== undefined) {
			if (typeof node.movement_controller_path !== 'string') { throw new Error('Invalid movement controller path.'); }
			if (node.movement_controller_path) { validateResourcePath(node.movement_controller_path.split('::')[0]); }
		}
	}
	const pending = ['.'];
	const visited = new Set<string>();
	while (pending.length > 0) {
		const path = pending.pop()!;
		const node = value.nodes[path];
		if (!isRecord(node) || visited.has(path)) {
			throw new Error(`Missing, repeated, or cyclic scene node: ${path}`);
		}
		visited.add(path);
		for (const child of node.children as string[]) {
			const parent = child.includes('/') ? child.slice(0, child.lastIndexOf('/')) : '.';
			if (child === '.' || parent !== path) {
				throw new Error(`Incorrect scene parent for: ${child}`);
			}
			pending.push(child);
		}
	}
	if (visited.size !== Object.keys(value.nodes).length) {
		throw new Error('The scene graph contains unreachable nodes.');
	}
	return value as unknown as SceneGraph;
}

function validateNodePath(value: string): void {
	if (value !== '.' && value.split('/').some(part =>
		!part || part === '.' || part === '..' || /[\\:\0]/.test(part))) {
		throw new Error(`Invalid scene node path: ${value}`);
	}
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
