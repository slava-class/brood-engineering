-- scripts/spider.lua
-- Spider lifecycle and state management for Brood Engineering

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local anchor = require("scripts/anchor")

local spider = {}

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
        if inventory then
            inventory.insert({ name = "spiderling", count = 1 })
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

        -- Find non-colliding position near target
        local target_pos = target.position
        local surface = spider_entity.surface
        local dest = surface.find_non_colliding_position(
            "spiderling",
            target_pos,
            5,
            0.5
        ) or target_pos

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

    local surface = spider_entity.surface
    local current_pos = spider_entity.position

    -- Jump in the direction spider is facing
    local orientation = spider_entity.orientation or 0
    local angle = orientation * 2 * math.pi
    local jump_dist = constants.jump_distance

    local target_pos = {
        x = current_pos.x + jump_dist * math.sin(angle),
        y = current_pos.y - jump_dist * math.cos(angle),
    }

    local valid_pos = surface.find_non_colliding_position(
        "spiderling",
        target_pos,
        jump_dist * 2,
        0.5
    )

    if valid_pos then
        spider_entity.teleport(valid_pos)
    end

    -- Clear task if we were stuck on it
    spider.clear_task(spider_id)
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

    local dist = utils.distance(spider_entity.position, target.position)
    return dist < constants.task_arrival_distance
end

--- Check if spider is stuck (no speed)
---@param spider_data table
---@return boolean
function spider.is_stuck(spider_data)
    local spider_entity = spider_data.entity
    if not spider_entity or not spider_entity.valid then return false end

    return spider_entity.speed == 0 and spider_data.status == "moving_to_task"
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
