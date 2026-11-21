import { execFile } from 'node:child_process';
import { validateResourcePath } from './project_context';

export type SceneOperation =
	| 'add_node'
	| 'add_instance'
	| 'attach_behavior'
	| 'assign_movement'
	| 'attach_script'
	| 'remove_script'
	| 'rename'
	| 'remove';
export interface SceneEdit {
	operation: SceneOperation;
	path: string;
	expected_hashes: Record<string, string>;
	name?: string;
	node_type?: string;
	instance_scene?: string;
	interaction_resource?: string;
	automation_resource?: string;
	movement_configuration?: string;
	script_path?: string;
}
export interface SceneEditResult {
	scene_path: string;
	operation: SceneOperation;
	path: string;
	new_path: string;
	content_hash: string;
}

export interface ScriptInspection {
	script_path: string;
	base_type: string;
	dependency_hashes: Record<string, string>;
}

export async function inspectScript(project: string, executable: string, source: string, nativeType: string,
	report: (message: string) => void): Promise<ScriptInspection> {
	validateResourcePath(source, '.gd');
	const value = await run(project, executable, ['inspect-script', source, nativeType], undefined, report);
	if (!isRecord(value) || value.script_path !== source || typeof value.base_type !== 'string' || !value.base_type
		|| !isRecord(value.dependency_hashes) || !Object.hasOwn(value.dependency_hashes, source)
		|| Object.keys(value.dependency_hashes).length > 1000) { throw new Error('Malformed script inspection result.'); }
	for (const [path, hash] of Object.entries(value.dependency_hashes)) {
		validateResourcePath(path, '.gd');
		if (typeof hash !== 'string' || !/^[a-f0-9]{64}$/.test(hash)) { throw new Error('Malformed script dependency hash.'); }
	}
	return value as unknown as ScriptInspection;
}

export async function nodeTypes(project: string, executable: string,
	report: (message: string) => void): Promise<string[]> {
	const value = await run(project, executable, ['node-types'], undefined, report);
	if (!Array.isArray(value) || !value.every(item => typeof item === 'string' && item.length > 0)
		|| new Set(value).size !== value.length || value.length > 10000) {
		throw new Error('Malformed native node type catalogue.');
	}
	return value;
}

export async function editScene(project: string, executable: string, source: string,
	request: SceneEdit, report: (message: string) => void): Promise<SceneEditResult> {
	validateResourcePath(source, '.tscn');
	const value = await run(project, executable, ['edit', source], request, report);
	if (!isRecord(value) || value.scene_path !== source || value.operation !== request.operation
		|| value.path !== request.path || typeof value.new_path !== 'string'
		|| typeof value.content_hash !== 'string' || !/^[a-f0-9]{64}$/.test(value.content_hash)) {
		throw new Error('Malformed structural editing result.');
	}
	return value as unknown as SceneEditResult;
}

function run(project: string, executable: string, args: string[], request: SceneEdit | undefined,
	report: (message: string) => void): Promise<unknown> {
	const input = request === undefined ? '' : JSON.stringify(request);
	if (Buffer.byteLength(input, 'utf8') > 1024 * 1024) {
		throw new Error('Scene edit requests cannot exceed 1 MiB.');
	}
	return new Promise((resolve, reject) => {
		const child = execFile(executable, ['--headless', '--path', project,
			'--script', 'res://Framework/Env/Authoring/Scenes/scene_editing_cli.gd', '--', ...args],
		{ cwd: project, encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024 },
		(error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[scene-editing] ';
				const packets = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (packets.length !== 1) { throw error ?? new Error('Godot must return exactly one scene-editing result.'); }
				const packet: unknown = JSON.parse(packets[0].slice(prefix.length));
				if (!isRecord(packet) || typeof packet.ok !== 'boolean' || typeof packet.error !== 'string'
					|| !Object.hasOwn(packet, 'value')) { throw new Error('Malformed scene-editing response.'); }
				if (!packet.ok) { throw new Error(packet.error); }
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
					throw new Error('Godot reported a scene-editing error. See Framework Scenes output.');
				}
				resolve(packet.value);
			} catch (failure) { reject(failure); }
		});
		child.stdin?.on('error', () => { /* Process completion reports a closed pipe. */ });
		child.stdin?.end(input);
	});
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
