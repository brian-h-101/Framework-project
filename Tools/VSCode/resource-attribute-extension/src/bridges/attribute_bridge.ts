import { execFile } from 'node:child_process';
import { validateResourcePath } from '../workspace/project_context';

export type ValueKind = 'int' | 'float' | 'String' | 'StringName' | 'bool' | 'Nil' | 'Dictionary' | 'Array';
export interface KeySegment { kind: 'String' | 'StringName' | 'int' | 'index' | 'unsupported'; text: string }
export interface AttributeNode {
	label: string;
	kind: string;
	path: KeySegment[];
	value_text: string;
	children: AttributeNode[];
	editable: boolean;
	mutable: boolean;
	can_add: boolean;
}
export interface AttributeGraph {
	version: 1;
	source_path: string;
	content_hash: string;
	supported: boolean;
	root: AttributeNode | null;
}
export interface AttributeEdit {
	expected_hash: string;
	operation: 'set' | 'add' | 'rename' | 'remove';
	path: KeySegment[];
	key?: KeySegment;
	value_type?: ValueKind;
	value_text?: string;
}
const PREFIX = '[resource-attribute] ';

export function inspectAttributes(project: string, executable: string, source: string,
	report: (message: string) => void, signal?: AbortSignal): Promise<AttributeGraph> {
	return run(project, executable, source, undefined, report, signal);
}

export async function editAttributes(project: string, executable: string, source: string,
	edit: AttributeEdit, report: (message: string) => void): Promise<AttributeGraph> {
	const graph = await run(project, executable, source, edit, report);
	if (!graph.supported) {
		throw new Error('Editing did not return a container fragment.');
	}
	return graph;
}

function run(project: string, executable: string, source: string, edit: AttributeEdit | undefined,
	report: (message: string) => void, signal?: AbortSignal): Promise<AttributeGraph> {
	validateResourcePath(source, '.tres');
	const input = edit === undefined ? '' : JSON.stringify(edit);
	if (Buffer.byteLength(input, 'utf8') > 1024 * 1024) {
		throw new Error('Attribute edit requests cannot exceed 1 MiB.');
	}
	return new Promise((resolve, reject) => {
		const child = execFile(executable, [
			'--headless', '--path', project,
			'--script', 'res://Framework/Env/Authoring/Attributes/attribute_cli.gd',
			'--', edit === undefined ? 'inspect' : 'edit', source
		], { cwd: project, encoding: 'utf8', windowsHide: true, timeout: 30_000,
			maxBuffer: 16 * 1024 * 1024, signal }, (error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const packets = stdout.split(/\r?\n/).filter(line => line.startsWith(PREFIX));
				if (packets.length !== 1) {
					throw error ?? new Error('Godot must return exactly one attribute result.');
				}
				const packet: unknown = JSON.parse(packets[0].slice(PREFIX.length));
				if (!isRecord(packet) || typeof packet.ok !== 'boolean' || typeof packet.error !== 'string'
					|| !Object.hasOwn(packet, 'value')) {
					throw new Error('Malformed attribute bridge result.');
				}
				if (!packet.ok) { throw new Error(packet.error); }
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
					throw new Error('Godot reported an error. See Resource Attribute output.');
				}
				resolve(validateGraph(packet.value, source));
			} catch (failure) { reject(failure); }
		});
		child.stdin?.on('error', () => { /* Process completion reports a closed pipe. */ });
		child.stdin?.end(input);
	});
}

export function validateGraph(value: unknown, source: string): AttributeGraph {
	if (!isRecord(value) || value.version !== 1 || value.source_path !== source
		|| typeof value.content_hash !== 'string' || !/^[a-f0-9]{64}$/.test(value.content_hash)
		|| typeof value.supported !== 'boolean') {
		throw new Error('Unsupported or malformed attribute graph.');
	}
	validateResourcePath(source, '.tres');
	if (!value.supported) {
		if (value.root !== null) { throw new Error('Unsupported Resources cannot contain attribute trees.'); }
		return value as unknown as AttributeGraph;
	}
	let count = 0;
	function visit(node: unknown, path: KeySegment[], addressable: boolean): void {
		if (++count > 10000 || path.length > 64 || !isRecord(node)
			|| typeof node.label !== 'string' || typeof node.kind !== 'string' || !node.kind
			|| typeof node.value_text !== 'string' || !Array.isArray(node.children)
			|| !Array.isArray(node.path) || !node.path.every(validSegment)
			|| JSON.stringify(node.path) !== JSON.stringify(path)
			|| typeof node.editable !== 'boolean' || typeof node.mutable !== 'boolean'
			|| typeof node.can_add !== 'boolean') {
			throw new Error('Malformed or oversized attribute tree.');
		}
		const collection = node.kind === 'Dictionary' || node.kind === 'Array';
		const scalar = ['int', 'float', 'String', 'StringName', 'bool', 'Nil'].includes(node.kind);
		if (node.mutable !== (addressable && path.length > 0)
			|| node.can_add !== (addressable && collection)
			|| (node.editable && (!addressable || path.length < 2 || !scalar))
			|| (!collection && node.children.length > 0)
			|| (path.length === 0 && node.kind !== 'Dictionary')) {
			throw new Error('Invalid attribute capabilities.');
		}
		const seen = new Set<string>();
		for (const [index, child] of node.children.entries()) {
			if (!isRecord(child) || !Array.isArray(child.path) || child.path.length !== path.length + 1) {
				throw new Error('Invalid attribute child path.');
			}
			const part: unknown = child.path.at(-1);
			if (!validSegment(part) || seen.has(JSON.stringify(part))
				|| (node.kind === 'Array' && (part.kind !== 'index' || part.text !== String(index)))
				|| (node.kind === 'Dictionary' && part.kind === 'index')) {
				throw new Error('Invalid or repeated attribute key.');
			}
			seen.add(JSON.stringify(part));
			visit(child, [...path, part], addressable && part.kind !== 'unsupported');
		}
	}
	visit(value.root, [], true);
	return value as unknown as AttributeGraph;
}

export function validSegment(value: unknown): value is KeySegment {
	return isRecord(value) && ['String', 'StringName', 'int', 'index', 'unsupported'].includes(String(value.kind))
		&& typeof value.text === 'string';
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
