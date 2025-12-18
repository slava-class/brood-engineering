-- scripts/utils.lua
-- Utility functions for Brood Engineering

local utils = {}

---@param quality any
---@return string? quality_name
local function normalize_quality_name(quality)
    if type(quality) == "table" then
        return quality.name
    end
    if type(quality) == "string" and quality ~= "" then
        return quality
    end
    return nil
end

---@param stack any
---@return ItemStackDefinition? safe_stack
function utils.safe_item_stack(stack)
    if stack == nil then
        return nil
    end

    local ok_name, name = pcall(function()
        return stack.name
    end)
    if not ok_name or type(name) ~= "string" or name == "" then
        return nil
    end

    local count = 1
    local ok_count, maybe_count = pcall(function()
        return stack.count
    end)
    if ok_count and type(maybe_count) == "number" and maybe_count >= 1 then
        count = maybe_count
    end

    local safe = { name = name, count = count }

    local ok_q, quality = pcall(function()
        return stack.quality
    end)
    if ok_q then
        local quality_name = normalize_quality_name(quality)
        if quality_name and quality_name ~= "normal" then
            safe.quality = quality_name
        end
    end

    return safe
end

---@class UtilsSpillItemStackOpts
---@field allow_belts boolean? nil
---@field drop_full_stack boolean? nil
---@field enable_looted boolean? nil
---@field force ForceID? nil
---@field max_radius number? nil
---@field use_start_position_on_failure boolean? nil

---@param surface LuaSurface
---@param position MapPosition
---@param stack ItemStackIdentification
---@param opts UtilsSpillItemStackOpts?
---@return LuaEntity[]? created
---@return any? err
function utils.spill_item_stack(surface, position, stack, opts)
    if not (surface and (surface.valid == nil or surface.valid)) then
        return nil, "invalid_surface"
    end
    if not position then
        return nil, "missing_position"
    end
    if not stack then
        return nil, "missing_stack"
    end

    local stack_arg = stack
    if type(stack) == "table" then
        stack_arg = utils.safe_item_stack(stack) or stack
    end

    local args = {
        position = position,
        stack = stack_arg,
    }
    if opts then
        for k, v in pairs(opts) do
            if v ~= nil then
                args[k] = v
            end
        end
    end

    local ok, created_or_err = pcall(function()
        return surface.spill_item_stack(args)
    end)
    if not ok then
        return nil, created_or_err
    end
    return created_or_err, nil
end

---@class UtilsCreateItemOnGroundOpts
---@field force ForceID? nil
---@field raise_built boolean? nil
---@field create_build_effect_smoke boolean? nil
---@field spawn_decorations boolean? nil
---@field move_stuck_players boolean? nil
---@field player PlayerIdentification? nil

---@param surface LuaSurface
---@param position MapPosition
---@param stack any
---@param opts UtilsCreateItemOnGroundOpts?
---@return LuaEntity? entity
---@return any? err
function utils.create_item_on_ground(surface, position, stack, opts)
    if not (surface and (surface.valid == nil or surface.valid)) then
        return nil, "invalid_surface"
    end
    if not position then
        return nil, "missing_position"
    end

    local safe_stack = utils.safe_item_stack(stack)
    if not safe_stack then
        return nil, "invalid_stack"
    end
    if not (game and game.create_inventory) then
        return nil, "missing_game"
    end

    local inv = game.create_inventory(1)
    local item = inv and inv[1] or nil
    if not item then
        if inv and inv.destroy then
            pcall(inv.destroy, inv)
        end
        return nil, "missing_inventory_itemstack"
    end

    local ok_set, set_err = pcall(function()
        item.set_stack(safe_stack)
    end)
    if not ok_set then
        pcall(inv.destroy, inv)
        return nil, set_err
    end

    local args = {
        name = "item-on-ground",
        position = position,
        item = item,
    }
    if opts then
        for k, v in pairs(opts) do
            if v ~= nil then
                args[k] = v
            end
        end
    end

    local ok_create, entity_or_err = pcall(function()
        return surface.create_entity(args)
    end)

    pcall(inv.destroy, inv)

    if not ok_create then
        return nil, entity_or_err
    end
    return entity_or_err, nil
end

---@return boolean
local function debug_logging_enabled()
    local override = storage and storage.debug_logging_override
    if override ~= nil then
        return override == true
    end

    return settings
        and settings.global
        and settings.global["brood-debug-logging"]
        and settings.global["brood-debug-logging"].value
end

--- Check whether debug logging is enabled.
---@return boolean
function utils.debug_enabled()
    return debug_logging_enabled()
end

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
    local dist = radius * math.sqrt(math.random()) -- sqrt for uniform distribution
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
    if not entity or not entity.valid then
        return 0
    end
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
    if not player or not player.valid then
        return nil
    end
    return player.physical_vehicle or player.character or nil
end

--- Get inventory from an entity (character, car, spider-vehicle, etc.)
---@param entity LuaEntity
---@return LuaInventory?
function utils.get_entity_inventory(entity)
    if not entity or not entity.valid then
        return nil
    end

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
    if not inventory or not inventory.valid then
        return false
    end
    return inventory.get_item_count(item) >= 1
end

--- Check if inventory has space for an item
---@param inventory LuaInventory
---@param item ItemStackDefinition|string
---@return boolean
function utils.inventory_has_space(inventory, item)
    if not inventory or not inventory.valid then
        return false
    end
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

    if area <= 1 then
        return "small"
    elseif area <= 4 then
        return "medium"
    elseif area <= 9 then
        return "large"
    else
        return "huge"
    end
end

--- Log a message (debug helper)
---@param msg string
function utils.log(msg)
    if not debug_logging_enabled() then
        return
    end
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
