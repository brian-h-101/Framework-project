import { isDeepStrictEqual } from 'node:util';
import { loadResourceGraph, type ResourceGraph } from '../bridges/resource_bridge';

// A small browsing packet can describe a tree, but it is never write authority.
// Prepare the original full inspection before any dialog can commit an edit.
export async function prepareEditGraph(graph: ResourceGraph, project: string, executable: string,
	report: (message: string) => void): Promise<ResourceGraph> {
	if (graph.mode !== 'browse') { return graph; }
	if (graph.roots.length !== 1 || graph.supported === false) { throw new Error('Choose a supported Resource to edit.'); }
	const kind = graph.nodes[graph.roots[0]]?.kind;
	const requiresExecutors = kind !== 'starting_attributes' && kind !== 'configuration';
	report('[bridge] Validating Resource and project state for editing...');
	const fresh = await loadResourceGraph(project, executable, report, graph.roots[0]);
	if (fresh.mode === 'browse' || (requiresExecutors && !fresh.executor_snapshot)
		|| Object.entries(graph.dependency_hashes).some(([path, hash]) => fresh.dependency_hashes[path] !== hash)
		|| !isDeepStrictEqual(graph.nodes, fresh.nodes) || !isDeepStrictEqual(graph.executors, fresh.executors)) {
		throw new Error('The Resource or its executor metadata changed since it was displayed. Refresh and retry.');
	}
	return fresh;
}
