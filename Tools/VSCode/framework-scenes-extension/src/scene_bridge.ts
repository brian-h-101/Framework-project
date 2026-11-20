import { execFile } from 'node:child_process';
import { validateResourcePath } from './project_context';

export interface SceneNode {
	path: string;
	name: string;
	type: string;
	source_path: string;
	source_node_path: string;
	instance_path: string;
	base_scene_path: string;
	script_path: string;
	children: string[];
}

export interface SceneGraph {
	version: 1;
	source_path: string;
	root: '.';
	nodes: Record<string, SceneNode>;
	dependencies: string[];
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
			'--script', 'res://Framework/Env/Authoring/Scenes/scene_graph_export.gd',
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
				resolve(validateSceneGraph(packet.value, scenePath));
			} catch (failure) {
				reject(failure);
			}
		});
	});
}

export function validateSceneGraph(value: unknown, scenePath: string): SceneGraph {
	if (!isRecord(value) || value.version !== 1 || value.source_path !== scenePath
		|| value.root !== '.' || !isRecord(value.nodes)
		|| !Array.isArray(value.dependencies)) {
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
	for (const [path, node] of Object.entries(value.nodes)) {
		if (!isRecord(node) || node.path !== path
			|| !['name', 'type', 'source_path', 'source_node_path', 'instance_path',
				'base_scene_path', 'script_path'].every(key => typeof node[key] === 'string')
			|| node.name === '' || !Array.isArray(node.children)
			|| !node.children.every(child => typeof child === 'string')
			|| new Set(node.children).size !== node.children.length) {
			throw new Error(`Malformed scene node: ${path}`);
		}
		validateNodePath(path);
		validateNodePath(node.source_node_path as string);
		for (const key of ['source_path', 'instance_path', 'base_scene_path'] as const) {
			const resource = node[key] as string;
			if (key === 'source_path' || resource !== '') {
				validateResourcePath(resource, '.tscn');
				if (!dependencies.has(resource)) {
					throw new Error(`Missing scene dependency: ${resource}`);
				}
			}
		}
		if (node.script_path !== '') {
			validateResourcePath(node.script_path as string);
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
