# Factorio API usage smells (Brood Engineering)

This doc captures Factorio runtime API callsites in this repo that look “off” (or inconsistent) and are worth auditing/fixing.

- Target game version: Factorio `2.0` (see `info.json`)
- Offline docs corpus used for verification: `2.0.72`

## High-level checklist

- [ ] Normalize “destroy” calls to match `LuaEntity.destroy` (no `{ raise_destroyed = ... }` tables)
- [ ] Fix `LuaControl.teleport(...)` argument order (esp. “surface”)
- [ ] Fix `LuaSurface.find_non_colliding_position(...)` argument order
- [ ] Fix `LuaEntity.revive(...)` calling convention (and any wrapper helpers)
- [ ] Fix `LuaSurface.set_tiles(...)` calling convention / argument order
- [ ] Fix `LuaSurface.spill_item_stack(...)` calling convention (table vs args) consistently
- [ ] Confirm `LuaSurface.create_entity{ name="item-on-ground", ... }` uses the correct key for the item stack (`item` vs `stack`)
- [ ] Add thin wrapper helpers for these APIs and use them everywhere
- [ ] Run FactorioTest integration tests after changes

## 1) `LuaEntity.destroy` uses boolean params, not `{ raise_destroyed = ... }`

Docs: `mise run docs -- open runtime/classes/LuaEntity.md#destroy`

Signature (docs):

```lua
LuaEntity.destroy(do_cliff_correction?: boolean, player?: PlayerIdentification, raise_destroy?: boolean, undo_index?: uint32) -> boolean
```

Smell:

- Several callsites pass a table to `destroy(...)` and/or use the key `raise_destroyed` (note the “-ed”), but the docs show a boolean parameter named `raise_destroy` (no “-ed”).
- Some callsites use `raise_destroy`, others use `raise_destroyed`, suggesting a mix of old/new conventions.

Callsites (table argument and/or `raise_destroyed` key):

- `scripts/behaviors/deconstruct_tile.lua:239` (`drop.destroy({ raise_destroy = true })`)
- `scripts/spider.lua:334` (`spider_entity.destroy({ raise_destroy = false })`)
- `scripts/behaviors/item_proxy.lua:350` (`proxy.destroy({ raise_destroy = false })`)
- `scripts/behaviors/deconstruct_entity.lua:125` (`item_entity.destroy({ raise_destroyed = true })`)
- `scripts/behaviors/deconstruct_entity.lua:471` (`entity.destroy({ raise_destroyed = true })`)
- `scripts/behaviors/deconstruct_entity.lua:542` (`entity.destroy({ raise_destroyed = true })`)
- `tests/toggle_disable_recall_test.lua:73` (`e.destroy({ raise_destroyed = false })`)
- `tests/test_utils.lua:548` (`e.destroy({ raise_destroyed = false })`)
- `tests/test_utils.lua:1087` (`entity.destroy({ raise_destroyed = false })`)
- `tests/test_utils.lua:1179` (`e.destroy({ raise_destroyed = false })`)
- `tests/test_utils.lua:1195` (`e.destroy({ raise_destroyed = false })`)

Follow-ups:

- [ ] Decide on desired semantics (raise events or not) and encode them using the documented `raise_destroy` boolean parameter.
- [ ] Remove `raise_destroyed` usage entirely (audit for typos vs intended behavior).

## 2) `LuaControl.teleport` surface is the 5th parameter (not the 2nd)

Docs: `mise run docs -- open runtime/classes/LuaControl.md#teleport`

Signature (docs):

```lua
LuaControl.teleport(build_check_type?: defines.build_check_type, position: MapPosition, raise_teleported?: boolean, snap_to_grid?: boolean, surface?: SurfaceIdentification) -> boolean
```

Smell:

- Calls like `teleport(valid_pos, surface)` appear to treat “surface” as the 2nd param, but the docs show the 2nd param is `position`, and `surface` is the 5th param.

Callsites:

- `scripts/spider.lua:584` (`spider_entity.teleport(valid_pos, surface)`)

Additional callsites that likely rely on positional overload behavior (still worth verifying):

- `scripts/spider.lua:637` (`spider_entity.teleport(valid_pos)`)
- `scripts/spider.lua:657` (`spider_entity.teleport(valid_pos)`)
- `scripts/behaviors/build_entity.lua:171` (`spider_entity.teleport(reposition)`)
- `tests/idle_recall_test.lua:79` (`ctx.anchor_entity.teleport({ x = ..., y = ... })`)

Follow-ups:

- [ ] Replace multi-arg calls with the documented arg order (and verify which overloads are actually supported in 2.0).
- [ ] Consider a helper like `utils.teleport(control, position, surface?)` to centralize correctness.

## 3) `LuaSurface.find_non_colliding_position` argument order differs from our usage

Docs: `mise run docs -- open runtime/classes/LuaSurface.md#find_non_colliding_position`

Signature (docs):

```lua
LuaSurface.find_non_colliding_position(center: MapPosition, force_to_tile_center?: boolean, name: EntityID, precision: double, radius: double) -> MapPosition?
```

Smell:

- Many calls use the old/other order: `find_non_colliding_position(name, center, radius, precision)`.
- If the engine follows the documented signature strictly, those calls will type-mismatch (table where boolean expected, etc.).

