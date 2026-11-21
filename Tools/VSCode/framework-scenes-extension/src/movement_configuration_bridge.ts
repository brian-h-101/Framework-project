import { execFile } from 'node:child_process';
import { validateResourcePath } from './project_context';

export interface MovementConfigurationEntry {
	source_path: string;
	action_id: string;
	behavior_id: string;
	dependency_hashes: Record<string, string>;
}

export function validateMovementConfigurations(value: unknown): MovementConfigurationEntry[] {
	if (!isRecord(value) || value.version !== 1 || !Array.isArray(value.configurations)
		|| value.configurations.length > 10000) {
		throw new Error('Malformed movement configuration catalogue.');
	}
	const paths = new Set<string>();
	return value.configurations.map(entry => {
		if (!isRecord(entry) || typeof entry.source_path !== 'string'
			|| !entry.source_path.startsWith('res://Framework/Content/Configuration/')
			|| typeof entry.action_id !== 'string' || !entry.action_id.trim()
			|| typeof entry.behavior_id !== 'string' || !entry.behavior_id.trim()
			|| !isRecord(entry.dependency_hashes) || Object.keys(entry.dependency_hashes).length > 1000) {
			throw new Error('Malformed movement configuration entry.');
		}
		validateResourcePath(entry.source_path, '.tres');
		if (paths.has(entry.source_path) || !Object.hasOwn(entry.dependency_hashes, entry.source_path)) {
			throw new Error('Duplicate or unguarded movement configuration.');
		}
		paths.add(entry.source_path);
		const hashes: Record<string, string> = {};
		for (const [source, hash] of Object.entries(entry.dependency_hashes)) {
			validateResourcePath(source);
			if (!/\.(gd|tres)$/.test(source) || typeof hash !== 'string' || !/^[a-f0-9]{64}$/.test(hash)) {
				throw new Error('Malformed movement dependency hash.');
			}
			hashes[source] = hash;
		}
		return { source_path: entry.source_path, action_id: entry.action_id,
			behavior_id: entry.behavior_id, dependency_hashes: hashes };
	}).sort((left, right) => left.source_path.localeCompare(right.source_path));
}

export function loadMovementConfigurations(project: string, executable: string,
	report: (message: string) => void): Promise<MovementConfigurationEntry[]> {
	return new Promise((resolve, reject) => {
		execFile(executable, ['--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Scenes/movement_configuration_catalog_export.gd'],
		{ cwd: project, encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024 },
		(error, stdout, stderr) => {
			try {
				if (stderr.trim()) { report(stderr.trim()); }
				const prefix = '[movement-configurations] ';
				const packets = stdout.split(/\r?\n/).filter(line => line.startsWith(prefix));
				if (packets.length !== 1) { throw error ?? new Error('Expected one movement configuration response.'); }
				const packet: unknown = JSON.parse(packets[0].slice(prefix.length));
				if (!isRecord(packet) || typeof packet.ok !== 'boolean' || typeof packet.error !== 'string'
					|| !Object.hasOwn(packet, 'value')) { throw new Error('Malformed movement configuration response.'); }
				if (!packet.ok) { throw new Error(packet.error); }
				if (error) { throw error; }
				if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
					throw new Error('Godot reported a movement catalogue error. See Framework Scenes output.');
				}
				resolve(validateMovementConfigurations(packet.value));
			} catch (failure) { reject(failure); }
		});
	});
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
