import { stat } from 'node:fs/promises';
import {
	dirname,
	isAbsolute,
	join,
	relative,
	resolve,
	sep
} from 'node:path';

export interface ProjectContext {
	projectDirectory: string;
	workspaceDirectory: string;
}

export async function resolveProjectContext(
	filePath: string,
	workspaceDirectories: readonly string[]
): Promise<ProjectContext> {
	if (!isAbsolute(filePath)) {
		throw new Error('Expected an absolute file path.');
	}

	const resourcePath = resolve(filePath);

	const roots = workspaceDirectories
		.map(directory => resolve(directory))
		.filter(directory => isInside(directory, resourcePath));

	if (roots.length === 0) {
		throw new Error(
			'Choose a file inside an opened workspace folder.'
		);
	}

	if (!await isFile(resourcePath)) {
		throw new Error(`Expected an existing file: ${resourcePath}`);
	}

	let directory = dirname(resourcePath);

	while (roots.some(root => isInside(root, directory))) {
		const projectFile = join(directory, 'project.godot');

		if (await isFile(projectFile)) {
			const exporter = join(
				directory,
				'Framework',
				'Env',
				'Authoring',
				'Resources',
				'Inspection',
				'resource_graph_export.gd'
			);

			if (!await isFile(exporter)) {
				throw new Error(
					'The nearest Godot project has no Framework Resources '
					+ `exporter: ${directory}`
				);
			}

			const workspaceDirectory = roots
				.filter(root => isInside(root, directory))
				.sort((left, right) => right.length - left.length)[0];

			return {
				projectDirectory: directory,
				workspaceDirectory
			};
		}

		const parent = dirname(directory);

		if (parent === directory) {
			break;
		}

		directory = parent;
	}

	throw new Error(
		`No project.godot was found inside the workspace for: ${resourcePath}`
	);
}

export async function resourcePathInProject(
	context: ProjectContext,
	filePath: string
): Promise<string> {
	if (!isAbsolute(filePath) || !filePath.endsWith('.tres')) {
		throw new Error('Expected an absolute .tres file path.');
	}

	const resourcePath = resolve(filePath);

	const projectError =
		'Choose a resource from the same Godot project as the destination.';

	if (!isInside(context.projectDirectory, resourcePath)) {
		throw new Error(projectError);
	}

	const actualContext = await resolveProjectContext(
		resourcePath,
		[context.workspaceDirectory]
	);

	if (
		relative(
			context.projectDirectory,
			actualContext.projectDirectory
		) !== ''
	) {
		throw new Error(projectError);
	}

	const relativePath = relative(
		context.projectDirectory,
		resourcePath
	).split(sep).join('/');

	if (
		relativePath.split('/').some(segment =>
			!segment
			|| segment === '.'
			|| segment === '..'
			|| /[\\:\0]/.test(segment)
		)
	) {
		throw new Error('Expected a project-relative .tres resource.');
	}

	return `res://${relativePath}`;
}

export function isInside(directory: string, candidate: string): boolean {
	const remainingPath = relative(directory, candidate);

	return (
		remainingPath === ''
		|| (
			!isAbsolute(remainingPath)
			&& remainingPath !== '..'
			&& !remainingPath.startsWith(`..${sep}`)
		)
	);
}

export function validateResourcePath(source: string, extension?: string): void {
	if (!source.startsWith('res://') || (extension && !source.endsWith(extension))
		|| source.slice(6).split('/').some(part => !part || part === '.' || part === '..' || /[\\:\0]/.test(part))) {
		throw new Error('Expected a canonical project-relative resource path.');
	}
}

async function isFile(filePath: string): Promise<boolean> {
	try {
		return (await stat(filePath)).isFile();
	} catch (error) {
		if (
			typeof error === 'object'
			&& error !== null
			&& 'code' in error
			&& (
				error.code === 'ENOENT'
				|| error.code === 'ENOTDIR'
			)
		) {
			return false;
		}

		throw error;
	}
}
