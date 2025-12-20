-- scripts/spider.lua
-- Spider lifecycle and state management for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local anchor = require("scripts/anchor")
local fapi = require("scripts/fapi")

local spider = {}

---@param spider_entity LuaEntity?
---@return ItemStackDefinition
local function get_recall_item_stack(spider_entity)
    if spider_entity and spider_entity.valid then
        local proto = spider_entity.prototype
        local items = proto and proto.items_to_place_this or nil
        local it = items and items[1] or nil
        if it and it.name then
            local count = it.count or 1
            if not count or count < 1 then
                count = 1
            end
            return { name = it.name, count = count }
        end
    end
    return { name = "spiderling", count = 1 }
end

---@param spider_entity LuaEntity
---@param ghost LuaEntity
---@return MapPosition? destination
local function get_build_entity_approach_position(spider_entity, ghost)
    if not (spider_entity and spider_entity.valid) then
        return nil
    end
    if not (ghost and ghost.valid and ghost.type == "entity-ghost") then
        return nil
    end

    local surface = spider_entity.surface
    if not (surface and (surface.valid == nil or surface.valid)) then
        return nil
    end

    local box = ghost.bounding_box
    if not (box and box.left_top and box.right_bottom) then
        return nil
    end

    -- Keep well clear of the ghost footprint. Large ghosts (5x5+) can fail to revive if the
    -- spider (or its legs) overlaps the future collision box.
    local padding = math.max(constants.task_arrival_distance + 0.5, 4)
    local mid_x = (box.left_top.x + box.right_bottom.x) / 2
    local mid_y = (box.left_top.y + box.right_bottom.y) / 2

    local candidates = {
        { x = box.left_top.x - padding, y = mid_y },
        { x = box.right_bottom.x + padding, y = mid_y },
        { x = mid_x, y = box.left_top.y - padding },
        { x = mid_x, y = box.right_bottom.y + padding },
    }

    local best = nil
    local best_dist = nil
    for _, candidate in ipairs(candidates) do
        local pos = fapi.find_non_colliding_position(surface, "spiderling", candidate, 10, 0.5)
        if pos then
            local dist = utils.distance(spider_entity.position, pos)
            if not best_dist or dist < best_dist then
                best = pos
                best_dist = dist
            end
        end
    end

    return best
end

---@param spider_id string
---@return Vector
local function compute_follow_offset(spider_id)
    local n = tonumber(tostring(spider_id):match("%d+")) or 1
    local angle = (n * 0.61803398875) * (2 * math.pi)
    local radius = constants.follow_offset_radius
    return { x = math.cos(angle) * radius, y = math.sin(angle) * radius }
end

---@param spider_entity LuaEntity
local function clear_autopilot(spider_entity)
    if not (spider_entity and spider_entity.valid) then
        return
    end
    -- Writing nil clears all queued destinations.
    spider_entity.autopilot_destination = nil
end

---@param spider_entity LuaEntity
---@param waypoints MapPosition[]
local function set_autopilot_path(spider_entity, waypoints)
    if not (spider_entity and spider_entity.valid) then
        return
    end
    clear_autopilot(spider_entity)
    if not (waypoints and waypoints[1]) then
        return
    end
    for _, waypoint in ipairs(waypoints) do
        spider_entity.add_autopilot_destination(waypoint)
    end
end

---@param anchor_entity LuaEntity
---@param spider_entity LuaEntity
---@param spider_id string
local function follow_anchor(anchor_entity, spider_entity, spider_id)
    if not (anchor_entity and anchor_entity.valid) then
        return
    end
    if not (spider_entity and spider_entity.valid) then
        return
    end
    clear_autopilot(spider_entity)
    spider_entity.follow_target = anchor_entity
    spider_entity.follow_offset = compute_follow_offset(spider_id)
end

