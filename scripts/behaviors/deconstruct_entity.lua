-- scripts/behaviors/deconstruct_entity.lua
-- Deconstruct marked entities behavior

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "deconstruct_entity",
    priority = constants.priorities.deconstruct_entity,
}

--- Find entities marked for deconstruction
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    return surface.find_entities_filtered({
        area = area,
        force = force,
        to_be_deconstructed = true,
    })
end

--- Get items that would be returned when mining an entity
---@param entity LuaEntity
---@return ItemStackDefinition?
local function get_mine_result(entity)
    -- Handle item-on-ground specially
    if entity.type == "item-entity" then
        local stack = entity.stack
        if stack and stack.valid_for_read then
            return { name = stack.name, count = stack.count, quality = stack.quality }
        end
        return nil
    end
    
    -- Regular entity
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

--- Check if we can deconstruct this entity (have space for results)
---@param entity LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(entity, inventory)
    if not entity or not entity.valid then return false end
    if not entity.to_be_deconstructed() then return false end
    if not inventory or not inventory.valid then return false end
    
    -- Cliffs need explosives
    if entity.type == "cliff" then
        -- Check for cliff explosives of any quality
        for name, quality in pairs(prototypes.quality) do
            local item = { name = "cliff-explosives", quality = quality }
            if utils.inventory_has_item(inventory, item) then
                return true
            end
        end
        return false
    end
    
    -- Check if we have space for the result
    local result = get_mine_result(entity)
    if result then
        return utils.inventory_has_space(inventory, result)
    end
    
    -- No result, can always deconstruct
    return true
end

--- Deconstruct the entity
---@param spider_data table
---@param entity LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, entity, inventory, anchor_data)
    if not entity or not entity.valid then return false end
    if not entity.to_be_deconstructed() then return false end
    if not inventory or not inventory.valid then return false end
    
    -- Handle cliffs specially
    if entity.type == "cliff" then
        -- Find and consume cliff explosives
        for name, quality in pairs(prototypes.quality) do
            local item = { name = "cliff-explosives", quality = quality }
            if utils.inventory_has_item(inventory, item) then
                inventory.remove({ name = "cliff-explosives", count = 1, quality = name })
                entity.destroy({ raise_destroy = true })
                return true
            end
        end
        return false
    end
    
    -- Handle item-on-ground (picking up items)
    if entity.type == "item-entity" then
        local stack = entity.stack
        if stack and stack.valid_for_read then
            local inserted = inventory.insert(stack)
            if inserted > 0 then
                if inserted >= stack.count then
                    entity.destroy({ raise_destroy = true })
                else
                    stack.count = stack.count - inserted
                end
                return true
            end
        end
        return false
    end
    
    -- Regular entity - get contents first
    local entity_contents = {}
    for i = 1, 11 do
        local inv = entity.get_inventory(i)
        if inv and inv.valid then
            for _, item in pairs(inv.get_contents()) do
                entity_contents[#entity_contents + 1] = item
            end
        end
    end
    
    -- Handle belts
    local belt_types = {
        ["transport-belt"] = true,
        ["underground-belt"] = true,
        ["splitter"] = true,
        ["loader"] = true,
        ["loader-1x1"] = true,
        ["linked-belt"] = true,
        ["lane-splitter"] = true,
    }
    
    if belt_types[entity.type] then
        for i = 1, entity.get_max_transport_line_index() do
            local line = entity.get_transport_line(i)
            if line and line.valid then
                for _, item in pairs(line.get_contents()) do
                    entity_contents[#entity_contents + 1] = item
                end
            end
        end
    end
    
    -- Mine the entity
    local result = get_mine_result(entity)
    
    -- Destroy the entity
    entity.destroy({ raise_destroy = true })
    
    -- Insert mined item
    if result then
        inventory.insert(result)
    end
    
    -- Insert contents
    for _, item in pairs(entity_contents) do
        inventory.insert(item)
    end
    
    return true
end

--- Get unique ID for an entity
---@param entity LuaEntity
---@return string
function behavior.get_task_id(entity)
    return "deconstruct_entity_" .. utils.get_entity_id(entity)
end

return behavior
