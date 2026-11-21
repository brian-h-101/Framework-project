import { execFile } from 'node:child_process';
import type { ValueNode } from './behavior_editing_bridge';
import { validateExecutors, validateSpecs, type ArgumentSpec, type ExecutorDescriptor, type ExecutorSnapshot } from '../resources/executor_metadata';

export interface ResourceLink {
	role: string;
	target: string;
	index: number;
}

export interface ResourceNode {
	id: string;
	kind: string;
	source_path: string;
	content_hash: string;
	links: ResourceLink[];
	data: ValueNode;
	operator?: string;
	value_text?: string;
	behavior_id?: string;
	supports_effects?: boolean;
	behavior_error?: string;
	argument_specs?: ArgumentSpec[];
}

export interface ResourceGraph {
	version: 2;
	supported?: boolean;
	source_path?: string;
	roots: string[];
	nodes: Record<string, ResourceNode>;
	dependency_hashes: Record<string, string>;
	catalog_paths: string[];
	executors?: ExecutorDescriptor[];
	executor_snapshot?: ExecutorSnapshot;
}

export function validateGraph(value: unknown): asserts value is ResourceGraph {
	if (!isRecord(value) || value.version !== 2
		|| !Array.isArray(value.roots) || !value.roots.every(isPath)
		|| (value.supported !== undefined && typeof value.supported !== 'boolean')
		|| (value.source_path !== undefined && !isPath(value.source_path))
		|| new Set(value.roots).size !== value.roots.length
		|| !isRecord(value.nodes) || !isRecord(value.dependency_hashes)
		|| !Array.isArray(value.catalog_paths) || !value.catalog_paths.every(isPath)) {
		throw new Error('Unsupported or malformed resource graph.');
	}
	for (const [path, hash] of Object.entries(value.dependency_hashes)) {
		if (!isPath(path) || typeof hash !== 'string' || !/^[a-f0-9]{64}$/.test(hash)) {
			throw new Error('Malformed resource dependency hashes.');
		}
	}
	validateExecutors(value.executors, value.executor_snapshot);
	if (value.supported === false && (!isPath(value.source_path)
		|| value.roots.length !== 0 || Object.keys(value.nodes).length !== 0 || value.catalog_paths.length !== 0
		|| Object.keys(value.dependency_hashes).length !== 1 || !Object.hasOwn(value.dependency_hashes, value.source_path))) {
		throw new Error('An unsupported Resource must return an empty, source-scoped graph.');
	}
	for (const [path, node] of Object.entries(value.nodes)) {
		if (!isPath(path) || !isRecord(node) || node.source_path !== path
			|| typeof node.id !== 'string'
			|| !['action', 'interaction', 'condition', 'condition_group', 'automation'].includes(String(node.kind))
			|| node.content_hash !== value.dependency_hashes[path]
			|| !Array.isArray(node.links)) {
			throw new Error(`Malformed resource node: ${path}`);
		}
		for (const link of node.links) {
			if (!isRecord(link) || !['action', 'requirements', 'condition', 'interaction'].includes(String(link.role))
				|| !isPath(link.target) || !Object.hasOwn(value.nodes, link.target)
				|| !Number.isInteger(link.index)) {
				throw new Error(`Malformed resource link: ${path}`);
			}
		}
		validateValueNode(node.data, 0, { count: 0 });
		if ((node.behavior_id !== undefined && typeof node.behavior_id !== 'string')
			|| (node.supports_effects !== undefined && typeof node.supports_effects !== 'boolean')
			|| (node.behavior_error !== undefined && typeof node.behavior_error !== 'string')) { throw new Error('Malformed action behavior metadata.'); }
		if (node.argument_specs !== undefined) { validateSpecs(node.argument_specs); }
		if ((node.kind === 'condition' || node.kind === 'condition_group')
			&& typeof node.operator !== 'string') {
			throw new Error(`Missing condition operator: ${path}`);
		}
		if (node.kind === 'condition' && typeof node.value_text !== 'string') {
			throw new Error(`Missing comparison value: ${path}`);
		}
	}
	for (const path of [...value.roots, ...value.catalog_paths]) {
		if (!Object.hasOwn(value.dependency_hashes, path)) {
			throw new Error(`Missing inspected file hash: ${path}`);
		}
	}
	for (const root of value.roots) {
		if (!Object.hasOwn(value.nodes, root)) { throw new Error(`Missing root: ${root}`); }
	}
}

function validateValueNode(node: unknown, depth: number, state: { count: number }): void {
	if (++state.count > 10_000 || depth > 64 || !isRecord(node)
		|| typeof node.label !== 'string' || typeof node.kind !== 'string'
		|| typeof node.value_text !== 'string' || !Array.isArray(node.path)
		|| !node.path.every(part => isRecord(part) && typeof part.text === 'string'
			&& ['String', 'StringName', 'int', 'index', 'unsupported'].includes(String(part.kind)))
		|| !Array.isArray(node.children)
		|| !['editable', 'mutable', 'can_add', 'can_rename', 'can_remove', 'can_add_effect']
			.every(key => typeof node[key] === 'boolean')
		|| !Array.isArray(node.allowed_types) || !node.allowed_types.every(item => typeof item === 'string')
		|| !Array.isArray(node.choices) || !node.choices.every(item => typeof item === 'string')) {
		throw new Error('Malformed behavior data tree.');
	}
	for (const child of node.children) { validateValueNode(child, depth + 1, state); }
}

export function isPath(value: unknown): value is string {
	return typeof value === 'string' && value.startsWith('res://') && value.endsWith('.tres')
		&& value.slice(6).split('/').every(part => !!part && part !== '.' && part !== '..'
			&& !/[\\:\0]/.test(part));
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function loadResourceGraph(
	projectDirectory: string,
	godotExecutable: string,
	report: (message: string) => void,
	resourcePath?: string
): Promise<ResourceGraph> {
	return new Promise((resolve, reject) => {
		const args = ['--headless', '--path', projectDirectory, '--script',
			'res://Framework/Env/Authoring/Resources/resource_graph_export.gd'];
		if (resourcePath !== undefined) { args.push('--', resourcePath); }
		execFile(godotExecutable, args, {
			cwd: projectDirectory, encoding: 'utf8', windowsHide: true,
			timeout: 30_000, maxBuffer: 16 * 1024 * 1024
		}, (error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[resource-graph] ';
				const lines = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (lines.length !== 1) {
					throw error ?? new Error('Godot must return exactly one resource-graph result.');
				}
				const packet = JSON.parse(lines[0].slice(prefix.length));
				if (packet?.ok !== true) {
					throw new Error(packet?.error || 'The Godot resource exporter failed.');
				}
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stderr + '\n' + stdout)) {
					throw new Error('Godot reported an error during resource inspection.');
				}
				validateGraph(packet.value);
				if (resourcePath !== undefined && (packet.value.supported === false
					? packet.value.source_path !== resourcePath
					: packet.value.roots.length !== 1 || packet.value.roots[0] !== resourcePath)) {
					throw new Error('Selected-resource graph does not match the requested resource.');
				}
				resolve(packet.value);
			} catch (failure) { reject(failure); }
		});
	});
}
