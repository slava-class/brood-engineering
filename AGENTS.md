# Brood Engineering — Agent Notes

## Testing (FactorioTest)

This repo uses the FactorioTest framework for in‑game integration tests.

Steps:

1. Install tools via mise: `mise install`
   - Installs `bun` and `node` as configured in `.mise.toml`.
   - Node is still required because FactorioTest CLI shells out to `npx fmtk`.
2. Install dev deps: `bun install`
3. Launch the test scenario:
   - Preferred: `mise run factorio-test` (task defined in `.mise.toml`).
   - Or directly: `bun run --bun test:factorio -- --factorio-path "/path/to/factorio"`
4. When Factorio opens, tests should auto-start; if they don’t, click **“Reload mods and run tests”** in the FactorioTest UI.

Logs:

- Latest run: `factorio-test-data-dir/factorio-current.log`
- Previous run: `factorio-test-data-dir/factorio-previous.log`

macOS note:

- `factorio-test-data-dir/config.ini` must use `read-data=__PATH__executable__/../data` for app bundles. Keep that line if you recreate the data dir.

## Factorio Docs (Use Liberally)

Use the `mise run docs` command liberally during development (and while writing tests) to quickly find the exact API symbol/behavior you need, with stable IDs and paths.

It wraps the local `factorio-llm-docs` corpus (search/get/open) and defaults to a checkout at `~/workspace/factorio-llm-docs`.
If your checkout lives elsewhere, set `FACTORIO_LLM_DOCS_ROOT=/path/to/factorio-llm-docs`.

Codex CLI note:

- In approval-gated runs (especially `approval_policy=untrusted`), `mise run docs -- ...` may be aborted until the user approves the command. If that happens, re-run it while explicitly requesting approval (with a 1-sentence justification).

## Factorio API Usage (MUST)

When writing gameplay code or tests, you **MUST** look up the Factorio API in the offline docs before using **any** Factorio runtime/prototype API. Do not guess signatures, return values, or calling conventions.

- **MUST** use `mise run docs -- search "<symbol>"` and then `mise run docs -- open "<hit>"` (or `mise run docs -- open "runtime:method:LuaX.y"`) to confirm:
  - The symbol exists in the target Factorio version.
  - Parameter names/order and whether it uses a named-params table calling convention.
  - Return values (including multi-return) and nilability.
  - Any notes/constraints that affect correctness.
- **MUST** treat docs as the source of truth over intuition; Factorio APIs frequently differ across versions.
- **MUST** assume some APIs require the single “named parameter table” form even if you expect positional arguments.
- **Recommended:** create small wrapper helpers in our own code for tricky API interactions. Once a wrapper is implemented + validated, you can use that wrapper freely, but you must still look up Factorio APIs when adding/changing wrapper behavior.

### Usage

- List available Factorio versions:
  - `mise run docs -- versions`
- Search the corpus (supports filters):
  - `mise run docs -- search "<query>" [--version <x.y.z>] [--limit <n>] [--stage runtime,prototype,auxiliary] [--kind <kinds>] [--name <names>] [--member <members>]`
- Open the top search hit directly:
  - `mise run docs -- search "<query>" --open`
- Print only chunk ids (one per line):
  - `mise run docs -- search "<query>" --print-ids`
- Search/versions as JSON (for scripts/tools):
  - `mise run docs -- versions --json`
  - `mise run docs -- search "<query>" --json`
- Get a specific chunk by exact chunk id:
  - `mise run docs -- get "<chunkId>" [--version <x.y.z>]`
- Open content by chunk id, `relPath`, or `symbols.json` key:
  - `mise run docs -- open "<chunkId>" [--version <x.y.z>]`
  - `mise run docs -- open "<relPath>" [--version <x.y.z>]`
  - `mise run docs -- open "runtime:method:LuaSurface.set_tiles" [--version <x.y.z>]`
- If your query/path starts with `--`, use end-of-flags:
  - `mise run docs -- search -- "--weird"`

Notes:

- Non-JSON output prints `Using version: ...` to stderr; use `--quiet` to suppress it, or `--json` for machine-readable output.

## Formatting (StyLua)

- Lua formatting is done with StyLua via mise.
- Install: `mise install`
- Format: `mise run fmt-lua`
- Check only: `mise run fmt-lua-check`

## Debug Logging (Tests)

- FactorioTest runs default to quiet logs (debug logging is force-disabled in `control.lua` when `script.active_mods["factorio-test"]` is present).
- Enable debug output for a specific test by calling `remote.call("brood-engineering-test", "set_debug_logging_override", true)` and reset with `false` when done.
- Convenience helpers live in `tests/test_utils.lua` (for example, `test_utils.with_debug_logging(function() ... end)`).

## Tile Deconstruction Gotcha

- Tiles ordered for deconstruction also create `deconstructible-tile-proxy` entities which are marked `to_be_deconstructed`.
- Do not treat those proxies as entity deconstruction work; tile deconstruction must be handled via `LuaControl.mine_tile` (see `scripts/behaviors/deconstruct_tile.lua`), and `deconstruct_entity` should ignore `entity.type == "deconstructible-tile-proxy"` to avoid double-counting tasks/spawning extra spiders.

Quick docs lookups:

- `LuaControl.mine_tile` (what actually performs tile mining): `mise run docs -- open runtime:method:LuaControl.mine_tile`
- `LuaPrototypes.quality` (dictionary keyed by quality name): `mise run docs -- open runtime/classes/LuaPrototypes.md#quality`
- `LuaEntity.mine` (preferred way to deconstruct entities): `mise run docs -- open runtime:method:LuaEntity.mine`

## Adding tests

- Test files live under `tests/` as Lua modules.
- Register new modules in the FactorioTest init list in `control.lua` (under the `script.active_mods["factorio-test"]` gate).
- Any helper interfaces for tests should be added only inside that gate so they never ship into normal gameplay.
- **MUST** check our prototypes (especially `data.lua`) before assuming entity inventories/slots exist; many entities intentionally have inventories disabled (e.g., spiderlings may not have a usable trunk).

### Test patterns (Preferred)

- **No runtime `require()`**: FactorioTest disallows it (“outside of control.lua parsing”); keep `require(...)` at file top-level.
- Use `tests/test_utils.lua` wrappers: `describe_anchor_test`, `describe_surface_test`, `describe_remote_test`.
- Use `ctx.defer(...)` for cleanup (restore constants, destroy temporary inventories/entities, etc).
- Anchor suites: prefer `test_utils.anchor_opts.chest/character({ x_base=..., radii=..., spiderlings=... })`; `anchor_id_prefix` is auto-derived from suite name.
- Prefer `ctx.anchor_inventory` (already resolved) vs calling `test_utils.anchor_inventory(...)` repeatedly; use `ctx.assert_no_ghosts(...)` helpers where relevant.
