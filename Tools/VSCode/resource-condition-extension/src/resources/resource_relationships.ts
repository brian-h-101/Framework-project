export interface ResourceRelationship { role: string; resourceKind: string; label: string; optional: boolean }

export function relationships(kind: string): ResourceRelationship[] {
	if (kind === 'interaction') { return [
		{ role: 'action', resourceKind: 'action', label: 'Action', optional: false },
		{ role: 'requirements', resourceKind: 'condition_group', label: 'Requirements', optional: true }
	]; }
	if (kind === 'condition_group') { return [{ role: 'condition', resourceKind: 'condition', label: 'Condition', optional: true }]; }
	if (kind === 'automation') { return [{ role: 'interaction', resourceKind: 'interaction', label: 'Interaction', optional: false }]; }
	return [];
}
