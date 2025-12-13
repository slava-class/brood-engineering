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

## Adding tests

- Test files live under `tests/` as Lua modules.
- Register new modules in the FactorioTest init list in `control.lua` (under the `script.active_mods["factorio-test"]` gate).
- Any helper interfaces for tests should be added only inside that gate so they never ship into normal gameplay.
