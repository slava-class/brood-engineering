-- scripts/anchor.lua
-- Anchor management for Brood Engineering
-- An anchor is an inventory source that spiders work for

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local anchor = {}

--- Generate a unique anchor ID
---@return string
local function generate_anchor_id()
    storage.anchor_id_counter = (storage.anchor_id_counter or 0) + 1
    return "anchor_" .. storage.anchor_id_counter
end

--- Create an anchor for a player
---@param player LuaPlayer
---@return string? anchor_id
function anchor.create_for_player(player)
    local player_entity = utils.get_player_entity(player)
    if not player_entity then
        utils.log("Cannot create anchor: player has no entity")
        return nil
    end

    local anchor_id = generate_anchor_id()

    storage.anchors[anchor_id] = {
        type = "player",
        entity = player_entity,
        player_index = player.index,
        surface_index = player_entity.surface_index,
        position = { x = player_entity.position.x, y = player_entity.position.y },
        spiders = {},
    }

    -- Track player → anchor mapping
    storage.player_to_anchor = storage.player_to_anchor or {}
    storage.player_to_anchor[player.index] = anchor_id

    utils.log("Created anchor " .. anchor_id .. " for player " .. player.name)
    return anchor_id
end

--- Get anchor for a player
---@param player LuaPlayer
---@return table? anchor_data
function anchor.get_for_player(player)
    if not player or not player.valid then
        return nil
    end

    local anchor_id = storage.player_to_anchor and storage.player_to_anchor[player.index]
    if not anchor_id then
        return nil
    end

    return storage.anchors[anchor_id]
end

--- Get anchor ID for a player
---@param player LuaPlayer
---@return string? anchor_id
function anchor.get_id_for_player(player)
    if not player or not player.valid then
        return nil
    end
    return storage.player_to_anchor and storage.player_to_anchor[player.index]
end

--- Get anchor by ID
---@param anchor_id string
---@return table? anchor_data
function anchor.get(anchor_id)
    return storage.anchors[anchor_id]
end

--- Destroy an anchor
---@param anchor_id string
function anchor.destroy(anchor_id)
    local anchor_data = storage.anchors[anchor_id]
    if not anchor_data then
        return
    end

    -- Remove player mapping if player anchor
    if anchor_data.type == "player" and anchor_data.player_index then
        if storage.player_to_anchor then
            storage.player_to_anchor[anchor_data.player_index] = nil
        end
    end

    storage.anchors[anchor_id] = nil
    utils.log("Destroyed anchor " .. anchor_id)
end

--- Update anchor's entity reference (e.g., when player enters/exits vehicle)
---@param anchor_id string
---@param new_entity LuaEntity
function anchor.update_entity(anchor_id, new_entity)
    local anchor_data = storage.anchors[anchor_id]
    if not anchor_data then
        return
    end

    anchor_data.entity = new_entity
    if new_entity and new_entity.valid then
        anchor_data.surface_index = new_entity.surface_index
        anchor_data.position = { x = new_entity.position.x, y = new_entity.position.y }
    end
end

--- Update anchor's position cache (call each tick)
---@param anchor_data table
---@return boolean position_changed_significantly
function anchor.update_position(anchor_data)
    local entity = anchor_data.entity
    if not entity or not entity.valid then
        return false
    end

    local old_pos = anchor_data.position
    local new_pos = entity.position

    anchor_data.position = { x = new_pos.x, y = new_pos.y }
    anchor_data.surface_index = entity.surface_index

    -- Check if moved significantly (for teleport detection)
    local dist = utils.distance(old_pos, new_pos)
    return dist > constants.teleport_threshold
end

--- Get inventory for an anchor
---@param anchor_data table
---@return LuaInventory?
function anchor.get_inventory(anchor_data)
    if not anchor_data then
        return nil
    end

    local entity = anchor_data.entity
    if not entity or not entity.valid then
        return nil
    end

    return utils.get_entity_inventory(entity)
end

--- Get work area for an anchor (bounding box)
---@param anchor_data table
---@return BoundingBox
function anchor.get_work_area(anchor_data)
    local pos = anchor_data.position
    local radius = constants.anchor_scan_radius
    return utils.area_around(pos, radius)
end

--- Get expanded work area including all spider positions
---@param anchor_data table
---@return BoundingBox
function anchor.get_expanded_work_area(anchor_data)
    local min_x, max_x = anchor_data.position.x, anchor_data.position.x
    local min_y, max_y = anchor_data.position.y, anchor_data.position.y

    for _, spider_data in pairs(anchor_data.spiders) do
        local spider = spider_data.entity
        if spider and spider.valid then
            local sp = spider.position
            if sp.x < min_x then
                min_x = sp.x
            end
            if sp.x > max_x then
                max_x = sp.x
            end
            if sp.y < min_y then
                min_y = sp.y
            end
            if sp.y > max_y then
                max_y = sp.y
            end
        end
    end

    local radius = constants.anchor_scan_radius
    return {
        { min_x - radius, min_y - radius },
        { max_x + radius, max_y + radius },
    }
end

--- Get force for an anchor
---@param anchor_data table
---@return LuaForce[]
function anchor.get_force(anchor_data)
    local entity = anchor_data.entity
    if entity and entity.valid then
        return { entity.force.name, "neutral" }
    end
    return { "player", "neutral" }
end

--- Get surface for an anchor
---@param anchor_data table
---@return LuaSurface?
function anchor.get_surface(anchor_data)
    local entity = anchor_data.entity
    if entity and entity.valid then
        return entity.surface
    end
    return nil
end

--- Count spiders for an anchor
---@param anchor_data table
---@return integer
function anchor.get_spider_count(anchor_data)
    return utils.table_size(anchor_data.spiders)
end

--- Check if anchor can deploy more spiders
---@param anchor_data table
---@return boolean
function anchor.can_deploy_spider(anchor_data)
    local count = anchor.get_spider_count(anchor_data)
    return count < constants.max_spiders_per_anchor
end

--- Check if anchor has spiderlings in inventory
---@param anchor_data table
---@return boolean has_any
---@return integer count
function anchor.has_spiderlings_in_inventory(anchor_data)
    local inventory = anchor.get_inventory(anchor_data)
    if not inventory then
        return false, 0
    end

    local count = inventory.get_item_count("spiderling")
    return count > 0, count
end

--- Check if anchor's entity is valid
---@param anchor_data table
---@return boolean
function anchor.is_valid(anchor_data)
    return anchor_data and anchor_data.entity and anchor_data.entity.valid
end

--- Internal iterator for anchors
---@param _ any
---@param key string?
---@return string?, table?
local function iterate_anchors(_, key)
    return next(storage.anchors, key)
end

--- Iterate all anchors
---@return fun(): string, table
function anchor.iterate()
    return iterate_anchors
end

return anchor
