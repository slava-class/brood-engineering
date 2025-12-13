-- scripts/spider.lua
-- Spider lifecycle and state management for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local anchor = require("scripts/anchor")

local spider = {}

---@param spider_entity LuaEntity
---@param ghost LuaEntity
---@return MapPosition? destination
local function get_build_entity_approach_position(spider_entity, ghost)
    if not (spider_entity and spider_entity.valid) then return nil end
    if not (ghost and ghost.valid and ghost.type == "entity-ghost") then return nil end

    local surface = spider_entity.surface
    if not (surface and (surface.valid == nil or surface.valid)) then return nil end

    local box = ghost.bounding_box
    if not (box and box.left_top and box.right_bottom) then return nil end

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
        local pos = surface.find_non_colliding_position("spiderling", candidate, 10, 0.5)
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
    if not spider_entity or not spider_entity.valid then return end

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
    if not anchor_data then return nil end

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
    if not anchor_entity or not anchor_entity.valid then return nil end

    local surface = anchor_entity.surface
    local spawn_pos = utils.random_position_in_radius(anchor_data.position, 5)
    local valid_pos = surface.find_non_colliding_position(
        "spiderling",
        spawn_pos,
        10,
        0.5
    )

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
        entity = spider_entity,
        entity_id = entity_id,
        anchor_id = anchor_id,
        status = "deployed_idle",
        task = nil,
        idle_since = nil,
    }

    -- Store in anchor and global tracking
    anchor_data.spiders[spider_id] = spider_data
    storage.spider_to_anchor[spider_id] = anchor_id
    storage.entity_to_spider[entity_id] = spider_id

    -- Set initial color
    update_spider_color(spider_entity, "deployed_idle")

    -- Set follow target to anchor
    spider_entity.follow_target = anchor_entity

    utils.log("Deployed spider " .. spider_id .. " for anchor " .. anchor_id)
    return spider_id
end

