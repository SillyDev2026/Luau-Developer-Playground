import test from 'node:test';
import assert from 'node:assert/strict';
import { createDefaultProject, addFile, renameFile, deleteFile, validateProject, normalizePath, saveProject, loadProject, STORAGE_KEY, countLines, projectSize } from '../src/store.js';
import { highlightLuau } from '../src/highlight.js';
import { buildShareState, buildPlaygroundURL } from '../src/runner.js';

const memoryStorage = () => {
  const cache = new Map();
  return { getItem: key => cache.get(key) ?? null, setItem: (key, value) => cache.set(key, value) };
};

test('initial workspace contains Luau examples', () => {
  const project = createDefaultProject();
  assert.equal(project.active, 'main.luau');
  assert.match(project.files['main.luau'], /--!strict/);
  assert.ok(Object.keys(project.files).length >= 3);
});

test('file creation and folders', () => {
  const original = createDefaultProject();
  const newProject = addFile(original, 'math/add', 'return 12');
  assert.equal(newProject.files['math/add.luau'], 'return 12');
  assert.equal(newProject.active, 'math/add.luau');
  assert.equal(original.files['math/add.luau'], undefined);
  assert.throws(() => addFile(newProject, 'math/add'), /already exists/);
});

test('rename and delete preserve contents', () => {
  const original = createDefaultProject();
  const renamed = renameFile(original, 'main.luau', 'src/index.luau');
  assert.equal(renamed.active, 'src/index.luau');
  assert.equal(renamed.files['src/index.luau'], original.files['main.luau']);
  const deleted = deleteFile(renamed, 'src/index.luau');
  assert.equal(Object.hasOwn(deleted.files, 'src/index.luau'), false);
  assert.ok(deleted.active in deleted.files);
});

test('unsafe paths and malformed data are rejected', () => {
  for (const name of ['../abc.luau', '/root.luau', 'a//b', '.', 'C:\\test.luau', 'foo?bar']) {
    assert.throws(() => normalizePath(name));
  }
  assert.throws(() => validateProject({ files: { 'main.luau': 123 } }));
  assert.throws(() => validateProject({ files: {} }));
  assert.throws(() => validateProject({ files: { 'main.luau': 'x'.repeat(210000) } }));
});

test('project persistence round trip', () => {
  const storage = memoryStorage();
  const project = saveProject(createDefaultProject(), storage);
  assert.ok(storage.getItem(STORAGE_KEY));
  const loaded = loadProject(storage);
  assert.deepEqual(loaded, project);
});

test('broken storage falls back safely', () => {
  const storage = memoryStorage();
  storage.setItem(STORAGE_KEY, '{bad json');
  assert.equal(loadProject(storage).active, 'main.luau');
});

test('counts lines and bytes', () => {
  const project = createDefaultProject();
  assert.equal(countLines('a\nb'), 2);
  assert.ok(projectSize(project) > 100);
});

test('highlighting escapes user markup, and marks Luau syntax', () => {
  const markup = highlightLuau('local x = "<script>" -- hi\nprint(42)');
  assert.ok(markup.includes('&lt;script&gt;'));
  assert.ok(!markup.includes('<script>'));
  assert.ok(markup.includes('token keyword'));
  assert.ok(markup.includes('token number'));
});

test('share state is compatible with official v2 shape', () => {
  const project = createDefaultProject();
  const state = buildShareState(project);
  assert.equal(state.v, 2);
  assert.equal(state.f['main.luau'], project.files['main.luau']);
  assert.equal(state.a, 'main.luau');
  assert.equal(state.s.mode, 'strict');
});

test('runner URL embeds compressed source and compiler flags', () => {
  let passed = '';
  const project = createDefaultProject();
  const url = new URL(buildPlaygroundURL(project, { compressor: { compressToEncodedURIComponent: value => { passed = value; return 'compressed'; } } }));
  assert.equal(url.origin, 'https://play.luau.org');
  assert.equal(url.searchParams.get('embed'), 'true');
  assert.equal(url.hash, '#compressed');
  assert.match(passed, /optimizationLevel/);
  assert.match(passed, /main.luau/);
});
