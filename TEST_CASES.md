# Brood Engineering — Test Case Checklist

This is a forward-looking checklist of integration tests to add under `tests/` (FactorioTest), organized by subsystem and behavior.

## How “E2E” are the blueprint-string tests?

Blueprint-related tests in this repo currently span three different layers; it helps to be explicit about which layer a test is actually validating:

- **Import/parse layer (not Brood E2E):** `LuaItemStack.import_stack(blueprint_string)` is a Factorio engine feature. Tests here mostly validate “this fixture string is compatible with the current mod list / Factorio version” and provide better error messages when it isn’t.
- **Ghost placement layer (partial E2E):** `blueprint.build_blueprint(...)` is also engine behavior. It validates that a blueprint item (however created) can place ghosts/tiles into the world under the current prototypes.
- **Brood execution layer (Brood E2E):** once ghosts/tiles/orders exist in the world, Brood’s real end-to-end path is: task discovery → assignment limiting → spider movement/arrival → behavior execution → inventory accounting → cleanup.

The most valuable “true E2E for Brood” blueprint tests are the ones that assert the **Brood execution layer** results (ghosts disappear, entities exist, items consumed/returned, proxies cleared, no extra spiders spawned, etc.), regardless of whether the ghosts came from a string fixture or were created programmatically.

## Recommended blueprint test strategy (to reduce brittleness)

- Prefer **programmatic blueprint creation** (set entities/tiles on a `blueprint` stack, then optionally `export_stack()` → `import_stack()` roundtrip) for most behavioral coverage.
- Keep a **small number of golden blueprint-string fixtures** specifically for regressions against real player blueprints (accepting that they can be version/mod-list brittle).
- Treat “import-only” tests as **compatibility smoke** and keep their assertions minimal (don’t confuse them with Brood behavior coverage).

## P0 — Must-have regression tests

### Global enable/disable + recall correctness
- [ ] P0: Disabling via `brood-toggle` recalls all deployed spiders and returns **spiderling item** to anchor inventory (or spills if full).
- [ ] P0: Disable recalls also return **carried spider inventories** (trunk/ammo/trash) into the anchor, spilling overflow (regression for “items lost on recall”).
- [ ] P0: Re-enabling does not auto-deploy when there is no executable work (no “thrash deploy/recall”).
- [ ] P0: Disabling while spiders are `moving_to_task` clears assignments and does not leave `storage.assigned_tasks` entries behind.

### Assignment tracking integrity
- [ ] P0: `tasks.execute` clears `storage.assigned_tasks[task.id]` on success and on failure (e.g., target invalid mid-execution).
- [ ] P0: `tasks.cleanup_stale` removes assignments where the spider is missing, the anchor is missing, or the spider has a different task.
- [ ] P0: Destroyed spider entities (via `on_object_destroyed`) clear `storage.entity_to_spider`, `storage.spider_to_anchor`, and any assigned task id.

### Item-request-proxy / module insertion correctness (known pain area)
- [ ] P0: Insert plan consumes exactly the requested count (never pulls full stacks).
- [ ] P0: Insert plan targeting a specific slot: if the slot already contains the correct module+quality, treat it as satisfied without consuming from anchor.
- [ ] P0: Removal plan swaps a wrong module: removed module ends in anchor inventory (or spills if full), then insert happens; proxy plans are cleared.
- [ ] P0: Multiple insert positions in a plan: progresses one slot at a time without skipping or duplicating work.
- [ ] P0: Proxy clean-up: when plans become empty/stale, the proxy has no remaining `item_requests`/`insert_plan`/`removal_plan` entries (or is destroyed).
- [ ] P0: Two proxies targeting the same entity: Brood makes progress without oscillation (no infinite “remove/insert” loops).

## P1 — Core behavior coverage gaps

### Upgrade behavior (`scripts/behaviors/upgrade.lua`)
- [ ] P1: Upgrades a marked entity to its upgrade target and consumes the correct item from anchor inventory.
- [ ] P1: Preserves direction/position/force and returns the old entity’s placeable item into the anchor inventory.
- [ ] P1: Respects quality: `get_upgrade_quality()` vs current `entity.quality` and removes the correct quality item.
- [ ] P1: Fails gracefully when anchor inventory lacks the required upgrade item (no entity change; upgrade remains).
- [ ] P1: Fails gracefully when anchor inventory has no space for the old item (no entity change).
- [ ] P1: Interacts correctly with `item_proxy`: proxies for entities being upgraded are ignored until the upgrade is done.

### Tile building behaviors (`build_foundation` vs `build_tile`)
- [ ] P1: Foundation tile ghost is picked before non-foundation tile ghost when both exist (priority + correct filtering).
- [ ] P1: `build_tile` ignores foundation tiles (and vice versa) across a tile set containing both.
- [ ] P1: Tile ghost revive consumes the correct item count (including tiles where `count` > 1).
- [ ] P1: Tile ghost revive failure leaves inventory unchanged and task remains available.

