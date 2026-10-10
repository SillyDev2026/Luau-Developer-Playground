import test from 'node:test';
import assert from 'node:assert/strict';
import { COMMUNITY_KEY, validateGithub, validateDiscord, sanitizeCommunity, saveCommunity, loadCommunity, parseRelease, newerVersion, shouldShowUpdate } from '../src/community-settings.js';
import { formatAnnouncement, validDiscordWebhook, shouldAnnounce } from '../scripts/announce-discord.mjs';

function storage() {
  const map = new Map();
  return { getItem: key => map.get(key) ?? null, setItem: (key, value) => map.set(key, value), removeItem: key => map.delete(key) };
}
test('github profile accepts public handles and rejects credentials/URLs', () => {
  for (const x of ['', 'SillyDev2026', 'ab-cd', 'a', 'a'.repeat(39)]) assert.equal(validateGithub(x), true);
  for (const x of ['-alice', 'bob-', 'bob--alice', 'bad name', 'https://github.com/test', 'a'.repeat(40)]) assert.equal(validateGithub(x), false);
});
test('discord handles accept modern usernames, reject URL and spaces', () => {
  for (const x of ['', 'silly.dev', 'dev_name', '1234']) assert.equal(validateDiscord(x), true);
  for (const x of ['A.B', 'x', '.foo..bar', 'https://discord.com/webhook', 'abc def']) assert.equal(validateDiscord(x), false);
});
test('profile storage does not include unrecognized secret fields and survives invalid data', () => {
  const s = storage();
  const profile = saveCommunity(s, {github:'SillyDev2026',discord:'User_Name',inAppUpdates:true, token:'private-secret', webhook:'private-webhook'});
  assert.equal(profile.discord, 'user_name');
  assert.equal(s.getItem(COMMUNITY_KEY).includes('private-secret'), false);
  assert.equal(s.getItem(COMMUNITY_KEY).includes('private-webhook'), false);
  assert.deepEqual(loadCommunity(s), profile);
  s.setItem(COMMUNITY_KEY, '{not JSON');
  assert.equal(loadCommunity(s).github, '');
  assert.equal(loadCommunity(s).inAppUpdates, true);
  assert.throws(() => saveCommunity(s, {github:'https://github.com/example'}));
});
test('release feed validates strings and limits untrusted content', () => {
  const update = parseRelease({version:'1.8.0',title:'Release',changes:['Safe', 25, 'x'.repeat(300)]});
  assert.deepEqual(update.changes, ['Safe']);
  assert.throws(()=>parseRelease({version:'1.8',title:'Invalid',changes:['x']}));
  assert.throws(()=>parseRelease({version:'1.8.0',title:'Bad',changes:[]}));
});
test('update state compares actual semver numbers, not lexical strings', () => {
  assert.equal(newerVersion('1.10.0', '1.9.9'),true);
  assert.equal(newerVersion('1.8.0','1.8.0'),false);
  assert.equal(shouldShowUpdate({version:'1.8.0'}, {inAppUpdates:false,lastSeenRelease:''}), false);
  assert.equal(shouldShowUpdate({version:'1.8.0'}, {inAppUpdates:true,lastSeenRelease:'1.7.0'}), true);
});
test('Discord webhook host is fixed and messages cannot ping users', () => {
  assert.equal(validDiscordWebhook('https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyzABCDEFghijk'),true);
  for (const x of ['https://discord.com.evil.test/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyzABCDEFghijk','javascript:alert(1)','http://discord.com/api/webhooks/123/abc', 'https://discord.com/api/webhooks/123456789012345678/foo']) assert.equal(validDiscordWebhook(x),false);
  const payload = formatAnnouncement({version:'1.8.0'}, {version:'1.8.0',title:'@everyone **Update**',changes:['<@123> a fix']});
  assert.deepEqual(payload.allowed_mentions,{parse:[]});
  assert.equal(payload.content.includes('@everyone'), false);
  assert.ok(payload.content.includes('LuauForge v1.8.0'));
  assert.throws(()=>formatAnnouncement({version:'1.7.0'},{version:'1.8.0',title:'',changes:[]}));
});
test('Discord channels notify only on version-changing GitHub pushes', async () => {
  assert.equal(await shouldAnnounce({event:'push',current:'1.8.0',previous:'1.7.0'}),true);
  assert.equal(await shouldAnnounce({event:'push',current:'1.8.0',previous:'1.8.0'}),false);
  assert.equal(await shouldAnnounce({event:'workflow_dispatch',current:'1.8.0',previous:'1.7.0'}),false);
});
