-- scripts/behaviors/build_foundation.lua
-- Build foundation tile ghosts (landfill, etc.)
-- These are prioritized because other buildings may need them

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "build_foundation",
    priority = constants.priorities.build_foundation,
}

-- Cache foundation tile names
local foundation_tiles = nil

--- Get set of foundation tile names
---@return table<string, boolean>
local function get_foundation_tiles()
    if not foundation_tiles then
        foundation_tiles = {}
        for name, tile in pairs(prototypes.tile) do
            if tile.is_foundation then
                foundation_tiles[name] = true
            end
        end
    end
    return foundation_tiles
end

--- Find foundation tile ghosts in area
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaEntity[]
function behavior.find_tasks(surface, area, force)
    local tile_ghosts = surface.find_entities_filtered({
        area = area,
        force = force,
        type = "tile-ghost",
    })

    local foundations = get_foundation_tiles()
    local result = {}

    for _, ghost in pairs(tile_ghosts) do
        if ghost.valid and foundations[ghost.ghost_name] then
            result[#result + 1] = ghost
        end
    end

    return result
end

--- Check if we can build this tile ghost
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

    -- Get item needed
    local tile_proto = prototypes.tile[ghost.ghost_name]
    if not tile_proto then
        return false
    end

    local items = tile_proto.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    return utils.inventory_has_item(inventory, item_name)
end

--- Build the tile ghost
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

    local tile_name = ghost.ghost_name
    local tile_proto = prototypes.tile[tile_name]
    if not tile_proto then
        return false
    end

    local items = tile_proto.items_to_place_this
    if not items or not items[1] then
        return false
    end

    local item_name = items[1].name
    local item_count = items[1].count or 1

    if not utils.inventory_has_item(inventory, item_name) then
        return false
    end

    local position = ghost.position
    local surface = ghost.surface

    -- Revive the tile ghost
    local collisions, tile, proxy = ghost.revive({
        raise_revive = true,
    })

    if tile or not ghost.valid then
        -- Remove item from inventory
        inventory.remove({ name = item_name, count = item_count })
        return true
    end

    return false
end

--- Get unique ID for a tile ghost
---@param ghost LuaEntity
---@return string
function behavior.get_task_id(ghost)
    return "build_foundation_" .. utils.get_entity_id(ghost)
end

return behavior