### Deconstruction behaviors (entity + tile)
- [ ] P1: `deconstruct_entity` ignores `deconstructible-tile-proxy` entities even though they are `to_be_deconstructed` (no double-counting).
- [ ] P1: `deconstruct_tile` mines tiles via a **character anchor** and returns mined items to that inventory.
- [ ] P1: `deconstruct_tile` handles tiles with no mine result (or where mining yields nothing) without spinning forever.
- [ ] P1: `unblock_deconstruct` selects only deconstruct-marked blockers that overlap entity ghosts (not “any deconstruct-marked entity”).

### Spider movement completion correctness
- [ ] P1: `on_spider_command_completed` executes the current task once (no double-execute) even if Factorio fires the event early/late.
- [ ] P1: “Close enough” execution path triggers when the autopilot event never fires (spider reaches target but destinations list stays non-empty).
- [ ] P1: Large-ghost approach positioning avoids revive failures (spider does not stand inside future collision box).

## P2 — Anchor and player lifecycle

### Anchor entity switching (vehicle/character)
- [ ] P2: `on_player_driving_changed_state` updates anchor entity and updates follow targets for idle spiders.
- [ ] P2: Switching into a vehicle doesn’t break inventory access (anchor inventory changes from character_main to car_trunk/spider_trunk).
- [ ] P2: Switching out of a vehicle restores correct anchor inventory and spiders keep working without re-creating anchors.

### Surface changes + teleport behavior
- [ ] P2: `on_player_changed_surface` updates anchor surface and teleports all spiders to the new surface near the anchor.
- [ ] P2: Teleport threshold path: large anchor move in one tick triggers spider teleport and clears tasks safely.
- [ ] P2: Post-teleport, assigned tasks are cleared (no stale assignments to now-unreachable tasks).

### Player removal / cleanup
- [ ] P2: Removing a player destroys their anchor and recalls all spiders, leaving no orphaned storage entries.
- [ ] P2: Removing a player while spiders are mid-task doesn’t leak `storage.assigned_tasks`.

## P3 — Task selection and fairness

### Priority order + tie-breaking
- [ ] P3: When multiple task types exist, the chosen task matches behavior priority order (full matrix across behaviors).
- [ ] P3: Already-assigned tasks are skipped across all behaviors (not just build ghosts).
- [ ] P3: Shuffle/fairness: over many iterations, task selection doesn’t starve a subset of targets (sanity check, not statistical perfection).

### Assignment limiting edge cases
- [ ] P3: `max_assignments_per_tick` cap is enforced when many spiders are idle and many tasks exist.
- [ ] P3: `max_deploys_per_tick` cap is enforced under heavy work (no sudden spawn storm).
- [ ] P3: Cap resets per-tick and per-anchor (multi-anchor scenario).

## P4 — Stress, scaling, and “won’t crash” scenarios

### Large-area blueprint cycles
- [ ] P4: Medium blueprint cycle (dozens of ghosts) completes: build → deconstruct → inventory restored → area cleaned.
- [ ] P4: Cycle includes mixed tasks: foundation tiles + regular tiles + entities + item proxies + upgrades.

### High entity churn
- [ ] P4: Destroy/invalidations: ghost destroyed mid-approach, entity mined by “someone else”, proxy removed mid-plan; Brood recovers without errors.
- [ ] P4: Tree/rock random mine products (including `amount_min = 0`) never crashes any behavior.

### Stuck recovery
- [ ] P4: Spider stuck detection triggers `spider.jump` and makes progress toward task (controlled obstacle scenario).
- [ ] P4: Jump fallback (no valid task) does not break follow-target behavior and does not spam jumps.

## Blueprint-specific additions (explicitly labeled)

### Import compatibility smoke (engine layer; not Brood E2E)
- [ ] P?: Import golden blueprint strings under the default FactorioTest mod list (base + elevated-rails + quality + space-age) and assert `imported == true`.
- [ ] P?: When `quality` is disabled, importing a quality-bearing string is skipped with a clear message (don’t fail the suite).

### Blueprint roundtrip (engine + fixture stability)
- [ ] P?: Programmatically build a blueprint stack (`set_blueprint_entities`/`set_blueprint_tiles`), `export_stack()`, then `import_stack()` and ensure the imported blueprint still places equivalent ghosts/tiles.
- [ ] P?: Roundtrip preserves requested module plans (insert/removal plans still target the intended slots and items).

### Ghost placement is only a setup step (Brood E2E starts after)
- [ ] P?: Given ghosts created programmatically (no string), Brood builds them, consumes items, and clears ghosts.
- [ ] P?: Given module proxies created programmatically (no string), Brood satisfies and clears them.

