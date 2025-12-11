-- scripts/behaviors/build_entity.lua
-- Build entity ghosts behavior

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "build_entity",
    priority = constants.priorities.build_entity,
}

--- Find entity ghosts in area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    return surface.find_entities_filtered({
        area = area,
        force = force,
        type = "entity-ghost",
    })
end

--- Check if we can build this ghost
---@param ghost LuaEntity
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(ghost, inventory)
    if not ghost or not ghost.valid then return false end
    if not inventory or not inventory.valid then return false end

    -- Get item needed to build
    local items = ghost.ghost_prototype.items_to_place_this
    if not items or not items[1] then return false end

    local item_name = items[1].name
    local quality = ghost.quality
    local item_with_quality = { name = item_name, quality = quality }

    return utils.inventory_has_item(inventory, item_with_quality)
end

--- Build the ghost
---@param spider_data table
---@param ghost LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, ghost, inventory, anchor_data)
    if not ghost or not ghost.valid then return false end
    if not inventory or not inventory.valid then return false end

    -- Get item needed
    local items = ghost.ghost_prototype.items_to_place_this
    if not items or not items[1] then return false end

    local item_name = items[1].name
    local item_count = items[1].count or 1
    local quality = ghost.quality
    local item_with_quality = { name = item_name, quality = quality }

    -- Double-check inventory
    if not utils.inventory_has_item(inventory, item_with_quality) then
        return false
    end

    -- Revive the ghost
    local collisions, revived_entity, proxy = ghost.revive({
        return_item_request_proxy = false,
        raise_revive = true,
    })

    if revived_entity then
        -- Remove item from inventory
        inventory.remove({ name = item_name, count = item_count, quality = quality.name })

        -- Optional: Show item projectile
        if settings.global["brood-show-item-projectiles"] and
           settings.global["brood-show-item-projectiles"].value then
            local spider_entity = spider_data.entity
            local anchor_entity = anchor_data.entity
            if spider_entity and spider_entity.valid and anchor_entity and anchor_entity.valid then
                -- Create visual projectile from anchor to spider
                local projectile_name = item_name .. "-spiderling-projectile"
                if prototypes.entity[projectile_name] then
                    anchor_entity.surface.create_entity({
                        name = projectile_name,
                        position = anchor_entity.position,
                        target = spider_entity,
                        force = anchor_entity.force,
                        speed = 0.3,
                    })
                end
            end
        end

        return true
    end

    return false
end

--- Get unique ID for a ghost
---@param ghost LuaEntity
---@return string
function behavior.get_task_id(ghost)
    return "build_entity_" .. utils.get_entity_id(ghost)
end

return behavior
