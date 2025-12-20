-- control.lua
-- Main entry point for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local anchor = require("scripts/anchor")
local spider = require("scripts/spider")
local tasks = require("scripts/tasks")

local function debug_enabled()
    return utils.debug_enabled()
end

---------------------------------------------------------------------------
-- STORAGE INITIALIZATION
---------------------------------------------------------------------------

local function setup_storage()
    storage.anchors = storage.anchors or {}
    storage.spider_to_anchor = storage.spider_to_anchor or {}
    storage.entity_to_spider = storage.entity_to_spider or {}
    storage.assigned_tasks = storage.assigned_tasks or {}
    storage.player_to_anchor = storage.player_to_anchor or {}
    storage.assignment_limits = storage.assignment_limits or {}
    storage.global_enabled = storage.global_enabled ~= false -- default true
    storage.anchor_id_counter = storage.anchor_id_counter or 0
    storage.spider_id_counter = storage.spider_id_counter or 0
    -- Deprecated: older versions used this for tile deconstruction confirmation.
    storage.pending_tile_deconstruct = nil

    -- Clean up any non-serialisable task data from older versions
    -- (tasks should not keep behavior tables/functions in storage)
    for _, anchor_data in pairs(storage.anchors) do
        if anchor_data.spiders then
            for _, spider_data in pairs(anchor_data.spiders) do
                local task = spider_data.task
                if task and task.behavior then
                    if not task.behavior_name and task.behavior.name then
                        task.behavior_name = task.behavior.name
                    end
                    task.behavior = nil
                end
            end
        end
    end
end

