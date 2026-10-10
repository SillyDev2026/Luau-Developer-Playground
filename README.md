## Public GitHub module imports (v1.7)

LuauForge supports **public, opt-in, commit-pinned** Luau modules. In Libraries select **Add public GitHub module**, paste a GitHub `.lua` or `.luau` file URL, preview it, accept the trust checkbox, and select **Pin & import**. The app inserts `local MyModule = require("@Owner/Repo/path/MyModule.luau")` and loads the pinned public source into sandboxed Luau WASM. Modules needing Roblox services must instead run inside Roblox Studio.

Public modules **TestTools**, **MathKit**, and **MathKitTests** are available without setup. MathKitTests imports the other two using relative dependencies and exposes `run()`:

```luau
local T = require("@SillyDev2026/Luau-Developer-Playground/community/TestTools.luau")
T.run("from public GitHub", function()
    T.equal(20 + 22, 42)
end)
local Suite = require("@SillyDev2026/Luau-Developer-Playground/community/tests/MathKitTests.luau")
Suite.run()
```

GitHub code imports are **read-only**. GitHub Pages cannot push to other users' repositories without a separately authorized OAuth application; to publish a shared module, commit the `.luau` file in your public GitHub repository using GitHub's editor. Each user can then add the public file URL in LuauForge. Imports are pinned locally on that device, outside the workspace's existing storage format. Dependency imports inside a GitHub module must use explicit `.luau`/`.lua` file extensions and stay within the repository. The built-in public starter modules are distributed with this site.

---

# LuauForge 1.6 — Developer Dashboard + Studio Library Catalog

Adds twenty live, independently dismissible dashboard widgets: project overview, opened files, quick actions, runtime health, diagnostics, run performance, benchmark history, module catalog, dependency health, API search, tests, storage, activity, GitHub status, templates, code quality, comparisons, transparent project checks, preferences, and recovery. Accessible from the Home icon on phones and desktops. Widgets use actual locally held project state rather than placeholder metrics; unavailable values display honestly.

## New source imports

Seven source-pinned Roblox Studio modules are bundled in `public/studio-libraries/`: NexusDataStore, ZonePlusV2/ZonePlusNext, BufferUtil, Compression, Signal, Promise, and NetStream. Their sources are maintained by SillyDev2026 and pinned by commit and Git blob hash in `scripts/fetch-studio-libraries.mjs`. They are *Studio-only* and are **not executable** inside the standalone Luau WASM VM: Roblox DataStoreService, Workspace, RunService and task scheduler are unavailable. Some modules also require companion ModuleScripts such as `PlayersData`, `EventBus` or an entire `NetworkHandler` folder; consult their upstream READMEs before using them. The catalog provides source download, workspace import, and Studio-specific examples. Full folder dependencies are *not* automatically installed.

Run `npm run fetch:studio` to populate the pinned source files locally before the production build. `npm run check` validates their presence in the deployment artifact. Existing three WASM-compatible number libraries remain unchanged.

# LuauForge v1.5.0 — Developer Toolbox

LuauForge v1.5 adds **20 optional developer actions** on top of the tested v1.0.1 editor. It does not change the saved workspace format, WASM binary, or built-in FastNum/NanoNum/OmegaNum sources. From a phone, open **Settings → Developer Toolbox v1.5**; from a computer open the Inspector.

## 20 developer actions

| Area | Tools | Behavior |
| --- | --- | --- |
| Refactoring | Rename symbol · preview, Find all references, Type explorer, Quick fixes, Saved snippets | Conservative lexical refactoring with explicit preview and recovery snapshots; basic type inspection; manually confirmed safe suggestions; persistent custom snippets. **Renames do not promise language-server-level scope correctness**. |
| Modules | Missing import suggestions, Module graph & unused files, Generate module docs, Pinned library versions, Custom module shelf | Finds likely imports, shows incoming/outgoing dependencies and advisory unused files, generates Markdown source summaries, inspects exact bundled library pins, and keeps reusable user modules locally. **Alternate built-in versions are not downloaded automatically.** |
| Benchmarks | Benchmark Suite 3.0, Benchmark comparison & history, Export benchmark CSV, Run project tests | Runs warmups and batched samples **inside real Luau WASM** using `os.clock()`, reports min/median/P95/max/mean/ns-op, stores last 50 runs, exports CSV/JSON and retains the existing .test.luau runner. |
| Workspace | ZIP project import, Split editor, Mobile focus mode, Recovery manager, API documentation, Live Luau diagnostics | Validated ZIP restore for .lua/.luau, two editable panels on desktop, phone-first focus layout, snapshot + JSON backup, existing API browser and opt-in WASM type checking. |

### Benchmarking instructions

In **Settings → Developer Toolbox → Benchmark Suite 3.0**, enter a valid Luau expression such as `math.sqrt(i)`, optional setup code (e.g. `local FastME = require("@FastNum")`), iterations, warmup and samples. The benchmark runs inside Luau WASM and prints CPU-time measurements, **not** browser layout/DOM timing. Numbers are browser-WASM measurements, not Roblox server statistics; use the separately bundled Roblox Studio benchmark script for native timings. The benchmark UI is safe to cancel using the existing Stop control; it does not upload code to a backend.

### Module and refactoring limitations

The source analyzer is intentionally conservative: comments and string literals are excluded, property member names are not renamed, and bulk changes require confirmation and create a snapshot. Complex lexical shadowing and dynamically resolved module paths are not resolved by the lightweight analyzer—use Luau WASM type diagnostics and review changes. Unused-module hints are advisory, not deletion instructions. Custom modules and benchmark history use browser local storage and may be unavailable in private browsing. The built-in version inspector displays pinned sources; to test another source version, import it as a new workspace module.

### ZIP source restore

The ZIP importer validates CRC32, entry sizes, paths, and limits before accepting Luau source files. It accepts uncompressed ZIPs and deflate archives when `DecompressionStream('deflate-raw')` is available; non-Luau files such as README files are ignored. It refuses to silently overwrite existing workspace paths and saves a snapshot before import.

### Editor sizing

The existing v1.0.1 screen-responsive shell remains unchanged; all new options sit inside the scrollable Settings drawer. On phones, focus mode temporarily hides the console and secondary panels. Split editing is limited to tablet/desktop viewport sizes. The IntelliSense popup retains the v1.0.1 opaque colors and cursor-based positioning.

### Verification

Run `npm run check`, `npm run smoke:wasm`, `npm run smoke:libraries`, and `npm run smoke:v15`. Browser geometry is tested separately at 320, 360, 393, 800, 1280 and 1600 CSS pixels. Real interactive browser smoke tests may be restricted by sandbox policy; don't assume they passed if the environment blocked navigation.

---

# Previous releases

## v1.0.1 — editor visibility and responsive layout hotfix

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

**v1.5 follow-up:** The regular Files → Import picker accepts source ZIP archives; phone Focus Mode keeps Settings accessible so you can turn it off.

### Deployment checks

`npm run fetch:studio` downloads and verifies the pinned Git blobs (plus NexusDataStore, Signal and NetStream companion files). A CI build uses this command before `npm run check`. The standalone browser-based number libraries are kept separate from Studio-only sources. Custom project data is not changed. Offline app-shell caching covers dashboard code; Studio source packages are downloaded on demand and require an initial online visit.
