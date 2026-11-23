import { isProfileSharedFolder, libraryRequest } from './behavior_library_bridge';
import { validateResourcePath } from '../workspace/project_context';

export const CONFIGURATION_FIELD_TYPES = ['int', 'float', 'bool', 'String', 'StringName'] as const;
export const CONFIGURATION_TYPE_SUFFIX = '.type.tres';
export type ConfigurationFieldType = typeof CONFIGURATION_FIELD_TYPES[number];
export interface ConfigurationField {
	name: string;
	type: ConfigurationFieldType;
	default_text: string;
}
export interface ConfigurationType {
	id: string;
	label: string;
	source_path: string;
	content_hash: string;
	fields: ConfigurationField[];
}

export function isConfigurationFieldType(value: unknown): value is ConfigurationFieldType {
	return CONFIGURATION_FIELD_TYPES.some(type => type === value);
}

export function isConfigurationIdentifier(value: unknown): value is string {
	return typeof value === 'string' && /^[a-z][a-z0-9_]{0,63}$/.test(value);
}

export async function loadConfigurationTypes(project: string, executable: string, folder: string,
	report: (message: string) => void): Promise<ConfigurationType[]> {
	if (!isProfileSharedFolder(folder)) { throw new Error('Choose a profile’s Shared folder.'); }
	const types = await libraryRequest(project, executable, 'configuration-types', folder, {}, report) as ConfigurationType[];
	if (!Array.isArray(types) || types.some(type => !type || !isConfigurationIdentifier(type.id) || type.id === 'movement'
		|| typeof type.label !== 'string' || !type.label.trim()
		|| typeof type.source_path !== 'string' || !type.source_path.endsWith(CONFIGURATION_TYPE_SUFFIX)
		|| type.source_path.slice(0, type.source_path.lastIndexOf('/')) !== folder
		|| !/^[a-f0-9]{64}$/.test(type.content_hash)
		|| !Array.isArray(type.fields) || !type.fields.length || type.fields.length > 64
		|| type.fields.some(field => !field || !isConfigurationIdentifier(field.name)
			|| !isConfigurationFieldType(field.type) || typeof field.default_text !== 'string')
		|| new Set(type.fields.map(field => field.name)).size !== type.fields.length)
		|| new Set(types.map(type => type.id)).size !== types.length) {
		throw new Error('Malformed Configuration Type catalogue.');
	}
	for (const type of types) { validateResourcePath(type.source_path, CONFIGURATION_TYPE_SUFFIX); }
	return types;
}
