# LuauForge — Luau Developer Playground v0.2.0

A dependency-free, responsive, GitHub Pages-compatible Luau development workspace with real Luau compilation and execution through the **official Luau Playground**.

> **Runtime boundary:** LuauForge edits and stores code locally. Selecting **Run** opens the official Luau Playground in an embedded iframe with code preloaded through its compressed share format. Compiler/type-check output appears inside that embedded site, **not** inside LuauForge's separate status console. Roblox APIs such as `game`, `workspace`, and DataStoreService cannot run in the standalone Luau engine.

## What's new in v0.2

- Responsive layout tuned for desktop, tablet, narrow phones and short displays
- Drag-to-resize explorer and output panel (also keyboard accessible); size preferences are saved
- Adjust editor font size 11–22px; reset layout sizes
- Mobile file explorer and settings drawer with click-away overlay
- Find and replace (current file), case-sensitive toggle, previous/next matches, replace all
- Quick commands and file navigation palette; Ctrl/Cmd+P
- Go to line; Ctrl/Cmd+G
- Local project snapshots, capped at six recovery points, with restore/delete
- Filter explorer files and collapse folders
- Multiline indent/outdent with Tab / Shift+Tab
- New Roblox ModuleScript template (Studio-only execution)
- Drag/drop .lua/.luau/workspace JSON into the editor
- Copy current source; guard editor against storage file size limits
- v0.1 save migration, fixes for lost cursor position on settings changes and deleted tabs

## Core features

- Syntax-highlighted multi-file Luau editor, named folders and tabs
- Strict / Nonstrict / Nocheck and compiler optimization O0/O1/O2 settings passed to the official runner
- Automatic browser-local saves, project JSON import/export, single-file download
- Dark/light themes, responsive mobile interface and keyboard shortcuts
- GitHub Actions checks and GitHub Pages deployment

## Development

No npm install or external packages are needed to edit, run tests or create the static build.

```bash
npm run dev
npm run check
```

Open http://localhost:4173/ for local development.

## Deploy

The GitHub Actions workflow builds and deploys the `dist/` directory to GitHub Pages from `main`.

1. Go to **Settings → Pages** in the repository.
2. Set **Build and deployment** source to **GitHub Actions**.
3. Push to `main`; check the Actions status.
4. Open https://sillydev2026.github.io/Luau-Developer-Playground/ when deployment finishes.

All static asset links are relative, so hosting in a repository subpath works without Vite.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Ctrl/Cmd + Enter | Open official Luau runner |
| Ctrl/Cmd + S | Save locally |
| Ctrl/Cmd + F | Find / replace |
| Ctrl/Cmd + P | Commands & file search |
| Ctrl/Cmd + G | Go to line |
| Tab / Shift+Tab | Indent / outdent source |
| Escape | Close dialogs/drawers/search |
| `/` outside text fields | Focus explorer filter |

## Storage and privacy

- Files, layout preferences, and snapshots use your browser's `localStorage`. This isn't cloud sync; data can be lost when clearing browser storage. **Export a JSON backup regularly.**
- v0.1 saves under `luau-dev-playground:v1` are loaded and migrated to `v2` upon saving. Original v1 data is retained.
- Projects have size/file limits. Import validates files and rejects invalid/malformed projects. A failed import doesn't replace the working project.
- The official runner needs an internet connection. The LZ-String codec is currently loaded from cdnjs. The editor works offline after assets are cached by the browser, but no offline execution is promised.
- Running code passes the project's source in the official Playground share URL, which that page can read. **Never place secrets in scripts intended for sharing or external execution.**
- The embedded official runner is a cross-origin iframe and LuauForge cannot capture or control its execution results. No independent WASM engine is included in v0.2.

## Source layout

```text
index.html                   Accessible responsive UI
src/main.js                  Editor, controls, panes, commands and runner integration
src/styles.css               Layout, themes and responsive styling
src/store.js                 Versioned validated project and migration
src/editor-utils.js          Find, replace, line navigation and indentation
src/snapshots.js             Local recovery point management
src/highlight.js             Safe presentation-only Luau lexer
src/runner.js                Official Luau Playground compressed-share integration
scripts/build.mjs            Dependency-free production build
scripts/serve.mjs            Local dev server
.github/workflows/           GitHub Actions tests / Pages deploy
public/                      Brand assets
tests/                       Node unit and build tests
```

## Later versions

Standalone Luau WASM engine, in-editor type diagnostics, richer file search, IndexedDB project storage, and GitHub synchronization are separate future work. They are not described as v0.2 features.
