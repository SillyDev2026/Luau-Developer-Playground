import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { CURRENT_VERSION } from '../src/community-settings.js';
const read = file => readFile(new URL('../'+file,import.meta.url),'utf8');
test('version consistent across app package, public feed, console, and cache',async()=>{
 const [p,feed,html,sw,js]=await Promise.all(['package.json','public/updates.json','index.html','public/sw.js','src/v1.js'].map(read));
 const version=JSON.parse(p).version;
 assert.equal(version,'3.4.5');assert.equal(JSON.parse(feed).version,version);assert.equal(CURRENT_VERSION,version);
 assert.ok(html.includes('v='+version));assert.ok(sw.includes('luauforge-v'+version));
 assert.ok(js.includes('Welcome to LuauForge v'+'\x24{CURRENT_VERSION}'));
 assert.doesNotMatch(js,/Welcome to LuauForge 1[.]0/);
});
test('the official Discord invite is present in dashboard and community settings',async()=>{
 const html=await read('index.html');
 assert.equal(html.split('https://discord.gg/z8qUMDV8gD').length-1,2);
 assert.match(html,/target="_blank" rel="noopener noreferrer"/);
 assert.match(html,/id="dashboard-release"/);assert.match(html,/id="community-settings"/);
});
test('workspace save setting and editor geometry remain unchanged',async()=>{
 const [html,css,js]=await Promise.all(['index.html','src/v1.css','src/v1.js'].map(read));
 assert.match(html,/id="code-input"/);assert.match(html,/id="mobile-dock"/);
 assert.ok(css.includes('--sidebar-width:266px'));assert.ok(css.includes('--output-height:202px'));
 assert.ok(js.includes('luauforge:v1:settings'));
});
