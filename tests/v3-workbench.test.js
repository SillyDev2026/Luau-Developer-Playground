import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { workspaceSearch, formatWhitespace, qualityAudit, compareSources, createLockfile, parseLockfile, projectReport } from '../src/v3/core.js';
const sample={ 'modules/Math.luau': '--!strict\nlocal Math = {}\nfunction Math.add(a, b) return a + b end\nreturn Math\n', 'main.luau':'--!strict\nlocal Math = require("modules/Math.luau")\nprint(Math.add(20,22))\n' };
test('whole-project literal search reports accurate filename, line, and column',()=>{
 const hit=workspaceSearch(sample,'Math.add');assert.equal(hit.matches.length,2);assert.equal(hit.matches[0].file,'main.luau');assert.equal(hit.matches[0].line,3);assert.equal(hit.matches[0].column,7);
});
test('search supports whole-word and case-sensitive modes',()=>{
 const files={'one.luau':'foo fooBar FOO\n-- foo'};
 assert.equal(workspaceSearch(files,'foo',{wholeWord:true}).matches.length,3);
 assert.equal(workspaceSearch(files,'FOO',{wholeWord:true,caseSensitive:true}).matches.length,1);
});
test('project search cannot use uncontrolled regex and caps results',()=>{
 const r=workspaceSearch({'a.luau':'a.a.a.a.a.a.'},'.',{maxResults:2});assert.equal(r.matches.length,2);assert.equal(r.truncated,true);
 assert.throws(()=>workspaceSearch(sample,''),/search term/);
});
test('search truncation flag is true only if extra results exist',()=>{
 const exact=workspaceSearch({'a.luau':'hi hi'},'hi',{maxResults:2});assert.equal(exact.matches.length,2);assert.equal(exact.truncated,false);
 const extra=workspaceSearch({'a.luau':'hi hi hi'},'hi',{maxResults:2});assert.equal(extra.matches.length,2);assert.equal(extra.truncated,true);
});
test('search ignores comments when opted out',()=>{
 const files={'x.luau':'-- hello\nlocal s = "hello"\nprint("hello")'};
 assert.equal(workspaceSearch(files,'hello',{includeComments:false}).matches.length,0);
});
test('formatter never wraps local assignments and preserves CRLF',()=>{
 const code='local a = b   \r\nlocal n = 3\r\n';
 assert.equal(formatWhitespace(code),'local a = b\r\nlocal n = 3\r\n');
});
test('formatter preserves quoted and long literal trailing spaces',()=>{
 assert.equal(formatWhitespace('local s = "text  "   \n'), 'local s = "text  "   \n');
 assert.equal(formatWhitespace('local s = [[\nabc   \n]]\n'), 'local s = [[\nabc   \n]]\n');
});
test('formatter leaves comments untouched and appends final newline',()=>{
 assert.equal(formatWhitespace('local a = b'), 'local a = b\n');
 assert.equal(formatWhitespace('-- hi   \n'), '-- hi   \n');
});
test('static quality audit distinguishes warnings from advisory findings',()=>{
 const audit=qualityAudit({'main.luau':'-- TODO make fast\nlocal a = 3  \nprint(a)\n'});
 assert.ok(audit.findings.some(x=>/developer note/.test(x.message)));
 assert.ok(audit.findings.some(x=>/Trailing whitespace/.test(x.message)));
 assert.ok(audit.findings.some(x=>/type-checking/.test(x.message))===false); // tiny script exempt
});
test('diff shows removed and added lines',()=>{
 const r=compareSources('local a = b\n','local a = c\n');
 assert.equal(r.limited,false);assert.ok(r.changes.some(x=>x.kind==='removed'));assert.ok(r.changes.some(x=>x.kind==='added'));
});
test('diff protects browser from large quadratic comparisons',()=>{
 assert.equal(compareSources('x\n'.repeat(350),'y').limited,true);
});
test('lockfile exports versioned immutable GitHub package pins',()=>{
 const pin={specifier:'@Owner/Repo/src/Math.luau',sha:'a'.repeat(40),size:390};
 const json=createLockfile(sample,[pin],{projectName:'Demo'});
 assert.equal(json.version,1);assert.equal(json.packages[0].sha,'a'.repeat(40));
 assert.deepEqual(parseLockfile(JSON.stringify(json)).packages[0],pin);
});
test('lockfile rejects traversal, mutable versions and malformed content',()=>{
 assert.throws(()=>parseLockfile('{no'),/valid JSON/);
 assert.throws(()=>parseLockfile(JSON.stringify({schema:'luauforge-lockfile',version:1,packages:[{specifier:'@Owner/Repo/../secret.luau',sha:'a'.repeat(40)}]})),/Invalid module/);
 assert.throws(()=>parseLockfile(JSON.stringify({schema:'luauforge-lockfile',version:1,packages:[{specifier:'@Owner/Repo/Math.lua',sha:'main'}]})),/Invalid module/);
});
test('lockfile rejects duplicate module names and version mismatch',()=>{
 const pin={specifier:'@Owner/Repo/Math.lua',sha:'a'.repeat(40)};
 assert.throws(()=>parseLockfile(JSON.stringify({schema:'luauforge-lockfile',version:1,packages:[pin,pin]})),/Duplicate/);
 assert.throws(()=>parseLockfile(JSON.stringify({schema:'luauforge-lockfile',version:2,packages:[]})),/Unsupported/);
});
test('project reports contain accurate file and dependency counts',()=>{
 const report=projectReport({name:'Demo',files:sample},[{specifier:'@Owner/Repo/Math.lua',sha:'a'.repeat(40)}]);
 assert.match(report,/Files: 2/);assert.match(report,/Pinned public modules: 1/);assert.match(report,/modules\/Math.luau/);
});
test('v3 UI is additive and versioned for offline deployment',async()=>{
 const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
 const sw=await readFile(new URL('../public/sw.js',import.meta.url),'utf8');
 const ui=await readFile(new URL('../src/v3/ui.js',import.meta.url),'utf8');
 for(const id of ['code-input','mobile-dock','dashboard-view','v3-actions'])assert.match(html,new RegExp(`id="${id}"`));
 assert.match(html,/v3\/ui\.css\?v=3\.0\.1/);
 assert.match(sw,/luauforge-v3\.0\.1/);assert.match(sw,/src\/v3\/ui\.js/);
 assert.match(ui,/snapshot\(\)/);assert.match(ui,/source\(after\)/);
});


test('diff and audit truncation are only reported for actual omitted results',()=>{
 const same='a\n'.repeat(239)+'tail';
 assert.equal(compareSources(same,same).truncated,false);
 assert.equal(compareSources(same,same+'\nextra').truncated,true);
 const notes={'n.luau':'-- TODO first\n-- TODO second\n'};
 assert.equal(qualityAudit(notes,{maxFindings:2}).truncated,false);
 assert.equal(qualityAudit(notes,{maxFindings:1}).truncated,true);
});
test('rejects nonnumeric lockfile sizes and exact-source mismatches',async()=>{
 const candidate={schema:'luauforge-lockfile',version:1,packages:[{specifier:'@Owner/Repo/file.luau',sha:'a'.repeat(40),size:'unknown'}]};
 assert.throws(()=>parseLockfile(JSON.stringify(candidate)),/size/);
 const ui=await readFile(new URL('../src/v3/ui.js',import.meta.url),'utf8');
 assert.match(ui,/File changed since the preview/);
 assert.match(ui,/source\.specifier!==pin\.specifier/);
 assert.match(ui,/source\.size!==pin\.size/);
});
