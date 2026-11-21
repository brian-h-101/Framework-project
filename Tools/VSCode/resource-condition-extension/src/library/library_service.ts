import { lstat, mkdir, open, readdir, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { libraryRequest, validateCatalogue, type LibraryCatalogue, type LibraryEntry,
	type ResourceDraft, type DeletionPreview, BEHAVIOR_ROOT } from '../bridges/behavior_library_bridge';
import { loadResourceGraph } from '../bridges/resource_bridge';
import type { ProjectContext } from '../workspace/project_context';
import { checkedBehaviorPath, checkedProjectPath, directoryFingerprint, nameError, sha256 } from './library_paths';

export class LibraryService {
	constructor(readonly context: ProjectContext, private readonly executable: string,
		private readonly report: (message: string) => void,
		private readonly ready: (deleting?: boolean) => Promise<void> = async () => undefined) {}

	async catalogue(signal?: AbortSignal): Promise<LibraryCatalogue> {
		return validateCatalogue(await libraryRequest(this.context.projectDirectory, this.executable,
			'catalogue', undefined, {}, this.report, signal));
	}

	private async parent(entry: LibraryEntry, name: string): Promise<string> {
		const error = nameError(name);
		if (error) { throw new Error(error); }
		if (!['root', 'folder'].includes(entry.kind)) { throw new Error('Choose an Behavior category.'); }
		await this.ready();
		const path = await checkedBehaviorPath(this.context, entry.source_path, 'directory');
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

	async createResource(entry: LibraryEntry, name: string, request: Record<string, unknown>, catalogue: LibraryCatalogue): Promise<string> {
		if (!name.endsWith('.tres')) { throw new Error('Use a .tres filename.'); }
		await this.parent(entry, name);
		const source = entry.source_path + '/' + name;
		const draft = await libraryRequest(this.context.projectDirectory, this.executable, 'draft', source,
			{ ...request, executor_snapshot: catalogue.executor_snapshot, expected_parent: entry.fingerprint, expected_entries: Object.fromEntries(catalogue.entries.map(item => [item.source_path, item.fingerprint])) }, this.report) as ResourceDraft;
		if (!draft || draft.source_path !== source || typeof draft.source_text !== 'string'
			|| Buffer.byteLength(draft.source_text) > 1024 * 1024 || sha256(Buffer.from(draft.source_text)) !== draft.content_hash
			|| !/^uid:\/\/[a-z0-9]+$/.test(draft.uid) || !draft.source_text.split(/\r?\n/)[0].includes(`uid="${draft.uid}"`)) {
			throw new Error('Godot returned an invalid behavior Resource draft.');
		}
		await this.ready();
		await this.verifyCatalogue(catalogue);
		for (const [source, expected] of Object.entries(catalogue.executor_snapshot?.hashes ?? {})) {
			if (sha256(await readFile(await checkedProjectPath(this.context, source))) !== expected) { throw new Error('Executor sources changed. Refresh and retry.'); }
		}
		for (const [source, expected] of Object.entries(catalogue.executor_snapshot?.directories ?? {})) {
			const path = source === 'res://' ? this.context.projectDirectory : await checkedProjectPath(this.context, source);
			if (await directoryFingerprint(path) !== expected) { throw new Error('Executor source directories changed. Refresh and retry.'); }
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
			const graph = await loadResourceGraph(this.context.projectDirectory, this.executable, this.report, source);
			if (graph.supported === false || graph.nodes[source]?.content_hash !== draft.content_hash
				|| graph.nodes[source]?.kind !== request.resource_kind || graph.nodes[source]?.id !== request.id) {
				throw new Error('The newly published behavior Resource failed verification.');
			}
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
			const path = await checkedBehaviorPath(this.context, entry.source_path, entry.kind === 'resource' ? 'file' : 'directory');
			const hash = entry.kind === 'resource' ? sha256(await readFile(path)) : await directoryFingerprint(path);
			if (hash !== entry.fingerprint) { throw new Error('The Behavior library changed. Refresh and retry.'); }
		}
	}

	async previewDeletion(entry: LibraryEntry): Promise<DeletionPreview> {
		if (entry.kind !== 'resource' || !entry.supported) { throw new Error('Choose a behavior Resource.'); }
		await this.ready(true);
		const path = await checkedBehaviorPath(this.context, entry.source_path, 'file');
		if (sha256(await readFile(path)) !== entry.fingerprint) { throw new Error('The Resource changed. Refresh and retry.'); }
		const preview = await libraryRequest(this.context.projectDirectory, this.executable, 'deletion-preview',
			entry.source_path, { expected_hash: entry.fingerprint }, this.report) as DeletionPreview;
		if (!preview || preview.source_path !== entry.source_path || preview.content_hash !== entry.fingerprint
			|| !Array.isArray(preview.consumers) || !preview.hashes || !preview.directories
			|| preview.hashes[entry.source_path] !== entry.fingerprint) { throw new Error('Invalid dependency inspection result.'); }
		return preview;
	}

	async deleteResource(entry: LibraryEntry, preview: DeletionPreview, trash: (path: string) => Promise<void>): Promise<void> {
		if (entry.kind !== 'resource' || !entry.supported || preview.source_path !== entry.source_path
			|| preview.content_hash !== entry.fingerprint) { throw new Error('The deletion selection changed. Refresh and retry.'); }
		if (preview.consumers.length) { throw new Error('This Resource is still referenced. Unassign it from its consumers first.'); }
		await this.ready(true);
		for (const [source, expected] of Object.entries(preview.hashes)) {
			const path = await checkedProjectPath(this.context, source);
			if (!/^[a-f0-9]{64}$/.test(expected) || sha256(await readFile(path)) !== expected) {
				throw new Error('Project references changed. Run Delete Resource again.');
			}
		}
		for (const [source, expected] of Object.entries(preview.directories)) {
			const path = source === 'res://' ? this.context.projectDirectory : await checkedProjectPath(this.context, source);
			if (await directoryFingerprint(path) !== expected) { throw new Error(`Project directories changed: ${source}. Run Delete Resource again.`); }
		}
		const path = await checkedBehaviorPath(this.context, entry.source_path, 'file');
		await this.ready(true);
		if (sha256(await readFile(path)) !== entry.fingerprint) { throw new Error('The Resource changed. Refresh and retry.'); }
		await trash(path);
	}

	async deleteEmptyCategory(entry: LibraryEntry, trash: (path: string) => Promise<void>): Promise<void> {
		if (entry.kind !== 'folder' || entry.source_path === BEHAVIOR_ROOT) { throw new Error('The Behavior library root cannot be deleted.'); }
		await this.ready(true);
		const path = await checkedBehaviorPath(this.context, entry.source_path, 'directory');
		if ((await readdir(path)).length || await directoryFingerprint(path) !== entry.fingerprint) {
			throw new Error('Only an unchanged, empty category can be deleted.');
		}
		await this.ready(true);
		if ((await readdir(path)).length) { throw new Error('The category is no longer empty.'); }
		await trash(path);
	}
}
