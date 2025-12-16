-- scripts/behaviors/upgrade.lua
-- Upgrade entities marked for upgrade

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "upgrade",
    priority = constants.priorities.upgrade,
}

--- Find entities marked for upgrade
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    return surface.find_entities_filtered({
        area = area,
        force = force,
        to_be_upgraded = true,
    })
end

--- Check if we can upgrade this entity
---@param entity LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(entity, inventory)
    if not entity or not entity.valid then
        return false
    end
    if not entity.to_be_upgraded() then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    -- Get upgrade target
    local target = entity.get_upgrade_target()
    if not target then
        return false
    end

    -- Get item needed for target
    local items = target.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    local quality = entity.get_upgrade_quality() or entity.quality
    local item_with_quality = { name = item_name, quality = quality }

    -- Check if we have the item
    if not utils.inventory_has_item(inventory, item_with_quality) then
        return false
    end

    -- Check if we have space for the old item
    local old_items = entity.prototype.items_to_place_this
    if old_items and old_items[1] then
        local old_item = {
            name = old_items[1].name,
            count = old_items[1].count or 1,
            quality = entity.quality and entity.quality.name or "normal",
        }
        if not utils.inventory_has_space(inventory, old_item) then
            return false
        end
    end

    return true
end

--- Upgrade the entity
---@param spider_data table
---@param entity LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, entity, inventory, anchor_data)
    if not entity or not entity.valid then
        return false
    end
    if not entity.to_be_upgraded() then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    local target = entity.get_upgrade_target()
    if not target then
        return false
    end

    local target_quality = entity.get_upgrade_quality() or entity.quality

    -- Get item needed
    local items = target.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    local item_count = items[1].count or 1
    local item_with_quality = { name = item_name, quality = target_quality }

    if not utils.inventory_has_item(inventory, item_with_quality) then
        return false
    end

    -- Get old item info
    local old_items = entity.prototype.items_to_place_this
    local old_item_name = old_items and old_items[1] and old_items[1].name
    local old_item_count = old_items and old_items[1] and (old_items[1].count or 1) or 1
    local old_quality = entity.quality and entity.quality.name or "normal"

    -- Store entity data we need to preserve
    local surface = entity.surface
    local position = entity.position
    local direction = entity.direction
    local force = entity.force

    -- Cancel upgrade order first
    entity.cancel_upgrade(force)

    -- Perform the upgrade
    local new_entity = surface.create_entity({
        name = target.name,
        position = position,
        direction = direction,
        force = force,
        quality = target_quality,
        fast_replace = true,
        player = nil,
        spill = false,
        raise_built = true,
        create_build_effect_smoke = false,
    })

    if new_entity then
        -- Remove new item from inventory
        inventory.remove({ name = item_name, count = item_count, quality = target_quality.name })

        -- Return old item to inventory
        if old_item_name then
            inventory.insert({ name = old_item_name, count = old_item_count, quality = old_quality })
        end

        return true
    end

    return false
end

--- Get unique ID for an entity
---@param entity LuaEntity
---@return string
function behavior.get_task_id(entity)
    return "upgrade_" .. utils.get_entity_id(entity)
end

return behavior
