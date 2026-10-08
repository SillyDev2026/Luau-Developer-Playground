import { validateProject } from './store.js';
export const SNAPSHOT_KEY = 'luau-dev-playground:snapshots:v1';
export const MAX_SNAPSHOTS = 6;
export function listSnapshots(storage = globalThis.localStorage) {
  try {
    const parsed = JSON.parse(storage.getItem(SNAPSHOT_KEY) || '[]');
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(item => item && typeof item.id === 'string' && typeof item.createdAt === 'number' && typeof item.project === 'object');
  } catch { return []; }
}
export function createSnapshot(project, storage = globalThis.localStorage, createdAt = Date.now()) {
  const data = validateProject(project);
  const existing = listSnapshots(storage);
  const snapshot = { id: `${createdAt}-${Math.random().toString(36).slice(2, 10)}`, createdAt, name: data.name, project: data };
  const next = [snapshot, ...existing].slice(0, MAX_SNAPSHOTS);
  storage.setItem(SNAPSHOT_KEY, JSON.stringify(next));
  return snapshot;
}
export function restoreSnapshot(id, storage = globalThis.localStorage) {
  const snapshot = listSnapshots(storage).find(item => item.id === id);
  if (!snapshot) throw new Error('Snapshot not found.');
  return validateProject(snapshot.project);
}
export function deleteSnapshot(id, storage = globalThis.localStorage) {
  const next = listSnapshots(storage).filter(item => item.id !== id);
  storage.setItem(SNAPSHOT_KEY, JSON.stringify(next));
}
