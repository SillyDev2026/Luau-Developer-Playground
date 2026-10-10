// GitHub Actions only: sends one site-wide Discord channel announcement after
// a successful deployment and only when the release version changes.
// The webhook is a GitHub Actions secret, never exposed in public website JS.
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { promisify } from 'node:util';
import { execFile as execFileCallback } from 'node:child_process';
const runGit = promisify(execFileCallback);
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const WEBSITE = 'https://sillydev2026.github.io/Luau-Developer-Playground/';
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
  return { content: `**LuauForge v${pkg.version} is live!**\n${clean(release.title)}\n${changes}\n${WEBSITE}`, allowed_mentions: { parse: [] } };
}
export async function shouldAnnounce({ event = process.env.GITHUB_EVENT_NAME || '', current, previous }) {
  return event === 'push' && /^\d+\.\d+\.\d+$/.test(current) && current !== previous;
}
export async function announce() {
  const secret = process.env.LUAUFORGE_DISCORD_WEBHOOK_URL || '';
  if (!secret) { console.log('Discord announcements disabled: configure LUAUFORGE_DISCORD_WEBHOOK_URL as a GitHub Actions secret.'); return false; }
  if (!validDiscordWebhook(secret)) throw new Error('Discord webhook secret has an invalid URL format.');
  const pkg = JSON.parse(await readFile(join(root, 'package.json'), 'utf8'));
  const release = JSON.parse(await readFile(join(root, 'public/updates.json'), 'utf8'));
  let previous = '';
  try { const { stdout } = await runGit('git', ['show','HEAD^:package.json'], { cwd:root }); previous = JSON.parse(stdout).version || ''; }
  catch { console.log('Previous release version unavailable; skipping announcement to avoid duplicates.'); return false; }
  if (!await shouldAnnounce({ current:pkg.version, previous })) { console.log('No new release version; Discord announcement skipped.'); return false; }
  const payload = formatAnnouncement(pkg, release);
  const response = await fetch(secret, { method:'POST', headers:{ 'content-type':'application/json' }, body:JSON.stringify(payload), signal:AbortSignal.timeout(12000) });
  if (!response.ok) throw new Error(`Discord channel announcement failed (HTTP ${response.status}). Check webhook permissions and rate limits.`);
  console.log(`Discord channel release announcement published for v${pkg.version}.`);
  return true;
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) announce().catch(error => { console.error(error.message); process.exitCode = 1; });
