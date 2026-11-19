import { execFile } from 'node:child_process';

export type ConditionValueType = 'int' | 'float';

export interface ConditionComparisonEdit {
	operator: string;
	value_type: ConditionValueType;
	value_text: string;
	message: string;
}

export interface ConditionComparisonResult extends ConditionComparisonEdit {
	condition_path: string;
}

const CLI_SCRIPT =
	'res://Framework/Env/Authoring/condition_editing_cli.gd';

const RESULT_PREFIX = '[condition-editing-result] ';

export async function getConditionComparison(
	projectDirectory: string,
	godotExecutable: string,
	conditionPath: string,
	report: (message: string) => void
): Promise<ConditionComparisonResult> {
	const value = await runConditionEditing(
		projectDirectory,
		godotExecutable,
		['get-comparison', conditionPath],
		report
	);

	const operator = value.operator;
	const valueType = value.value_type;
	const valueText = value.value_text;
	const message = value.message;

	if (
		value.condition_path !== conditionPath
		|| typeof operator !== 'string'
		|| !['==', '!=', '>', '>=', '<', '<='].includes(operator)
		|| (
			valueType !== 'int'
			&& valueType !== 'float'
		)
		|| typeof valueText !== 'string'
		|| valueText.length === 0
		|| typeof message !== 'string'
	) {
		throw new Error('Malformed condition-comparison result.');
	}

	return {
		condition_path: conditionPath,
		operator,
		value_type: valueType,
		value_text: valueText,
		message
	};
}

export async function setConditionComparison(
	projectDirectory: string,
	godotExecutable: string,
	conditionPath: string,
	edit: ConditionComparisonEdit,
	report: (message: string) => void
): Promise<ConditionComparisonResult> {
	const request: ConditionComparisonEdit = { ...edit };

	const value = await runConditionEditing(
		projectDirectory,
		godotExecutable,
		[
			'set-comparison',
			conditionPath,
			request.operator,
			request.value_type,
			request.value_text,
			request.message
		],
		report
	);

	const valueType = value.value_type;
	const valueText = value.value_text;

	if (
		value.condition_path !== conditionPath
		|| value.operator !== request.operator
		|| (
			valueType !== 'int'
			&& valueType !== 'float'
		)
		|| valueType !== request.value_type
		|| typeof valueText !== 'string'
		|| valueText.length === 0
		|| value.message !== request.message
	) {
		throw new Error('Malformed condition-editing result.');
	}

	return {
		condition_path: conditionPath,
		operator: request.operator,
		value_type: valueType,
		value_text: valueText,
		message: request.message
	};
}

function runConditionEditing(
	projectDirectory: string,
	godotExecutable: string,
	userArguments: readonly string[],
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
				CLI_SCRIPT,
				'--',
				...userArguments
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
							+ 'condition-editing result.'
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
						throw new Error(
							'Invalid condition-editing response.'
						);
					}

					if (!packet.ok) {
						throw new Error(
							packet.error || 'Condition editing failed.'
						);
					}

					if (error) {
						throw error;
					}

					if (!isRecord(packet.value)) {
						throw new Error(
							'Malformed condition-editing result.'
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
