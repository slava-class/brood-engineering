-- scripts/behaviors/unblock_deconstruct.lua
-- Deconstruct entities that are blocking ghost placement
-- Higher priority than regular deconstruction

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local deconstruct = require("scripts/behaviors/deconstruct_entity")

local behavior = {
    name = "unblock_deconstruct",
    priority = constants.priorities.unblock_deconstruct,
}

--- Check if an entity is blocking any ghost
---@param entity LuaEntity
---@param force LuaForce[]
---@return boolean
local function is_blocking_ghost(entity, force)
    if not entity or not entity.valid then
        return false
    end

    local surface = entity.surface
    local box = entity.bounding_box

    -- Find ghosts in the same area
    local ghosts = surface.find_entities_filtered({
        area = box,
        force = force,
        type = "entity-ghost",
    })

    -- Check if any ghost overlaps with this entity
    for _, ghost in pairs(ghosts) do
        if ghost.valid then
            local ghost_box = ghost.bounding_box
            -- Simple bounding box overlap check
            if
                box.left_top.x < ghost_box.right_bottom.x
                and box.right_bottom.x > ghost_box.left_top.x
                and box.left_top.y < ghost_box.right_bottom.y
                and box.right_bottom.y > ghost_box.left_top.y
            then
                return true
            end
        end
    end

    return false
end

--- Find entities marked for deconstruction that are blocking ghosts
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    local decon_entities = surface.find_entities_filtered({
        area = area,
        force = force,
        to_be_deconstructed = true,
    })

    local blocking = {}
    for _, entity in pairs(decon_entities) do
        if is_blocking_ghost(entity, force) then
            blocking[#blocking + 1] = entity
        end
    end

    return blocking
end

--- Check if we can deconstruct this entity
---@param entity LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(entity, inventory)
    return deconstruct.can_execute(entity, inventory)
end

--- Deconstruct the entity
---@param spider_data table
---@param entity LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, entity, inventory, anchor_data)
    -- Delegate to regular deconstruct behavior
    return deconstruct.execute(spider_data, entity, inventory, anchor_data)
end

--- Get unique ID for an entity
---@param entity LuaEntity
---@return string
function behavior.get_task_id(entity)
    return "unblock_" .. utils.get_entity_id(entity)
end

return behavior
