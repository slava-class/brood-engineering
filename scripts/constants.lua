-- scripts/constants.lua
-- All tunable values for Brood Engineering
-- Adjust these to tweak behavior

local constants = {
    ---------------------------------------------------------------------------
    -- RADII (tiles)
    ---------------------------------------------------------------------------

    -- How far the anchor scans for tasks
    anchor_scan_radius = 120,

    -- How far a spider scans for self-assignment
    spider_personal_radius = 10,

    -- Distance to be considered "near anchor" for recall
    near_anchor_threshold = 10,

    ---------------------------------------------------------------------------
    -- COUNTS
    ---------------------------------------------------------------------------

    -- Maximum spiders per anchor
    max_spiders_per_anchor = 200,

    -- Maximum task assignments per tick (prevents lag spikes)
    max_assignments_per_tick = 32,

    -- Maximum spider deployments per tick
    max_deploys_per_tick = 8,

    ---------------------------------------------------------------------------
    -- TIMING (ticks, 60 ticks = 1 second)
    ---------------------------------------------------------------------------

    -- How long spider waits near anchor before recalling
    idle_timeout_ticks = 240, -- 4 seconds

    -- How long an anchor can have no work before recalling idle spiders
    -- How long an anchor can have no work before recalling idle spiders
    -- (2 seconds gives a quick cleanup once an area is finished)
    no_work_recall_timeout_ticks = 120, -- 2 seconds

    -- Main loop interval
    main_loop_interval = 30, -- twice per second

    ---------------------------------------------------------------------------
    -- MOVEMENT
    ---------------------------------------------------------------------------

    -- If anchor moves this far in one tick, teleport spiders
    teleport_threshold = 50,

    -- Nudge distance when stuck
    jump_distance = 5,

    -- Minimum distance before requesting a path (avoid tiny paths)
    path_request_min_distance = 8,

    -- Minimum ticks between path requests per spider
    path_request_cooldown_ticks = 120,

    -- Minimum ticks between stuck-triggered path requests
    path_request_stuck_cooldown_ticks = 60,

    -- Retry delay when the pathfinder is busy
    path_retry_delay_ticks = 120,

    -- Waypoint spacing when applying pathfinding results
    path_waypoint_spacing = 6,

    -- Max waypoints to enqueue for a path
    path_max_waypoints = 24,

    -- Follow offset radius around the anchor
    follow_offset_radius = 3,

    -- Minimum movement distance to consider as progress
    stuck_move_threshold = 0.25,

    -- Tile tasks can be executed from a bit farther away
    tile_task_arrival_distance = 0,

    -- How far from a tile ghost we search for a walkable approach point
    tile_approach_search_radius = 10,

    -- Only update return destinations if the anchor moved this far
    return_destination_update_distance = 6,

    -- Teleport to destination when stuck and already close enough
    stuck_teleport_distance = 10,

    -- Max distance moved while stuck to allow teleport recovery
    stuck_teleport_max_move = 3,

    -- How long speed must be zero before considered stuck (ticks)
    stuck_timeout_ticks = 120, -- ~2 seconds

    -- Speed threshold to treat as "stopped"
    stuck_speed_threshold = 0.01,

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
