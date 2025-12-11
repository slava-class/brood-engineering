-- scripts/behaviors/deconstruct_tile.lua
-- Remove tiles marked for deconstruction

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "deconstruct_tile",
    priority = constants.priorities.deconstruct_tile,
}

--- Find tiles marked for deconstruction
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaTile[]
function behavior.find_tasks(surface, area, force)
    return surface.find_tiles_filtered({
        area = area,
        force = force,
        to_be_deconstructed = true,
    })
end

--- Get item returned when mining a tile
---@param tile LuaTile
---@return ItemStackDefinition?
local function get_tile_mine_result(tile)
    local tile_proto = tile.prototype
    if not tile_proto then return nil end
    
    local mineable = tile_proto.mineable_properties
    if not mineable or not mineable.products then return nil end
    
    for _, product in pairs(mineable.products) do
        if product.type == "item" then
            local amount = product.amount or product.amount_max or 1
            return { name = product.name, count = amount }
        end
    end
    
    return nil
end

--- Check if we can deconstruct this tile
---@param tile LuaTile
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(tile, inventory)
    if not tile or not tile.valid then return false end
    if not inventory or not inventory.valid then return false end
    
    -- Check space for result
    local result = get_tile_mine_result(tile)
    if result then
        return utils.inventory_has_space(inventory, result)
    end
    
    return true
end

--- Deconstruct the tile
---@param spider_data table
---@param tile LuaTile
---@param inventory LuaInventory
---@param anchor_data table
---@return boolean
function behavior.execute(spider_data, tile, inventory, anchor_data)
    if not tile or not tile.valid then return false end
    if not inventory or not inventory.valid then return false end
    
    local surface = tile.surface
    local position = tile.position
    local result = get_tile_mine_result(tile)
    
    -- Get the hidden tile (what's underneath)
    local hidden_tile = tile.hidden_tile
    local replacement = hidden_tile or "grass-1"  -- fallback
    
    -- Cancel deconstruction first
    tile.cancel_deconstruction(game.forces["player"])
    
    -- Set the tile to the hidden/replacement tile
    surface.set_tiles({
        { name = replacement, position = position },
    }, true, true, true, true)
    
    -- Insert mined item
    if result then
        inventory.insert(result)
    end
    
    return true
end

--- Get unique ID for a tile
---@param tile LuaTile
---@return string
function behavior.get_task_id(tile)
    return utils.get_tile_key(tile)
end

return behavior