---@param path PathfinderWaypoint[]
---@param destination MapPosition?
---@return MapPosition[]
local function build_waypoints(path, destination)
    local waypoints = {}
    local last_pos = nil

    for _, waypoint in ipairs(path) do
        local pos = waypoint and (waypoint.position or waypoint) or nil
        if pos then
            if not last_pos or utils.distance(last_pos, pos) >= constants.path_waypoint_spacing then
                waypoints[#waypoints + 1] = { x = pos.x, y = pos.y }
                last_pos = pos
                if #waypoints >= constants.path_max_waypoints then
                    break
                end
            end
        end
    end

    if destination then
        local last = waypoints[#waypoints]
        if not last or utils.distance(last, destination) > 0.5 then
            waypoints[#waypoints + 1] = { x = destination.x, y = destination.y }
        end
    end

    return waypoints
end

---@param spider_id string
---@param spider_data table
---@param destination MapPosition
---@param kind "task"|"return"
---@param task_id string?
---@param opts { force?: boolean }?
---@return uint32? request_id
local function request_path(spider_id, spider_data, destination, kind, task_id, opts)
    if not (destination and spider_data) then
        return nil
    end

    local spider_entity = spider_data.entity
    if not (spider_entity and spider_entity.valid) then
        return nil
    end

    local nav = spider_data.nav or {}
    local force_request = opts and opts.force or false
    local cooldown = force_request and constants.path_request_stuck_cooldown_ticks or constants.path_request_cooldown_ticks
    if nav.last_request_tick and (game.tick - nav.last_request_tick) < cooldown then
        return nil
    end

    local distance = utils.distance(spider_entity.position, destination)
    if not force_request and distance < constants.path_request_min_distance then
        return nil
    end

    local prototype = spider_entity.prototype
    if not (prototype and prototype.collision_box and prototype.collision_mask) then
        return nil
    end

    local surface = spider_entity.surface
    if not (surface and (surface.valid == nil or surface.valid)) then
        return nil
    end

    local id = surface.request_path({
        bounding_box = prototype.collision_box,
        collision_mask = prototype.collision_mask,
        start = spider_entity.position,
        goal = destination,
        force = spider_entity.force,
        pathfind_flags = {
            allow_paths_through_own_entities = true,
            cache = true,
        },
        entity_to_ignore = spider_entity,
    })

    if not id then
        return nil
    end

    storage.path_requests = storage.path_requests or {}
    storage.path_requests[id] = {
        spider_id = spider_id,
        anchor_id = spider_data.anchor_id,
        task_id = task_id,
        kind = kind,
        destination = { x = destination.x, y = destination.y },
        requested_tick = game.tick,
    }

    nav.request_id = id
    nav.last_request_tick = game.tick
    nav.pending_retry = false
    nav.kind = kind
    nav.task_id = task_id
    nav.destination = { x = destination.x, y = destination.y }
    spider_data.nav = nav

    return id
end

---@param spider_data table
local function clear_navigation(spider_data)
    if not spider_data then
        return
    end
    local nav = spider_data.nav
    if nav and nav.request_id and storage.path_requests then
        storage.path_requests[nav.request_id] = nil
    end
    spider_data.nav = nil
    spider_data.last_position = nil
    spider_data.last_move_tick = nil
    spider_data.stuck_since = nil
    spider_data.stuck_origin = nil
end

---@param behavior_name string?
---@return number
local function arrival_distance_for_behavior(behavior_name)
    if
        behavior_name == "build_tile"
        or behavior_name == "build_foundation"
        or behavior_name == "deconstruct_tile"
    then
        return math.max(constants.tile_task_arrival_distance, constants.task_arrival_distance)
    end
    return constants.task_arrival_distance
end

--- Generate unique spider ID
---@return string
local function generate_spider_id()
    storage.spider_id_counter = (storage.spider_id_counter or 0) + 1
    return "spider_" .. storage.spider_id_counter
end

--- Set spider color based on status
---@param spider_entity LuaEntity
---@param status string
local function update_spider_color(spider_entity, status)
    if not spider_entity or not spider_entity.valid then
        return
    end

    local color
    if status == "deployed_idle" then
        color = constants.colors.idle
    elseif status == "moving_to_task" then
        color = constants.colors.moving
    elseif status == "executing" then
        color = constants.colors.executing
    else
        color = constants.colors.idle
    end

    spider_entity.color = color
end

--- Deploy a spider from inventory
---@param anchor_id string
---@return string? spider_id
function spider.deploy(anchor_id)
    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return nil
    end

    -- Check if we can deploy
    if not anchor.can_deploy_spider(anchor_data) then
        return nil
    end

    -- Check inventory
    local inventory = anchor.get_inventory(anchor_data)
    if not inventory or not utils.inventory_has_item(inventory, "spiderling") then
        return nil
    end

    -- Find spawn position
    local anchor_entity = anchor_data.entity
    if not anchor_entity or not anchor_entity.valid then
        return nil
    end

    local surface = anchor_entity.surface
    local spawn_pos = utils.random_position_in_radius(anchor_data.position, 5)
    local valid_pos = fapi.find_non_colliding_position(surface, "spiderling", spawn_pos, 10, 0.5)

    if not valid_pos then
        valid_pos = anchor_data.position
    end

    -- Remove from inventory
    inventory.remove({ name = "spiderling", count = 1 })

    -- Create spider entity
    local spider_entity = surface.create_entity({
        name = "spiderling",
        position = valid_pos,
        force = anchor_entity.force,
    })

    if not spider_entity then
        -- Refund item
        inventory.insert({ name = "spiderling", count = 1 })
        return nil
    end

    -- Register for destruction tracking
    local entity_id = utils.get_entity_id(spider_entity)

    -- Create spider data
    local spider_id = generate_spider_id()
    local spider_data = {
        id = spider_id,
        entity = spider_entity,
        entity_id = entity_id,
        anchor_id = anchor_id,
        status = "deployed_idle",
        task = nil,
        idle_since = nil,
        nav = nil,
    }

    -- Store in anchor and global tracking
    anchor_data.spiders[spider_id] = spider_data
    storage.spider_to_anchor[spider_id] = anchor_id
    storage.entity_to_spider[entity_id] = spider_id

    -- Set initial color
    update_spider_color(spider_entity, "deployed_idle")

    -- Set follow target to anchor
    follow_anchor(anchor_entity, spider_entity, spider_id)

    utils.log("Deployed spider " .. spider_id .. " for anchor " .. anchor_id)
    return spider_id
end

--- Recall a spider to inventory
---@param spider_id string
function spider.recall(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    local recall_item = get_recall_item_stack(spider_entity)

    -- Clear task assignment
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end
    clear_navigation(spider_data)

    -- Return item to inventory if entity is valid
    if spider_entity and spider_entity.valid then
        local inventory = anchor.get_inventory(anchor_data)
        local anchor_entity = anchor_data.entity
        local spill_surface = spider_entity.surface
            or (anchor_entity and anchor_entity.valid and anchor_entity.surface)
            or nil
        local spill_position = spider_entity.position
            or (anchor_entity and anchor_entity.valid and anchor_entity.position)
            or nil
        local spill_force = (anchor_entity and anchor_entity.valid and anchor_entity.force) or spider_entity.force

        local function spill(stack)
            if not (spill_surface and spill_position and stack) then
                return
            end
            local safe_stack = utils.safe_item_stack(stack)
            if not safe_stack then
                return
            end

            local created, err = utils.spill_item_stack(spill_surface, spill_position, safe_stack, {
                enable_looted = true,
                allow_belts = false,
                max_radius = 0,
                use_start_position_on_failure = true,
                force = spill_force,
            })
            if created and #created > 0 then
                return
            end
            if err then
                utils.log("spill_item_stack failed: " .. tostring(err))
            end

            local created2, err2 = utils.spill_item_stack(spill_surface, spill_position, safe_stack, {
                max_radius = 0,
                use_start_position_on_failure = true,
            })
            if created2 and #created2 > 0 then
                return
            end
            if err2 then
                utils.log("spill_item_stack fallback failed: " .. tostring(err2))
            end

            -- Final fallback: spawn the item directly (used in spider.on_death too).
            local drop_position = spill_position
            pcall(function()
                local pos = fapi.find_non_colliding_position(spill_surface, "item-on-ground", spill_position, 10, 0.5)
                if pos then
                    drop_position = pos
                end
            end)

            local item_on_ground, create_err = utils.create_item_on_ground(spill_surface, drop_position, safe_stack, {
                force = spill_force,
                raise_built = false,
                create_build_effect_smoke = false,
                spawn_decorations = false,
            })
            if item_on_ground and item_on_ground.valid then
                pcall(function()
                    item_on_ground.to_be_looted = true
                end)
                pcall(function()
                    item_on_ground.order_deconstruction(spill_force)
                end)
            elseif create_err then
                utils.log("create_item_on_ground failed: " .. tostring(create_err))
            end
        end

        if inventory and inventory.valid then
            -- Return any items the spider is carrying (trunk/ammo/trash) to the anchor inventory.
            local inventory_ids = {
                defines.inventory.spider_trunk,
                defines.inventory.spider_ammo,
                defines.inventory.spider_trash,
            }
            for _, inv_id in ipairs(inventory_ids) do
                ---@diagnostic disable-next-line: param-type-mismatch
                local spider_inv = spider_entity.get_inventory(inv_id)
                if spider_inv and spider_inv.valid then
                    for i = 1, #spider_inv do
                        local stack = spider_inv[i]
                        if stack and stack.valid_for_read then
                            local inserted = inventory.insert(stack)
                            if inserted and inserted > 0 then
                                stack.count = stack.count - inserted
                                if stack.count <= 0 then
                                    stack.clear()
                                end
                            end

                            if stack and stack.valid_for_read and stack.count and stack.count > 0 then
                                local quality = stack.quality
                                local quality_name = type(quality) == "table" and quality.name or quality
                                spill({ name = stack.name, count = stack.count, quality = quality_name })
                                stack.clear()
                            end
                        end
                    end
                end
            end

            local expected = recall_item.count or 1
            local returned = inventory.insert(recall_item)
            local missing = expected - (returned or 0)
            if missing > 0 then
                spill({ name = recall_item.name, count = missing, quality = recall_item.quality })
            end
        else
            -- No valid anchor inventory; ensure the spiderling item isn't lost.
            spill(recall_item)
        end
        fapi.destroy_quiet(spider_entity)
    end

    -- Clean up tracking
    if spider_data.entity_id then
        storage.entity_to_spider[spider_data.entity_id] = nil
    end
    storage.spider_to_anchor[spider_id] = nil
    anchor_data.spiders[spider_id] = nil

    utils.log("Recalled spider " .. spider_id)
end

--- Handle spider arriving at task
---@param spider_id string
function spider.arrive_at_task(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    spider_data.status = "executing"
    update_spider_color(spider_data.entity, "executing")
end

--- Complete current task and return to idle
---@param spider_id string
function spider.complete_task(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    -- Clear task assignment tracking
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end

    spider_data.task = nil
    spider_data.status = "deployed_idle"
    spider_data.idle_since = nil
    clear_navigation(spider_data)

    update_spider_color(spider_data.entity, "deployed_idle")

    -- Set follow target back to anchor
    local spider_entity = spider_data.entity
    if spider_entity and spider_entity.valid then
        local anchor_entity = anchor_data.entity
        follow_anchor(anchor_entity, spider_entity, spider_id)
    end
end

--- Assign a task to a spider
---@param spider_id string
---@param task table
function spider.assign_task(spider_id, task)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return
    end

    clear_navigation(spider_data)

    -- Track task assignment
    if task.id then
        storage.assigned_tasks[task.id] = spider_id
    end

    spider_data.task = task
    spider_data.status = "moving_to_task"
    spider_data.idle_since = nil

    update_spider_color(spider_entity, "moving_to_task")

    -- Set destination
    local target = task.entity or task.tile
    if target and target.valid then
        spider_entity.follow_target = nil

        local surface = spider_entity.surface
        local target_pos = target.position

        -- For large entity ghosts, approach from outside the footprint so the spider/legs
        -- don't block `ghost.revive()` collisions during placement.
        local dest = nil
        if
            task.behavior_name == "build_entity"
            and target.object_name == "LuaEntity"
            and target.type == "entity-ghost"
        then
            dest = get_build_entity_approach_position(spider_entity, target)
        end

        -- Default: find a nearby non-colliding position close to the target.
        if not dest then
            local search_radius = constants.tile_approach_search_radius
            if task.behavior_name ~= "build_tile"
                and task.behavior_name ~= "build_foundation"
                and task.behavior_name ~= "deconstruct_tile" then
                search_radius = 5
            else
                search_radius = math.min(search_radius, constants.tile_task_arrival_distance)
            end
            dest = fapi.find_non_colliding_position(surface, "spiderling", target_pos, search_radius, 0.5) or target_pos
        end

        task.approach_position = dest

        spider_data.nav = {
            kind = "task",
            destination = { x = dest.x, y = dest.y },
            task_id = task.id,
            request_id = nil,
            last_request_tick = nil,
            pending_retry = false,
        }
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        spider_data.stuck_since = nil

        set_autopilot_path(spider_entity, { dest })
        request_path(spider_id, spider_data, dest, "task", task.id)
    end
end

--- Clear a spider's task (e.g., if target becomes invalid)
---@param spider_id string
function spider.clear_task(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    -- Clear task assignment tracking
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end

    spider_data.task = nil
    spider_data.status = "deployed_idle"
    clear_navigation(spider_data)

    update_spider_color(spider_data.entity, "deployed_idle")

    -- Resume following anchor
    local spider_entity = spider_data.entity
    if spider_entity and spider_entity.valid then
        clear_autopilot(spider_entity)
        local anchor_entity = anchor_data.entity
        follow_anchor(anchor_entity, spider_entity, spider_id)
    end
end

--- Teleport spider to anchor (when anchor teleports)
---@param spider_id string
function spider.teleport_to_anchor(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return
    end

    local anchor_entity = anchor_data.entity
    if not anchor_entity or not anchor_entity.valid then
        return
    end

    -- Find valid position near anchor
    local surface = anchor_entity.surface
    local spawn_pos = utils.random_position_in_radius(anchor_data.position, 10)
    local valid_pos = fapi.find_non_colliding_position(surface, "spiderling", spawn_pos, 20, 0.5)
        or anchor_data.position

    -- Teleport
    fapi.teleport(spider_entity, valid_pos, surface)

    -- Clear any task
    spider.clear_task(spider_id)
end

--- Make spider jump (when stuck)
---@param spider_id string
function spider.jump(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return
    end
    local anchor_entity = anchor_data.entity

    local destination = spider_data.nav and spider_data.nav.destination or nil
    if destination then
        local stuck_since = spider_data.stuck_since
        if stuck_since and (game.tick - stuck_since) >= constants.stuck_timeout_ticks then
            local stuck_origin = spider_data.stuck_origin
            local moved = stuck_origin and utils.distance(spider_entity.position, stuck_origin) or math.huge
            local dist_to_dest = utils.distance(spider_entity.position, destination)
            if moved <= constants.stuck_teleport_max_move and dist_to_dest <= constants.stuck_teleport_distance then
                local ok = fapi.teleport(spider_entity, destination, spider_entity.surface)
                if not ok then
                    local fallback = fapi.find_non_colliding_position(
                        spider_entity.surface,
                        "spiderling",
                        destination,
                        4,
                        0.5
                    )
                    if fallback then
                        fapi.teleport(spider_entity, fallback, spider_entity.surface)
                    end
                end
                spider_data.stuck_since = nil
                spider_data.stuck_origin = nil
                spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
                spider_data.last_move_tick = game.tick
                return
            end
        end

        local requested = request_path(spider_id, spider_data, destination, "task", spider_data.task and spider_data.task.id, {
            force = true,
        })
        if requested then
            return
        end
    end

    local surface = spider_entity.surface
    local current_pos = spider_entity.position

    local desired_pos = nil
    if destination then
        local dx = destination.x - current_pos.x
        local dy = destination.y - current_pos.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local jump_dist = math.min(constants.jump_distance, dist)
        if dist > 0 and jump_dist > 0 then
            desired_pos = {
                x = current_pos.x + (dx / dist) * jump_dist,
                y = current_pos.y + (dy / dist) * jump_dist,
            }
        end
    end

    if not desired_pos then
        local orientation = spider_entity.orientation or 0
        local angle = orientation * 2 * math.pi
        local jump_dist = constants.jump_distance
        desired_pos = {
            x = current_pos.x + jump_dist * math.sin(angle),
            y = current_pos.y - jump_dist * math.cos(angle),
        }
    end

    local valid_pos = fapi.find_non_colliding_position(surface, "spiderling", desired_pos, constants.jump_distance, 0.5)
    if not valid_pos then
        local search_box = {
            { current_pos.x - constants.jump_distance, current_pos.y - constants.jump_distance },
            { current_pos.x + constants.jump_distance, current_pos.y + constants.jump_distance },
        }
        valid_pos = surface.find_non_colliding_position_in_box("spiderling", search_box, 0.5)
    end

    if valid_pos then
        fapi.teleport(spider_entity, valid_pos)
    end

    if destination then
        set_autopilot_path(spider_entity, { destination })
        spider_data.stuck_since = nil
        return
    end

    spider.clear_task(spider_id)
    follow_anchor(anchor_entity, spider_entity, spider_id)
end

---@param event {id: uint32, path?: PathfinderWaypoint[], try_again_later: boolean}
function spider.handle_path_request_finished(event)
    if not (event and event.id) then
        return
    end

    local requests = storage.path_requests
    local entry = requests and requests[event.id] or nil
    if not entry then
        return
    end
    requests[event.id] = nil

    local spider_id = entry.spider_id
    local spider_data = spider.get(spider_id)
    if not (spider_data and spider_data.nav) then
        return
    end

    local nav = spider_data.nav
    if nav.request_id ~= event.id then
        return
    end

    nav.request_id = nil
    nav.last_path_tick = game.tick

    if entry.task_id and (not spider_data.task or spider_data.task.id ~= entry.task_id) then
        return
    end

    if event.try_again_later then
        nav.pending_retry = true
        nav.retry_after_tick = game.tick + constants.path_retry_delay_ticks
        return
    end

    local path = event.path
    if not (path and path[1]) then
        return
    end

    local waypoints = build_waypoints(path, entry.destination)
    if not (waypoints and waypoints[1]) then
        return
    end

    set_autopilot_path(spider_data.entity, waypoints)
    nav.pending_retry = false
    nav.retry_after_tick = nil
    nav.destination = entry.destination
end

---@param spider_id string
function spider.ensure_navigation(spider_id)
    local spider_data = spider.get(spider_id)
    if not spider_data then
        return
    end

    local nav = spider_data.nav
    if not (nav and nav.destination) then
        return
    end

    if nav.request_id then
        return
    end

    if nav.pending_retry and nav.retry_after_tick and game.tick < nav.retry_after_tick then
        return
    end

    request_path(spider_id, spider_data, nav.destination, nav.kind or "task", nav.task_id)

    local spider_entity = spider_data.entity
    if not (spider_entity and spider_entity.valid) then
        return
    end

    local destinations = spider_entity.autopilot_destinations
    if not spider_entity.autopilot_destination and not (destinations and destinations[1]) then
        set_autopilot_path(spider_entity, { nav.destination })
    end
end

---@param spider_id string
---@param anchor_data table
---@param opts { clear_nav?: boolean }?
function spider.ensure_follow_anchor(spider_id, anchor_data, opts)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders and anchor_data.spiders[spider_id] or nil
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    local anchor_entity = anchor_data.entity
    if not (spider_entity and spider_entity.valid and anchor_entity and anchor_entity.valid) then
        return
    end

    if opts and opts.clear_nav then
        clear_navigation(spider_data)
    end

    if spider_entity.follow_target ~= anchor_entity or (opts and opts.clear_nav) then
        follow_anchor(anchor_entity, spider_entity, spider_id)
    end
end

---@param spider_id string
---@param anchor_data table
function spider.ensure_return_navigation(spider_id, anchor_data)
    if not anchor_data then
        return
    end

    local spider_data = anchor_data.spiders and anchor_data.spiders[spider_id] or nil
    if not spider_data then
        return
    end

    local spider_entity = spider_data.entity
    local anchor_entity = anchor_data.entity
    if not (spider_entity and spider_entity.valid and anchor_entity and anchor_entity.valid) then
        return
    end

    local anchor_pos = anchor_data.position
    local nav = spider_data.nav
    local offset = compute_follow_offset(spider_id)
    local desired = { x = anchor_pos.x + offset.x, y = anchor_pos.y + offset.y }

    local function pick_destination()
        return fapi.find_non_colliding_position(anchor_entity.surface, "spiderling", desired, 8, 0.5) or anchor_pos
    end

    if nav and nav.kind == "return" then
        local prev = nav.anchor_position
        local moved = prev and utils.distance(prev, anchor_pos) or math.huge
        if moved >= constants.return_destination_update_distance then
            nav.destination = pick_destination()
            nav.anchor_position = { x = anchor_pos.x, y = anchor_pos.y }
            nav.pending_retry = false
            nav.retry_after_tick = nil
            nav.request_id = nil
            set_autopilot_path(spider_entity, { nav.destination })
            request_path(spider_id, spider_data, nav.destination, "return", nil)
        end
    else
        nav = {
            kind = "return",
            destination = pick_destination(),
            anchor_position = { x = anchor_pos.x, y = anchor_pos.y },
            request_id = nil,
            last_request_tick = nil,
            pending_retry = false,
        }
        spider_data.nav = nav
        spider_entity.follow_target = nil
        set_autopilot_path(spider_entity, { nav.destination })
        request_path(spider_id, spider_data, nav.destination, "return", nil)
    end
end

--- Handle spider death (drop as item)
---@param spider_entity LuaEntity
function spider.on_death(spider_entity)
    if not spider_entity or not spider_entity.valid then
        return
    end

    -- Drop item on ground (marked for deconstruction).
    -- Entity/task tracking is cleaned up by the on_object_destroyed
    -- handler in control.lua.
    local surface = spider_entity.surface
    local position = spider_entity.position
    local force = spider_entity.force

    local item_on_ground = nil
    do
        local created, err = utils.spill_item_stack(surface, position, { name = "spiderling", count = 1 }, {
            allow_belts = false,
            enable_looted = true,
            force = force,
            max_radius = 0,
            use_start_position_on_failure = true,
        })
        if created and created[1] and created[1].valid then
            item_on_ground = created[1]
        elseif err then
            utils.log("spill_item_stack (spider death) failed: " .. tostring(err))
        end
    end

    if not (item_on_ground and item_on_ground.valid) then
        item_on_ground = utils.create_item_on_ground(surface, position, { name = "spiderling", count = 1 }, {
            force = force,
            raise_built = false,
            create_build_effect_smoke = false,
            spawn_decorations = false,
        })
    end

    if item_on_ground and item_on_ground.valid then
        pcall(function()
            item_on_ground.to_be_looted = true
        end)
        pcall(function()
            item_on_ground.order_deconstruction(force)
        end)
    end

    utils.log("Spider died, dropped as item")
end

--- Get spider data by ID
---@param spider_id string
---@return table? spider_data
function spider.get(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then
        return nil
    end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then
        return nil
    end

    return anchor_data.spiders[spider_id]
end

--- Check if spider has arrived at task location
---@param spider_data table
---@return boolean
function spider.has_arrived(spider_data)
    if not spider_data.task then
        return false
    end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return false
    end

    local target = spider_data.task.entity or spider_data.task.tile
    if not target or not target.valid then
        return false
    end

    -- Prefer the planned destination, but also accept proximity to the task target.
    -- In practice spiders can end up close to the target even if the autopilot destination
    -- isn't cleared (or was adjusted by pathing/collisions).
    local threshold = arrival_distance_for_behavior(spider_data.task.behavior_name)
    if threshold < 1.0 then
        threshold = 1.0
    end

    local dest = spider_data.nav and spider_data.nav.destination or spider_data.task.approach_position
    local dist_to_dest = dest and utils.distance(spider_entity.position, dest) or math.huge
    local dist_to_target = utils.distance(spider_entity.position, target.position)

    local dist_to_queue = math.huge
    local destinations = spider_entity.autopilot_destinations
    if destinations and #destinations > 0 then
        local last_dest = destinations[#destinations]
        local dest_pos = last_dest and (last_dest.position or last_dest) or nil
        if dest_pos then
            dist_to_queue = utils.distance(spider_entity.position, dest_pos)
        end
    end

    return math.min(dist_to_dest, dist_to_target, dist_to_queue) < threshold
end

--- Check if spider is stuck (no speed)
---@param spider_data table
---@return boolean
function spider.is_stuck(spider_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return false
    end

    if spider_data.status ~= "moving_to_task" then
        spider_data.stuck_since = nil
        return false
    end

    local speed = spider_entity.speed or 0
    local target = spider_data.task and (spider_data.task.entity or spider_data.task.tile) or nil
    local arrive_pos = (spider_data.nav and spider_data.nav.destination)
        or (spider_data.task and spider_data.task.approach_position)
        or (target and target.valid and target.position)
        or nil
    local dist = arrive_pos and utils.distance(spider_entity.position, arrive_pos) or math.huge

    local threshold = arrival_distance_for_behavior(spider_data.task and spider_data.task.behavior_name or nil)
    if threshold < 1.0 then
        threshold = 1.0
    end

    if dist <= threshold then
        spider_data.stuck_since = nil
        spider_data.stuck_origin = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    local last_pos = spider_data.last_position
    if not last_pos then
        spider_data.stuck_since = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    local moved = utils.distance(spider_entity.position, last_pos)

    if moved >= constants.stuck_move_threshold or speed > constants.stuck_speed_threshold then
        spider_data.stuck_since = nil
        spider_data.stuck_origin = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    if not spider_data.stuck_since then
        spider_data.stuck_since = game.tick
        spider_data.stuck_origin = { x = spider_entity.position.x, y = spider_entity.position.y }
    end
    return (game.tick - spider_data.stuck_since) >= constants.stuck_timeout_ticks
end

---@param spider_data table
---@param destination MapPosition?
---@param threshold number
---@return boolean
local function is_stuck_toward(spider_data, destination, threshold)
    local spider_entity = spider_data.entity
    if not (spider_entity and spider_entity.valid) then
        return false
    end

    if not destination then
        spider_data.stuck_since = nil
        return false
    end

    local dist = utils.distance(spider_entity.position, destination)
    if dist <= threshold then
        spider_data.stuck_since = nil
        spider_data.stuck_origin = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    local last_pos = spider_data.last_position
    if not last_pos then
        spider_data.stuck_since = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    local moved = utils.distance(spider_entity.position, last_pos)
    local speed = spider_entity.speed or 0
    if moved >= constants.stuck_move_threshold or speed > constants.stuck_speed_threshold then
        spider_data.stuck_since = nil
        spider_data.stuck_origin = nil
        spider_data.last_position = { x = spider_entity.position.x, y = spider_entity.position.y }
        spider_data.last_move_tick = game.tick
        return false
    end

    if not spider_data.stuck_since then
        spider_data.stuck_since = game.tick
        spider_data.stuck_origin = { x = spider_entity.position.x, y = spider_entity.position.y }
    end
    return (game.tick - spider_data.stuck_since) >= constants.stuck_timeout_ticks
end

---@param spider_data table
---@return boolean
function spider.is_return_stuck(spider_data)
    if not spider_data then
        return false
    end

    local nav = spider_data.nav
    if not (nav and nav.kind == "return") then
        return false
    end

    local threshold = math.max(constants.near_anchor_threshold, constants.task_arrival_distance)
    return is_stuck_toward(spider_data, nav.destination, threshold)
end

--- Check if spider is near its anchor
---@param spider_data table
---@param anchor_data table
---@return boolean
function spider.is_near_anchor(spider_data, anchor_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return false
    end

    local dist = utils.distance(spider_entity.position, anchor_data.position)
    return dist < constants.near_anchor_threshold
end

--- Check if spider's task is still valid
---@param spider_data table
---@return boolean
function spider.is_task_valid(spider_data)
    if not spider_data.task then
        return false
    end

    local target = spider_data.task.entity or spider_data.task.tile
    return target and target.valid
end

--- Get personal work area for a spider
---@param spider_data table
---@return BoundingBox
function spider.get_personal_area(spider_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then
        return { { 0, 0 }, { 0, 0 } }
    end

    return utils.area_around(spider_entity.position, constants.spider_personal_radius)
end

return spider
