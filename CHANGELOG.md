## v0.3.4 — Built-in number libraries

- Added first-party library catalog for FastNum v2.9.5, NanoNum v2.4.10 and OmegaNumV2 v2.4.0.
- Added library API browser, quick import, one-click runnable examples and runtime export inspection.
- Added `require("@FastNum")`, `require("@NanoNum")`, `require("@OmegaNum")` through virtual workspace modules.
- Included built-ins in cold-load/cached require benchmarking inside Luau WASM, excluding frontend timings.
- Added strict Pages build verification for all three source libraries and real WASM integration smoke tests.
- Added browser-only OmegaNum JSONEncode adapter; original source remains untouched.

## v0.3.3 — Module tests and Luau VM benchmarks
- Fixed folder-based relative module loading with flattened synthetic module registration.
- Supported nested relative requires, module cache, `.lua`/`.luau` paths, and `init.luau`.
- Added Luau `os.clock()` measurements around each direct `require()` call; timing and cached/cold reporting appear in Output.
- Added 12-run module benchmark panel that measures cold loads and cached lookups inside fresh Luau states.
- Added true WASM integration tests for multi-module execution.

## v0.3.2 — 2026-10-08

- Fix browser WASM import failure under the GitHub Pages Jekyll branch deployment.
- Resolve runtime files from both `/wasm/` and `/public/wasm/`, always validating JS glue and WebAssembly magic/size before importing.
- Pin and commit official WebAssembly assets from GitHub Actions to make source-based Pages hosting reliable.
- Cache-bust the editor and worker modules when deploying a new version.
- Add regression tests for both publishing layouts and the runtime asset synchronization workflow.

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

## v0.3.6 — Luau IntelliSense + Roblox Studio API completion

- Type any partial in-scope local variable (for example `t` → `test` / `testSpeed`) and accept with Enter/Tab; parameters, loops and lexical shadowing are recognized.
- Autocomplete from local type annotations, inferred `game:GetService("Players")` and `Instance.new("Part")` expressions, table fields, and standard Luau library functions.
- Roblox engine methods, properties, events, class types and enum names/values from a compact API index generated in CI from the Roblox Studio API dump. Inherited class members are included. On an offline or unconfigured source-branch deployment, a curated fallback is used.
- Asynchronously enrich local suggestions using the official Luau WASM type checker; handle stale responses when the cursor or active file changes.
- Existing slash-command AutoRequire and the built-in FastNum, NanoNum and OmegaNum autocomplete remain available.
- Keep the generated API index stable between builds and sync it to the repository so GitHub Pages source/Jekyll and Actions deployments work.
- Roblox engine completions are **editor metadata only**; browser WASM does not provide `game`, DataStores, or other Roblox Studio runtime services.
