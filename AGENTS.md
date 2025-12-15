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

### Usage

- List available Factorio versions:
  - `mise run docs -- versions`
- Search the corpus (supports filters):
  - `mise run docs -- search "<query>" [--version <x.y.z>] [--limit <n>] [--stage runtime,prototype,auxiliary] [--kind <kinds>] [--name <names>] [--member <members>]`
- Get a specific chunk by exact chunk id:
  - `mise run docs -- get "<chunkId>" [--version <x.y.z>]`
- Open a markdown page by `relPath`:
  - `mise run docs -- open "<relPath>" [--version <x.y.z>]`

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
- Do not treat those proxies as entity deconstruction work; tile deconstruction must be handled via `LuaEntity.mine_tile` (see `scripts/behaviors/deconstruct_tile.lua`), and `deconstruct_entity` should ignore `entity.type == "deconstructible-tile-proxy"` to avoid double-counting tasks/spawning extra spiders.

## Adding tests

- Test files live under `tests/` as Lua modules.
- Register new modules in the FactorioTest init list in `control.lua` (under the `script.active_mods["factorio-test"]` gate).
- Any helper interfaces for tests should be added only inside that gate so they never ship into normal gameplay.
