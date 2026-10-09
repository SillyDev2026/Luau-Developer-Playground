import { createDefaultProject, validateProject, loadProject, saveProject, addFile, renameFile, deleteFile } from './store.js';
import { createSnapshot, listSnapshots, restoreSnapshot } from './snapshots.js';

// All v0.1–v0.4.1 localStorage projects remain readable via store.js.
// v1 makes a copy before mutations so a bad edit never corrupts the saved file.
export class Workspace {
  constructor({ storage = globalThis.localStorage, onChange = () => {}, onError = () => {}, onSave = () => {} } = {}) {
    this.storage = storage;
    this.onChange = onChange;
    this.onError = onError;
    this.onSave = onSave;
    this.project = loadProject(storage);
    this.tabs = [this.project.active];
    this.saveTimer = null;
    this.revision = 0;
    this.savedRevision = 0;
  }
  update(patch, { save = true } = {}) {
    const next = validateProject(typeof patch === 'function' ? patch(this.project) : { ...this.project, ...patch });
    this.project = next;
    if (!this.tabs.includes(next.active)) this.tabs.push(next.active);
    this.tabs = this.tabs.filter(file => Object.hasOwn(next.files, file));
    this.revision++;
    this.onChange(this.project);
    if (save) this.scheduleSave();
    return next;
  }
  source(text) {
    if (typeof text !== 'string' || text === this.project.files[this.project.active]) return this.project;
    const name = this.project.active;
    return this.update(project => ({ ...project, files: { ...project.files, [name]: text } }));
  }
  open(name) {
    if (!Object.hasOwn(this.project.files, name)) throw new Error(`File missing: ${name}`);
    return this.update({ active: name }, { save: true });
  }
  create(name, text = '') { return this.update(addFile(this.project, name, text)); }
  rename(oldName, newName) {
    const next = renameFile(this.project, oldName, newName);
    this.tabs = this.tabs.map(name => name === oldName ? newName : name);
    return this.update(next);
  }
  remove(name) { return this.update(deleteFile(this.project, name)); }
  close(name) {
    this.tabs = this.tabs.filter(file => file !== name);
    if (!this.tabs.length) this.tabs.push(name === this.project.active ? Object.keys(this.project.files).find(p => p !== name) || name : this.project.active);
    if (name === this.project.active && this.tabs.length) this.open(this.tabs.at(-1));
    else this.onChange(this.project);
  }
  replace(next) {
    this.flush();
    this.tabs = [];
    return this.update(validateProject(next));
  }
  scheduleSave() {
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => { this.saveTimer = null; this.flush(); }, 350);
  }
  flush() {
    if (this.saveTimer !== null) { clearTimeout(this.saveTimer); this.saveTimer = null; }
    if (this.savedRevision === this.revision) return true;
    try {
      this.project = saveProject(this.project, this.storage);
      this.savedRevision = this.revision;
      this.onSave();
      return true;
    } catch (error) { this.onError(error); return false; }
  }
  snapshot() { this.flush(); return createSnapshot(this.project, this.storage); }
  snapshots() { return listSnapshots(this.storage); }
  restore(id) { const before = this.snapshot(); this.replace(restoreSnapshot(id, this.storage)); return before; }
  reset() { this.snapshot(); return this.replace(createDefaultProject()); }
  dispose() { this.flush(); }
}

export function findProjectTests(project) {
  return Object.keys(project.files).filter(path => /(?:\.test|\.spec)\.lua(u)?$/i.test(path) || /^tests\/.*\.lua(u)?$/i.test(path)).sort();
}

export function classifyScript(path) {
  if (/(?:\.test|\.spec)\.lua(u)?$/i.test(path) || path.startsWith('tests/')) return 'test';
  if (path.startsWith('modules/') || path.startsWith('lib/')) return 'module';
  return 'script';
}
