import { execFile } from 'node:child_process';

export type ResourceKind =
	| 'action'
	| 'condition'
	| 'condition_group'
	| 'interaction'
	| 'automation';

export interface ResourceCatalogEntry {
	id: string;
	kind: ResourceKind;
	source_path: string;
}

export interface ResourceCatalog {
	version: 1;
	resources: ResourceCatalogEntry[];
}

const RESULT_PREFIX = '[resource-catalog] ';

export function loadResourceCatalog(
	projectDirectory: string,
	godotExecutable: string,
	report: (message: string) => void
): Promise<ResourceCatalog> {
	return new Promise((resolve, reject) => {
		execFile(
			godotExecutable,
			[
				'--headless',
				'--path',
				projectDirectory,
				'--script',
				'res://Framework/Env/Authoring/Resources/resource_catalog_export.gd'
			],
			{
				cwd: projectDirectory,
				encoding: 'utf8',
				windowsHide: true,
				timeout: 30_000,
				maxBuffer: 4 * 1024 * 1024
			},
			(error, stdout, stderr) => {
				try {
					if (stderr.trim()) {
						report(stderr.trim());
					}

					const lines = stdout
						.split(/\r?\n/)
						.filter(line => line.startsWith(RESULT_PREFIX));

					if (lines.length !== 1) {
						throw error ?? new Error(
							'Godot must return exactly one resource-catalog result.'
						);
					}

					const packet: unknown = JSON.parse(
						lines[0].slice(RESULT_PREFIX.length)
					);

					if (
						!isRecord(packet)
						|| typeof packet.ok !== 'boolean'
						|| typeof packet.error !== 'string'
						|| !Object.hasOwn(packet, 'value')
					) {
						throw new Error('Invalid resource-catalog response.');
					}

					if (!packet.ok) {
						throw new Error(
							packet.error || 'Resource catalogue export failed.'
						);
					}

					if (error) {
						throw error;
					}
					if (/^(SCRIPT ERROR|ERROR):/m.test(stdout + '\n' + stderr)) {
						throw new Error('Godot reported a resource catalogue error. See Framework Scenes output.');
					}

					const catalog = packet.value;

					if (
						!isRecord(catalog)
						|| catalog.version !== 1
						|| !Array.isArray(catalog.resources)
					) {
						throw new Error(
							'Unsupported or malformed resource catalogue.'
						);
					}

					const resources: ResourceCatalogEntry[] = [];
					const paths = new Set<string>();

					for (const entry of catalog.resources) {
						if (
							!isRecord(entry)
							|| typeof entry.id !== 'string'
							|| entry.id.length === 0
							|| !isResourceKind(entry.kind)
							|| !isResourcePath(entry.source_path)
						) {
							throw new Error('Malformed resource-catalog entry.');
						}

						if (paths.has(entry.source_path)) {
							throw new Error(
								`Duplicate catalogue path: ${entry.source_path}`
							);
						}

						paths.add(entry.source_path);

						resources.push({
							id: entry.id,
							kind: entry.kind,
							source_path: entry.source_path
						});
					}

					resolve({
						version: 1,
						resources
					});
				} catch (failure) {
					reject(failure);
				}
			}
		);
	});
}

function isRecord(
	value: unknown
): value is Record<string, unknown> {
	return (
		typeof value === 'object'
		&& value !== null
		&& !Array.isArray(value)
	);
}

function isResourceKind(value: unknown): value is ResourceKind {
	return (
		value === 'action'
		|| value === 'condition'
		|| value === 'condition_group'
		|| value === 'interaction'
		|| value === 'automation'
	);
}

function isResourcePath(value: unknown): value is string {
	if (
		typeof value !== 'string'
		|| !value.startsWith('res://')
		|| !value.endsWith('.tres')
	) {
		return false;
	}

	return value.slice('res://'.length).split('/').every(
		segment =>
			segment.length > 0
			&& segment !== '.'
			&& segment !== '..'
			&& !/[\\:\0]/.test(segment)
	);
}
