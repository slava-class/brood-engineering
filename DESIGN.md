# Brood Engineering — Design Document

**Version:** 0.1.0
**Target:** Factorio 2.0
**Status:** Initial Development

---

## Overview

Brood Engineering is a Factorio mod that provides autonomous construction spiders with a clean, extensible architecture. Spiders auto-deploy when work exists, execute construction/deconstruction tasks, and auto-recall when idle.

### Design Philosophy

- **Anchor abstraction** — Spiders work for an "anchor" (inventory source). Today that's the player; tomorrow it's Webs/FOBs.
- **Behavior composition** — Task types are modular behaviors that can be mixed and matched per spider type.
- **Two-tier assignment** — Anchors assign distant tasks; spiders self-assign nearby tasks to avoid wasted trips.
- **Future-ready** — Architecture anticipates castes, Webs, fuel systems, and Mother Zero transformation.

---

## Core Concepts

### Anchor

An anchor is anything that:
1. Has a position in the world
2. Has an inventory spiders can access
3. Can have spiders assigned to it

For v0.1, each player has exactly one anchor (their character or vehicle). The anchor abstraction allows adding Web buildings later without restructuring.

### Spider

A small spidertron that:
1. Belongs to an anchor
2. Has a state machine (idle → moving → executing → idle)
3. Has a set of behaviors it can perform
4. Can self-assign tasks within personal radius

### Behavior

A behavior is a task type (build, deconstruct, upgrade, etc.) that defines:
1. How to find potential tasks
2. Whether a task can be executed given inventory
3. How to execute the task

Behaviors are composable — a spider's capabilities are just its list of behaviors.

---

## Data Structures

### Storage Schema

```lua
storage = {
    -- All anchors in the game
    anchors = {
        [anchor_id] = {
            type = "player",              -- "player" | "web" (future)
            entity = LuaEntity,           -- character, spidertron, or web building
            player_index = number,        -- for player-type anchors
            surface_index = number,
            position = MapPosition,       -- cached, updated each tick
            spiders = {                   -- spiders belonging to this anchor
                [spider_id] = spider_data,
            },
        },
    },

    -- Reverse lookup: spider → anchor
    spider_to_anchor = {
        [spider_id] = anchor_id,
    },

    -- Tracks which tasks are currently assigned (prevents double-assignment)
    assigned_tasks = {
        [task_id] = spider_id,
    },

    -- Master toggle
    global_enabled = true,
}
```

### Spider Data

```lua
spider_data = {
    entity = LuaEntity,                   -- the spiderling entity
    anchor_id = anchor_id,
    status = "deployed_idle",             -- see State Machine below
    task = nil,                           -- current task if any
    idle_since = nil,                     -- game.tick when became idle near anchor
    behaviors = { ... },                  -- list of behavior modules (reference)
}
```

### Task Data

```lua
task = {
    id = string,                          -- unique identifier (entity UUID or tile key)
    entity = LuaEntity,                   -- target entity (ghost, to-deconstruct, etc.)
    tile = LuaTile,                       -- OR target tile (for tile tasks)
    behavior = Behavior,                  -- which behavior handles this task
}
```

---

## State Machine

### Spider States

```
in_inventory        Not deployed; exists only as item count in anchor inventory
deployed_idle       Deployed, no task; either walking toward anchor or waiting
moving_to_task      Has task, walking to it
executing           At task location, performing action (instant in v0.1)
```

### State Transitions

```
in_inventory → deployed_idle
    When: Work exists within anchor radius AND spider count < max AND global enabled
    Action: Remove item from inventory, spawn spider entity near anchor

deployed_idle → moving_to_task
    When: Task assigned (by anchor or self)
    Action: Set autopilot destination, update status

moving_to_task → executing
    When: Spider arrives at task location
    Action: Execute task immediately

executing → deployed_idle
    When: Task complete
    Action: Clear task, check for nearby work

deployed_idle → in_inventory
    When: Near anchor AND idle for timeout duration
    OR: Global toggle disabled
    Action: Destroy entity, add item to inventory

moving_to_task → deployed_idle
    When: Task becomes invalid (entity removed, etc.)
    Action: Clear task, revert to idle
```

---

## Task Assignment

### Two-Tier Model

**Tier 1: Anchor Assignment**
- Anchor scans full radius (configurable, default 40 tiles)
- Finds all potential tasks across all behaviors
- Assigns tasks to idle spiders at anchor

