import { execFile } from 'node:child_process';
import { validateResourcePath } from '../workspace/project_context';
import { validateExecutors, validateSpecs, type ArgumentSpec, type ExecutorDescriptor, type ExecutorSnapshot } from '../resources/executor_metadata';

export const BEHAVIOR_ROOT = 'res://Framework/Content/Behavior';
export interface LibraryEntry {
	source_path: string;
	parent_path: string;
	name: string;
	kind: 'root' | 'folder' | 'resource' | 'blocked';
	fingerprint: string;
	supported: boolean;
	resource_kind?: 'action' | 'condition' | 'condition_group' | 'interaction' | 'automation' | '';
	id?: string;
	valid?: boolean;
	argument_specs?: ArgumentSpec[];
}
export interface LibraryCatalogue { version: 1; root_path: string; entries: LibraryEntry[];
	executors?: ExecutorDescriptor[]; executor_snapshot?: ExecutorSnapshot }
export interface ResourceDraft { source_path: string; source_text: string; content_hash: string; uid: string }
export interface DeletionPreview {
	source_path: string;
	content_hash: string;
	consumers: { source_path: string; kind: string }[];
	hashes: Record<string, string>;
	directories: Record<string, string>;
}

export function libraryRequest(project: string, executable: string, operation: 'catalogue' | 'draft' | 'deletion-preview',
	source: string | undefined, request: Record<string, unknown>, report: (message: string) => void,
	signal?: AbortSignal): Promise<unknown> {
	if (source !== undefined) { validateResourcePath(source, '.tres'); }
	const input = JSON.stringify(request);
	if (Buffer.byteLength(input) > 1024 * 1024) { throw new Error('Library requests cannot exceed 1 MiB.'); }
	return new Promise((resolve, reject) => {
		const args = ['--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Resources/behavior_library_cli.gd', '--', operation];
		if (source !== undefined) { args.push(source); }
		const child = execFile(executable, args, { cwd: project, encoding: 'utf8', windowsHide: true,
			timeout: 60_000, maxBuffer: 16 * 1024 * 1024, signal }, (error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[behavior-library] ';
				const packets = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (packets.length !== 1) { throw error ?? new Error('Godot returned no unique library result.'); }
				const packet = JSON.parse(packets[0].slice(prefix.length));
				if (packet?.ok !== true) { throw new Error(packet?.error || 'Library authoring failed.'); }
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) { throw new Error('Godot reported a library error. See Resource Condition output.'); }
				resolve(packet.value);
			} catch (failure) { reject(failure); }
		});
		child.stdin?.on('error', () => undefined);
		child.stdin?.end(input);
	});
}

export function validateCatalogue(value: unknown): LibraryCatalogue {
	const catalogue = value as LibraryCatalogue;
	if (!catalogue || catalogue.version !== 1 || catalogue.root_path !== BEHAVIOR_ROOT
		|| !Array.isArray(catalogue.entries) || catalogue.entries.length > 10001) {
		throw new Error('Malformed authored library catalogue.');
	}
	const seen = new Map<string, LibraryEntry>();
	validateExecutors(catalogue.executors, catalogue.executor_snapshot);
	for (const entry of catalogue.entries) {
		if (!entry || typeof entry.source_path !== 'string' || typeof entry.parent_path !== 'string'
			|| typeof entry.name !== 'string' || typeof entry.supported !== 'boolean'
			|| !['root', 'folder', 'resource', 'blocked'].includes(entry.kind)
			|| (entry.kind !== 'blocked' && !/^[a-f0-9]{64}$/.test(entry.fingerprint))) {
			throw new Error('Malformed authored library entry.');
		}
		validateResourcePath(entry.source_path);
		if ((entry.source_path !== BEHAVIOR_ROOT && !entry.source_path.startsWith(BEHAVIOR_ROOT + '/'))
			|| seen.has(entry.source_path) || entry.name !== entry.source_path.split('/').at(-1)) {
			throw new Error('Invalid or repeated authored library path.');
		}
		if (entry.kind === 'root') {
			if (entry.source_path !== BEHAVIOR_ROOT || entry.parent_path !== '') { throw new Error('Invalid library root.'); }
		} else {
			const parent = seen.get(entry.parent_path);
			if (!parent || !['root', 'folder'].includes(parent.kind)
				|| entry.source_path.slice(0, entry.source_path.lastIndexOf('/')) !== entry.parent_path) {
				throw new Error('Invalid library parent relationship.');
			}
		}
		if (entry.kind === 'resource' && !entry.source_path.endsWith('.tres')) { throw new Error('Invalid library resource.'); }
		if (entry.kind === 'resource' && (typeof entry.id !== 'string' || typeof entry.valid !== 'boolean'
			|| !['', 'action', 'condition', 'condition_group', 'interaction', 'automation'].includes(entry.resource_kind ?? '?')
			|| !Array.isArray(entry.argument_specs) || !entry.argument_specs.every(spec => spec && typeof spec.name === 'string'
				&& typeof spec.numeric === 'boolean'))) { throw new Error('Invalid behavior schema information.'); }
		seen.set(entry.source_path, entry);
		if (entry.argument_specs?.length) { validateSpecs(entry.argument_specs); }
	}
	if (catalogue.entries.filter(entry => entry.kind === 'root').length !== 1) { throw new Error('Missing unique library root.'); }
	return catalogue;
}
