import { lstat, mkdir, open, readdir, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { libraryRequest, validateCatalogue, type LibraryCatalogue, type LibraryEntry,
	type SceneDraft, type DeletionPreview, SCENE_ROOTS } from './scene_library_bridge';
import { loadSceneGraph } from '../scene_bridge';
import type { ProjectContext } from '../project_context';
import { checkedLibraryPath, checkedProjectPath, directoryFingerprint, nameError, sha256 } from './library_paths';

export class LibraryService {
	constructor(readonly context: ProjectContext, readonly executable: string,
		private readonly report: (message: string) => void,
		private readonly ready: (deleting?: boolean) => Promise<void> = async () => undefined) {}

	async catalogue(signal?: AbortSignal): Promise<LibraryCatalogue> {
		return validateCatalogue(await libraryRequest(this.context.projectDirectory, this.executable,
			'catalogue', undefined, {}, this.report, signal));
	}

	private async parent(entry: LibraryEntry, name: string): Promise<string> {
		const error = nameError(name);
		if (error) { throw new Error(error); }
		if (!['root', 'folder'].includes(entry.kind)) { throw new Error('Choose a scene category.'); }
		await this.ready();
		const path = await checkedLibraryPath(this.context, entry.source_path, 'directory');
		if (await directoryFingerprint(path) !== entry.fingerprint) { throw new Error('The parent directory changed. Refresh and retry.'); }
		if ((await readdir(path)).some(sibling => sibling.toLowerCase() === name.toLowerCase())) {
			throw new Error('A file or category with that name already exists.');
		}
		return path;
	}

	async createCategory(entry: LibraryEntry, name: string): Promise<string> {
		await this.parent(entry, name);
		await this.ready();
		const parent = await this.parent(entry, name);
		await mkdir(join(parent, name));
		return entry.source_path + '/' + name;
	}

	async createScene(entry: LibraryEntry, name: string, request: Record<string, unknown>, catalogue: LibraryCatalogue): Promise<string> {
		if (!name.endsWith('.tscn')) { throw new Error('Use a .tscn filename.'); }
		await this.parent(entry, name);
		const source = entry.source_path + '/' + name;
		const draft = await libraryRequest(this.context.projectDirectory, this.executable, 'draft', source,
			{ ...request, expected_parent: entry.fingerprint }, this.report) as SceneDraft;
		if (!draft || draft.source_path !== source || typeof draft.source_text !== 'string'
			|| Buffer.byteLength(draft.source_text) > 1024 * 1024 || sha256(Buffer.from(draft.source_text)) !== draft.content_hash
			|| typeof draft.node_name !== 'string' || draft.node_name !== request.node_name || typeof draft.root_type !== 'string'
			|| !draft.dependency_hashes || typeof draft.dependency_hashes !== 'object' || Array.isArray(draft.dependency_hashes)
			|| !/^uid:\/\/[a-z0-9]+$/.test(draft.uid) || !draft.source_text.split(/\r?\n/)[0].includes(`uid="${draft.uid}"`)) {
			throw new Error('Godot returned an invalid scene draft.');
		}
		await this.ready();
		await this.verifyCatalogue(catalogue);
		for (const [dependency, expected] of Object.entries(draft.dependency_hashes ?? {})) {
			const file = await checkedProjectPath(this.context, dependency);
			if (!/^[a-f0-9]{64}$/.test(expected) || sha256(await readFile(file)) !== expected) {
				throw new Error('A scene template dependency changed. Retry creation.');
			}
		}
		const parent = await this.parent(entry, name);
		const path = join(parent, name);
		const handle = await open(path, 'wx');
		const owned = await handle.stat();
		try {
			await handle.writeFile(draft.source_text, 'utf8');
			await handle.sync();
		} catch (error) {
			await handle.close();
			const current = await lstat(path);
			if (current.ino === owned.ino && current.dev === owned.dev && !current.isSymbolicLink()) { await unlink(path); }
			throw error;
		}
		await handle.close();
		try {
			const graph = await loadSceneGraph(this.context.projectDirectory, this.executable, source, this.report);
			if (graph.dependency_hashes[source] !== draft.content_hash || graph.nodes['.'].name !== draft.node_name
				|| graph.nodes['.'].type !== draft.root_type) { throw new Error('The newly published scene failed verification.'); }
			await this.ready();
		} catch (error) {
			const current = await lstat(path);
			if (!current.isSymbolicLink() && current.ino === owned.ino && current.dev === owned.dev
				&& sha256(await readFile(path)) === draft.content_hash) { await unlink(path); }
			throw error;
		}
		return source;
	}

	private async verifyCatalogue(catalogue: LibraryCatalogue): Promise<void> {
		for (const entry of catalogue.entries) {
			if (entry.kind === 'blocked') { continue; }
			const path = await checkedLibraryPath(this.context, entry.source_path, entry.kind === 'resource' ? 'file' : 'directory');
			const hash = entry.kind === 'resource' ? sha256(await readFile(path)) : await directoryFingerprint(path);
			if (hash !== entry.fingerprint) { throw new Error('The Scene library changed. Refresh and retry.'); }
		}
	}

	async previewDeletion(entry: LibraryEntry): Promise<DeletionPreview> {
		if (entry.kind !== 'resource' || !entry.supported) { throw new Error('Choose a scene.'); }
		await this.ready(true);
		const path = await checkedLibraryPath(this.context, entry.source_path, 'file');
		if (sha256(await readFile(path)) !== entry.fingerprint) { throw new Error('The scene changed. Refresh and retry.'); }
		const preview = await libraryRequest(this.context.projectDirectory, this.executable, 'deletion-preview',
			entry.source_path, { expected_hash: entry.fingerprint }, this.report) as DeletionPreview;
		if (!preview || preview.source_path !== entry.source_path || preview.content_hash !== entry.fingerprint
			|| !Array.isArray(preview.consumers) || !preview.hashes || !preview.directories
			|| preview.hashes[entry.source_path] !== entry.fingerprint) { throw new Error('Invalid dependency inspection result.'); }
		return preview;
	}

	async deleteScene(entry: LibraryEntry, preview: DeletionPreview, trash: (path: string) => Promise<void>): Promise<void> {
		if (entry.kind !== 'resource' || !entry.supported || preview.source_path !== entry.source_path
			|| preview.content_hash !== entry.fingerprint) { throw new Error('The deletion selection changed. Refresh and retry.'); }
		if (preview.consumers.length) { throw new Error('This scene is still referenced. Unassign it from its consumers first.'); }
		await this.ready(true);
		for (const [source, expected] of Object.entries(preview.hashes)) {
			const path = await checkedProjectPath(this.context, source);
			if (!/^[a-f0-9]{64}$/.test(expected) || sha256(await readFile(path)) !== expected) {
				throw new Error('Project references changed. Run Delete Scene again.');
			}
		}
		for (const [source, expected] of Object.entries(preview.directories)) {
			const path = source === 'res://' ? this.context.projectDirectory : await checkedProjectPath(this.context, source);
			if (await directoryFingerprint(path) !== expected) { throw new Error(`Project directories changed: ${source}. Run Delete Scene again.`); }
		}
		const path = await checkedLibraryPath(this.context, entry.source_path, 'file');
		await this.ready(true);
		if (sha256(await readFile(path)) !== entry.fingerprint) { throw new Error('The scene changed. Refresh and retry.'); }
		await trash(path);
	}

	async deleteEmptyCategory(entry: LibraryEntry, trash: (path: string) => Promise<void>): Promise<void> {
		if (entry.kind !== 'folder' || SCENE_ROOTS.some(root => entry.source_path === root)) { throw new Error('Scene library roots cannot be deleted.'); }
		await this.ready(true);
		const path = await checkedLibraryPath(this.context, entry.source_path, 'directory');
		if ((await readdir(path)).length || await directoryFingerprint(path) !== entry.fingerprint) {
			throw new Error('Only an unchanged, empty category can be deleted.');
		}
		await this.ready(true);
		if ((await readdir(path)).length) { throw new Error('The category is no longer empty.'); }
		await trash(path);
	}
}
