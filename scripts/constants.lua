-- scripts/constants.lua
-- All tunable values for Brood Engineering
-- Adjust these to tweak behavior

local constants = {
    ---------------------------------------------------------------------------
    -- RADII (tiles)
    ---------------------------------------------------------------------------

    -- How far the anchor scans for tasks
    anchor_scan_radius = 40,

    -- How far a spider scans for self-assignment
    spider_personal_radius = 8,

    -- Distance to be considered "near anchor" for recall
    near_anchor_threshold = 5,

    ---------------------------------------------------------------------------
    -- COUNTS
    ---------------------------------------------------------------------------

    -- Maximum spiders per anchor
    max_spiders_per_anchor = 200,

    -- Maximum task assignments per tick (prevents lag spikes)
    max_assignments_per_tick = 4,

    -- Maximum spider deployments per tick
    max_deploys_per_tick = 2,

    ---------------------------------------------------------------------------
    -- TIMING (ticks, 60 ticks = 1 second)
    ---------------------------------------------------------------------------

    -- How long spider waits near anchor before recalling
    idle_timeout_ticks = 240,  -- 4 seconds

    -- Main loop interval
    main_loop_interval = 30,  -- twice per second

    ---------------------------------------------------------------------------
    -- MOVEMENT
    ---------------------------------------------------------------------------

    -- If anchor moves this far in one tick, teleport spiders
    teleport_threshold = 50,

    -- Jump distance when stuck
    jump_distance = 4,

    -- How close spider needs to be to task to execute
    task_arrival_distance = 1.5,

    ---------------------------------------------------------------------------
    -- SPIDER PROTOTYPE
    ---------------------------------------------------------------------------

    -- Visual scale
    spider_scale = 0.125,

    -- Leg scale multiplier
    spider_leg_scale = 0.82,

    -- Movement speed multiplier (lower = slower)
    spider_speed_modifier = 0.5,

    -- Leg movement speed
    spider_leg_movement_speed = 0.75,

    ---------------------------------------------------------------------------
    -- COLORS (RGBA, 0-1 range)
    ---------------------------------------------------------------------------

    colors = {
        -- Idle, waiting for task
        idle = { r = 0.5, g = 0.5, b = 0.5, a = 1 },

        -- Moving to a task
        moving = { r = 1, g = 0.7, b = 0, a = 1 },

        -- Executing a task
        executing = { r = 0, g = 1, b = 0.3, a = 1 },

        -- Returning to anchor
        returning = { r = 0.3, g = 0.5, b = 1, a = 1 },
    },

    ---------------------------------------------------------------------------
    -- BEHAVIOR PRIORITIES (lower = higher priority)
    ---------------------------------------------------------------------------

    priorities = {
        unblock_deconstruct = 1,
        build_foundation = 2,
        build_entity = 3,
        upgrade = 4,
        item_proxy = 5,
        deconstruct_entity = 6,
        build_tile = 7,
        deconstruct_tile = 8,
    },

    ---------------------------------------------------------------------------
    -- MISC
    ---------------------------------------------------------------------------

    -- Allowed controller types for player anchors
    allowed_controllers = {
        [defines.controllers.character] = true,
        [defines.controllers.remote] = true,
    },

    -- Bounding box for tile operations
    tile_bounding_box = {
        left_top = { x = -0.5, y = -0.5 },
        right_bottom = { x = 0.5, y = 0.5 },
    },
}

return constants
