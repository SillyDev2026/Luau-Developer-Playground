# v3.3.0 — Standalone Windows EXE

Download **LuauForge-Server-Windows-x64.exe** directly from the website's **Server .exe** button or [server-download.html](../server-download.html). No ZIP extraction or Node installation is needed.

1. Double-click the EXE on a Windows x64 PC.
2. Keep its console window open; the local API URL is `http://127.0.0.1:8787`.
3. Enter that URL in the LuauForge **Shared Scripts** or **Feedback** page.
4. Databases are stored in `%LOCALAPPDATA%\LuauForgeServer` and survive executable updates.

This is a loopback-only HTTP server by default, not a remotely available HTTPS service. To invite someone from another device or connect remotely, use a trusted HTTPS reverse proxy/tunnel, or deploy the Node backend to a hosted HTTPS provider. **Do not publicly expose the HTTP listener.** The Discord bot remains disabled until its private `DISCORD_BOT_TOKEN` environment variable is set on the running server. No bot token is shipped in the EXE.

For advanced PowerShell configuration before starting the EXE:

```powershell
$env:PORT = '8787'
$env:HOST = '127.0.0.1'
& '.\LuauForge-Server-Windows-x64.exe'
```

The binary is currently unsigned. Verify that it came from the project's GitHub Release; Windows may show a SmartScreen warning. Closing the console stops the server (it is not installed as an auto-starting Windows service).

### Building the Windows executable

The `.github/workflows/windows-server-exe.yml` workflow uses a Windows x64 runner, Node.js 26 `--build-sea`, and build-only esbuild. It starts the actual EXE to verify `/health`, workspace creation, feedback status and persistent user data before attaching the **raw .exe** directly to GitHub Release `v3.3.0`. No ZIP is provided by the website.

---

# v3.2.0 — Feedback Discord forums setup

The site's new Feedback page requires this **separately hosted HTTPS Node backend**. It does not run on GitHub Pages. Suggestions and bug reports create actual threads in Discord forum channels using the bot's Discord REST API.

1. In the Discord Developer Portal, create or reuse your bot application. Add the bot to the server that owns both forum channels. It needs View Channel, Send Messages (including forum thread creation), Read Message History and Add Reactions in both forums. Do not post its token publicly.
2. Deploy `node server/index.mjs` with a persistent storage volume. Use `render.yaml` if using Render; make sure the plan supports persistent disk. The server must be reachable over HTTPS.
3. Configure the following server environment variables:

   - `DISCORD_BOT_TOKEN`: secret bot token (never checked into Git or exposed in the website).
   - `DISCORD_SUGGESTIONS_FORUM_ID=1558939401394851850`.
   - `DISCORD_BUG_REPORTS_FORUM_ID=1558939354234093638`.
   - `FEEDBACK_DATA_FILE=/var/data/feedback.json` (an actual persistent disk path).
   - `COLLAB_DATA_FILE=/var/data/workspaces.json` if shared scripts are also enabled.
   - `ALLOWED_ORIGINS=https://sillydev2026.github.io` (plus allowed localhost origins for local testing).

4. Open LuauForge → Feedback, enter your backend HTTPS origin, and connect a display-name profile. Create a test suggestion and verify the resulting Discord forum thread, then submit a bug report and verify the other forum. Test thumbs-up/down and undo.

API: `GET /api/feedback/status` reports whether the bot/channel settings exist (not whether Discord permissions have been validated). `POST /api/feedback/session` creates a pseudonymous tab token; `GET /api/feedback/posts` lists public website posts; `POST /api/feedback/posts` creates a Discord thread; `POST /api/feedback/posts/:id/vote` changes a website vote. The backend stores hashed profile tokens, messages, Discord thread IDs and votes in a separate JSON database. Do not run multiple Node replicas on that JSON file.

**Voting semantics:** website users can upvote/downvote or undo their own session's vote; totals are edited into the forum's bot-authored starter post. Discord users can separately react with native emojis. Discord reactions are **not** imported into the website count, and website visitors cannot react as Discord accounts via a shared bot token. Sessions are not verified identities, so malicious users can generate more profiles; rate limiting mitigates casual abuse but is not strong identity protection. Form content is untrusted and passed as plain text with all mentions disabled. The app doesn't add a moderation dashboard yet; server admins moderate forum posts in Discord.

**Reliability:** failed Discord thread creation returns a visible error and does not claim a successful post. If updating the forum vote summary fails after a valid local vote, the vote is retained and the summary retries on a later board refresh. If the bot is unconfigured, posting is disabled. Disconnecting from the Feedback UI only ends the current tab session. No Discord bot token is transmitted to the website.

---

# v3.1.1 updates: Scripts page and safer Studio synchronization

Open the new **Scripts** page from the top toolbar or mobile dock. Search and filter shared scripts, inspect published code, open the Luau editor, publish changed code, and (with editor permission) rename or move a script to another supported Studio destination. The workspace owner can remove invited developers with immediate token revocation; invited editors and viewers can use **Leave workspace** to revoke their own tokens. **Disconnect** only clears the browser tab, not the server token.

