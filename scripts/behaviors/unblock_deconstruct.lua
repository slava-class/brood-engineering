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

--- Get items that would be returned when mining an entity
---@param entity LuaEntity
---@return ItemStackDefinition?
local function get_mine_result(entity)
    if entity.type == "item-entity" then
        local stack = entity.stack
        if stack and stack.valid_for_read then
            return { name = stack.name, count = stack.count, quality = stack.quality }
        end
        return nil
    end

    local prototype = entity.prototype
    local mineable = prototype.mineable_properties

    if not mineable or not mineable.products then
        return nil
    end

    for _, product in pairs(mineable.products) do
        if product.type == "item" then
            local amount = product.amount or product.amount_max or 1
            return {
                name = product.name,
                count = amount,
                quality = entity.quality and entity.quality.name or "normal",
            }
        end
    end

    return nil
end

--- Check if we can deconstruct this entity
---@param entity LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(entity, inventory)
    if not entity or not entity.valid then
        return false
    end
    if not entity.to_be_deconstructed() then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    -- Cliffs need explosives
    if entity.type == "cliff" then
        -- `prototypes.quality` is keyed by quality name; pass the key (QualityID), not the prototype table.
        -- Docs: `mise run docs -- open runtime/classes/LuaPrototypes.md#quality`
        for quality_name, _ in pairs(prototypes.quality) do
            local item = { name = "cliff-explosives", quality = quality_name }
            if utils.inventory_has_item(inventory, item) then
                return true
            end
        end
        return false
    end

    -- Check space for result
    local result = get_mine_result(entity)
    if result then
        return utils.inventory_has_space(inventory, result)
    end

    return true
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