Callsites:

- `scripts/behaviors/build_entity.lua:89`
- `scripts/spider.lua:65`
- `scripts/spider.lua:135`
- `scripts/spider.lua:271`
- `scripts/spider.lua:484`
- `scripts/spider.lua:581`
- `scripts/spider.lua:635`
- `scripts/spider.lua:642`
- `scripts/spider.lua:655`

Follow-ups:

- [ ] Update all callsites to match the documented parameter order.
- [ ] Add a small wrapper to prevent future regressions.

## 4) `LuaEntity.revive` signature differs from our `{ raise_revive = true }` table usage

Docs: `mise run docs -- open runtime/classes/LuaEntity.md#revive`

Signature (docs):

```lua
LuaEntity.revive(overflow?: LuaInventory, raise_revive?: boolean) -> Dict<string, uint32>?, LuaEntity?, LuaEntity?
```

Smell:

- Some code calls `ghost.revive({ raise_revive = true })` and one wrapper passes an `options` table through.
- The docs show `revive` taking up to 2 positional parameters (`overflow`, `raise_revive`) rather than an options table.

Callsites:

- `scripts/behaviors/build_entity.lua:113` (`ghost.revive(options)`)
- `scripts/behaviors/build_tile.lua:114` (`ghost.revive({ raise_revive = true })`)
- `scripts/behaviors/build_foundation.lua:117` (`ghost.revive({ raise_revive = true })`)

Follow-ups:

- [ ] Align all revive calls with the documented signature.
- [ ] Revisit the `revive_ghost(...)` helper in `scripts/behaviors/build_entity.lua` to ensure it matches Factorio 2.0 semantics.

## 5) `LuaSurface.set_tiles` usage looks like 1.1-era ordering

Docs: `mise run docs -- open runtime/classes/LuaSurface.md#set_tiles`

Signature (docs):

```lua
LuaSurface.set_tiles(correct_tiles?: boolean, player?: PlayerIdentification, raise_event?: boolean, remove_colliding_decoratives?: boolean, remove_colliding_entities?: boolean | "abort_on_collision", tiles: Array<Tile>, undo_index?: uint32)
```

Smell:

- Call sites use `set_tiles(tiles, true)` which appears to be the legacy ordering.

Callsites:

- `tests/tile_deconstruct_test.lua:17`
- `tests/tile_deconstruct_test.lua:18`
- `tests/tile_deconstruct_test.lua:64`
- `tests/tile_deconstruct_test.lua:65`
- `tests/test_utils.lua:1072`
- `scripts/behaviors/deconstruct_tile.lua:483`

Follow-ups:

- [ ] Update these calls to match the documented parameter order/calling convention.
- [ ] Prefer batching tiles (docs recommend fewer calls).

## 6) `LuaSurface.spill_item_stack` calling convention needs confirmation + standardization

Docs: `mise run docs -- open runtime/classes/LuaSurface.md#spill_item_stack`

Signature (docs):

```lua
LuaSurface.spill_item_stack(allow_belts?: boolean, drop_full_stack?: boolean, enable_looted?: boolean, force?: ForceID, max_radius?: double, position: MapPosition, stack: ItemStackIdentification, use_start_position_on_failure?: boolean) -> Array<LuaEntity>
```

Smell:

- We currently pass a single table argument (Lua sugar for “named args”), which may or may not match Factorio 2.0’s expected calling convention.
- Regardless of what’s correct, this should be consistent across runtime code + tests.

Callsites:

- `scripts/behaviors/deconstruct_entity.lua:35`
- `scripts/behaviors/deconstruct_entity.lua:267`
- `tests/entity_deconstruct_test.lua:64`
- `tests/entity_deconstruct_test.lua:160`

Follow-ups:

- [ ] Confirm the actual supported call shape in Factorio 2.0 (table-style vs positional-style) and update all callsites accordingly.
- [ ] Wrap `spill_item_stack` behind a helper function so the repo has one canonical calling style.

## 7) `LuaSurface.create_entity` for `item-on-ground` uses `stack` key (docs show `item`)

Docs: `mise run docs -- open runtime/classes/LuaSurface.md#create_entity`

Signature (docs excerpt includes):

```lua
... force?: ForceID, item?: LuaItemStack, ... name: EntityID, position: MapPosition, ...
```

Smell:

- `scripts/spider.lua` creates `item-on-ground` using `stack = { name=..., count=... }`.
- The docs signature shows an `item?: LuaItemStack` parameter, not `stack`.

Callsites:

- `scripts/spider.lua:680` (uses `stack = { name = "spiderling", count = 1 }`)

Follow-ups:

- [ ] Confirm whether Factorio 2.0 expects `item = <LuaItemStack>` or still accepts `stack = <ItemStackDefinition>` for `item-on-ground`.
- [ ] If needed, update the callsite and add a small test to cover spider death drops.

## Appendix: “Mise docs” command notes (for sandboxed environments)

If `mise run docs` attempts to auto-install tools (and/or crashes), the following env vars were sufficient in this environment to prevent auto-install:

- [ ] Export `MISE_AUTO_INSTALL=0`
- [ ] Export `MISE_TASK_RUN_AUTO_INSTALL=0`
- [ ] Export `MISE_EXEC_AUTO_INSTALL=0`

