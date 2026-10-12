## 3.3.0 — 2026-10-11

- Add direct Windows Node server .exe download links in site header, Shared Scripts, Feedback, and dedicated setup page.
- Package the Node collaboration and Discord-feedback APIs into one Windows x64 standalone executable using Node 26 SEA and esbuild at build time.
- Default to local-only `127.0.0.1:8787` and persistent user data under `%LOCALAPPDATA%\LuauForgeServer`.
- Publish raw .exe in GitHub Release after Windows build/startup/API smoke tests (website does not download a ZIP).
- Keep bot secrets and optional HTTPS hosting separately configured; preserve Node source deployment and existing LuauForge workflows.

## 3.2.0 — 2026-10-11

- Introduce a full-width community Feedback page with separate suggestion and bug forms, search, filters, sorting, responsive post cards and direct Discord thread links.
- Add secure Node Discord forum integration, using suggestion channel `1558939401394851850` and bug-report channel `1558939354234093638`.
- Add website thumbs-up/down votes with one active vote per pseudonymous session, click-to-undo, server-side counts and updates to the bot-authored Discord forum message.
- Add optional bot-created 👍/👎 Discord reactions (separate from website counts), safe `allowed_mentions`, rate limiting, validation, privacy controls and failure reporting.
- Include independent persistent feedback storage, environment-configurable forum IDs, optional Render settings, mocked Discord integration tests and deploy docs.
- Keep private bot tokens outside the browser and preserve current editor, Studio bridge and local workspace features.

## 3.1.2 — 2026-10-11

- Read adjacent Luau `--`/`---` and block comments as function documentation, including in imported workspace ModuleScripts.
- Show the documentation in IntelliSense hover, imported function autocomplete and active parameter signature hints.
- Avoid unrelated comments, Luau `--!strict` directives and strings; display comments as plain text, not HTML.
- Add focused regressions for single-line and multiline docs, unrelated comments, anonymous functions and imported modules. Preserve existing editor and workspace behavior.

## 3.1.1 — 2026-10-11

- Create a full-width responsive Shared Scripts page and mobile/desktop navigation, with searchable/filterable script cards, source preview, script metadata controls, revision labels, and placement guidance.
- Fix shared script file identity, stale refresh/create races, publish dirty-state visibility, and accidental replacement of unpublished local drafts.
- Add owner-managed member removal and voluntary leave/revoke APIs, with permission checks.
- Retry failed Studio sync with exponential delay and surface per-script failure details; newly edited revisions remain immediately eligible.
- Harden Studio plugin endpoint validation, detect modified Studio source (including editor buffers), and destroy new tagged objects after failed source updates.
- Expand Node API and static UI regression tests; preserve local-only editor, Luau formatting, plugins, WASM and old project schemas.

## 3.1.0 — 2026-10-11

- Add opt-in Node collaboration service with persisted shared workspaces, owner/editor/viewer permissions, one-use 24-hour invites, bearer-token hashing, origin allowlisting, size limits and optimistic revision checks.
- Integrate a collaboration panel into the existing .io editor for creating Script, LocalScript and ModuleScript files; choose ReplicatedStorage, ServerScriptService, StarterGui or StarterPlayerScripts destinations.
- Build Studio plugin with user-approved token pairing, polling and ScriptEditorService-based managed script updates; protect unmanaged scripts and pause while Studio is running a game.
- Ship Node/server tests, optional Render deployment template and security/setup documentation. Requires separate persistent HTTPS hosting; Pages remains a static frontend.
- Keep local-only project storage, editor layout, IntelliSense, Luau WASM runtime and bundled libraries untouched by default.

## 3.0.6 — 2026-10-11

- Add public exported Luau type aliases distinct from private type declarations.
- Resolve imported Module.Data and enforce exported names in type-only completion.
- Derive type members from export type Data = typeof(data) and literal nested record aliases.
- Use declared exported type fields for typed local member completion rather than unrelated global/Roblox/WASM suggestions.
- Preserve same-file private type usage, protect masked strings/comments, and add cross-file regression coverage.
- Preserve saved workspaces, code formatting, Luau WASM runtime and editor layout.

## 3.0.5 — 2026-10-11

- Reset stale editor suggestions, pending async completions, and hover popups whenever a different Lua/Luau source file is loaded.
- Rebind IntelliSense to newly created scripts, opened files, renamed files, imports, and workspace restores.
- Suggest exported functions of relatively imported workspace modules across `.lua`, `.luau`, nested `scripts/`, `modules/`, and `tests/` folders.
- Share exported module signatures across completion, call hints, and hover; do not expose private helpers as module methods.
- Add tests for new script lifecycle, nested import resolution, module privacy, and typed functions. Preserve local workspace schema, editor geometry, and WASM runtime.

