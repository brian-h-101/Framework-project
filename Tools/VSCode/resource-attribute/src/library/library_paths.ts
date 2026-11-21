import { lstat, realpath, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import { AUTHORED_ROOT } from '../bridges/attribute_library_bridge';
import { validateResourcePath, type ProjectContext } from '../workspace/project_context';

export function nameError(name: string): string | undefined {
	if (!name || name.length > 120 || name.startsWith('.') || /[. ]$/.test(name)) {
		return 'Use 1–120 characters without a leading dot or trailing dots/spaces.';
	}
	if (/[<>:"/\\|?*\u0000-\u001f]/.test(name)) { return 'Names cannot contain Windows path separators or reserved characters.'; }
	if (/^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)/i.test(name)) { return 'That name is reserved by Windows.'; }
	return undefined;
}

export async function checkedProjectPath(context: ProjectContext, source: string): Promise<string> {
	validateResourcePath(source);
	const root = context.projectDirectory;
	if (relative(root, await realpath(root)) !== '') { throw new Error('The project path contains a link or junction.'); }
	let current = root;
	for (const part of source.slice(6).split('/')) {
		current = join(current, part);
		const info = await lstat(current);
		if (info.isSymbolicLink() || relative(current, await realpath(current)) !== '') {
			throw new Error('Authored libraries do not follow symbolic links or junctions.');
		}
		if (info.isDirectory()) {
			try {
				await lstat(join(current, 'project.godot'));
				throw new Error('Authored operations cannot cross into another Godot project.');
			} catch (error) { if (!missing(error)) { throw error; } }
		}
	}
	return current;
}

export async function checkedAuthoredPath(context: ProjectContext, source: string, kind: 'directory' | 'file'): Promise<string> {
	if (source !== AUTHORED_ROOT && !source.startsWith(AUTHORED_ROOT + '/')) {
		throw new Error('Choose a path inside Framework/Content/Authored.');
	}
	const path = await checkedProjectPath(context, source);
	const info = await lstat(path);
	if (kind === 'directory' ? !info.isDirectory() : !info.isFile() || !source.endsWith('.tres')) {
		throw new Error('The selected authored entry changed type. Refresh and retry.');
	}
	return path;
}

export async function directoryFingerprint(path: string): Promise<string> {
	const names = await readdir(path);
	names.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
	const entries = [];
	for (const name of names) {
		const info = await lstat(join(path, name));
		entries.push([name, info.isSymbolicLink() ? 'link' : info.isDirectory() ? 'directory' : 'file']);
	}
	return sha256(Buffer.from(JSON.stringify(entries)));
}

export function sha256(bytes: Uint8Array): string { return createHash('sha256').update(bytes).digest('hex'); }
export function missing(error: unknown): boolean {
	return typeof error === 'object' && error !== null && 'code' in error && error.code === 'ENOENT';
}
