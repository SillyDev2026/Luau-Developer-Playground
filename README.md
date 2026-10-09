# LuauForge v1.0.1 — editor visibility and responsive layout hotfix

- Fixed transparent and misplaced IntelliSense by replacing legacy undefined CSS colors with opaque v1 theme colors. Suggestions now follow the editor caret, flip above when near the bottom, and remain within the available editor height.
- Improved phone/tablet header, library drawer, mobile dock and console dimensions; editor font now remains at least 16px on phones to prevent browser zoom.
- Retained local project storage, pinned Luau WASM runtime, FastNum/NanoNum/OmegaNum and existing public APIs.

# LuauForge 1.0

**A browser-based Luau developer workspace with a self-hosted WebAssembly VM, type diagnostics, multi-file `require`, AutoRequire, mobile-first editing tools, tests, and module benchmarks.**

[Launch the deployed IDE](https://sillydev2026.github.io/Luau-Developer-Playground/) · [Luau documentation](https://luau.org/) · [Roblox Creator Hub](https://create.roblox.com/docs)

## Highlights

- **New v1 workspace shell:** responsive CSS Grid/Flex layout, bounded Files/Settings drawers, adaptive editor and console, touch-friendly tabs, resizable desktop panels, compact module catalog and safe-area-aware mobile dock.
- **Editor:** syntax highlighting, line numbers, automatic indent, paired brackets/quotes, Tab/Shift+Tab, find/replace, cursor position, word wrap, adjustable font size, keyboard shortcuts, and phone editing toolbar.
- **Luau IntelliSense:** locals and scoped variables, Roblox API and standard-library completions, signature hints, type annotations, F12 go-to-definition, symbol outline, and `/<module>` AutoRequire commands. Uses WASM suggestions where supported. Roblox engine API entries are reference metadata and **do not make Roblox engine services executable** in the browser.
- **Execution:** the pinned official Luau Playground's real Emscripten WASM runtime, running in independent execution and analysis web workers; Stop terminates execution while keeping the diagnostics worker. Console, diagnostics, bytecode and require timings are separate tabs.
- **Modules:** nested workspace relative `require("./modules/Math.luau")`, transitive dependencies, normalized paths, distinct module names, cached module exports, cycle detection and dependency graph.
- **Built-in libraries:** `require("@FastNum")`, `require("@NanoNum")` and `require("@OmegaNum")`; browse their API categories and use one-click example/import actions. Source is pinned to your GitHub repositories and kept outside the browser workspace's storage quota.
- **Benchmarking:** cold and cached `require()` timing sampled with `os.clock()` **inside Luau WASM**, separately from UI response latency. For native Roblox Studio/server performance, use `public/examples/studio/ModuleLoadBenchmark.server.luau`.
- **Tests:** run files in `tests/`, or filenames ending `.test.luau` / `.spec.luau`; Lua `assert` reports pass/fail and real Luau output.
- **Projects:** autosave, safe migration of old v0.1–v0.4.1 local projects, named projects, multiple files, recovery snapshots, import `.lua`, `.luau`, or project JSON; export JSON or a standard ZIP with project files.
- **GitHub:** import a *public raw source file* by URL; source ZIP and JSON can be uploaded to a repository. **There is no built-in authenticated GitHub push** or direct Roblox Studio sync in this release.
- **Offline:** installable PWA shell with service-worker caching of bundled WASM and libraries after a successful online visit; actual local projects remain in browser storage and are not sent to the website server.

### Start developing

1. Open the site, edit `main.luau` and press **Run**.
2. In the Files drawer select **New module** to create `modules/NewModule.luau`.
3. Import it from a script with `local Module = require("./modules/NewModule.luau")`, or type `/NewModule` and choose the AutoRequire suggestion.
4. Open **Modules** to browse the pinned number libraries. Example:

```luau
--!strict
local FastME = require("@FastNum")
local balance = FastME.add(FastME.fromNumber(1250), FastME.fromString("1e100"))
print(FastME.toString(balance))
```

### Test file

Create `tests/math.test.luau`:

```luau
--!strict
local Math = require("../modules/Math.luau")
assert(Math.add(20, 22) == 42, "wrong result")
print("PASS: Math.add")
```

Open **Settings → Run all tests**. Each file gets a fresh Luau execution state.

### Keyboard shortcuts

| Shortcut | Function |
| --- | --- |
| `Ctrl+Enter` | Run current script |
| `Ctrl+P` | Command palette |
| `Ctrl+F` | Find/replace |
| `Ctrl+S` | Save immediately |
| `Ctrl+B` | Benchmark a module |
| `Ctrl+Space` | Force autocomplete |
| `F12` | Go to local definition |
| `Ctrl+Shift+O` | Symbol outline (when editor focus is active) |
| `/ModuleName` | Insert or reuse a `require` |

## Technical architecture

- `index.html`, `src/v1.css`: v1 adaptive workspace shell
- `src/v1.js`: DOM/controller, file navigation, developer tools, dialogs and commands
- `src/v1-model.js`: storage, tabs, migration, safe project mutations, snapshots
- `src/v1-editor.js`: editor interaction, highlighting, indentation and bracket matching
- `src/v1-zip.js`: native ZIP export (UTF-8 filenames, STORE method, CRC32)
- `src/v1-graph.js`: graph and cycle detection via the real module resolver
- `src/wasm-client.js`, `src/wasm-worker.js`: isolated VM and analysis workers
- `src/module-bundle.js`, `src/builtin-libraries.js`: transformed relative imports, builtin module hydration and VM timing
- `src/auto-require.js`, `src/intellisense.js`, `src/editor-intelligence.js`, `src/roblox-api.js`: completion and API indexing
- `public/sw.js`, `public/manifest.webmanifest`: offline PWA

## Development

Requires Node 20+ and internet on the first build to fetch pinned Luau WASM and built-in module sources (both are already bundled in this release ZIP).

```bash
npm run dev
npm run check
npm run smoke:wasm
npm run smoke:libraries
npm run build
```

`npm run dev` serves the **source layout** on http://127.0.0.1:4173. `npm run build` emits `dist/`, flattening `public/` into the site root. The worker checks both layouts so custom GitHub Pages publishing works with the correct WASM asset path. Do not open HTML with `file://` because module workers and fetches require HTTP(S).

CI deploys `dist/` to GitHub Pages. In repository **Settings → Pages**, use **GitHub Actions** as the publishing source to avoid competing branch/Jekyll deployments. The custom workflow does not push another commit on deployment.

## Security and limitations

Luau scripts run in a dedicated WASM worker with termination support, **not a native Roblox backend**. No Roblox `DataStoreService`, `Workspace`, player replication, plugins or network APIs are emulated. CPU times measured with `os.clock()` reflect browser WASM, not Roblox server performance. Source files are stored in browser localStorage with a bounded per-file/project quota; exported backups and snapshots are recommended. The new editor retains a native textarea with a syntax layer for no-dependency offline operation; it **is not CodeMirror/Monaco** and does not implement all VS Code language-server or debugger capabilities. Direct Roblox Studio pairing and authenticated GitHub push still require separate applications/services and are not represented as completed.

## Source acknowledgments

Runtime: pinned [luau-lang/playground](https://github.com/luau-lang/playground). Bundled original-number libraries: [FastNum](https://github.com/SillyDev2026/FastNum), [NanoNum](https://github.com/SillyDev2026/NanoNum), [OmegaNumV2](https://github.com/SillyDev2026/OmegaNumV2). OmegaNum's isolated browser adapter replaces its Roblox `HttpService` JSON encoding dependency without editing upstream source.