## 3.0.4 — 2026-10-11

- Do not suggest already complete Luau keywords such as `end`, `else` or `return`.
- Automatic completion no longer intercepts Enter/newline or arrow-key cursor movement.
- Tab completes unfinished suggestions but preserves normal indentation for exact matches.
- Ctrl+Space explicitly enables arrow-key suggestion navigation and Enter/Tab acceptance.
- Add keyboard regression tests; preserve editor layout, workspace storage and Luau runtime.

## 3.0.3 — 2026-10-10

- Type-only completion for function parameters, returns, typed locals, casts and type aliases; stop mixing WASM value suggestions into annotation menus.
- Hover signatures for locally declared functions, imported workspace modules, documented bundled APIs and Roblox APIs.
- Extend call-site signature hints to workspace module functions, keep tooltips non-interactive, and cover pointer and import edge cases.
- Keep existing editor layout, workspace persistence and Luau WASM runtime unchanged.

## 3.0.2 — 2026-10-10

- Fix IntelliSense keyboard handling when suggestion lists are empty or hidden.
- Mask long bracket strings/comments consistently so completion and import analysis ignore literal text.
- Ignore comment/string brackets in editor bracket navigation.
- Reject stale source cleanup previews and lockfile imports whose exact pinned source does not match.
- Validate pinned package sizes and report truncation only when entries were actually omitted.
- Add regression tests for these cases without changing the saved workspace format.

# v3.0.1 — Console version and Discord community hotfix (2026-10-10)

- Console welcome and startup message share current v3.0.1 version; community release version corrected.
- Official Discord invite in Dashboard and settings, with external-link safety attributes.
- Exact-limit workspace search truncation corrected and regression tested.
- Refreshed offline cache; no changes to editor geometry, workspace saves or Luau VM.

# v3.0.0 — V3 Workbench foundation (2026-10-10)

- Isolated v3 project-tools UI and offline static analysis: multi-file search, project advisory audit, read-only diff and exportable Markdown report.
- Conservative, snapshot-backed source cleanup; preserves Luau assignments, string contents and user script formatting.
- Immutable pinned GitHub module lockfile export; user-reviewed lockfile import with explicit consent per module and rejection of invalid revisions/path traversal.
- Public GitHub Actions status reader and unified command palette access to v3 tools; no credentials in localStorage.
- Rebuilt offline cache, v3 responsive action grid and updated release feed to 3.0.0.
- Verified 156 automated tests, real Luau WASM module import/benchmark/libraries smoke checks, 320–1280px static Chromium geometry.
- Existing v2 workspace storage, WASM runtime, Studio libraries, GitHub `require("@")` imports, notifications, mobile layout, settings preserved.
- Not yet implemented: full 80-feature roadmap, GitHub OAuth/write backend, Discord DM subscription backend, production Studio sync, full language server/coverage/profiler.

---

## v1.8.1 — Secure Discord bot announcements

- Added optional Discord bot transport using a GitHub Actions secret and the configured application/channel identifiers.
- Added explicit manual test-message workflow input, gated behind successful Pages deployment.
- Preserved existing webhook transport as fallback, disabled unsolicited mentions, avoided logging secrets, and tested destination and permissions error handling.
- Preserved all editor, workspace, WASM, dashboard and phone functionality.

## v1.8.0 — Community and release updates

- Added optional local-only GitHub/Discord username settings, strict validation, save/clear actions, and an account overview in the Developer Dashboard.
- Added public `updates.json` feed, in-app release banner, release notes panel, update check, dismiss state and resilient offline handling.
- Added post-successful-deployment GitHub Actions Discord channel announcement; webhook stays in encrypted `LUAUFORGE_DISCORD_WEBHOOK_URL` repository secret. Version-change gate, mention suppression and nonblocking failures.
- Preserved Luau WASM runtime, existing project storage, module pins, test suites and mobile/desktop editor geometry.
- Personal Discord DM and authenticated GitHub sync are not included; both require a secure opt-in backend.

## v1.7.0 — Public GitHub module registry

