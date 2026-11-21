import { execFile } from 'node:child_process';
import type { ExecutorSnapshot } from '../resources/executor_metadata';

export interface DataPathPart {
	kind: 'String' | 'StringName' | 'int' | 'index' | 'unsupported';
	text: string;
}

export interface ValueNode {
	label: string;
	kind: string;
	path: DataPathPart[];
	value_text: string;
	children: ValueNode[];
	editable: boolean;
	mutable: boolean;
	can_add: boolean;
	can_rename: boolean;
	can_remove: boolean;
	can_add_effect: boolean;
	allowed_types: string[];
	choices: string[];
}

export interface BehaviorEdit {
	operation: string;
	expected_hashes: Record<string, string>;
	catalog_paths: string[];
	catalog_seed: string;
	executor_snapshot?: ExecutorSnapshot;
	behavior_id?: string;
	interaction_path?: string;
	path?: DataPathPart[];
	key?: DataPathPart;
	value_type?: string;
	value_text?: string;
	condition_index?: number;
	condition_path?: string;
	effect?: Record<string, unknown>;
}

export function editBehavior(
	project: string,
	executable: string,
	source: string,
	request: BehaviorEdit,
	report: (message: string) => void
): Promise<{ source_path: string; content_hash: string }> {
	const input = JSON.stringify(request);
	if (Buffer.byteLength(input) > 1024 * 1024) {
		return Promise.reject(new Error('The editing request exceeds 1 MiB.'));
	}
	return new Promise((resolve, reject) => {
		const child = execFile(executable, [
			'--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Resources/behavior_editing_cli.gd',
			'--', source
		], {
			cwd: project, encoding: 'utf8', windowsHide: true,
			timeout: 30_000, maxBuffer: 4 * 1024 * 1024
		}, (error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[behavior-editing] ';
				const lines = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (lines.length !== 1) {
					throw error ?? new Error('Godot returned no unique behavior-editing result.');
				}
				const packet = JSON.parse(lines[0].slice(prefix.length));
				if (packet?.ok !== true) {
					throw new Error(packet?.error || 'Behavior editing failed.');
				}
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stderr + '\n' + stdout)) {
					throw new Error('Godot reported an error during behavior editing.');
				}
				if (packet.value?.source_path !== source
					|| !/^[a-f0-9]{64}$/.test(packet.value?.content_hash ?? '')) {
					throw new Error('Malformed behavior-editing result.');
				}
				resolve(packet.value);
			} catch (failure) { reject(failure); }
		});
		child.stdin?.on('error', () => undefined);
		child.stdin?.end(input);
	});
}
