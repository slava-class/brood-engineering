# UPS Efficiency Plan (Brood Engineering)

This doc captures the UPS-focused improvements and patterns we discussed for the
spider/anchor/task system, along with concrete implementation ideas. It is
intended as an actionable roadmap rather than a design manifesto.

## Goals

- Reduce per-tick CPU cost in normal gameplay (one anchor today, many later).
- Remove surface-wide scans and avoid repeating expensive queries.
- Keep behavior deterministic and testable.
- Preserve the current gameplay feel (no unexpected delays or starvation).

## Constraints and Facts (Based on Runtime API)

- There is no API to ask “what changed near position X since last time”.
  You must react to events or scan an area.
- Event hooks exist for most work creation and cancellation.
- Use `script.set_event_filter` to reduce event traffic (filter by entity type,
  ghost status, etc.).
- There is no built-in mod hook to draw into the F4 debug overlay. Use
  `LuaRendering` or a small GUI panel for on-screen counters.

## Event-Driven Work Discovery

You can make most work detection event-driven and avoid periodic scanning.
Use events to enqueue work, and only fall back to a localized scan when you
need to repair or rebuild queues.

### Events to hook

Entity ghosts and builds:
- `defines.events.on_built_entity`
- `defines.events.on_robot_built_entity`

Tile ghosts and builds:
- `defines.events.on_player_built_tile`
- `defines.events.on_robot_built_tile`

Deconstruction marks:
- `defines.events.on_marked_for_deconstruction`
- `defines.events.on_cancelled_deconstruction`

Upgrade marks:
- `defines.events.on_marked_for_upgrade`
- `defines.events.on_cancelled_upgrade`

Completion / cleanup:
- `defines.events.on_player_mined_entity`
- `defines.events.on_robot_mined_entity`
- `defines.events.on_player_mined_tile`
- `defines.events.on_robot_mined_tile`
- `defines.events.on_object_destroyed` (for cleanup of tracked entities)

Notes:
- Tile deconstruction spawns `deconstructible-tile-proxy` entities. Those proxies
  are marked for deconstruction and must not be treated as “entity” work.
- Use filters for high-chatter events. For example, you can restrict
  `on_built_entity` to only ghosts or to specific types.

### Suggested event-flow

- When a relevant event arrives, enqueue a task record keyed by the entity or
  tile position. Do not scan the surface.
- If the event indicates cancellation or completion, mark the task as invalid
  or remove it from the queue (lazy removal is OK if validity checks exist).
- Maintain a per-surface “revision counter” and bump it when an event arrives.
  Anchors can compare `last_revision` to decide if cached work is stale.

## Work Queues + Long-Term Budgets

### Token-bucket budget

Per anchor:
- `budget = min(budget_max, budget + budget_per_tick)`
- Each assignment costs 1 token (or a weighted cost).
- If `budget == 0`, stop assigning for this anchor until a later tick.

Benefits:
- Prevents spikes from large backlogs.
- Fair to all anchors; no anchor can starve others.

### Queue structure

- `task_by_id` map for lookup.
- `task_ids` array for iteration in priority order.
- Use “swap-remove” for O(1) removals in arrays.
- Store minimal task fields (position, type, entity ref, created_tick).

### Long-term fairness

- “Budget per tick” enforces long-term limits even across hours of runtime.
- If you want strict fairness, rotate the iteration start index each tick.

## Spatial Bucketing

### Chunk buckets

Bucket tasks by chunk:
- `chunk_x = floor(pos.x / 32)`
- `chunk_y = floor(pos.y / 32)`
- key: `chunk_x .. ':' .. chunk_y`

Maintain:
- `tasks_by_chunk[chunk_key] = { task_ids = { ... } }`
- `anchors_by_chunk[chunk_key] = { anchor_ids = { ... } }` (optional)

Usage:
- When an anchor needs work, scan only chunks within an active radius.
- When tasks are added/removed, update chunk buckets.

Benefits:
- Keeps work discovery localized.
- Avoids expensive surface-wide queries.

## Tick Staggering

Even with a single anchor, adopting a staggered approach helps future scale.

Implementation:
- Assign each anchor a `tick_bucket = anchor_index % N`.
- Run assignment logic only when `game.tick % N == tick_bucket`.

Combine with budget:
- Smaller `budget_per_tick` and a larger `N` smooth spikes.

## Query Minimization and Caching

### Localized scans only

- Never scan entire surfaces.
- When a queue is empty or stale, do a bounded scan around the anchor to
  repair the queue (and then return to event-driven mode).

### Cache validity

- Cache entity references or task lists for a short window.
- Always guard with `if entity.valid` before use.
- Invalidate caches on “revision” changes (event-driven bumps).

## Assignment Strategy

### Avoid reassignment churn

- Do not reassign moving or working spiders every tick.
- Consider “re-evaluation windows”: only allow re-optimization every N ticks
  (ex: once every 120 ticks) to balance optimality with CPU cost.

### Push updates

- When a spider completes a task, signal the anchor to pull the next task
  rather than running a full scan each tick.

### Soft timeouts

- Re-evaluate stuck spiders on a timer rather than every tick.

## Data Structures and Lua Performance

- Arrays are faster for iteration; maps are best for lookup.
- Avoid transient table allocations in hot loops (use scratch tables).
- Keep `storage` access shallow and localize hot tables:
  `local tasks = storage.tasks` once per tick.
- Avoid repeated prototype lookups in inner loops; cache static info once.

## Observability (Low-Overhead)

- Add counters: `tasks_enqueued`, `assignments`, `queue_scans`,
  `budget_skips`, `tasks_completed`.
- Display counters with `LuaRendering` or a small GUI panel.
- Keep debug output off by default; enable with a runtime toggle.

## Suggested Incremental Plan

1. Add event hooks + filters and build per-anchor queues.
2. Add per-anchor token buckets to enforce assignment limits.
3. Add chunk buckets for localized queue scans.
4. Add revision-based cache invalidation.
5. Add staggered scheduling for anchors.
6. Add lightweight counters and a toggleable overlay.

## Risks / Trade-offs

- Event-driven discovery requires careful cleanup on cancellations and invalid
  entities; lazy removal must be guarded by `entity.valid` checks.
- If events are missed (mod disabled, migrations), a fallback scan is needed
  to rebuild queues.
- Too-aggressive budgets can delay work; set defaults conservatively.

## Recommended Defaults (Starting Point)

- `budget_max`: 4–8 tasks per anchor
- `budget_per_tick`: 1 task per anchor per tick
- `reassign_interval`: 120 ticks
- `stagger_modulo`: 4 (if multiple anchors)

These should be tuneable via settings and verified with a profiler.
