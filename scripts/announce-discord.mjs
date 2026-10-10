// GitHub Actions only. Post release notices AFTER successful Pages deployment.
// The Discord bot token or webhook is read only from Actions secrets, never
// from the website, localStorage, repository files, or user-controlled URLs.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { promisify } from 'node:util';
import { execFile as execFileCallback } from 'node:child_process';
const runGit = promisify(execFileCallback);
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const WEBSITE = 'https://sillydev2026.github.io/Luau-Developer-Playground/';

// Discord snowflake IDs are public identifiers, not credentials.
export const DISCORD_APPLICATION_ID = '1491648971041411163';
export const DISCORD_CHANNEL_ID = '1558591089529851915';
export const BOT_INVITE_URL = `https://discord.com/oauth2/authorize?client_id=${DISCORD_APPLICATION_ID}&scope=bot&permissions=3072`;

export function validSnowflake(id) {
  return typeof id === 'string' && /^\d{17,20}$/.test(id);
}
export function validDiscordWebhook(url) {
  try {
    const x = new URL(url);
    return x.protocol === 'https:' && ['discord.com', 'discordapp.com'].includes(x.hostname) && /^\/api\/webhooks\/\d{15,25}\/[A-Za-z0-9_-]{30,}$/.test(x.pathname) && !x.search && !x.hash;
  } catch { return false; }
}
export function formatAnnouncement(pkg, release) {
  if (pkg.version !== release.version) throw new Error('Package version and release feed do not match.');
  const clean = str => String(str).replace(/[@*`~<>|]/g, '').replace(/\s+/g, ' ').trim();
  const changes = release.changes.slice(0, 6).map(item => '• ' + clean(item).slice(0, 150)).join('\n');
  return {
    content: `**LuauForge v${pkg.version} is live!**\n${clean(release.title)}\n${changes}\n${WEBSITE}`.slice(0, 2000),
    allowed_mentions: { parse: [] }
  };
}
export function formatTestAnnouncement() {
  return { content: `**LuauForge Discord connection test**\nRelease announcements are configured for this channel.\n${WEBSITE}`, allowed_mentions: { parse: [] } };
}
export async function shouldAnnounce({ event = process.env.GITHUB_EVENT_NAME || '', current, previous, test = false }) {
  if (event === 'workflow_dispatch') return test === true;
  return event === 'push' && /^\d+\.\d+\.\d+$/.test(current) && current !== previous;
}
export async function deliverAnnouncement({ botToken = '', webhook = '', channelId = DISCORD_CHANNEL_ID, payload, fetchImpl = fetch }) {
  if (!payload || typeof payload.content !== 'string' || payload.content.length > 2000) throw new Error('Discord announcement body is invalid.');
  if (botToken) {
    if (!validSnowflake(channelId)) throw new Error('Discord channel ID is invalid.');
    const response = await fetchImpl(`https://discord.com/api/v10/channels/${channelId}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bot ${botToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ ...payload, allowed_mentions: { parse: [] } }),
      signal: AbortSignal.timeout(12000)
    });
    if (!response.ok) throw new Error(`Discord bot announcement failed (HTTP ${response.status}). Verify bot installation, token, and View Channel / Send Messages permissions.`);
    return 'bot';
  }
  if (webhook) {
    if (!validDiscordWebhook(webhook)) throw new Error('Discord webhook secret has an invalid URL format.');
    const response = await fetchImpl(webhook, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ...payload, allowed_mentions: { parse: [] } }),
      signal: AbortSignal.timeout(12000)
    });
    if (!response.ok) throw new Error(`Discord webhook announcement failed (HTTP ${response.status}). Check webhook permissions and rate limits.`);
    return 'webhook';
  }
  return 'disabled';
}
export async function announce() {
  const botToken = process.env.LUAUFORGE_DISCORD_BOT_TOKEN || '';
  const webhook = process.env.LUAUFORGE_DISCORD_WEBHOOK_URL || '';
  if (!botToken && !webhook) {
    console.log('Discord announcements disabled: set LUAUFORGE_DISCORD_BOT_TOKEN (preferred) or LUAUFORGE_DISCORD_WEBHOOK_URL in GitHub Actions secrets.');
    return false;
  }
  const test = process.env.LUAUFORGE_DISCORD_TEST_ANNOUNCEMENT === 'true';
  const event = process.env.GITHUB_EVENT_NAME || '';
  const pkg = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  const release = JSON.parse(await readFile(join(root, 'public/updates.json'), 'utf8'));
  let previous = '';
  if (event === 'push') {
    try {
      const { stdout } = await runGit('git', ['show', 'HEAD^:package.json'], { cwd: root });
      previous = JSON.parse(stdout).version || '';
    } catch { console.log('Previous release version unavailable; skipping announcement to avoid duplicates.'); return false; }
  }
  if (!await shouldAnnounce({ event, current: pkg.version, previous, test })) {
    console.log('No new release version or manual test request; announcement skipped.');
    return false;
  }
  const payload = test && event === 'workflow_dispatch' ? formatTestAnnouncement() : formatAnnouncement(pkg, release);
  const transport = await deliverAnnouncement({ botToken, webhook, payload });
  if (transport === 'disabled') return false;
  console.log(`LuauForge Discord ${test ? 'test' : 'release'} message posted using ${transport} transport.`);
  return true;
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) announce().catch(error => { console.error(error.message); process.exitCode = 1; });