--- Recall a spider to inventory
---@param spider_id string
function spider.recall(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    local spider_entity = spider_data.entity

    -- Clear task assignment
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end

    -- Return item to inventory if entity is valid
    if spider_entity and spider_entity.valid then
        local inventory = anchor.get_inventory(anchor_data)
        local anchor_entity = anchor_data.entity
	        local spill_surface = spider_entity.surface or (anchor_entity and anchor_entity.valid and anchor_entity.surface) or nil
	        local spill_position = spider_entity.position or (anchor_entity and anchor_entity.valid and anchor_entity.position) or nil
	        local spill_force = (anchor_entity and anchor_entity.valid and anchor_entity.force) or spider_entity.force

	        local function spill(stack)
	            if not (spill_surface and spill_position and stack) then return end
	            local safe_stack = { name = stack.name, count = stack.count }
	            if stack.quality and stack.quality ~= "normal" then
	                safe_stack.quality = stack.quality
	            end
	            local force_id = (type(spill_force) == "table" and spill_force.name) or spill_force

	            local ok, created_or_err = pcall(spill_surface.spill_item_stack, {
	                position = spill_position,
	                stack = safe_stack,
	                enable_looted = true,
	                allow_belts = false,
	                max_radius = 0,
	                use_start_position_on_failure = true,
	                force = force_id,
	            })

	            local created = ok and created_or_err or nil
	            if created and #created > 0 then return end

	            if not ok then
	                utils.log("spill_item_stack failed: " .. tostring(created_or_err))
	            end

	            local ok2, created2_or_err = pcall(spill_surface.spill_item_stack, {
	                position = spill_position,
	                stack = safe_stack,
	                max_radius = 0,
	                use_start_position_on_failure = true,
	            })
	            local created2 = ok2 and created2_or_err or nil
	            if created2 and #created2 > 0 then return end

	            if not ok2 then
	                utils.log("spill_item_stack fallback failed: " .. tostring(created2_or_err))
	            end

	            -- Final fallback: spawn the item directly (used in spider.on_death too).
	            local drop_position = spill_position
	            pcall(function()
	                local pos = spill_surface.find_non_colliding_position("item-on-ground", spill_position, 10, 0.5)
	                if pos then
	                    drop_position = pos
	                end
	            end)

	            local item_on_ground = spill_surface.create_entity({
	                name = "item-on-ground",
	                position = drop_position,
	                force = force_id,
	                stack = safe_stack,
	            })
	            if item_on_ground and item_on_ground.valid then
	                item_on_ground.to_be_looted = true
	                if item_on_ground.order_deconstruction then
	                    pcall(item_on_ground.order_deconstruction, item_on_ground, force_id)
	                end
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

	            local returned = inventory.insert({ name = "spiderling", count = 1 })
	            if (returned or 0) < 1 then
	                spill({ name = "spiderling", count = 1 })
	            end
	        else
	            -- No valid anchor inventory; ensure the spiderling item isn't lost.
	            spill({ name = "spiderling", count = 1 })
	        end
	        spider_entity.destroy({ raise_destroy = false })
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
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    spider_data.status = "executing"
    update_spider_color(spider_data.entity, "executing")
end

--- Complete current task and return to idle
---@param spider_id string
function spider.complete_task(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    -- Clear task assignment tracking
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end

	    spider_data.task = nil
	    spider_data.status = "deployed_idle"
	    spider_data.idle_since = nil

	    update_spider_color(spider_data.entity, "deployed_idle")

	    -- Set follow target back to anchor
	    local spider_entity = spider_data.entity
	    if spider_entity and spider_entity.valid then
	        -- Ensure any leftover autopilot destinations are cleared so the spider
	        -- truly returns to idle/following state.
	        pcall(function()
	            if spider_entity.clear_autopilot_destinations then
	                spider_entity.clear_autopilot_destinations()
	            end
	        end)
	        pcall(function()
	            local destinations = spider_entity.autopilot_destinations
	            if destinations then
	                for i = #destinations, 1, -1 do
	                    spider_entity.remove_autopilot_destination(i)
	                end
	            end
	        end)
	        pcall(function()
	            spider_entity.autopilot_destinations = {}
	        end)
	        spider_entity.autopilot_destination = nil

	        local anchor_entity = anchor_data.entity
	        if anchor_entity and anchor_entity.valid then
	            spider_entity.follow_target = anchor_entity
	        end
	    end
	end

--- Assign a task to a spider
---@param spider_id string
---@param task table
function spider.assign_task(spider_id, task)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return end

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
        if task.behavior_name == "build_entity" and target.object_name == "LuaEntity" and target.type == "entity-ghost" then
            dest = get_build_entity_approach_position(spider_entity, target)
        end

        -- Default: find a nearby non-colliding position close to the target.
        if not dest then
            dest = surface.find_non_colliding_position(
                "spiderling",
                target_pos,
                5,
                0.5
            ) or target_pos
        end

        task.approach_position = dest

        spider_entity.autopilot_destination = dest
    end
end

--- Clear a spider's task (e.g., if target becomes invalid)
---@param spider_id string
function spider.clear_task(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    -- Clear task assignment tracking
    if spider_data.task and spider_data.task.id then
        storage.assigned_tasks[spider_data.task.id] = nil
    end

    spider_data.task = nil
    spider_data.status = "deployed_idle"

    update_spider_color(spider_data.entity, "deployed_idle")

    -- Resume following anchor
    local spider_entity = spider_data.entity
    if spider_entity and spider_entity.valid then
        -- Clear any queued autopilot destinations as well as the current one.
        -- Some LuaEntity keys are not safe to probe directly; use pcall.
        pcall(function()
            if spider_entity.clear_autopilot_destinations then
                spider_entity.clear_autopilot_destinations()
            end
        end)
        pcall(function()
            local destinations = spider_entity.autopilot_destinations
            if destinations then
                for i = #destinations, 1, -1 do
                    spider_entity.remove_autopilot_destination(i)
                end
            end
        end)
        pcall(function()
            spider_entity.autopilot_destinations = {}
        end)
        spider_entity.autopilot_destination = nil
        local anchor_entity = anchor_data.entity
        if anchor_entity and anchor_entity.valid then
            spider_entity.follow_target = anchor_entity
        end
    end
end

--- Teleport spider to anchor (when anchor teleports)
---@param spider_id string
function spider.teleport_to_anchor(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return end

    local anchor_entity = anchor_data.entity
    if not anchor_entity or not anchor_entity.valid then return end

    -- Find valid position near anchor
    local surface = anchor_entity.surface
    local spawn_pos = utils.random_position_in_radius(anchor_data.position, 10)
    local valid_pos = surface.find_non_colliding_position(
        "spiderling",
        spawn_pos,
        20,
        0.5
    ) or anchor_data.position

    -- Teleport
    spider_entity.teleport(valid_pos, surface)

    -- Clear any task
    spider.clear_task(spider_id)

    -- Update follow target
    spider_entity.follow_target = anchor_entity
end

	--- Make spider jump (when stuck)
	---@param spider_id string
	function spider.jump(spider_id)
	    local anchor_id = storage.spider_to_anchor[spider_id]
	    if not anchor_id then return end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return end

    local spider_data = anchor_data.spiders[spider_id]
    if not spider_data then return end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return end
    local anchor_entity = anchor_data.entity

	    local surface = spider_entity.surface
	    local current_pos = spider_entity.position

	    -- Prefer jumping toward the current task to guarantee progress.
	    local target = spider_data.task and (spider_data.task.entity or spider_data.task.tile) or nil
	    if target and target.valid then
	        local tp = target.position
	        local dx = tp.x - current_pos.x
	        local dy = tp.y - current_pos.y
	        local dist = math.sqrt(dx * dx + dy * dy)
	        local jump_dist = math.min(constants.jump_distance, dist)

	        if dist > 0 and jump_dist > 0 then
	            local desired_pos = {
	                x = current_pos.x + (dx / dist) * jump_dist,
	                y = current_pos.y + (dy / dist) * jump_dist,
	            }
	            local valid_pos = surface.find_non_colliding_position(
	                "spiderling",
	                desired_pos,
	                constants.jump_distance * 2,
	                0.5
	            )
	            if valid_pos then
	                spider_entity.teleport(valid_pos)
	            end
	        end

	        -- Re-path to current task after the hop.
	        spider_entity.autopilot_destination = surface.find_non_colliding_position(
	            "spiderling",
	            tp,
	            5,
	            0.5
	        ) or tp
	        spider_data.stuck_since = nil
	        return
	    end

	    -- No valid task; jump in facing direction as a fallback.
	    local orientation = spider_entity.orientation or 0
	    local angle = orientation * 2 * math.pi
	    local jump_dist = constants.jump_distance
	    local fallback_pos = {
	        x = current_pos.x + jump_dist * math.sin(angle),
	        y = current_pos.y - jump_dist * math.cos(angle),
	    }
	    local valid_pos = surface.find_non_colliding_position(
	        "spiderling",
	        fallback_pos,
	        jump_dist * 2,
	        0.5
	    )
	    if valid_pos then
	        spider_entity.teleport(valid_pos)
	    end

	    spider.clear_task(spider_id)
	    if anchor_entity and anchor_entity.valid then
	        spider_entity.follow_target = anchor_entity
	    end
	end

--- Handle spider death (drop as item)
---@param spider_entity LuaEntity
function spider.on_death(spider_entity)
    if not spider_entity or not spider_entity.valid then return end

    -- Drop item on ground (marked for deconstruction).
    -- Entity/task tracking is cleaned up by the on_object_destroyed
    -- handler in control.lua.
    local surface = spider_entity.surface
    local position = spider_entity.position
    local force = spider_entity.force

	    local item_on_ground = surface.create_entity({
	        name = "item-on-ground",
	        position = position,
	        force = force,
	        stack = { name = "spiderling", count = 1 },
	    })

    if item_on_ground and item_on_ground.valid then
        item_on_ground.order_deconstruction(force)
    end

    utils.log("Spider died, dropped as item")
end

--- Get spider data by ID
---@param spider_id string
---@return table? spider_data
function spider.get(spider_id)
    local anchor_id = storage.spider_to_anchor[spider_id]
    if not anchor_id then return nil end

    local anchor_data = anchor.get(anchor_id)
    if not anchor_data then return nil end

    return anchor_data.spiders[spider_id]
end

--- Check if spider has arrived at task location
---@param spider_data table
---@return boolean
function spider.has_arrived(spider_data)
    if not spider_data.task then return false end

    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return false end

    local target = spider_data.task.entity or spider_data.task.tile
    if not target or not target.valid then return false end

    local arrive_pos = spider_data.task.approach_position or target.position
    local dist = utils.distance(spider_entity.position, arrive_pos)
    return dist < constants.task_arrival_distance
end

--- Check if spider is stuck (no speed)
---@param spider_data table
---@return boolean
function spider.is_stuck(spider_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return false end

    if spider_data.status ~= "moving_to_task" then
        spider_data.stuck_since = nil
        return false
    end

    local speed = spider_entity.speed or 0
    local target = spider_data.task and (spider_data.task.entity or spider_data.task.tile) or nil
    local arrive_pos = spider_data.task and spider_data.task.approach_position or (target and target.valid and target.position) or nil
    local dist = arrive_pos and utils.distance(spider_entity.position, arrive_pos) or math.huge

    -- Reset timer if moving or close enough to execute
    if speed > constants.stuck_speed_threshold or dist <= constants.task_arrival_distance then
        spider_data.stuck_since = nil
        return false
    end

    spider_data.stuck_since = spider_data.stuck_since or game.tick
    return (game.tick - spider_data.stuck_since) >= constants.stuck_timeout_ticks
end

--- Check if spider is near its anchor
---@param spider_data table
---@param anchor_data table
---@return boolean
function spider.is_near_anchor(spider_data, anchor_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return false end

    local dist = utils.distance(spider_entity.position, anchor_data.position)
    return dist < constants.near_anchor_threshold
end

--- Check if spider's task is still valid
---@param spider_data table
---@return boolean
function spider.is_task_valid(spider_data)
    if not spider_data.task then return false end

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