--- Recall all spiders for an anchor and destroy the anchor.
---@param anchor_id string
local function destroy_anchor(anchor_id)
    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    -- Copy spider IDs first, since recall() mutates the table.
    local spider_ids = {}
    for spider_id, _ in pairs(anchor_data.spiders) do
        spider_ids[#spider_ids + 1] = spider_id
    end
    for _, spider_id in ipairs(spider_ids) do
        spider.recall(spider_id)
    end

    anchor.destroy(anchor_id)
    if storage.assignment_limits then
        storage.assignment_limits[anchor_id] = nil
    end
end

---------------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- ASSIGNMENT LIMITING
---------------------------------------------------------------------------

local function get_assignment_limit(anchor_id)
    if not anchor_id then
        return nil
    end
    storage.assignment_limits = storage.assignment_limits or {}
    local limit = storage.assignment_limits[anchor_id]
    if not limit or limit.tick ~= game.tick then
        limit = { tick = game.tick, count = 0 }
        storage.assignment_limits[anchor_id] = limit
    end
    return limit
end

local function assign_task_capped(spider_id, task, anchor_id)
    if not task then
        return false
    end
    if not anchor_id and storage.spider_to_anchor then
        anchor_id = storage.spider_to_anchor[spider_id]
    end
    local limit = get_assignment_limit(anchor_id)
    if not limit or limit.count >= constants.max_assignments_per_tick then
        return false
    end

    if debug_enabled() then
        local target = task.tile or task.entity
        local desc = "nil"
        if target and target.valid then
            if task.tile then
                desc = string.format("tile:%s@%.0f,%.0f", target.name, target.position.x, target.position.y)
            elseif task.entity then
                desc = string.format(
                    "entity:%s(%s)@%.1f,%.1f",
                    target.name,
                    target.type or "?",
                    target.position.x,
                    target.position.y
                )
            end
        end
        utils.log(
            string.format(
                "[Assign] anchor=%s spider=%s behavior=%s task=%s %s",
                tostring(anchor_id or "?"),
                tostring(spider_id),
                tostring(task.behavior_name or "?"),
                tostring(task.id or "?"),
                desc
            )
        )
    end

    spider.assign_task(spider_id, task)
    limit.count = limit.count + 1
    return true
end

local function process_spider(spider_id, spider_data, anchor_data, inventory, anchor_area, anchor_id, work_exists)
    local spider_entity = spider_data.entity

    -- Validate spider entity
    if not spider_entity or not spider_entity.valid then
        -- Clean up invalid spider
        if spider_data.task and spider_data.task.id then
            storage.assigned_tasks[spider_data.task.id] = nil
        end
        if spider_data.entity_id then
            storage.entity_to_spider[spider_data.entity_id] = nil
        end
        storage.spider_to_anchor[spider_id] = nil
        anchor_data.spiders[spider_id] = nil
        return
    end

    local status = spider_data.status
    local surface = anchor.get_surface(anchor_data)
    if not surface then
        return
    end
    local force = anchor.get_force(anchor_data)

    -- Handle different states
    if status == "deployed_idle" then
        -- First, check for self-assignment (personal radius)
        local personal_area = spider.get_personal_area(spider_data)
        local task = tasks.find_best(surface, personal_area, force, inventory)

        if assign_task_capped(spider_id, task, anchor_id) then
            return
        end

        -- No nearby task - check if near anchor
        local near = spider.is_near_anchor(spider_data, anchor_data)

        if near then
            -- Track idle time
            if not spider_data.idle_since then
                spider_data.idle_since = game.tick
            elseif not work_exists and game.tick - spider_data.idle_since > constants.idle_timeout_ticks then
                -- Been idle too long with no work anywhere in the area, recall
                spider.recall(spider_id)
                return
            end
        else
            -- Not near anchor, walking back
            spider_data.idle_since = nil

            -- Make sure follow target is set
            local anchor_entity = anchor_data.entity
            if anchor_entity and anchor_entity.valid then
                if spider_entity.follow_target ~= anchor_entity then
                    spider_entity.follow_target = anchor_entity
                end
            end
        end
    elseif status == "moving_to_task" then
        -- Check if task is still valid
        if not spider.is_task_valid(spider_data) then
            spider.clear_task(spider_id)
            return
        end

        -- Execute tasks when we're "close enough", even if the autopilot completion
        -- event doesn't fire or the destination list isn't cleared.
        local function is_close_enough()
            local target = spider_data.task and (spider_data.task.entity or spider_data.task.tile) or nil
            if not (target and target.valid) then
                return false
            end

            local spider_pos = spider_entity.position
            local threshold = constants.task_arrival_distance
            if threshold < 1.0 then
                threshold = 1.0
            end

            local dist_to_target = utils.distance(spider_pos, target.position)
            if dist_to_target < threshold then
                return true
            end

            local approach = spider_data.task.approach_position
            if approach and utils.distance(spider_pos, approach) < threshold then
                return true
            end

            local destinations = spider_entity.autopilot_destinations
            if destinations and #destinations > 0 then
                local last_dest = destinations[#destinations]
                local dest_pos = last_dest and (last_dest.position or last_dest) or nil
                if dest_pos and utils.distance(spider_pos, dest_pos) < threshold then
                    return true
                end
            end

            -- If we're basically touching the target and not moving, treat it as arrived.
            local speed = spider_entity.speed or 0
            if speed <= constants.stuck_speed_threshold and dist_to_target < (threshold * 1.5) then
                return true
            end

            return false
        end

        -- If we're already close enough, execute even if the autopilot
        -- completion event doesn't fire (e.g., destination already reached).
        if is_close_enough() or spider.has_arrived(spider_data) then
            spider.arrive_at_task(spider_id)
            tasks.execute(spider_data, spider_data.task, inventory, anchor_data)
            spider.complete_task(spider_id)
            return
        end

        -- Basic stuck recovery.
        if spider.is_stuck(spider_data) then
            spider.jump(spider_id)
        end
    elseif status == "executing" then
        -- Shouldn't stay in this state long (instant execution)
        -- Just complete and move on
        spider.complete_task(spider_id)
    end
end

local function main_loop()
    -- Skip if globally disabled
    if not storage.global_enabled then
        return
    end

    for anchor_id, anchor_data in anchor.iterate() do
        -- Validate anchor
        if not anchor.is_valid(anchor_data) then
            -- Try to update entity reference for player anchors
            if anchor_data.type == "player" and anchor_data.player_index then
                local player = game.get_player(anchor_data.player_index)
                if player and player.valid then
                    local new_entity = utils.get_player_entity(player)
                    if new_entity and new_entity.valid then
                        anchor.update_entity(anchor_id, new_entity)
                    else
                        goto next_anchor
                    end
                else
                    destroy_anchor(anchor_id)
                    goto next_anchor
                end
            else
                destroy_anchor(anchor_id)
                goto next_anchor
            end
        end

        -- Check for player controller type
        if anchor_data.type == "player" and anchor_data.player_index then
            local player = game.get_player(anchor_data.player_index)
            if player and player.valid then
                if not constants.allowed_controllers[player.controller_type] then
                    goto next_anchor
                end
            end
        end

        -- Check for anchor teleport
        local teleported = anchor.update_position(anchor_data)
        if teleported then
            -- Teleport all spiders to anchor
            for spider_id, _ in pairs(anchor_data.spiders) do
                spider.teleport_to_anchor(spider_id)
            end
        end

        -- Get inventory and work area
        local inventory = anchor.get_inventory(anchor_data)
        if not inventory or not inventory.valid then
            goto next_anchor
        end

        local anchor_area = anchor.get_expanded_work_area(anchor_data)
        local surface = anchor.get_surface(anchor_data)
        if not surface then
            return
        end
        local force = anchor.get_force(anchor_data)

        -- Check if any executable work exists in the area around this anchor
        local work_exists = tasks.exist_executable_in_area(surface, anchor_area, force, inventory)

        -- Process each spider
        local limit = get_assignment_limit(anchor_id)
        local assignments_this_tick = limit and limit.count or 0

        for spider_id, spider_data in utils.random_pairs(anchor_data.spiders) do
            if assignments_this_tick >= constants.max_assignments_per_tick then
                break
            end
            process_spider(spider_id, spider_data, anchor_data, inventory, anchor_area, anchor_id, work_exists)
            limit = get_assignment_limit(anchor_id)
            assignments_this_tick = limit and limit.count or assignments_this_tick
        end

        -- Anchor-level task assignment for idle spiders at anchor
        local idle_at_anchor = {}
        for spider_id, spider_data in pairs(anchor_data.spiders) do
            if spider_data.status == "deployed_idle" and spider.is_near_anchor(spider_data, anchor_data) then
                idle_at_anchor[#idle_at_anchor + 1] = spider_id
            end
        end

        local spider_count = anchor.get_spider_count(anchor_data)
        local has_spiderlings, spiderling_count = anchor.has_spiderlings_in_inventory(anchor_data)

        -- Only compute the task list when we need it (assignment or sizing auto-deploy).
        local available_tasks = nil
        if
            work_exists
            and (
                (#idle_at_anchor > 0 and assignments_this_tick < constants.max_assignments_per_tick)
                or (has_spiderlings and spider_count < constants.max_spiders_per_anchor)
            )
        then
            available_tasks = tasks.find_all(surface, anchor_area, force, inventory)
        end

        if #idle_at_anchor > 0 and assignments_this_tick < constants.max_assignments_per_tick then
            if not available_tasks then
                available_tasks = tasks.find_all(surface, anchor_area, force, inventory)
            end

            for _, spider_id in ipairs(idle_at_anchor) do
                if #available_tasks == 0 then
                    break
                end
                if assignments_this_tick >= constants.max_assignments_per_tick then
                    break
                end

                local task = table.remove(available_tasks, 1)
                if assign_task_capped(spider_id, task, anchor_id) then
                    assignments_this_tick = assignments_this_tick + 1
                end
            end
        end

        -- Auto-deploy: scale spiders to the amount of work, instead of deploying a full
        -- burst every tick as long as any work exists.
        if has_spiderlings and spider_count < constants.max_spiders_per_anchor and work_exists then
            if not available_tasks then
                available_tasks = tasks.find_all(surface, anchor_area, force, inventory)
            end

            local assigned_count = 0
            for _, spider_data in pairs(anchor_data.spiders) do
                if spider_data.task and spider_data.task.id then
                    assigned_count = assigned_count + 1
                end
            end

            local pending_tasks = assigned_count + #available_tasks
            local desired_spiders = math.min(pending_tasks, constants.max_spiders_per_anchor)
            local needed_spiders = desired_spiders - spider_count

            if debug_enabled() and needed_spiders > 0 then
                utils.log(
                    string.format(
                        "[Deploy] anchor=%s pending=%d assigned=%d unassigned=%d spiders=%d need=%d",
                        anchor_id,
                        pending_tasks,
                        assigned_count,
                        #available_tasks,
                        spider_count,
                        needed_spiders
                    )
                )

                local counts = {}
                for _, t in ipairs(available_tasks) do
                    local name = t.behavior_name or "?"
                    counts[name] = (counts[name] or 0) + 1
                end
                local parts = {}
                for name, count in pairs(counts) do
                    parts[#parts + 1] = string.format("%s=%d", name, count)
                end
                table.sort(parts)
                utils.log("[Deploy] breakdown=" .. table.concat(parts, ", "))

                local sample = {}
                local sample_limit = math.min(#available_tasks, 16)
                for i = 1, sample_limit do
                    local t = available_tasks[i]
                    local target = t.tile or t.entity
                    if target and target.valid then
                        if t.tile then
                            sample[#sample + 1] = string.format(
                                "%s:%s@%.0f,%.0f",
                                tostring(t.behavior_name or "?"),
                                target.name,
                                target.position.x,
                                target.position.y
                            )
                        elseif t.entity then
                            sample[#sample + 1] = string.format(
                                "%s:%s(%s)@%.1f,%.1f",
                                tostring(t.behavior_name or "?"),
                                target.name,
                                target.type or "?",
                                target.position.x,
                                target.position.y
                            )
                        end
                    else
                        sample[#sample + 1] = tostring(t.behavior_name or "?") .. ":invalid"
                    end
                end
                if #available_tasks > sample_limit then
                    sample[#sample + 1] = string.format("...(+%d more)", #available_tasks - sample_limit)
                end
                utils.log("[Deploy] tasks=" .. table.concat(sample, ", "))
            end

            local deploys = 0
            while
                needed_spiders > 0
                and deploys < constants.max_deploys_per_tick
                and spider_count < constants.max_spiders_per_anchor
                and has_spiderlings
            do
                spider.deploy(anchor_id)
                deploys = deploys + 1
                needed_spiders = needed_spiders - 1
                spider_count = anchor.get_spider_count(anchor_data)
                has_spiderlings, spiderling_count = anchor.has_spiderlings_in_inventory(anchor_data)
            end
        end

        -- Recall idle spiders near the anchor if there has been no work for a while
        if not work_exists then
            anchor_data.no_work_since = anchor_data.no_work_since or game.tick
        else
            anchor_data.no_work_since = nil
        end

        if
            anchor_data.no_work_since
            and game.tick - anchor_data.no_work_since > constants.no_work_recall_timeout_ticks
        then
            local recall_ids = {}
            for spider_id, spider_data in pairs(anchor_data.spiders) do
                if spider_data.status == "deployed_idle" and spider.is_near_anchor(spider_data, anchor_data) then
                    recall_ids[#recall_ids + 1] = spider_id
                end
            end
            for _, spider_id in ipairs(recall_ids) do
                spider.recall(spider_id)
            end
        end

        ::next_anchor::
    end

    -- Periodic cleanup
    if game.tick % 300 == 0 then
        tasks.cleanup_stale()
    end
end

---------------------------------------------------------------------------
-- TOGGLE HANDLER
---------------------------------------------------------------------------

local function toggle_global(event)
    local name = event.prototype_name or event.input_name
    if name ~= "brood-toggle" then
        return
    end

    storage.global_enabled = not storage.global_enabled

    -- Update shortcut toggle state for all players
    for _, player in pairs(game.players) do
        player.set_shortcut_toggled("brood-toggle", storage.global_enabled)
    end

    if not storage.global_enabled then
        -- Recall all spiders
        for anchor_id, anchor_data in anchor.iterate() do
            local spider_ids = {}
            for spider_id, _ in pairs(anchor_data.spiders) do
                spider_ids[#spider_ids + 1] = spider_id
            end
            for _, spider_id in ipairs(spider_ids) do
                spider.recall(spider_id)
            end
        end
    end

    local player = game.get_player(event.player_index)
    if player then
        player.print(storage.global_enabled and "[Brood] Spiders enabled" or "[Brood] Spiders disabled - all recalled")
    end
end

---------------------------------------------------------------------------
-- PLAYER EVENTS
---------------------------------------------------------------------------

local function on_player_created(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        anchor.create_for_player(player)
        player.set_shortcut_toggled("brood-toggle", storage.global_enabled)
    end
end

local function on_player_removed(event)
    local anchor_id = storage.player_to_anchor and storage.player_to_anchor[event.player_index]
    if anchor_id then
        destroy_anchor(anchor_id)
    end
end

local function on_player_changed_surface(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    local anchor_data = anchor.get_for_player(player)
    if not anchor_data then
        return
    end

    -- Update anchor entity reference
    local new_entity = utils.get_player_entity(player)
    if new_entity and new_entity.valid then
        local anchor_id = anchor.get_id_for_player(player)
        if not anchor_id then
            return
        end
        anchor.update_entity(anchor_id, new_entity)

        -- Teleport all spiders
        for spider_id, _ in pairs(anchor_data.spiders) do
            spider.teleport_to_anchor(spider_id)
        end
    end
end

local function on_player_driving_changed_state(event)
    local player = game.get_player(event.player_index)
    if not player or not player.valid then
        return
    end

    local anchor_id = anchor.get_id_for_player(player)
    if not anchor_id then
        return
    end

    local new_entity = utils.get_player_entity(player)
    if new_entity and new_entity.valid then
        anchor.update_entity(anchor_id, new_entity)

        -- Update spider follow targets
        local anchor_data = anchor.get(anchor_id)
        if anchor_data then
            for spider_id, spider_data in pairs(anchor_data.spiders) do
                local spider_entity = spider_data.entity
                if spider_entity and spider_entity.valid then
                    if spider_data.status == "deployed_idle" then
                        spider_entity.follow_target = new_entity
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- SPIDER DEATH
---------------------------------------------------------------------------

local function on_entity_died(event)
    local entity = event.entity
    if not entity or entity.name ~= "spiderling" then
        return
    end

    spider.on_death(entity)
end

local function on_object_destroyed(event)
    local entity_id = event.registration_number or event.useful_id
    if not entity_id then
        return
    end

    local spider_id = storage.entity_to_spider[entity_id]
    if not spider_id and event.useful_id then
        spider_id = storage.entity_to_spider[event.useful_id]
    end
    if not spider_id then
        return
    end

    -- Clean up tracking
    local anchor_id = storage.spider_to_anchor[spider_id]
    if anchor_id then
        local anchor_data = anchor.get(anchor_id)
        if anchor_data then
            local spider_data = anchor_data.spiders[spider_id]
            if spider_data and spider_data.task and spider_data.task.id then
                storage.assigned_tasks[spider_data.task.id] = nil
            end
            anchor_data.spiders[spider_id] = nil
        end
    end

    storage.entity_to_spider[entity_id] = nil
    storage.spider_to_anchor[spider_id] = nil
end

---------------------------------------------------------------------------
-- SPIDER MOVEMENT COMPLETION
---------------------------------------------------------------------------

local function on_spider_command_completed(event)
    local vehicle = event.vehicle
    if not vehicle or not vehicle.valid or vehicle.name ~= "spiderling" then
        return
    end

    -- Find the corresponding spider_id/anchor_id
    local spider_id
    local anchor_id
    for id, a_id in pairs(storage.spider_to_anchor or {}) do
        local anchor_data = anchor.get(a_id)
        if anchor_data then
            local spider_data = anchor_data.spiders[id]
            if spider_data and spider_data.entity == vehicle then
                spider_id = id
                anchor_id = a_id
                break
            end
        end
    end

    if not spider_id or not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data or spider_data.status ~= "moving_to_task" or not spider_data.task then
        return
    end

    -- Ensure autopilot has actually finished.
    -- In some cases Factorio fires on_spider_command_completed before the
    -- destinations list is fully cleared; allow completion if we're already at the target.
    local destinations = vehicle.autopilot_destinations
    if destinations and #destinations > 0 then
        -- Sometimes Factorio emits this event before clearing the destinations list.
        -- For large tasks, spiders may stop at the destination without ever getting
        -- within task_arrival_distance of the task center, so also accept proximity
        -- to the current destination.
        local last_dest = destinations[#destinations]
        local dest_pos = last_dest and (last_dest.position or last_dest) or nil
        local dist_to_dest = dest_pos and utils.distance(vehicle.position, dest_pos) or math.huge
        if dist_to_dest > constants.task_arrival_distance and not spider.has_arrived(spider_data) then
            return
        end
    end

    local inventory = anchor.get_inventory(anchor_data)
    if not inventory or not inventory.valid then
        return
    end

    -- Mark as arrived and execute the current task
    spider.arrive_at_task(spider_id)
    local _ = tasks.execute(spider_data, spider_data.task, inventory, anchor_data)
    spider.complete_task(spider_id)

    -- Immediately try to pick up another task now that we're idle again
    local updated_spider_data = anchor_data.spiders[spider_id]
    if updated_spider_data and updated_spider_data.status == "deployed_idle" then
        local limit = get_assignment_limit(anchor_id)
        if limit and limit.count >= constants.max_assignments_per_tick then
            return
        end
        local surface = anchor.get_surface(anchor_data)
        if surface then
            local anchor_area = anchor.get_expanded_work_area(anchor_data)
            local force = anchor.get_force(anchor_data)
            local work_exists = tasks.exist_executable_in_area(surface, anchor_area, force, inventory)
            process_spider(spider_id, updated_spider_data, anchor_data, inventory, anchor_area, anchor_id, work_exists)
        end
    end
end
---------------------------------------------------------------------------
-- TRIGGER CREATED ENTITY (for capsule throwing, if we add it later)
---------------------------------------------------------------------------

local function on_trigger_created_entity(event)
    local entity = event.entity
    if not entity or entity.name ~= "spiderling" then
        return
    end

    local source = event.source
    if not source or not source.valid then
        return
    end

    -- Find the player
    local player
    if source.type == "character" then
        player = source.player
    end

    if not player or not player.valid then
        return
    end

    -- Get anchor and register spider
    local anchor_id = anchor.get_id_for_player(player)
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    -- Register the spider
    local entity_id = utils.get_entity_id(entity)
    local spider_id = "spider_" .. (storage.spider_id_counter or 0) + 1
    storage.spider_id_counter = (storage.spider_id_counter or 0) + 1

    local spider_data = {
        entity = entity,
        entity_id = entity_id,
        anchor_id = anchor_id,
        status = "deployed_idle",
        task = nil,
        idle_since = nil,
    }

    anchor_data.spiders[spider_id] = spider_data
    storage.spider_to_anchor[spider_id] = anchor_id
    storage.entity_to_spider[entity_id] = spider_id

    -- Set color and follow target
    entity.color = constants.colors.idle
    entity.follow_target = anchor_data.entity
end

---------------------------------------------------------------------------
-- EVENT REGISTRATION
---------------------------------------------------------------------------

script.on_init(function()
    setup_storage()

    -- Keep FactorioTest runs quiet by default; enable per-test via remote override.
    if script.active_mods and script.active_mods["factorio-test"] and storage.debug_logging_override == nil then
        storage.debug_logging_override = false
    end

    -- Create anchors for existing players
    for _, player in pairs(game.players) do
        anchor.create_for_player(player)
        player.set_shortcut_toggled("brood-toggle", storage.global_enabled)
    end
end)

script.on_configuration_changed(function()
    setup_storage()

    -- Keep FactorioTest runs quiet by default; enable per-test via remote override.
    if script.active_mods and script.active_mods["factorio-test"] and storage.debug_logging_override == nil then
        storage.debug_logging_override = false
    end

    -- Ensure all players have anchors
    for _, player in pairs(game.players) do
        local existing = anchor.get_for_player(player)
        if not existing then
            anchor.create_for_player(player)
        end
        player.set_shortcut_toggled("brood-toggle", storage.global_enabled)
    end
end)

-- Main loop
script.on_nth_tick(constants.main_loop_interval, main_loop)

-- Toggle
script.on_event("brood-toggle", toggle_global)
script.on_event(defines.events.on_lua_shortcut, toggle_global)

-- Player events
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(defines.events.on_player_removed, on_player_removed)
script.on_event(defines.events.on_player_changed_surface, on_player_changed_surface)
script.on_event(defines.events.on_player_driving_changed_state, on_player_driving_changed_state)

-- Spider death
script.on_event(defines.events.on_entity_died, on_entity_died)
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
script.on_event(defines.events.on_spider_command_completed, on_spider_command_completed)

-- Trigger created (for future capsule throwing)
script.on_event(defines.events.on_trigger_created_entity, on_trigger_created_entity)

---------------------------------------------------------------------------
-- FACTORIO TEST INTEGRATION (dev-only)
---------------------------------------------------------------------------

if script.active_mods and script.active_mods["factorio-test"] then
    if remote and remote.add_interface and not (remote.interfaces and remote.interfaces["brood-engineering-test"]) then
        remote.add_interface("brood-engineering-test", {
            set_debug_logging_override = function(enabled)
                storage.debug_logging_override = enabled
            end,
            press_brood_toggle = function(player_index)
                toggle_global({
                    prototype_name = "brood-toggle",
                    player_index = player_index or 1,
                })
            end,
            reset_assignment_limits = function()
                storage.assignment_limits = {}
            end,
            try_assign_task_capped = function(spider_id, task, anchor_id)
                return assign_task_capped(spider_id, task, anchor_id)
            end,
            get_assignment_count = function(anchor_id)
                local limit = get_assignment_limit(anchor_id)
                return limit and limit.count or 0
            end,
            run_main_loop = function()
                local prev = storage.global_enabled
                storage.global_enabled = true
                main_loop()
                storage.global_enabled = prev
            end,
        })
    end

    -- When running under FactorioTest via CLI, auto-start tests on the next tick.
    -- This avoids needing to click "Reload mods and run tests" in the UI.
    local function try_start_factoriotests()
        if not remote or not remote.call or not remote.interfaces then
            return
        end
        if remote.interfaces["factorio-test"] then
            pcall(function()
                remote.call("factorio-test", "runTests")
            end)
        elseif remote.interfaces["Factorio Test"] then
            pcall(function()
                remote.call("Factorio Test", "runTests")
            end)
        end
    end

    script.on_nth_tick(1, function()
        try_start_factoriotests()
        script.on_nth_tick(1, nil)
    end)

    require("__factorio-test__/init")({
        "tests/assignment_limit_test",
        "tests/assignment_tracking_integrity_test",
        "tests/tasks_test",
        "tests/spider_test",
        "tests/deploy_recall_test",
        "tests/idle_recall_test",
        "tests/entity_deconstruct_test",
        "tests/upgrade_test",
        "tests/blueprint_scenario_test",
        "tests/blueprint_cycle_test",
        "tests/tile_deconstruct_test",
        "tests/build_entity_large_test",
        "tests/module_insert_test",
        "tests/recall_spill_test",
        "tests/toggle_disable_recall_test",
        "tests/disable_while_moving_test",
        "tests/spider_destroy_cleanup_test",
    }, {
        log_passed_tests = true,
        log_skipped_tests = true,
    })
end
