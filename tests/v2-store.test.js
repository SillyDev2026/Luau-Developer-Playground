import test from 'node:test';
import assert from 'node:assert/strict';
import { STORAGE_KEY, LEGACY_STORAGE_KEY, createDefaultProject, validateProject, loadProject, saveProject } from '../src/store.js';
import { MAX_SNAPSHOTS, listSnapshots, createSnapshot, restoreSnapshot, deleteSnapshot } from '../src/snapshots.js';
const memoryStorage = () => { const map = new Map(); return { getItem: key => map.get(key) ?? null, setItem: (key, value) => map.set(key, value) }; };

test('v0.1 project migrates with safe v0.2 settings defaults', () => {
  const storage = memoryStorage();
  const old = createDefaultProject();
  delete old.fontSize;
  delete old.sidebarWidth;
  delete old.outputHeight;
  storage.setItem(LEGACY_STORAGE_KEY, JSON.stringify(old));
  const project = loadProject(storage);
  assert.equal(project.fontSize, 13);
  assert.equal(project.sidebarWidth, 258);
  assert.equal(project.outputHeight, 202);
  assert.equal(project.files['main.luau'], old.files['main.luau']);
  saveProject(project, storage);
  assert.ok(storage.getItem(STORAGE_KEY));
});
test('corrupted current storage falls back to earlier valid snapshot', () => {
  const storage = memoryStorage();
  storage.setItem(STORAGE_KEY, '{invalid');
  storage.setItem(LEGACY_STORAGE_KEY, JSON.stringify(createDefaultProject()));
  assert.equal(loadProject(storage).active, 'main.luau');
});
test('layout dimensions and file paths are bounded', () => {
  const data = validateProject({ ...createDefaultProject(), fontSize: 900, sidebarWidth: -1, outputHeight: Infinity });
  assert.equal(data.fontSize, 22);
  assert.equal(data.sidebarWidth, 205);
  assert.equal(data.outputHeight, 202);
  assert.throws(() => validateProject({ ...data, files: { 'a/../b.luau': 'code' } }));
});
test('snapshots persist and are validated on restore', () => {
  const storage = memoryStorage();
  const project = createDefaultProject();
  const first = createSnapshot(project, storage, 100);
  assert.equal(restoreSnapshot(first.id, storage).active, 'main.luau');
  assert.equal(listSnapshots(storage).length, 1);
  deleteSnapshot(first.id, storage);
  assert.equal(listSnapshots(storage).length, 0);
  assert.throws(() => restoreSnapshot(first.id, storage));
});
test('snapshots keep only bounded newest entries', () => {
  const storage = memoryStorage();
  const project = createDefaultProject();
  for (let i = 0; i < MAX_SNAPSHOTS + 4; i++) createSnapshot(project, storage, 1000 + i);
  assert.equal(listSnapshots(storage).length, MAX_SNAPSHOTS);
  assert.equal(listSnapshots(storage)[0].createdAt, 1000 + MAX_SNAPSHOTS + 3);
});
