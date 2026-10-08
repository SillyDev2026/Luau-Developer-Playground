# LuauForge v0.3.2 — WASM deployment repair

**Important:** GitHub Pages supports an Actions artifact and a branch/Jekyll source, but the two build layouts place WASM files at different paths. v0.3.2 resolves both automatically. The Pages deployment workflow pins and commits official Luau Playground JS and WASM runtime assets into `public/wasm/`, so a Jekyll branch deployment has a usable runtime. The custom Actions build also publishes copies at `wasm/`.

# LuauForge v0.3.1 — Luau Developer Playground

A mobile-friendly, multi-file Luau editor with self-hosted **Luau WebAssembly** execution, type checking, diagnostics, bytecode inspection, snapshots, and local autosave. Hosted as a static GitHub Pages site at:

https://sillydev2026.github.io/Luau-Developer-Playground/

## v0.3.1 runtime/deployment fix

- Fixed a broken deployment path: the old site looked for `public/wasm/luau-module.js`, which can be missing when Pages publishes the branch rather than the Actions artifact. The build now flattens `public/` into `dist/` (same convention as Vite) and loads `wasm/luau-module.js` and `wasm/luau.wasm` relative to the worker's project URL.
- Added versioned asset URLs, preflight validation and actionable HTTP/HTML errors when a Pages deployment is incomplete.
- The build and CI **fail** if the matching Lua module loader or WASM engine is absent, instead of deploying a broken site.
- Fixed execution worker retry/termination state and avoided an older stopped run clearing the status of a newer one.
- Preserved the v0.1/v0.2 project storage format, file browser, search, mobile layout, snapshots and official Playground fallback.

## IMPORTANT: GitHub Pages source setting

In your repo, visit **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**, **not** `Deploy from a branch`.

The successful `Test and deploy GitHub Pages` job creates a complete artifact, including the 4.7 MB Luau WASM engine. GitHub's older automatic `pages build and deployment` job may also run when the site is set to deploy from a branch. A branch deployment does not contain the WASM assets (they are intentionally downloaded in Actions and not committed), so it can overwrite the functional site with a page that fails at runtime. Switching the source to GitHub Actions is necessary and cannot be fixed by JavaScript alone.

After changing Source, visit the **Actions** tab, rerun **Test and deploy GitHub Pages**, then hard-refresh the website. To verify the correct release, both of these URLs must return the actual file rather than a 404 or HTML page:

- `https://sillydev2026.github.io/Luau-Developer-Playground/wasm/luau-module.js`
- `https://sillydev2026.github.io/Luau-Developer-Playground/wasm/luau.wasm`

## Run locally

Requires Node.js 22 or later (built-in fetch) and internet access the first time to obtain the pinned assets.

```bash
npm run fetch:wasm
npm run dev
```

Visit `http://localhost:4173/`. For a complete production build:

```bash
npm run check
npm run smoke:wasm
```

`npm run check` includes 37+ unit/contract tests, syntax checks, production build and WASM packaging verification. `npm run smoke:wasm` executes a real Luau program and verifies type diagnostics and bytecode.

The runtime assets are pinned to official `luau-lang/playground` commit `e232f443148728fe5b8e714f1796aaa676287df7`. The `scripts/fetch-wasm.mjs` script downloads the matching Emscripten loader and engine. They are intentionally excluded from the Git source via `.gitignore`, but packaged into `dist/` by GitHub Actions.

## Workspace features

- Lua/Luau editor with highlighting, tabs, file-tree folders and import/export.
- Execution via a dedicated Web Worker, with Stop button for runaway scripts.
- Independent analysis worker for Luau errors, type diagnostics and bytecode viewing, selectable strictness and O0/O1/O2.
- Local snapshots, autosave, file search and find/replace, resizing and dark/light themes.
- Responsive layout for phone, tablet and desktop.
- Optional official Luau Playground share/embed runner.

This WebAssembly engine is a standalone Luau VM, **not Roblox Studio**. Roblox APIs such as `game`, `workspace`, `Players` and `DataStoreService` are not present. Browser timings are not directly comparable to Luau performance inside Roblox Studio.

## Privacy

Source code edited in LuauForge stays in the browser for local execution. Local projects use `localStorage`; clearing browser data may delete them. Export workspaces frequently. Opening the optional hosted Playground will send the shared source through its URL. Never put secrets in code you intend to share.

## Layout

- `src/` — editor, storage, workers, runtime client
- `public/` — static assets and fetched WebAssembly engine (WASM files ignored by Git)
- `scripts/` — build, fetch, verify, local server and real Luau smoke tests
- `tests/` — unit tests and static deploy/worker contracts
- `.github/workflows/` — CI and GitHub Pages release pipeline
