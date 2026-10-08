## v0.3.2 — 2026-10-08

- Repair Pages/Jekyll runtime mismatch by committing pinned Luau WASM assets to the branch.
- Support both root `wasm/` and `public/wasm/` runtime locations.
- Validate binary and loader before dynamic import; improve error messages.
- Cache-bust the main editor module and Web Worker on release.

# Changelog

## 0.3.1 — WebAssembly deployment and runtime repair

- Fixed the GitHub Pages missing Luau module error by serving WASM assets at project-root `/wasm/` instead of `/public/wasm/`.
- Added asset preflight checks, readable errors, release version cache busting, and stronger CI verification.
- Fixed worker termination/retry and stale execution status races.
- Updated Pages setup instructions; requires **GitHub Actions** deployment source rather than branch publishing.
- Added reproducible WASM packaging tests and error/restart regression coverage.

## v0.3.0 — WebAssembly engine

- Added native browser Luau WASM execution with a dedicated stoppable worker.
- Added Luau type checking, navigable diagnostics, and bytecode inspection.
- Pinned WASM provenance and automatic download in GitHub Pages CI.
- Added stop button, keyboard shortcuts, and updated mobile output layout.
- Kept official Playground fallback and v0.2 local storage compatibility.


## 0.2.0 — Workspace and responsive layout overhaul

- Rebalanced desktop, tablet, phone, and short-screen layout; improved positioning and size of controls, tabs, toolbar, and output.
- Resizable sidebar and output panel with saved sizes and keyboard-accessible handles.
- Added editor font scaling, layout reset, settings drawer, and more usable mobile navigation.
- Added in-file find and replace, replace-all, go-to-line, and quick command/file palette.
- Added project snapshots with restoration and a six-snapshot retention limit.
- Added explorer file filtering, collapsible folders, multi-line indent/outdent, copy, Roblox ModuleScript template, and drag/drop import.
- Migrates existing v0.1 browser saves automatically, without discarding older storage.
- Preserves cursor and scroll on settings changes; guards edits against file-size overflow; validates multi-file imports before committing changes.
- Fixed deleted-tab cleanup, folder visibility, and word-wrap gutter alignment.
- Expanded automated validation and build checks.
- The official Luau Playground remains the runtime; this is not a standalone WASM VM and the console cannot capture iframe output.

## 0.1.0 — Initial release

- Multi-file editor, syntax highlighting, local autosave, templates, import/export, themes and official Playground runner integration.