A failed Studio update now exposes an error in the script page and retries after 15 seconds, increasing up to five minutes on repeated failure. A newer code revision skips the old backoff. Studio plugin revisions now keep a source checksum to detect changes made directly in Studio, including an open editor source buffer, before applying an update. If a new script cannot be populated, the plugin destroys its empty placeholder. For older managed scripts without a checksum, back up the place and manually inspect on first upgrade. The plugin does not auto-resolve source conflicts or class-change conflicts.

All existing Node backend data files keep the same storage schema. GitHub Pages deployment still does not deploy Node hosting; set up an HTTPS backend and install the Studio plugin separately.

---

# LuauForge shared workspaces and Studio bridge (v3.1.0)

The GitHub Pages .io website is a static frontend. It cannot run Node.js. You must deploy the opt-in collaboration backend on a separate HTTPS host. Existing local projects stay local; only scripts created or published into a shared workspace are uploaded.

## Local setup

Requires Node.js 22+. No third-party npm packages.

1. Run: npm run collab:serve
2. Visit http://127.0.0.1:8787/health to verify the API.
3. Run: npm run dev
4. Open LuauForge on http://127.0.0.1:4173; in Inspector open Shared Workspace + Roblox Studio.
5. Enter http://127.0.0.1:8787 as the API origin, give yourself a display name, and create a workspace.
6. Create a Script, LocalScript or ModuleScript, select its Studio destination, click Edit, then Publish to synchronize it.
7. Generate a one-use invitation code and send the code plus the API URL privately. The invited editor or viewer joins with their own display name.

When running local-only, set HOST=127.0.0.1 (otherwise the backend listens on all interfaces). Do not expose plain HTTP to the internet.

## Public deployment

Deploy server/index.mjs to Render, Railway, Fly, or a VPS behind HTTPS and a persistent disk:

- PORT: Assigned by hosting provider (default 8787).
- HOST: 0.0.0.0.
- COLLAB_DATA_FILE: Persistent volume path, e.g. /var/data/workspaces.json.
- ALLOWED_ORIGINS: Comma-separated frontend origins, e.g. https://sillydev2026.github.io,http://localhost:4173.

Start command: node server/index.mjs. An optional render.yaml blueprint configures the persistent volume. The service uses a single-process atomic JSON database; do not run more than one server replica against it. For larger teams migrate to a transactional database.

## Install Roblox Studio bridge

1. Open studio/LuauForgeBridge.plugin.lua in the repo. Install the Lua source as a LOCAL STUDIO PLUGIN SCRIPT (not a Script in a published game).
2. In Roblox Studio enable HTTP requests / approve the API URL prompt if needed.
3. On the website, the workspace owner generates a Studio pairing token. The workspace ID appears in the Shared Workspace panel.
4. In Roblox Studio click LuauForge → Workspace Bridge and paste the HTTPS API origin, workspace ID and Studio token. Press Connect.
5. In Edit mode the plugin polls for pending scripts approximately every 5 seconds, creates managed scripts, and updates source with ScriptEditorService:UpdateSourceAsync.

Supported placements:
- ReplicatedStorage -> game.ReplicatedStorage
- ServerScriptService -> game.ServerScriptService
- StarterGui -> game.StarterGui
- StarterPlayerScripts -> game.StarterPlayer.StarterPlayerScripts

Typical execution: server Script in ServerScriptService; UI LocalScript in StarterGui; player LocalScript in StarterPlayerScripts; shared ModuleScript in ReplicatedStorage. Some type/service combinations can be stored but not executed.

Existing Studio scripts without matching LuauForgeWorkspace / LuauForgeScriptId attributes are never overwritten. Class changes to already managed objects require manual review. The plugin never deletes scripts or uploads Studio source to the web; this MVP is web -> Studio only. The Studio token is kept only in plugin memory for the session.

## Permissions and limitations

- Owner creates invite codes (single use, 24 hour expiration), edits scripts and controls Studio pairing.
- Editor reads, creates and publishes shared scripts. Editor-published Luau may run in Studio / the game once synced. Invite trusted people only.
- Viewer can read, not edit or pair Studio.
- All session tokens and one-use invite codes are random secrets. Server stores only SHA-256 digests. Generating a new Studio token invalidates the old one.
- The browser keeps its session token in sessionStorage, not in exported workspaces; Disconnect clears it from the tab, but does NOT revoke the server-side token.
- SHARED script source and display names are saved on YOUR HOSTED BACKEND. Protect disk and backups; never commit data files or tokens to GitHub.
- Save/Publish is explicit, not per-keystroke. Concurrent changes use revision checks (HTTP 409) instead of overwriting. Team list polls every 5 seconds.
- There is no GitHub/Roblox SSO, live cursors/CRDT editing, multi-instance database, Studio-to-web uploads, or automatic token revocation in this MVP.

API tests: npm test. Health endpoint: GET /health.
