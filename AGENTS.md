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

## Local Factorio API Docs

- The full Factorio Lua API docs are vendored under `factorio-api-docs/` for offline reference.
- Entry points: `factorio-api-docs/index-runtime.html` (runtime) and `factorio-api-docs/index-prototype.html` (prototypes).

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