- Import public `.lua` and `.luau` modules by repository and path using `require("@Owner/Repo/path/File.luau")`.
- Explicit preview and consent, commit SHA pinning, bounded downloads, repository traversal checks and Studio-only detection.
- Lightweight per-device pin registry separate from legacy saved workspace schema.
- Three public, runnable examples (TestTools, MathKit, MathKitTests), auto-require suggestions, source links and runnable tests.
- Module loader hydrates GitHub sources before analysis and execution; relative dependencies use pinned revisions and real Luau VM caching.
- Existing built-in libraries and editor layout retained.

## v1.6.0 — Dashboard and verified Studio source catalog
- Add 20 live dashboard widgets with local settings, navigation and recovery hooks.
- Add seven pinned Roblox Studio source modules; never misrepresent Studio-only modules as WASM-compatible.
- Preserve v1.5 editor, WASM VM, existing projects, library sources, and responsive drawer geometry.
- Add source integrity checks, dashboard model tests and Studio catalog tests.
- Expose Home on the mobile dock and editor header with no workspace reset.

## v1.5.0 — Additive developer toolbox release

- Follow-up: restore ZIPs from the standard file picker and keep phone Settings accessible while Focus Mode is enabled.

- 20 optional tools covering lexical refactoring/references/types, conservative quick fixes, saved snippets, import suggestions, module dependency inspection, API Markdown docs, pinned libraries and user-saved module shelf.
- Advanced Luau WASM CPU benchmark suite: warmup, batched samples, median, P95, throughput, history and CSV/JSON export.
- ZIP import with path validation, size limits and CRC checks; optional DEFLATE unpacking; explicit conflict checks and recovery snapshots.
- Focus mode, desktop split editor, recovery and offline cache checks; preserve existing phone layout, IntelliSense contrast and workspace storage schema.
- Builtins remain pinned to FastNum 2.9.5, NanoNum 2.4.10 and OmegaNum 2.4.0. Roblox native server APIs remain unavailable inside WASM.
- Regression tests for ZIP safety, safe edits, dependency hints, history, and actual WASM bench measurement. Browser interactive testing remains subject to environment availability.

## v1.0.1 — mobile layout & IntelliSense hotfix

- Fix IntelliSense background transparency caused by v0.x CSS variables missing from the v1 theme.
- Anchor suggestions near the text caret, move above when space below is limited, and dynamically size to fit phone keyboards.
- Raise completion overlay above editor content while retaining accessible keyboard navigation.
- Improve responsive mobile panel sizing, header spacing, library buttons and code-editor font minimum; retain project storage.
- Update PWA cache and add regression coverage for popup geometry and contrast.

# Changelog

## v1.0.0 — Full adaptive workspace rebuild

### Added
- New no-dependency, modular editor/application shell (`v1.js`, `v1.css`, model/editor/graph/zip helpers) with responsive desktop/tablet/mobile proportions and safe-area-aware navigation.
- PWA manifest and service worker for local self-hosted Luau WASM, source, and builtin-library asset caching after first online visit.
- Real project-source ZIP export, project JSON import/export and public GitHub raw-source import.
- Multi-file Luau test runner with pass/fail reporting, standard `.test.luau`, `.spec.luau` and `tests/` discovery.
- Relative module dependency graph with unresolved-require and circular-require reporting.
- Inspector with compiler mode/O0–O2, live diagnostics switch, font size, wrap, recovery, benchmarks, tests and bytecode.
- Accessible command palette, source tabs, search/replace, mobile editing toolbar, and intuitive action placement.
- Dedicated unit tests for project migration, ZIP integrity, indentation, graph and responsive UI contracts.

### Fixed
- Mobile library card clipping and oversized actions by bounded three-column grids and viewport-relative drawers.
- Request promise hanging when a runtime worker rejects a `postMessage` operation.
- Autosave status now reflects successful persistence rather than showing "Saving" indefinitely.
- Worker asset URL revisioning for cache-safe v1 scripts.
- Removed automatic deployment workflow source-file commits to avoid push/build loops; GitHub Actions is the single intended publication source.
- Preserved older saved projects with original v2 storage format and snapshots; no forced destructive migration.

### Deliberately retained
- Pinned official Luau VM, diagnostics, autocomplete and bytecode bindings; parser/compiler integration is not replaced with a guessed approximation.
- Pinned FastNum, NanoNum and OmegaNum sources and multi-file bundler that were verified by existing WASM smoke suites.

### Not included
- Native Roblox service execution, Studio plugin pairing, authenticated GitHub write access, full LSP reference-rename/refactor support, interactive step-debugging; these require separate runtime integration or server-side components.
