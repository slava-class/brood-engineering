-- scripts/utils.lua
-- Utility functions for Brood Engineering

local utils = {}

--- Calculate distance between two positions
---@param pos1 MapPosition
---@param pos2 MapPosition
---@return number
function utils.distance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Get a random position within radius of center
---@param center MapPosition
---@param radius number
---@return MapPosition
function utils.random_position_in_radius(center, radius)
    local angle = math.random() * 2 * math.pi
    local dist = radius * math.sqrt(math.random())  -- sqrt for uniform distribution
    return {
        x = center.x + dist * math.cos(angle),
        y = center.y + dist * math.sin(angle),
    }
end

--- Get a random position on a tile (within ±0.5 of center)
---@param center MapPosition
---@return MapPosition
function utils.random_position_on_tile(center)
    return {
        x = center.x + (math.random() - 0.5),
        y = center.y + (math.random() - 0.5),
    }
end

--- Create a bounding box area around a position
---@param center MapPosition
---@param radius number
---@return BoundingBox
function utils.area_around(center, radius)
    return {
        { center.x - radius, center.y - radius },
        { center.x + radius, center.y + radius },
    }
end

--- Iterate over a table in random order
--- Useful for fair task assignment
---@generic K, V
---@param tbl table<K, V>
---@return fun(): K, V
function utils.random_pairs(tbl)
    -- Collect keys
    local keys = {}
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    
    -- Fisher-Yates shuffle
    for i = #keys, 2, -1 do
        local j = math.random(i)
        keys[i], keys[j] = keys[j], keys[i]
    end
    
    -- Iterator
    local i = 0
    return function()
        i = i + 1
        local key = keys[i]
        if key ~= nil then
            return key, tbl[key]
        end
    end
end

--- Get unique ID for an entity (using registration)
---@param entity LuaEntity
---@return uint64
function utils.get_entity_id(entity)
    if not entity or not entity.valid then return 0 end
    local reg_number = script.register_on_object_destroyed(entity)
    return reg_number
end

--- Get unique string key for a tile
---@param tile LuaTile
---@return string
function utils.get_tile_key(tile)
    local pos = tile.position
    local surface = tile.surface.name
    return string.format("tile_%s_%d_%d", surface, pos.x, pos.y)
end

--- Check if a table is empty
---@param tbl table
---@return boolean
function utils.is_empty(tbl)
    return next(tbl) == nil
end

--- Get table size (works for non-array tables)
---@param tbl table
---@return integer
function utils.table_size(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--- Safely get player entity (character or vehicle)
---@param player LuaPlayer
---@return LuaEntity?
function utils.get_player_entity(player)
    if not player or not player.valid then return nil end
    return player.physical_vehicle or player.character or nil
end

--- Get inventory from an entity (character, car, spider-vehicle, etc.)
---@param entity LuaEntity
---@return LuaInventory?
function utils.get_entity_inventory(entity)
    if not entity or not entity.valid then return nil end
    
    local entity_type = entity.type
    
    if entity_type == "character" then
        return entity.get_inventory(defines.inventory.character_main)
    elseif entity_type == "car" then
        return entity.get_inventory(defines.inventory.car_trunk)
    elseif entity_type == "spider-vehicle" then
        return entity.get_inventory(defines.inventory.spider_trunk)
    elseif entity_type == "cargo-wagon" then
        return entity.get_inventory(defines.inventory.cargo_wagon)
    elseif entity_type == "container" or entity_type == "logistic-container" then
        return entity.get_inventory(defines.inventory.chest)
    end
    
    return nil
end

--- Check if inventory has at least one of an item
---@param inventory LuaInventory
---@param item ItemIDAndQualityIDPair|string
---@return boolean
function utils.inventory_has_item(inventory, item)
    if not inventory or not inventory.valid then return false end
    return inventory.get_item_count(item) >= 1
end

--- Check if inventory has space for an item
---@param inventory LuaInventory
---@param item ItemStackDefinition|string
---@return boolean
function utils.inventory_has_space(inventory, item)
    if not inventory or not inventory.valid then return false end
    return inventory.can_insert(item)
end

--- Convert ItemIDAndQualityIDPair to ItemStackDefinition
---@param item ItemIDAndQualityIDPair
---@return ItemStackDefinition
function utils.to_item_stack(item)
    local name = type(item.name) == "string" and item.name or item.name.name
    local quality = item.quality
    if type(quality) == "table" then
        quality = quality.name
    end
    return { name = name, quality = quality or "normal" }
end

--- Get the entity size category based on bounding box
---@param entity LuaEntity
---@return "small"|"medium"|"large"|"huge"
function utils.get_entity_size(entity)
    local box = entity.bounding_box
    local w = math.abs(box.right_bottom.x - box.left_top.x)
    local h = math.abs(box.right_bottom.y - box.left_top.y)
    local area = w * h
    
    if area <= 1 then return "small"
    elseif area <= 4 then return "medium"
    elseif area <= 9 then return "large"
    else return "huge"
    end
end

--- Log a message (debug helper)
---@param msg string
function utils.log(msg)
    log("[Brood] " .. msg)
end

--- Print to player (debug helper)
---@param msg string
function utils.print_all(msg)
    for _, player in pairs(game.players) do
        player.print("[Brood] " .. msg)
    end
end

return utils