**Tier 2: Spider Self-Assignment**
- Idle spider scans personal radius (configurable, default 8 tiles)
- If task found, self-assigns without returning to anchor
- Prevents wasted round-trips

### Assignment Flow

```
Every N ticks (main loop):
    For each anchor:
        Update position cache
        Check for teleport (anchor moved far)

        For each spider:
            If status == "deployed_idle":
                # Tier 2: Self-assignment
                personal_area = spider position ± personal_radius
                task = find_best_task(behaviors, personal_area, inventory)
                If task:
                    assign(spider, task)
                    continue

                # No nearby task — check if should recall
                If near_anchor:
                    If idle long enough:
                        recall(spider)
                Else:
                    walk_toward_anchor(spider)

            If status == "moving_to_task":
                If arrived:
                    execute_task(spider)
                If task_invalid:
                    clear_task(spider)

        # Tier 1: Anchor assignment for any remaining idle spiders at anchor
        anchor_area = anchor position ± anchor_radius
        tasks = find_all_tasks(behaviors, anchor_area, inventory)
        For each idle spider near anchor:
            task = pop_best_task(tasks)
            If task:
                assign(spider, task)

        # Auto-deploy if work exists and below max
        If tasks remain AND spider_count < max:
            deploy_spider(anchor)
```

### Task Priority

Behaviors are checked in priority order. Lower number = higher priority.

| Priority | Behavior | Description |
|----------|----------|-------------|
| 1 | `unblock_deconstruct` | Deconstruct entities blocking ghost placement |
| 2 | `build_foundation` | Place foundation tiles (landfill) that enable building |
| 3 | `build_entity` | Build entity ghosts |
| 4 | `upgrade` | Upgrade marked entities |
| 5 | `item_proxy` | Insert/remove items via item-request-proxy |
| 6 | `deconstruct_entity` | Deconstruct marked entities |
| 7 | `build_tile` | Place non-foundation tile ghosts |
| 8 | `deconstruct_tile` | Remove marked tiles |

---

## Behaviors

### Behavior Interface

```lua
Behavior = {
    name = string,                        -- unique identifier
    priority = number,                    -- lower = higher priority

    -- Find all potential tasks in area
    -- Returns array of LuaEntity or {entity=, tile=} tables
    find_tasks = function(surface, area, force) → task_targets[]

    -- Can this task be executed given current inventory?
    can_execute = function(target, inventory) → boolean

    -- Execute the task. Returns true on success.
    execute = function(spider_data, task, inventory, anchor) → boolean

    -- Get unique ID for a task target (for tracking assignment)
    get_task_id = function(target) → string
}
```

### Behavior Implementations (Summary)

**unblock_deconstruct**
- Finds: Entities marked for deconstruction that overlap with entity ghosts
- Executes: Mines entity, returns products to inventory

**build_foundation**
- Finds: Tile ghosts where tile prototype `is_foundation == true`
- Executes: Places tile, consumes item from inventory

**build_entity**
- Finds: Entity ghosts
- Executes: Revives ghost, consumes item from inventory

**upgrade**
- Finds: Entities marked for upgrade
- Executes: Swaps entity for upgrade target, handles inventory

**item_proxy**
- Finds: Item-request-proxy entities
- Executes: Inserts or removes items per proxy plan

**deconstruct_entity**
- Finds: Entities marked for deconstruction (excluding unblock targets)
- Executes: Mines entity, returns products

**build_tile**
- Finds: Tile ghosts (non-foundation)
- Executes: Places tile

**deconstruct_tile**
- Finds: Tiles marked for deconstruction
- Executes: Removes tile, returns item

---

## Configuration

All tunable values in `scripts/constants.lua`:

```lua
constants = {
    -- Radii
    anchor_scan_radius = 40,              -- anchor task scanning
    spider_personal_radius = 8,           -- spider self-assignment
    near_anchor_threshold = 5,            -- "near anchor" for recall

    -- Counts
    max_spiders_per_anchor = 200,         -- flat cap
    max_spiders_per_tick = 4,             -- limit assignments per tick

    -- Timing
    idle_timeout_ticks = 240,             -- 4 seconds before recall
    main_loop_interval = 30,              -- ticks between main loop

    -- Movement
    teleport_threshold = 50,              -- anchor movement triggers spider teleport
    jump_distance = 4,                    -- unstuck jump distance (halved)

    -- Spider prototype
    spider_scale = 0.125,
    spider_speed_modifier = 0.5,          -- slower for debugging

    -- Features
    show_item_projectiles = true,         -- visual feedback (setting-controlled)

    -- Colors (RGBA 0-1)
    colors = {
        idle = { r = 0.5, g = 0.5, b = 0.5, a = 1 },       -- gray
        moving = { r = 1, g = 0.7, b = 0, a = 1 },         -- orange
        executing = { r = 0, g = 1, b = 0.3, a = 1 },      -- green
        returning = { r = 0.3, g = 0.5, b = 1, a = 1 },    -- blue
    },
}
```

