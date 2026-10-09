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
