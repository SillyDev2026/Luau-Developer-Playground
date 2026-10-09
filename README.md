# LuauForge v0.4.1 — Responsive scaling patch

The layout uses relative viewport widths, CSS Grid/Flexbox, and `clamp()` constraints (web equivalent of Roblox `UDim2.fromScale` plus min/max constraints). Mobile drawers fit the viewport, buttons have fixed readable font sizes, and panels do not overlap the editor. Desktop explorer resizing remains available. No project data is migrated or erased.

# LuauForge v0.4.0

**v0.4:** context-aware signature help with active parameter highlighting; F12 go to local definition; Ctrl+Shift+O symbol outline; Ctrl+Space manual completion; safer stale-request handling; keyboard-friendly suggestions; optional debounced Luau WASM error/warning indicator. These are editor features built on the existing Luau WASM runtime and do not emulate Roblox services.

# LuauForge v0.3.4 — Built-in FastNum, NanoNum and OmegaNum

LuauForge comes with three **real, pinned, user-owned big-number libraries**, which load directly from the published website in the Luau WASM environment (never copied into localStorage or your personal project).

| Library | Import | Source release | Example |
| --- | --- | --- | --- |
| FastNum / FastME | `local FastME = require("@FastNum")` | FastNum 2.9.5 | `FastME.toString(FastME.add(FastME.fromNumber(2), FastME.fromNumber(3)))` |
| NanoNum | `local NanoNum = require("@NanoNum")` | NanoNum 2.4.10 | `NanoNum.formatScientific(NanoNum.fromString("1e1000"))` |
| OmegaNum | `local OmegaNum = require("@OmegaNum")` | OmegaNumV2 2.4.0 | `OmegaNum.toDisplay(OmegaNum.fromString("1e1000"))` |

Select one of the modules in the built-in library panel. **Example** creates a runnable workspace script without overwriting existing files. **API** shows categorized example signatures and lets you insert code, see source, or generate a script that inspects the actual exported function names. The **Bench require** dropdown includes all three built-ins and benchmarks inside the Luau VM using `os.clock()`, not frontend request timing.

## Implementation details

- Libraries are served from `public/libraries/*.lua`, flattened to `libraries/*.lua` in GitHub Actions deployments. The loader handles either GitHub Pages publishing layout.
- Sources are pinned at the upstream release revisions recorded in `scripts/library-versions.json`, and original Lua source is preserved in the checked-in assets.
- Prebuilt code is loaded on demand only when an example or a workspace script imports it. It is kept in a non-persistent virtual module namespace outside the 200 KB user-file limit. Dependency bundling maps `require("@FastNum")` into the WASM's flat module filesystem automatically; no Roblox `Instance` is required.
- Current OmegaNum requires `game:GetService("HttpService")` for JSON serialization. A narrowly-scoped `HttpService:JSONEncode` compatibility adapter runs in the browser VM, but **the original upstream OmegaNum source is never modified**.
- Scripts depending on actual Roblox services still require Roblox Studio. These library tests run in browser WebAssembly, not Roblox's native server.
- Each benchmark uses fresh Luau VM states for cold module loads and the same VM state's `require` cache for hot lookups, with 12 samples. It excludes web download and frontend rendering but is **not** equivalent to native Roblox server timing.

## Verify

```bash
npm test
npm run fetch:wasm
npm run smoke:libraries
npm run check
```

# LuauForge v0.3.3 — Module Test & VM Profiling

The workspace now supports **real multi-file module execution** even though the pinned official Playground WASM runtime supports only flat module filenames. LuauForge maps relative workspace imports to unique engine-compatible module identifiers while preserving require caching.

Example project:

`src/main.luau`:
```luau
local Math = require("./modules/Math.luau")
print(Math.add(20, 22))
local Again = require("./modules/Math.luau")
print(Math == Again)
```

`src/modules/Math.luau`:
```luau
local Math = {}
function Math.add(a: number, b: number): number
    return a + b
end
return Math
```

Click **Run** for output, and **Bench require** after selecting a module in Workspace settings to measure its first load and cached require. Each of the 12 samples runs in a fresh Luau VM state; the module load time is measured using Luau's own `os.clock()` and excludes frontend render or network time. Nested require calls are included in the parent's loading cost. Each run resets the module cache; repeated requires inside one run use cached module exports.

**Scope:** These are browser-hosted Luau VM timings, **not Roblox backend/server timings**. GitHub Pages cannot host a server. For authentic Roblox server benchmarks, execute an equivalent test inside a Roblox Studio server or a separately hosted trusted backend.

Supported: relative literal module imports (`./` and `../`), directory `init.luau` fallback, `.lua`/`.luau` modules, nested modules, cycle errors from native Luau, and module cache. Limitations: dynamic/computed require expressions, Roblox `Instance`/ModuleScript references, `@alias` imports, and require expressions in backtick interpolation aren't transformed. Errors for missing and ambiguous modules are raised before execution. For typechecker diagnostics after a rewritten require, the column may differ from the original source.

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

## IntelliSense and Roblox Engine API (v0.3.6)

LuauForge now completes ordinary local names and inferred types, not just `/` AutoRequire commands. `local` declarations are **lexical, not global**: symbols declared in an `if`, `do`, function or loop do not leak into the enclosing scope.

```luau
local test = 100
local testSpeed = 25
-- Type t for test / testSpeed completions.

local Players = game:GetService("Players")
-- Type Players.Get to discover GetPlayers and other members.

local block: Part = Instance.new("Part")
-- Type block.Pos to complete Position.

-- Type Enum.Material.N to complete Neon.
```

Select a suggestion using **Enter**, **Tab**, arrow keys, or touch. Type `/Fas`, `/Nano`, `/Omega`, or `/ModuleName` on a new line to use AutoRequire. The editor merges fast lexical/type/Roblox API metadata suggestions with asynchronously obtained native Luau WASM completions when available.

The bundled engine API index is generated by `npm run fetch:roblox-api` from the Studio API dump tracked at https://github.com/MaximumADHD/Roblox-Client-Tracker (unofficial data mirror). The build filters restricted and hidden members and includes public classes, member signatures, inherited members, and enum values. GitHub Actions generates and synchronizes `public/roblox-api.json`. A small offline fallback ships in `src/roblox-api.js`.

**Roblox API completion does not equal Roblox execution:** Studio services/Instance APIs are suggested for authoring, but calling them in standalone browser WASM still fails unless you provide your own mock. Use Roblox Studio to run gameplay scripts and perform server-side benchmarks.
