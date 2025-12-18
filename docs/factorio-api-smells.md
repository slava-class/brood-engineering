# Factorio API usage smells (Brood Engineering)

This doc captures Factorio runtime API callsites in this repo that are easy to get subtly wrong (calling convention, arg order, “takes table” vs positional) and records the verified shapes for the Factorio `2.0` line.

- Target game version: Factorio `2.0` (see `info.json`)
- Offline docs corpus used for verification: `2.0.72` (`~/workspace/factorio-llm-docs/llm-docs/2.0.72/runtime-api.json`)

## High-level checklist

- [ ] Prefer wrappers for “gotcha” APIs (`scripts/fapi.lua`, `scripts/utils.lua`)
- [ ] Audit `LuaEntity.destroy{...}` semantics (`raise_destroy` true/false everywhere)
- [ ] Keep `LuaControl.teleport(position, surface, ...)` callsites consistent (and wrapped)
- [ ] Keep `LuaSurface.find_non_colliding_position(name, center, ...)` callsites consistent (and wrapped)
- [ ] Keep `LuaSurface.set_tiles(tiles, correct_tiles, ...)` callsites consistent (and wrapped)
- [ ] Standardize all `LuaSurface.spill_item_stack{...}` usage via a single helper
- [ ] Avoid undocumented `create_entity{ stack = ... }` patterns; use documented `item = <LuaItemStack>` if needed
- [ ] Run FactorioTest integration tests after changes

## Canonical source of truth

The Markdown pages are useful for descriptions, but the canonical calling convention and positional argument order for a specific Factorio version is:

- `runtime-api.json` (runtime): `~/workspace/factorio-llm-docs/llm-docs/<version>/runtime-api.json`
- `prototype-api.json` (data stage): `~/workspace/factorio-llm-docs/llm-docs/<version>/prototype-api.json`

In particular:

- `format.takes_table` tells you whether the function/method expects a single named-argument table.
- `parameters[].order` tells you the positional call order (when `takes_table` is false).

## 1) `LuaEntity.destroy` uses the named-table calling convention

Verified (runtime-api.json):

- `takes_table: true`
- Keys: `do_cliff_correction?`, `raise_destroy?`, `player?`, `undo_index?`

Repo status:

- `raise_destroyed` typos were removed; callsites use `{ raise_destroy = ... }`.

Follow-ups:

- [ ] Decide when we actually want `raise_destroy = true` vs `false` and make it consistent.

## 2) `LuaControl.teleport` has `surface` as the 2nd positional arg

Verified (runtime-api.json):

- `takes_table: false`
- Positional order: `position`, `surface?`, `raise_teleported?`, `snap_to_grid?`, `build_check_type?`

Repo status:

- `scripts/fapi.lua` exposes `fapi.teleport(control, position, surface, opts)` to avoid order confusion.

Follow-ups:

- [ ] Use `fapi.teleport` everywhere we pass a surface (avoid mixing styles).

## 3) `LuaSurface.find_non_colliding_position` takes `name` first

Verified (runtime-api.json):

- `takes_table: false`
- Positional order: `name`, `center`, `radius`, `precision`, `force_to_tile_center?`

Repo status:

- `scripts/fapi.lua` exposes `fapi.find_non_colliding_position(surface, name, center, radius, precision, force_to_tile_center)`.

Follow-ups:

- [ ] Keep callsites using `fapi.find_non_colliding_position` for consistency.

## 4) `LuaEntity.revive` uses the named-table calling convention

Verified (runtime-api.json):

- `takes_table: true`
- Keys: `raise_revive?`, `overflow?`

Repo status:

- `scripts/behaviors/build_entity.lua` calls `ghost.revive({ raise_revive = true, overflow = inventory })`.
- `scripts/behaviors/build_tile.lua` / `scripts/behaviors/build_foundation.lua` call `ghost.revive({ raise_revive = true })`.

Follow-ups:

- [ ] Consider wrapping `revive` if we add more complicated options (so keys stay consistent).

## 5) `LuaSurface.set_tiles` takes `tiles` first (positional)

Verified (runtime-api.json):

- `takes_table: false`
- Positional order: `tiles`, `correct_tiles?`, `remove_colliding_entities?`, `remove_colliding_decoratives?`, `raise_event?`, `player?`, `undo_index?`

Repo status:

- `scripts/fapi.lua` exposes `fapi.set_tiles(surface, tiles, correct_tiles, opts)`.

Follow-ups:

- [ ] Prefer `fapi.set_tiles` in helpers/tests where call order confusion is likely.

## 6) `LuaSurface.spill_item_stack` uses the named-table calling convention

Verified (runtime-api.json):

- `takes_table: true`
- Keys (in order): `position`, `stack`, `enable_looted?`, `force?`, `allow_belts?`, `max_radius?`, `use_start_position_on_failure?`, `drop_full_stack?`

Repo status:

- `scripts/utils.lua` exposes `utils.spill_item_stack(surface, position, stack, opts)` for one canonical call shape.

Follow-ups:

- [ ] Move remaining direct `surface.spill_item_stack{...}` usages behind `utils.spill_item_stack` (including tests, if we want full consistency).

## 7) `LuaSurface.create_entity` for `item-on-ground` uses `item = <LuaItemStack>`

Verified (runtime-api.json):

- `LuaSurface.create_entity{ ... item?: LuaItemStack, ... }` (not `stack = <ItemStackDefinition>`)

Repo status:

- `scripts/utils.lua` exposes `utils.create_item_on_ground(surface, position, stack, opts)` which builds a temporary `LuaInventory` via `game.create_inventory(1)` and passes `item = inv[1]`.

Follow-ups:

- [ ] If we want to avoid the temp-inventory pattern, try to rely exclusively on `utils.spill_item_stack` for item drops.

## Appendix: “mise docs” notes for sandboxed environments

- [ ] Set `MISE_CACHE_DIR`/`MISE_DATA_DIR`/`MISE_STATE_DIR`/`MISE_CONFIG_DIR`/`MISE_TMP_DIR` in the shell environment before running `mise` (repo `.mise.toml` `[env]` only affects task subprocesses).
- [ ] Consider adding a “no auto-install” mode to the docs runner so `mise run docs` can operate without network access.
