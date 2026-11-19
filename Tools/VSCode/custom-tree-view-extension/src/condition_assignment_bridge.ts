import { execFile } from 'node:child_process';

export interface ConditionAssignmentResult {
	group_path: string;
	condition_path: string;
	condition_count: number;
}

export interface InteractionRequirementsResult {
	interaction_path: string;
	group_path: string;
}

export interface InteractionActionResult {
	interaction_path: string;
	action_path: string;
}

export interface InteractionSourceResult {
	interaction_path: string;
	source_path: string;
	kind: 'action' | 'condition_group';
}

type AssignmentOperation =
	| 'add-condition'
	| 'set-requirements'
	| 'set-action'
	| 'resolve-interaction-source';

const RESULT_PREFIX = '[condition-assignment-result] ';

export async function addConditionToGroup(
	projectDirectory: string,
	godotExecutable: string,
	groupPath: string,
	conditionPath: string,
	report: (message: string) => void
): Promise<ConditionAssignmentResult> {
	const value = await runAssignment(
		projectDirectory,
		godotExecutable,
		'add-condition',
		groupPath,
		conditionPath,
		report
	);

	if (
		value.group_path !== groupPath
		|| value.condition_path !== conditionPath
		|| typeof value.condition_count !== 'number'
		|| !Number.isInteger(value.condition_count)
		|| value.condition_count < 1
	) {
		throw new Error('Malformed condition-assignment result.');
	}

	return {
		group_path: groupPath,
		condition_path: conditionPath,
		condition_count: value.condition_count
	};
}

export async function setInteractionRequirements(
	projectDirectory: string,
	godotExecutable: string,
	interactionPath: string,
	groupPath: string,
	report: (message: string) => void
): Promise<InteractionRequirementsResult> {
	const value = await runAssignment(
		projectDirectory,
		godotExecutable,
		'set-requirements',
		interactionPath,
		groupPath,
		report
	);

	if (
		value.interaction_path !== interactionPath
		|| value.group_path !== groupPath
	) {
		throw new Error('Malformed interaction-requirements result.');
	}

	return {
		interaction_path: interactionPath,
		group_path: groupPath
	};
}

export async function setInteractionAction(
	projectDirectory: string,
	godotExecutable: string,
	interactionPath: string,
	actionPath: string,
	report: (message: string) => void
): Promise<InteractionActionResult> {
	const value = await runAssignment(
		projectDirectory,
		godotExecutable,
		'set-action',
		interactionPath,
		actionPath,
		report
	);

	if (
		value.interaction_path !== interactionPath
		|| value.action_path !== actionPath
	) {
		throw new Error('Malformed interaction-action result.');
	}

	return {
		interaction_path: interactionPath,
		action_path: actionPath
	};
}

export async function resolveInteractionSource(
	projectDirectory: string,
	godotExecutable: string,
	interactionPath: string,
	sourcePath: string,
	report: (message: string) => void
): Promise<InteractionSourceResult> {
	const value = await runAssignment(
		projectDirectory,
		godotExecutable,
		'resolve-interaction-source',
		interactionPath,
		sourcePath,
		report
	);

	const kind = value.kind;

	if (
		value.interaction_path !== interactionPath
		|| value.source_path !== sourcePath
		|| (
			kind !== 'action'
			&& kind !== 'condition_group'
		)
	) {
		throw new Error('Malformed interaction-source result.');
	}

	return {
		interaction_path: interactionPath,
		source_path: sourcePath,
		kind
	};
}

function runAssignment(
	projectDirectory: string,
	godotExecutable: string,
	operation: AssignmentOperation,
	destinationPath: string,
	sourcePath: string,
	report: (message: string) => void
): Promise<Record<string, unknown>> {
	return new Promise<Record<string, unknown>>((resolve, reject) => {
		execFile(
			godotExecutable,
			[
				'--headless',
				'--path',
				projectDirectory,
				'--script',
				'res://Framework/Env/Authoring/condition_assignment_cli.gd',
				'--',
				operation,
				destinationPath,
				sourcePath
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
							'Godot must return exactly one '
							+ 'condition-assignment result.'
						);
					}

					const packet: unknown = JSON.parse(
						lines[0].slice(RESULT_PREFIX.length)
					);

					if (
						!isRecord(packet)
						|| typeof packet.ok !== 'boolean'
						|| typeof packet.error !== 'string'
					) {
						throw new Error(
							'Invalid condition-assignment response.'
						);
					}

					if (!packet.ok) {
						throw new Error(
							packet.error || 'Condition assignment failed.'
						);
					}

					if (error) {
						throw error;
					}

					if (!isRecord(packet.value)) {
						throw new Error(
							'Malformed condition-assignment result.'
						);
					}

					resolve(packet.value);
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
