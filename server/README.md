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
