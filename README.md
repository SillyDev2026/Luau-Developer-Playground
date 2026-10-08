# LuauForge — Luau Developer Playground v0.1.0

A responsive, GitHub Pages-compatible development workspace for Luau programmers.

## Working features

- Multi-file Luau workspace with tabs and nested file paths
- Syntax coloring, line numbers, cursor position, Tab-to-indent, Ctrl+S and Ctrl+Enter
- Strict/nonstrict/nocheck compiler mode and O0/O1/O2 settings
- Real Luau compilation, analysis and execution via the **official Luau Playground** iframe
- Persistent local workspace (browser localStorage), autosave, project and single-file export
- Import `.lua`, `.luau` and project `.json` files
- Dark/light mode, mobile layout, sample templates, quick download
- Automated Node tests and GitHub Actions deployment

## Run locally

No npm dependencies or compilation are necessary. Start the built-in local server:

```bash
npm run dev
```

Open `http://localhost:4173/`. **Internet access is required to load the external official Luau runner and LZ-String share codec.** The editor still works without them. To run checks:

```bash
npm run check
```

## GitHub Pages deployment

1. Create a public GitHub repository named `Luau-Developer-Playground` (or use another name).
2. Upload these files, keeping the `.github/workflows/` directory.
3. In repository **Settings → Pages → Build and deployment**, choose **GitHub Actions**.
4. Push to `main`. The deployment workflow tests and publishes `dist/` automatically.
5. URL: `https://YOUR_USERNAME.github.io/Luau-Developer-Playground/`.

All asset URLs are relative and work under a GitHub Pages repository path without a Vite base setting.

## What the runner does

Click **Run code** or press **Ctrl+Enter**. The site serializes the current workspace in the official Luau Playground's v2 compressed share format, then loads an embedded frame hosted at `https://play.luau.org/`. The external engine provides actual compilation, type diagnostics, execution and output **inside that iframe**. It is not a custom Luau engine and the page does not read or capture its output due to cross-origin browser protections. Changes inside the runner do not sync back; edit in LuauForge and reopen to refresh its source. Large projects use the active file only if the generated URL is too long.

The runner does **not** provide Roblox engine services (`game`, `workspace`, `Instance`, DataStore etc.), and it is not a replacement for testing in Roblox Studio. The external engine and compiler are from the official Luau project: https://github.com/luau-lang/playground .

## Privacy and limits

- Local source is stored in your browser's localStorage (same browser and origin only). Export backups regularly.
- Launching the runner places compressed source in a URL fragment and loads the official Luau site. The fragment is not sent in HTTP requests to that site's server, but the external page's scripts can read it. **Do not execute or share secrets**.
- Browser storage is not encrypted and has a quota; large projects and cross-device sync are not supported yet.
- Only `.lua` and `.luau` files can be imported directly, and project JSON imports are validated and size-limited.
- The CDN provides the `lz-string` share codec. For fully independent execution in v0.2, integrate a locally bundled official Luau WASM runtime.

## Structure

```text
index.html                  UI and editor shell
src/main.js                 UI, file editor, import/export and runner wiring
src/store.js                Validated project model and persistence
src/highlight.js            Presentation syntax highlighting
src/runner.js               Official Luau compressed-share integration
src/styles.css              Responsive dark/light design
scripts/build.mjs           Dependency-free static build
public/favicon.svg          Branding
.github/workflows/          CI and GitHub Pages deployment
tests/                      Unit tests
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Ctrl / Cmd + Enter | Open official runner |
| Ctrl / Cmd + S | Save workspace locally |
| Tab | Insert four spaces |
| Escape | Close runner |

## Next version

Local WASM integration with directly streamed console output, in-editor compiler diagnostics, background type analysis, and robust IndexedDB storage. The v0.1 runner currently uses the official hosted engine instead.
