import { stat, realpath } from 'node:fs/promises';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';

export interface ProjectContext {
	projectDirectory: string;
	workspaceDirectory: string;
}

export function isInside(directory: string, candidate: string): boolean {
	const remainder = relative(directory, candidate);
	return remainder === '' || (
		!isAbsolute(remainder)
		&& remainder !== '..'
		&& !remainder.startsWith(`..${sep}`)
	);
}

export async function resolveProjectContext(
	filePath: string,
	workspaceDirectories: readonly string[]
): Promise<ProjectContext> {
	if (!isAbsolute(filePath)) {
		throw new Error('Expected an absolute file path.');
	}
	const candidate = resolve(filePath);
	const roots = workspaceDirectories.map(root => resolve(root))
		.filter(root => isInside(root, candidate));
	if (roots.length === 0 || !await isFile(candidate)) {
		throw new Error('Choose an existing scene inside an opened workspace folder.');
	}
	if (relative(candidate, await realpath(candidate)) !== '') {
		throw new Error('Scene authoring does not follow symbolic links or junctions.');
	}
	let directory = dirname(candidate);
	while (roots.some(root => isInside(root, directory))) {
		if (await isFile(join(directory, 'project.godot'))) {
			if (!await isFile(join(directory, 'Framework/Env/Authoring/Scenes/Inspection/scene_graph_export.gd'))) {
				throw new Error(`The nearest Godot project has no Framework Scenes exporter: ${directory}`);
			}
			return {
				projectDirectory: directory,
				workspaceDirectory: roots.filter(root => isInside(root, directory))
					.sort((left, right) => right.length - left.length)[0]
			};
		}
		const parent = dirname(directory);
		if (parent === directory) {
			break;
		}
		directory = parent;
	}
	throw new Error(`No project.godot was found inside the workspace for: ${candidate}`);
}

export async function scenePathInProject(
	context: ProjectContext,
	filePath: string
): Promise<string> {
	if (!isAbsolute(filePath) || !filePath.endsWith('.tscn')) {
		throw new Error('Expected an absolute .tscn file path.');
	}
	const actual = await resolveProjectContext(filePath, [context.workspaceDirectory]);
	if (relative(actual.projectDirectory, context.projectDirectory) !== '') {
		throw new Error('Choose a scene from the same Godot project.');
	}
	const result = `res://${relative(context.projectDirectory, filePath).split(sep).join('/')}`;
	validateResourcePath(result, '.tscn');
	return result;
}

export function validateResourcePath(value: string, extension?: string): void {
	if (
		!value.startsWith('res://')
		|| (extension !== undefined && !value.endsWith(extension))
		|| value.slice(6).split('/').some(part =>
			!part || part === '.' || part === '..' || /[\\:\0]/.test(part)
		)
	) {
		throw new Error(`Invalid project resource path: ${value}`);
	}
}

async function isFile(filePath: string): Promise<boolean> {
	try {
		return (await stat(filePath)).isFile();
	} catch (error) {
		if (typeof error === 'object' && error !== null && 'code' in error
			&& (error.code === 'ENOENT' || error.code === 'ENOTDIR')) {
			return false;
		}
		throw error;
	}
}
