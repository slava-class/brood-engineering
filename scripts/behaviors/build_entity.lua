-- scripts/behaviors/build_entity.lua
-- Build entity ghosts behavior

local constants = require("scripts/constants")
local utils = require("scripts/utils")
local fapi = require("scripts/fapi")

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
    if not ghost or not ghost.valid then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    -- Get item needed to build
    local items = ghost.ghost_prototype.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    local quality = ghost.quality
    local quality_name = type(quality) == "table" and quality.name or quality or "normal"
    local item_with_quality = { name = item_name, quality = quality_name }

    return utils.inventory_has_item(inventory, item_with_quality)
end

---@param spider_entity LuaEntity
---@param ghost LuaEntity
---@param padding number
---@return MapPosition? position
local function find_reposition(spider_entity, ghost, padding)
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

    local mid_x = (box.left_top.x + box.right_bottom.x) / 2
    local mid_y = (box.left_top.y + box.right_bottom.y) / 2

    local candidates = {
        { x = box.left_top.x - padding, y = mid_y },
        { x = box.right_bottom.x + padding, y = mid_y },
        { x = mid_x, y = box.left_top.y - padding },
        { x = mid_x, y = box.right_bottom.y + padding },
        { x = box.left_top.x - padding, y = box.left_top.y - padding },
        { x = box.right_bottom.x + padding, y = box.left_top.y - padding },
        { x = box.left_top.x - padding, y = box.right_bottom.y + padding },
        { x = box.right_bottom.x + padding, y = box.right_bottom.y + padding },
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

---@param ghost LuaEntity
---@param options table
---@return boolean ok
---@return table? collided_items
---@return LuaEntity? revived_entity
---@return LuaEntity? proxy
local function revive_ghost(ghost, options)
    -- Docs: `mise run docs -- open runtime/classes/LuaEntity.md#revive`
    -- Note: `LuaEntity.revive` uses the named-table calling convention.
    local revive_opts = options or nil
    local ok, collided_items, revived_entity, proxy = pcall(function()
        return ghost.revive(revive_opts)
    end)
    if not ok then
        return false, nil, nil, nil
    end
    return true, collided_items, revived_entity, proxy
end

--- Build the ghost
---@param spider_data table
---@param ghost LuaEntity
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, ghost, inventory, anchor_data)
    if not ghost or not ghost.valid then
        return false
    end
    if not inventory or not inventory.valid then
        return false
    end

    -- Get item needed
    local items = ghost.ghost_prototype.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    local item_count = items[1].count or 1
    local quality = ghost.quality
    local quality_name = type(quality) == "table" and quality.name or quality or "normal"
    local item_with_quality = { name = item_name, quality = quality_name }

    -- Double-check inventory
    if not utils.inventory_has_item(inventory, item_with_quality) then
        return false
    end

    local options = {
        raise_revive = true,
        overflow = inventory,
    }

    -- Revive the ghost. If it fails, try once more after moving the spider out of the
    -- future collision box (big ghosts are more likely to overlap the spider/legs).
    local _, revived_entity = nil, nil
    do
        local ok, _, revived = revive_ghost(ghost, options)
        if ok then
            revived_entity = revived
        end
    end
    if not revived_entity and spider_data and spider_data.entity and spider_data.entity.valid then
        local spider_entity = spider_data.entity
        local reposition = find_reposition(spider_entity, ghost, 6)
        if reposition then
            pcall(function()
                fapi.teleport(spider_entity, reposition)
            end)
        end

        local ok, _, revived = revive_ghost(ghost, options)
        if ok then
            revived_entity = revived
        end
    end

    if revived_entity then
        -- Remove item from inventory
        inventory.remove({ name = item_name, count = item_count, quality = quality_name })

        -- Optional: Show item projectile
        if settings.global["brood-show-item-projectiles"] and settings.global["brood-show-item-projectiles"].value then
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
