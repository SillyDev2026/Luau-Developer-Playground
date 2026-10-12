import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { windowsDataDirectory,windowsServerConfig } from '../server/windows-config.mjs';

test('Windows EXE defaults to loopback and persistent per-user storage',()=>{
 const env={LOCALAPPDATA:'C:\\Users\\Example\\AppData\\Local'};
 const config=windowsServerConfig(env);
 assert.equal(config.host,'127.0.0.1');
 assert.equal(config.port,8787);
 assert.equal(config.directory,join(env.LOCALAPPDATA,'LuauForgeServer'));
 assert.equal(config.dataFile,join(config.directory,'workspaces.json'));
 assert.equal(config.feedbackDataFile,join(config.directory,'feedback.json'));
 assert.equal(config.discordBotToken,'');
 assert.ok(config.allowedOrigins.includes('https://sillydev2026.github.io'));
 assert.equal(windowsDataDirectory(env),config.directory);
});
test('Windows EXE respects host, port, data paths and Discord secret environment',()=>{
 const config=windowsServerConfig({LOCALAPPDATA:'C:\\Temp',PORT:'9898',HOST:'0.0.0.0',
   COLLAB_DATA_FILE:'X:/data/workspaces.json',FEEDBACK_DATA_FILE:'X:/data/feedback.json',
   ALLOWED_ORIGINS:'https://example.org, https://sillydev2026.github.io',
   DISCORD_BOT_TOKEN:'not-a-real-token'});
 assert.equal(config.host,'0.0.0.0');assert.equal(config.port,9898);
 assert.equal(config.dataFile,'X:/data/workspaces.json');
 assert.equal(config.feedbackDataFile,'X:/data/feedback.json');
 assert.equal(config.discordBotToken,'not-a-real-token');
 assert.deepEqual(config.allowedOrigins,['https://example.org','https://sillydev2026.github.io']);
 assert.throws(()=>windowsServerConfig({PORT:'99999'}),/PORT/);
 assert.throws(()=>windowsServerConfig({PORT:'invalid'}),/PORT/);
});
test('direct executable download link and bundled Windows build workflow are present',async()=>{
 const root=new URL('../',import.meta.url);
 const read=path=>readFile(new URL(path,root),'utf8');
 const [html,workflow,script,docs,sw]=await Promise.all([
   read('index.html'),read('.github/workflows/windows-server-exe.yml'),
   read('scripts/build-windows-server.mjs'),read('server/README.md'),read('public/sw.js')
 ]);
 const asset='LuauForge-Server-Windows-x64.exe';
 assert.match(html,/id="server-exe-download"/);
 assert.match(html,/id="server-exe-scripts"/);
 assert.match(html,/id="server-exe-feedback"/);
 assert.ok(html.includes('/releases/download/v3.3.0/'+asset));
 assert.ok(workflow.includes('windows-latest'));
 assert.ok(workflow.includes('node-version: \'26\''));
 assert.ok(workflow.includes('releases')||workflow.includes('action-gh-release'));
 assert.ok(workflow.includes(asset));
 assert.match(script,/--build-sea/);
 assert.match(script,/esbuild/);
 assert.match(docs,/Windows.*EXE/i);
 assert.match(sw,/3\.4\.4/);
});
