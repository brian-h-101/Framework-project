import { execFile } from 'node:child_process';

export interface ResourceLink {
	role: string;
	target: string;
}

export interface ResourceNode {
	id: string;
	kind: string;
	source_path: string;
	links: ResourceLink[];
	operator?: string;
	value_text?: string;
}

export interface ResourceGraph {
	version: 1;
	roots: string[];
	nodes: Record<string, ResourceNode>;
}

const RESULT_PREFIX = '[resource-graph] ';

export function loadResourceGraph(
	projectDirectory: string,
	godotExecutable: string,
	report: (message: string) => void,
	resourcePath?: string
): Promise<ResourceGraph> {
	return new Promise((resolve, reject) => {
		const argumentsList = [
			'--headless',
			'--path',
			projectDirectory,
			'--script',
			'res://Framework/Env/Authoring/resource_graph_export.gd'
		];

		if (resourcePath !== undefined) {
			argumentsList.push('--', resourcePath);
		}

		execFile(
			godotExecutable,
			argumentsList,
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
							'Godot must return exactly one resource-graph result.'
						);
					}

					const packet: unknown = JSON.parse(
						lines[0].slice(RESULT_PREFIX.length)
					);

					if (!isRecord(packet)) {
						throw new Error('Invalid resource-graph response.');
					}

					if (packet.ok !== true) {
						throw new Error(
							typeof packet.error === 'string'
								? packet.error
								: 'The Godot resource exporter failed.'
						);
					}

					if (error) {
						throw error;
					}

					const graph = packet.value;

					if (
						!isRecord(graph)
						|| graph.version !== 1
						|| !Array.isArray(graph.roots)
						|| !graph.roots.every(
							(root: unknown) => typeof root === 'string'
						)
						|| !isRecord(graph.nodes)
					) {
						throw new Error(
							'Unsupported or malformed resource graph.'
						);
					}

					if (
						resourcePath !== undefined
						&& (
							graph.roots.length !== 1
							|| graph.roots[0] !== resourcePath
							|| !Object.hasOwn(graph.nodes, resourcePath)
						)
					) {
						throw new Error(
							'Selected-resource graph does not match '
							+ 'the requested resource.'
						);
					}

					resolve({
						version: 1,
						roots: graph.roots,
						nodes: graph.nodes as Record<string, ResourceNode>
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
