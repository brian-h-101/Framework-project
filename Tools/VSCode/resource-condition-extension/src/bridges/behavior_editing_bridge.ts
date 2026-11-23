import { execFile } from 'node:child_process';
import type { ExecutorSnapshot } from '../resources/executor_metadata';
import type { ConfigurationFieldType } from './configuration_types';

export interface DataPathPart {
	kind: 'String' | 'StringName' | 'int' | 'index' | 'unsupported';
	text: string;
}

export interface SequenceRow { role: string; step_id: string; [key: string]: unknown }

export interface ValueNode {
	layout_path?: string;
	sequence?: SequenceRow;
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
	action?: string;
	key_codes?: string[];
	movement_behavior_path?: string;
	velocity_step_id?: string;
	input_actions?: Record<string, string>;
	controller_kind?: 'keyboard' | 'ai';
	targeting?: string;
	distance_unit?: string;
	stopping_distance?: number;
	pixels_per_unit?: number;
	expected_parent?: string;
	type_id?: string;
	type_label?: string;
	type_fields?: { name: string; type: ConfigurationFieldType; value_text: string }[];
	configuration_schema_path?: string;
	configuration_values?: Record<string, string>;
	presentation_preset?: boolean;
	fragment_paths?: string[];
	step_id?: string;
	new_id?: string;
	step_kind?: string;
	label?: string;
	direction?: number;
	field?: string;
	executor_id?: string;
	arguments?: {name: string; value_type: string; value_text: string}[];
	condition_id?: string;
	requirement?: Record<string, unknown>;
	operation: string;
	expected_hashes: Record<string, string>;
	catalog_paths: string[];
	catalog_seed: string;
	executor_snapshot?: ExecutorSnapshot;
	behavior_id?: string;
	interaction_path?: string;
	role?: string;
	target_path?: string;
	path?: DataPathPart[];
	key?: DataPathPart;
	value_type?: string;
	value_text?: string;
	condition_index?: number;
	condition_path?: string;
	effect?: Record<string, unknown>;
}

interface EditResult {
	source_path: string;
	content_hash: string;
	source_text?: unknown;
	uid?: unknown;
}

export async function draftConfiguration(
	project: string,
	executable: string,
	source: string,
	request: BehaviorEdit,
	report: (message: string) => void
): Promise<{ source_path: string; content_hash: string; source_text: string; uid: string }> {
	const result = await editBehavior(project, executable, source, request, report);
	if (typeof result.source_text !== 'string' || Buffer.byteLength(result.source_text, 'utf8') > 1024 * 1024
		|| typeof result.uid !== 'string' || !/^uid:\/\/[a-z0-9]+$/.test(result.uid)
		|| !result.source_text.split(/\r?\n/, 1)[0].includes(`uid="${result.uid}"`)) {
		throw new Error('Godot returned an invalid configuration draft.');
	}
	return { ...result, source_text: result.source_text, uid: result.uid };
}

export function editBehavior(
	project: string,
	executable: string,
	source: string,
	request: BehaviorEdit,
	report: (message: string) => void
): Promise<EditResult> {
	const input = JSON.stringify(request);
	if (Buffer.byteLength(input) > 1024 * 1024) {
		return Promise.reject(new Error('The editing request exceeds 1 MiB.'));
	}
	return new Promise((resolve, reject) => {
		const child = execFile(executable, [
			'--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Resources/Behavior/behavior_editing_cli.gd',
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
