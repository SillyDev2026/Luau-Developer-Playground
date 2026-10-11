import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DISCORD_APPLICATION_ID, DISCORD_CHANNEL_ID, BOT_INVITE_URL,
  validSnowflake, validDiscordWebhook, deliverAnnouncement,
  formatTestAnnouncement, shouldAnnounce
} from '../scripts/announce-discord.mjs';

test('bot application, notification channel, and limited-scope invite are configured', () => {
  assert.equal(DISCORD_APPLICATION_ID, '1491648971041411163');
  assert.equal(DISCORD_CHANNEL_ID, '1558591089529851915');
  assert.equal(validSnowflake(DISCORD_CHANNEL_ID), true);
  assert.equal(validSnowflake('channel'), false);
  assert.equal(validSnowflake('123'), false);
  const invite = new URL(BOT_INVITE_URL);
  assert.equal(invite.hostname, 'discord.com');
  assert.equal(invite.searchParams.get('client_id'), DISCORD_APPLICATION_ID);
  assert.equal(invite.searchParams.get('permissions'), '3072');
  assert.equal(invite.searchParams.get('scope'), 'bot');
});

test('bot announcement targets configured channel, uses secret authorization and cannot mention roles', async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({url, options});
    return { ok: true, status: 200 };
  };
  const transport = await deliverAnnouncement({
    botToken: 'unit-test-bot-token', webhook: 'not a usable webhook',
    payload: { content: '**LuauForge release** @everyone', allowed_mentions: { parse: ['everyone'] } }, fetchImpl
  });
  assert.equal(transport, 'bot');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages`);
  assert.equal(calls[0].options.headers.Authorization, 'Bot unit-test-bot-token');
  assert.deepEqual(JSON.parse(calls[0].options.body).allowed_mentions, {parse: []});
});

test('without a credential the notifier makes no outgoing request', async () => {
  const fetchImpl = () => { throw new Error('unexpected outgoing request'); };
  assert.equal(await deliverAnnouncement({payload:formatTestAnnouncement(),fetchImpl}), 'disabled');
});

test('webhook fallback works, but does not accept non-Discord origins', async () => {
  const webhook='https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyzABCDEFghijk';
  assert.equal(validDiscordWebhook(webhook), true);
  let called = 0;
  const transport = await deliverAnnouncement({webhook,payload:formatTestAnnouncement(),fetchImpl:async (url,options)=>{
    called++;
    assert.equal(url,webhook);
    assert.equal(options.headers.Authorization,undefined);
    return {ok:true,status:204};
  }});
  assert.equal(transport,'webhook');
  assert.equal(called,1);
  await assert.rejects(()=>deliverAnnouncement({webhook:'https://discord.com.bad.example/api/webhooks/123/test',payload:formatTestAnnouncement()}),/invalid URL/);
});

test('Discord failures are surfaced without logging credential contents', async () => {
  await assert.rejects(() => deliverAnnouncement({botToken:'dont-log-this',payload:formatTestAnnouncement(),fetchImpl:async()=>({ok:false,status:403})}), error=>{
    assert.match(error.message,/HTTP 403/);
    assert.equal(error.message.includes('dont-log-this'),false);
    return true;
  });
});

test('announcement dispatch requires explicit test flag; releases require a version change', async () => {
  assert.equal(await shouldAnnounce({event:'workflow_dispatch',test:true,current:'3.0.0',previous:'3.0.0'}),true);
  assert.equal(await shouldAnnounce({event:'workflow_dispatch',test:false,current:'3.0.0',previous:'1.8.0'}),false);
  assert.equal(await shouldAnnounce({event:'push',test:false,current:'3.0.0',previous:'1.8.0'}),true);
  assert.equal(await shouldAnnounce({event:'push',test:false,current:'3.0.0',previous:'3.0.0'}),false);
});
