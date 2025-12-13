-- scripts/behaviors/deconstruct_tile.lua
-- Remove tiles marked for deconstruction

local constants = require("scripts/constants")
local utils = require("scripts/utils")

local behavior = {
    name = "deconstruct_tile",
    priority = constants.priorities.deconstruct_tile,
}

local function is_marked(tile)
    if not tile or not tile.valid then return false end
    if not tile.to_be_deconstructed then return false end
    local ok, marked = pcall(tile.to_be_deconstructed, tile)
    return (ok and marked) or false
end

---@param products Prototype.mineable_properties.products?
---@return ItemStackDefinition[]
local function get_product_stacks(products)
    if not products then return {} end
    local stacks = {}
    for _, product in pairs(products) do
        if product.type == "item" then
            local count = product.amount or product.amount_max or 1
            stacks[#stacks + 1] = { name = product.name, count = count }
        end
    end
    return stacks
end

--- Find tiles marked for deconstruction
---@param surface LuaSurface
---@param area BoundingBox
---@param force LuaForce[]
---@return LuaTile[]
function behavior.find_tasks(surface, area, force)
    -- Align with the proven working approach: use find_tiles_filtered with
    -- both `force` and `to_be_deconstructed` so the engine does the heavy lifting.
    local ok, tiles = pcall(surface.find_tiles_filtered, surface, {
        area = area,
        force = force,
        to_be_deconstructed = true,
    })
    tiles = (ok and tiles) or {}

    -- Some versions appear to require `force` for to_be_deconstructed, others ignore it.
    -- If we got nothing, try a couple of fallbacks.
    if #tiles == 0 then
        local ok2, tiles2 = pcall(surface.find_tiles_filtered, surface, {
            area = area,
            to_be_deconstructed = true,
        })
        if ok2 and tiles2 then
            tiles = tiles2
        end
    end

    local result = {}
    for _, tile in pairs(tiles) do
        if is_marked(tile) then
            result[#result + 1] = tile
        end
    end
    return result
end

---@param tile LuaTile
---@return Prototype.mineable_properties.products?
local function get_tile_products(tile)
    local tile_proto = tile and tile.valid and tile.prototype
    local mineable = tile_proto and tile_proto.mineable_properties
    return mineable and mineable.products or nil
end

--- Check if we can deconstruct this tile
---@param tile LuaTile
---@param inventory LuaInventory
---@return boolean
function behavior.can_execute(tile, inventory)
    if not tile or not tile.valid then return false end
    if not inventory or not inventory.valid then return false end
    if not is_marked(tile) then return false end
    
    -- Check space for result
    local products = get_tile_products(tile)
    local stacks = get_product_stacks(products)
    for _, stack in ipairs(stacks) do
        if not utils.inventory_has_space(inventory, stack) then
            return false
        end
    end

    return true
end

---@param miner_entity LuaEntity
---@param tile LuaTile
---@param anchor_inventory LuaInventory
---@param product_stacks ItemStackDefinition[]
---@return boolean
local function mine_tile_and_credit(miner_entity, tile, anchor_inventory, product_stacks)
    if not (miner_entity and miner_entity.valid and miner_entity.mine_tile) then return false end

    -- Track expected inventory deltas so we don't double-credit.
    local before = {}
    for _, stack in ipairs(product_stacks) do
        before[stack.name] = anchor_inventory.get_item_count(stack.name)
    end

    local ok, success = pcall(miner_entity.mine_tile, miner_entity, tile)
    if not ok or not success then
        return false
    end

    local miner_inventory = utils.get_entity_inventory(miner_entity)

    for _, stack in ipairs(product_stacks) do
        local expected = stack.count or 1
        local after = anchor_inventory.get_item_count(stack.name)
        local credited = math.max(0, after - (before[stack.name] or 0))
        local missing = expected - credited

        if missing > 0 then
            local moved = 0
            if miner_inventory and miner_inventory.valid then
                moved = miner_inventory.remove({ name = stack.name, count = missing })
                if moved > 0 then
                    anchor_inventory.insert({ name = stack.name, count = moved })
                end
            end

            missing = missing - moved
            if missing > 0 then
                anchor_inventory.insert({ name = stack.name, count = missing })
            end
        end
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
    if not behavior.can_execute(tile, inventory) then return false end

    local product_stacks = get_product_stacks(get_tile_products(tile))

    -- Prefer mining with the spider entity (it's guaranteed to be at the tile),
    -- and then move the mined items into the anchor inventory.
    local spider_entity = spider_data and spider_data.entity or nil
    if spider_entity and spider_entity.valid and spider_entity.mine_tile then
        if mine_tile_and_credit(spider_entity, tile, inventory, product_stacks) then
            return true
        end
    end

    -- Fallback to mining with the anchor entity (matches the proven working mod).
    local anchor_entity = anchor_data and anchor_data.entity or nil
    if not (anchor_entity and anchor_entity.valid and anchor_entity.mine_tile) then
        return false
    end

    if not mine_tile_and_credit(anchor_entity, tile, inventory, product_stacks) then
        return false
    end

    -- Optional UI cleanup for player anchors (mirrors the working mod).
    if anchor_data and anchor_data.player_index then
        local player = game.get_player(anchor_data.player_index)
        if player and player.valid and player.clear_local_flying_texts then
            pcall(player.clear_local_flying_texts, player)
        end
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