---

## File Structure

```
brood-engineering/
├── info.json                     # Mod metadata
├── data.lua                      # Prototype definitions
├── data-final-fixes.lua          # Prototype modifications
├── control.lua                   # Event registration, main loop
├── settings.lua                  # Mod settings
├── DESIGN.md                     # This document
├── README.md                     # User documentation
├── changelog.txt                 # Version history
│
├── scripts/
│   ├── constants.lua             # All tunable values
│   ├── utils.lua                 # Helper functions
│   ├── anchor.lua                # Anchor CRUD, inventory access
│   ├── spider.lua                # Spider lifecycle, state machine
│   ├── tasks.lua                 # Task finding, assignment
│   │
│   └── behaviors/
│       ├── init.lua              # Exports ordered behavior list
│       ├── unblock_deconstruct.lua
│       ├── build_foundation.lua
│       ├── build_entity.lua
│       ├── upgrade.lua
│       ├── item_proxy.lua
│       ├── deconstruct_entity.lua
│       ├── build_tile.lua
│       └── deconstruct_tile.lua
│
└── locale/
    └── en/
        └── config.cfg            # English strings
```

---

## Events

### Subscribed Events

| Event | Handler | Purpose |
|-------|---------|---------|
| `on_init` | `setup_storage()` | Initialize storage tables |
| `on_configuration_changed` | `setup_storage()` | Handle mod updates |
| `on_player_created` | `create_player_anchor()` | Create anchor for new player |
| `on_player_removed` | `destroy_player_anchor()` | Cleanup |
| `on_player_changed_surface` | `handle_surface_change()` | Teleport spiders |
| `on_player_driving_changed_state` | `update_anchor_entity()` | Update anchor when entering/exiting vehicle |
| `on_nth_tick(N)` | `main_loop()` | Core logic |
| `on_lua_shortcut` | `toggle_global()` | Master toggle |
| `on_entity_died` | `handle_spider_death()` | Drop spider as item |
| `on_object_destroyed` | `cleanup_spider()` | Remove from tracking |

### Custom Input

| Input | Key | Action |
|-------|-----|--------|
| `brood-toggle` | Alt+B | Toggle global enabled |

---

## Future Expansion (Not in v0.1)

### Webs
- New anchor type with `type = "web"`
- Buildable entity with inventory
- Spiders anchor to nearest Web, not player
- Web has scan radius, fuel consumption, decay

### Castes
- Different spider prototypes per caste
- Caste determines behavior subset
- Builder, Cutter, Ferry, Crafter

### Mother Zero
- Player locked into spidertron vehicle
- Cannot handcraft (or severe penalty)
- Is the original anchor

### Fuel & Decay
- Spiders consume fuel
- Webs decay without maintenance
- Adds resource management layer

### Task Duration
- Tasks take time based on prototype values
- Visual feedback during execution
- Balance lever for difficulty

---

## Testing Strategy (Future)

When FactorioTest is integrated:

```lua
-- tests/anchor_test.lua
describe("anchor", function()
    it("creates anchor when player joins", ...)
    it("resolves inventory from character", ...)
    it("resolves inventory from spidertron", ...)
    it("destroys anchor when player leaves", ...)
end)

-- tests/spider_test.lua
describe("spider", function()
    it("deploys when work exists", ...)
    it("recalls after idle timeout", ...)
    it("teleports when anchor moves far", ...)
    it("drops as item on death", ...)
end)

-- tests/tasks_test.lua
describe("task assignment", function()
    it("assigns by priority order", ...)
    it("spider self-assigns within personal radius", ...)
    it("prevents double-assignment", ...)
end)
```

---

## Changelog

### v0.1.0 (In Development)
- Initial release
- Player-based anchors
- 8 behaviors (build, deconstruct, upgrade, tiles, item proxy)
- Two-tier task assignment
- Auto-deploy and auto-recall
- Global toggle
- State-based spider coloring
