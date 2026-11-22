import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { isAbsolute, relative, resolve, sep } from 'node:path';
import { inspectionCancelled, isPath, validateGraph, type ResourceGraph } from './resource_bridge';

interface Job {
	id: number; source: string; report: (message: string) => void; signal?: AbortSignal;
	resolve: (graph: ResourceGraph) => void; reject: (error: Error) => void;
	abort: () => void; timer?: ReturnType<typeof setTimeout>;
}

export class ResourceBrowsePool {
	private workers = new Map<string, BrowseWorker>();
	private disposed = false;
	constructor(private readonly timeoutMs = 30_000, private readonly idleMs = 120_000) {}

	load(project: string, executable: string, source: string, report: (message: string) => void,
		signal?: AbortSignal): Promise<ResourceGraph> {
		if (this.disposed || signal?.aborted) { return Promise.reject(inspectionCancelled()); }
		if (!isPath(source)) { return Promise.reject(new Error('Choose a canonical project .tres path.')); }
		const key = JSON.stringify([resolve(project), executable]);
		let worker = this.workers.get(key);
		if (!worker || worker.closed) {
			// Bound background processes when moving between projects in a workspace.
			for (const [oldKey, old] of this.workers) { if (old.closed) { this.workers.delete(oldKey); } }
			if (this.workers.size >= 2) { const first = this.workers.entries().next().value!; first[1].close(); this.workers.delete(first[0]); }
			worker = new BrowseWorker(project, executable, this.timeoutMs, this.idleMs);
			this.workers.set(key, worker);
		}
		return worker.load(source, report, signal);
	}

	invalidate(file?: string): void {
		for (const [key, worker] of this.workers) {
			const part = file === undefined ? '' : relative(worker.project, file);
			if (file === undefined || part === '' || (!isAbsolute(part) && part !== '..' && !part.startsWith('..' + sep))) {
				worker.close(); this.workers.delete(key);
			}
		}
	}

	dispose(): void { this.disposed = true; this.invalidate(); }
}

class BrowseWorker {
	closed = false;
	private readonly child: ChildProcessWithoutNullStreams;
	private queue: Job[] = [];
	private active?: Job;
	private ready = false;
	private nextId = 0;
	private output = '';
	private errorOutput = '';
	private idle?: ReturnType<typeof setTimeout>;

	constructor(readonly project: string, executable: string, private readonly timeoutMs: number, private readonly idleMs: number) {
		this.child = spawn(executable, ['--headless', '--path', project, '--script',
			'res://Framework/Env/Authoring/Resources/Inspection/resource_browse_worker.gd'],
		{ cwd: project, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
		this.child.stdout.setEncoding('utf8'); this.child.stderr.setEncoding('utf8');
		this.child.stdout.on('data', text => this.receive(String(text)));
		this.child.stderr.on('data', text => {
			this.errorOutput += String(text);
			if (this.errorOutput.length > 1024 * 1024 || /(?:^|\n)(?:SCRIPT ERROR|ERROR):/.test(this.errorOutput)) {
				this.close(new Error('Godot browsing failed: ' + this.errorOutput.slice(-3000)));
			}
		});
		this.child.on('error', error => this.close(error));
		this.child.stdin.on('error', error => this.close(error));
		this.child.on('exit', (code, signal) => {
			if (!this.closed) { this.close(new Error(`Godot browsing worker exited (${code ?? signal}). ${this.errorOutput.slice(-1000)}`)); }
		});
	}

	load(source: string, report: (message: string) => void, signal?: AbortSignal): Promise<ResourceGraph> {
		if (this.closed || signal?.aborted) { return Promise.reject(inspectionCancelled()); }
		clearTimeout(this.idle);
		return new Promise((resolve, reject) => {
			const job: Job = { id: ++this.nextId, source, report, signal, resolve, reject, abort: () => {
				if (this.active === job) { this.close(inspectionCancelled()); }
				else { this.queue = this.queue.filter(item => item !== job); this.finish(job, inspectionCancelled()); }
			} };
			job.timer = setTimeout(() => this.close(new Error('Godot resource inspection timed out. Select the Resource again to restart.')), this.timeoutMs);
			signal?.addEventListener('abort', job.abort, { once: true });
			this.queue.push(job); this.pump();
		});
	}

	private pump(): void {
		if (!this.ready || this.closed || this.active) { return; }
		this.active = this.queue.shift();
		if (!this.active) {
			this.idle = setTimeout(() => this.close(), this.idleMs); this.idle.unref?.(); return;
		}
		const data = Buffer.from(JSON.stringify({ id: this.active.id, source: this.active.source }), 'utf8');
		const header = Buffer.alloc(4); header.writeUInt32LE(data.length);
		this.child.stdin.write(Buffer.concat([header, data]));
	}

	private receive(text: string): void {
		if (this.closed) { return; }
		this.output += text;
		if (this.output.length > 16 * 1024 * 1024) { this.close(new Error('Godot browsing response exceeds 16 MiB.')); return; }
		let end: number;
		while ((end = this.output.indexOf('\n')) >= 0) {
			const line = this.output.slice(0, end).replace(/\r$/, ''); this.output = this.output.slice(end + 1);
			if (/^(SCRIPT ERROR|ERROR):/.test(line)) { this.close(new Error(line)); return; }
			const prefix = '[resource-browse] ';
			if (!line.startsWith(prefix)) { continue; }
			try {
				const packet = JSON.parse(line.slice(prefix.length));
				if (packet.protocol !== 1) { throw new Error('Unsupported Godot browsing protocol.'); }
				if (packet.ready === true && !this.ready) { this.ready = true; this.pump(); continue; }
				const job = this.active;
				if (!job || packet.id !== job.id || typeof packet.result?.ok !== 'boolean') { throw new Error('Unexpected Godot browsing response.'); }
				if (packet.result.ok !== true) { this.active = undefined; this.finish(job, new Error(packet.result.error || 'Resource inspection failed.')); this.pump(); continue; }
				const graph: unknown = packet.result.value; validateGraph(graph);
				if (graph.mode !== 'browse' || (graph.supported === false ? graph.source_path !== job.source : graph.roots.length !== 1 || graph.roots[0] !== job.source)) {
					throw new Error('Godot browsing response does not match the selected Resource.');
				}
				this.active = undefined; this.finish(job, undefined, graph); this.pump();
			} catch (error) { this.close(error instanceof Error ? error : new Error(String(error))); return; }
		}
	}

	private finish(job: Job, error?: Error, graph?: ResourceGraph): void {
		clearTimeout(job.timer); job.signal?.removeEventListener('abort', job.abort);
		if (error) { job.reject(error); } else { job.resolve(graph!); }
	}

	close(error: Error = inspectionCancelled()): void {
		if (this.closed) { return; }
		this.closed = true; clearTimeout(this.idle);
		const jobs = [...(this.active ? [this.active] : []), ...this.queue]; this.active = undefined; this.queue = [];
		for (const job of jobs) { this.finish(job, error); }
		this.child.stdin.destroy(); this.child.kill();
	}
}
