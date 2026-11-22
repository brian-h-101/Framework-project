export interface ArgumentSpec {
	name: string;
	allowed_types: string[];
	required: boolean;
	numeric: boolean;
}
export interface ExecutorDescriptor {
	id: string;
	label: string;
	description: string;
	supports_effects: boolean;
	arguments: ArgumentSpec[];
	script_path?: string;
}
export interface ExecutorSnapshot {
	hashes: Record<string, string>;
	directories: Record<string, string>;
}
export function isExecutorScriptPath(value: unknown): value is string {
	return typeof value === 'string'
		&& value.startsWith('res://')
		&& value.endsWith('.gd')
		&& value.slice(6).split('/').every(part =>
			!!part
			&& part !== '.'
			&& part !== '..'
			&& !/[\\:\0]/.test(part)
		);
}

const TYPES = ['int', 'float', 'String', 'StringName', 'bool', 'Nil', 'Array', 'Dictionary', 'Variant'];
export const argumentTypes = (spec: ArgumentSpec): string[] => spec.allowed_types.includes('Variant')
	? TYPES.filter(type => type !== 'Variant') : spec.allowed_types;
const record = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);

export function validateSpecs(value: unknown): asserts value is ArgumentSpec[] {
	if (!Array.isArray(value) || value.some(spec => !record(spec) || typeof spec.name !== 'string' || !spec.name.trim()
		|| typeof spec.required !== 'boolean' || typeof spec.numeric !== 'boolean'
		|| !Array.isArray(spec.allowed_types) || !spec.allowed_types.length
		|| spec.allowed_types.some(type => !TYPES.includes(type)) || new Set(spec.allowed_types).size !== spec.allowed_types.length
		|| (spec.allowed_types.includes('Variant') && spec.allowed_types.length !== 1))
		|| new Set(value.map(spec => spec.name)).size !== value.length) { throw new Error('Malformed executor argument metadata.'); }
}

export function validateExecutors(executors: unknown, snapshot: unknown, requireSnapshot = true): void {
	if (executors === undefined && snapshot === undefined) { return; }
	if (!Array.isArray(executors) || executors.some(entry => !record(entry) || typeof entry.id !== 'string' || !entry.id.trim()
		|| typeof entry.label !== 'string' || typeof entry.description !== 'string' || typeof entry.supports_effects !== 'boolean')
		|| new Set(executors.map(entry => entry.id)).size !== executors.length) { throw new Error('Malformed executor catalogue.'); }
	for (const entry of executors) {
		validateSpecs(entry.arguments);

		if (entry.script_path !== undefined
			&& entry.script_path !== ''
			&& !isExecutorScriptPath(entry.script_path)) {
			throw new Error('Malformed executor script path.');
		}
	}
	if (!requireSnapshot) {
		if (snapshot !== undefined) { throw new Error("Browsing metadata cannot carry a write snapshot."); }
		return;
	}
	if (!record(snapshot) || !record(snapshot.hashes) || !record(snapshot.directories)) { throw new Error('Missing executor source snapshot.'); }
	for (const [path, hash] of [...Object.entries(snapshot.hashes), ...Object.entries(snapshot.directories)]) {
		if (!path.startsWith('res://') || path.includes('\\') || path.includes('\0')
			|| path.slice(6).split('/').some(part => part === '.' || part === '..' || part.includes(':'))
			|| typeof hash !== 'string' || !/^[a-f0-9]{64}$/.test(hash)) { throw new Error('Malformed executor source snapshot.'); }
	}
}

