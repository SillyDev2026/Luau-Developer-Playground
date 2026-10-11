// Public account labels and in-app update preferences only. Never store OAuth,
// Discord bot tokens or webhook URLs in browser storage.
export const COMMUNITY_KEY = 'luauforge:community:v1';
export const CURRENT_VERSION = '3.0.2';
const DEFAULTS = Object.freeze({ github: '', discord: '', inAppUpdates: true, lastSeenRelease: '' });

export function validateGithub(name) {
  return name === '' || (/^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$/.test(name) && !name.includes('--'));
}
export function validateDiscord(name) {
  return name === '' || (/^[a-z0-9_.]{2,32}$/.test(name) && !name.includes('..'));
}
export function sanitizeCommunity(value) {
  const data = value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const github = typeof data.github === 'string' && validateGithub(data.github.trim()) ? data.github.trim() : '';
  const discord = typeof data.discord === 'string' && validateDiscord(data.discord.trim().toLowerCase()) ? data.discord.trim().toLowerCase() : '';
  const lastSeenRelease = typeof data.lastSeenRelease === 'string' && /^\d+\.\d+\.\d+$/.test(data.lastSeenRelease) ? data.lastSeenRelease : '';
  return { github, discord, inAppUpdates: data.inAppUpdates !== false, lastSeenRelease };
}
export function loadCommunity(storage) {
  try { return sanitizeCommunity(JSON.parse(storage.getItem(COMMUNITY_KEY) || '{}')); } catch { return { ...DEFAULTS }; }
}
export function saveCommunity(storage, value) {
  const settings = sanitizeCommunity(value);
  if (!validateGithub(String(value.github ?? '').trim())) throw new Error('GitHub username must use letters, digits, or single hyphens (max 39).');
  if (!validateDiscord(String(value.discord ?? '').trim().toLowerCase())) throw new Error('Discord username must be 2–32 lowercase characters: letters, digits, _ or .');
  storage.setItem(COMMUNITY_KEY, JSON.stringify(settings));
  return settings;
}
export function parseRelease(data) {
  if (!data || typeof data !== 'object' || !/^\d+\.\d+\.\d+$/.test(data.version || '')) throw new Error('Release feed has no valid version.');
  if (typeof data.title !== 'string' || data.title.length > 120 || !Array.isArray(data.changes)) throw new Error('Invalid release feed.');
  const changes = data.changes.filter(s => typeof s === 'string' && s.length <= 200).slice(0, 12);
  if (!changes.length) throw new Error('Release feed is empty.');
  return { version: data.version, title: data.title, changes, publishedAt: typeof data.publishedAt === 'string' ? data.publishedAt.slice(0, 35) : '' };
}
export function newerVersion(a, b) {
  const parse = s => /^\d+\.\d+\.\d+$/.test(s || '') ? s.split('.').map(Number) : [0,0,0];
  const x = parse(a), y = parse(b);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i];
  return false;
}
export function shouldShowUpdate(release, profile) {
  return profile.inAppUpdates && newerVersion(release.version, profile.lastSeenRelease);
}

export function mountCommunitySettings({ notify = () => {}, onOpenRelease = () => {} } = {}) {
  const $ = id => document.getElementById(id);
  const container = $('community-settings');
  const banner = $('release-banner');
  if (!container || !banner) return { check: async () => null, open: () => {} };
  const github = $('community-github'), discord = $('community-discord'), enabled = $('community-updates');
  const status = $('community-status'), changeList = $('release-changes');
  let profile = loadCommunity(localStorage);
  let latestRelease = null;
  const refreshFields = () => { github.value = profile.github; discord.value = profile.discord; enabled.checked = profile.inAppUpdates; };
  refreshFields();
  function displayRelease(release) {
    latestRelease = release;
    changeList.replaceChildren();
    const head = document.createElement('strong'); head.textContent = `${release.title} · v${release.version}`;
    changeList.append(head);
    const list = document.createElement('ul');
    for (const change of release.changes) { const li = document.createElement('li'); li.textContent = change; list.append(li); }
    changeList.append(list);
    banner.classList.toggle('hidden', !shouldShowUpdate(release, profile));
    $('release-banner-text').textContent = `${release.title} — v${release.version}`;
    status.textContent = `Latest public release: v${release.version}. Discord channel alerts require the site owner's webhook setup.`;
  }
  async function check({ quiet = false } = {}) {
    try {
      let res = await fetch(new URL('./updates.json', document.baseURI), { cache: 'no-store' });
      // GitHub's old branch-based Pages workflow can still serve /public/*.
      // Fallback avoids a false "no updates" status while owners switch to Actions.
      if (res.status === 404) res = await fetch(new URL('./public/updates.json', document.baseURI), { cache: 'no-store' });
      if (!res.ok) throw new Error(`Updates HTTP ${res.status}`);
      const release = parseRelease(await res.json());
      if (newerVersion(CURRENT_VERSION, release.version)) {
        banner.classList.add('hidden');
        status.textContent = `Update feed is older than this installation (v${CURRENT_VERSION}); refresh online to check newer releases.`;
        return release;
      }
      displayRelease(release);
      if (!quiet) notify(`Release feed checked: v${release.version}`);
      return release;
    } catch (err) {
      status.textContent = `Cannot check for updates: ${err.message}. Offline editing still works.`;
      if (!quiet) notify(status.textContent, true);
      return null;
    }
  }
  $('community-save').addEventListener('click', () => {
    try {
      profile = saveCommunity(localStorage, { ...profile, github: github.value, discord: discord.value, inAppUpdates: enabled.checked });
      if (latestRelease) displayRelease(latestRelease);
      notify('Public usernames and update preferences saved on this device. No Discord DM or GitHub account was connected.');
    } catch (err) { notify(err.message, true); }
  });
  $('community-clear').addEventListener('click', () => {
    localStorage.removeItem(COMMUNITY_KEY); profile = { ...DEFAULTS }; refreshFields();
    if (latestRelease) displayRelease(latestRelease);
    notify('Community preferences cleared on this device.');
  });
  $('community-check').addEventListener('click', () => check());
  $('release-dismiss').addEventListener('click', () => {
    if (!latestRelease) return;
    profile.lastSeenRelease = latestRelease.version;
    try { profile = saveCommunity(localStorage, profile); } catch { /* device storage unavailable */ }
    banner.classList.add('hidden');
  });
  $('release-open').addEventListener('click', () => { onOpenRelease(); container.scrollIntoView({ block:'start', behavior:'smooth' }); banner.classList.add('hidden'); });
  const profileSummary = $('community-summary');
  const updateSummary = () => { if(profileSummary) profileSummary.textContent = `${profile.github ? '@'+profile.github : 'No GitHub name'} · ${profile.discord || 'No Discord name'} · Profiles saved locally`; };
  $('community-save').addEventListener('click', updateSummary);
  $('community-clear').addEventListener('click', updateSummary);
  updateSummary();
  // A release can be seen only while visiting the site; service workers cannot
  // deliver Discord DMs. Channel announcements run separately in GitHub Actions.
  check({ quiet: true });
  return { check, open: () => { const card = $('community-settings'); card.scrollIntoView({ block: 'start', behavior: 'smooth' }); }, get profile() { return { ...profile }; }, get release() { return latestRelease; } };
}
